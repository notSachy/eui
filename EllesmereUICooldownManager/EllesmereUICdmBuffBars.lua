--------------------------------------------------------------------------------
--  EllesmereUICdmBuffBars.lua
--  Buff Bars: Tracked Buff Bars v2 (per-bar buff tracking with individual
--  settings) and legacy Buff Bars (disabled). Currently the legacy system is
--  disabled uncomment blocks to re-enable.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Set to true to enable Tracked Buff Bars functionality
local TBB_ENABLED = true

-- Forward references from main CDM file (set during init)
local ECME

function ns.InitBuffBars(ecme)
    ECME = ecme
end

-------------------------------------------------------------------------------
--  Tracked Buff Bars v2: Per-bar buff tracking with individual settings
--  Each bar tracks a single buff/aura and has its own display settings.
-------------------------------------------------------------------------------
local TBB_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local TBB_TEXTURES = {
    ["none"]          = nil,
    ["beautiful"]     = TBB_TEX_BASE .. "beautiful.tga",
    ["plating"]       = TBB_TEX_BASE .. "plating.tga",
    ["atrocity"]      = TBB_TEX_BASE .. "atrocity.tga",
    ["divide"]        = TBB_TEX_BASE .. "divide.tga",
    ["glass"]         = TBB_TEX_BASE .. "glass.tga",
    ["gradient-lr"]   = TBB_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TBB_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TBB_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TBB_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TBB_TEX_BASE .. "matte.tga",
    ["sheer"]         = TBB_TEX_BASE .. "sheer.tga",
}
local TBB_TEXTURE_ORDER = {
    "none", "beautiful", "plating",
    "atrocity", "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local TBB_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
ns.TBB_TEXTURES      = TBB_TEXTURES
ns.TBB_TEXTURE_ORDER = TBB_TEXTURE_ORDER
ns.TBB_TEXTURE_NAMES = TBB_TEXTURE_NAMES

-- Resolve player class color for default fill
local _tbbClassR, _tbbClassG, _tbbClassB = 0.05, 0.82, 0.62
do
    local _, ct = UnitClass("player")
    if ct then
        local cc = RAID_CLASS_COLORS[ct]
        if cc then _tbbClassR, _tbbClassG, _tbbClassB = cc.r, cc.g, cc.b end
    end
end

local TBB_DEFAULT_BAR = {
    spellID   = 0,
    name      = "New Bar",
    enabled   = true,
    height    = 24,
    width     = 270,
    verticalOrientation = false,
    texture   = "none",
    fillR     = _tbbClassR, fillG = _tbbClassG, fillB = _tbbClassB, fillA = 1,
    bgR       = 0, bgG = 0, bgB = 0, bgA = 0.4,
    gradientEnabled = false,
    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
    gradientDir = "HORIZONTAL",
    opacity   = 1.0,
    showTimer = true,
    timerSize = 11,
    timerX    = 0,
    timerY    = 0,
    showName  = true,
    nameSize  = 11,
    nameX     = 0,
    nameY     = 0,
    showSpark = true,
    iconDisplay = "none",
    iconSize    = 24,
    iconX       = 0,
    iconY       = 0,
    iconBorderSize = 0,
}
ns.TBB_DEFAULT_BAR = TBB_DEFAULT_BAR

--- Get tracked buff bars profile data (with lazy init)
function ns.GetTrackedBuffBars()
    if not ECME or not ECME.db then return { selectedBar = 1, bars = {} } end
    local p = ECME.db.profile
    if not p.trackedBuffBars then
        p.trackedBuffBars = { selectedBar = 1, bars = {} }
    end
    return p.trackedBuffBars
end

--- Add a new tracked buff bar
function ns.AddTrackedBuffBar()
    local tbb = ns.GetTrackedBuffBars()
    local newBar = {}
    -- Copy settings from the last bar if one exists, otherwise use defaults
    local source = (#tbb.bars > 0) and tbb.bars[#tbb.bars] or TBB_DEFAULT_BAR
    for k, v in pairs(TBB_DEFAULT_BAR) do
        newBar[k] = (source[k] ~= nil) and source[k] or v
    end
    -- Always reset spell-specific fields
    newBar.spellID = 0
    newBar.name = "Bar " .. (#tbb.bars + 1)
    tbb.bars[#tbb.bars + 1] = newBar
    tbb.selectedBar = #tbb.bars
    ns.BuildTrackedBuffBars()
    return #tbb.bars
end

--- Remove a tracked buff bar by index
function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    table.remove(tbb.bars, idx)
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = math.max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

--- Tracked buff bar frames
local tbbFrames = {}
local tbbTickFrame
local _tbbRebuildPending = false

local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    return (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("cdm")) or CDM_FONT_FALLBACK
end
local function GetCDMOutline()
    return "OUTLINE"
end
local function GetCDMUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
end
local function SetCDMFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    fs:SetFont(font, size, "OUTLINE")
    fs:SetShadowOffset(0, 0)
end

local function CreateTrackedBuffBarFrame(parent, idx)
    local bar = CreateFrame("StatusBar", "ECME_TBB" .. idx, parent)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.65)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    bar._bg = bg

    -- Spark
    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:Hide()
    bar._spark = spark

    -- Gradient overlay
    local grad = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    grad:SetAllPoints(bar:GetStatusBarTexture())
    grad:SetBlendMode("BLEND")
    grad:Hide()
    bar._gradient = grad

    -- Timer text
    local timerText = bar:CreateFontString(nil, "OVERLAY")
    SetCDMFont(timerText, GetCDMFont(), 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    bar._timerText = timerText

    -- Name text (left side)
    local nameText = bar:CreateFontString(nil, "OVERLAY")
    SetCDMFont(nameText, GetCDMFont(), 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    bar._nameText = nameText

    -- Icon (left of bar)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    icon:Hide()
    bar._icon = icon

    -- Icon border frame (4 edge textures)
    local iconBorder = CreateFrame("Frame", nil, bar)
    iconBorder:SetFrameLevel(bar:GetFrameLevel() + 3)
    iconBorder:Hide()
    bar._iconBorder = iconBorder

    bar:Hide()
    return bar
end

local function ApplyTrackedBuffBarSettings(bar, cfg)
    if not bar or not cfg then return end
    local w = cfg.width or 200
    local h = cfg.height or 18
    local isVert = cfg.verticalOrientation

    -- Vertical: swap dimensions so the bar is tall and narrow
    if isVert then
        bar:SetSize(h, w)
    else
        bar:SetSize(w, h)
    end

    -- Orientation
    bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")

    -- Texture (only re-set if changed to avoid fill flash)
    local texPath = TBB_TEXTURES[cfg.texture or "none"] or "Interface\\Buttons\\WHITE8x8"
    if bar._lastTexPath ~= texPath then
        bar:SetStatusBarTexture(texPath)
        bar._lastTexPath = texPath
    end

    -- Fill color (user-defined, defaults to class color)
    local fR, fG, fB, fA = cfg.fillR or _tbbClassR, cfg.fillG or _tbbClassG, cfg.fillB or _tbbClassB, cfg.fillA or 1
    bar:GetStatusBarTexture():SetVertexColor(fR, fG, fB, fA)

    -- Background color
    if bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end

    -- Gradient
    if cfg.gradientEnabled and bar._gradient then
        bar._gradient:SetAllPoints(bar:GetStatusBarTexture())
        local dir = cfg.gradientDir or "HORIZONTAL"
        local r1, g1, b1, a1 = fR, fG, fB, fA
        local r2, g2, b2, a2 = cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1
        if bar._gradient.SetGradient then
            bar._gradient:SetGradient(dir, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
        end
        bar._gradient:Show()
    elseif bar._gradient then
        bar._gradient:Hide()
    end

    -- Opacity
    bar:SetAlpha(cfg.opacity or 1.0)

    -- Timer
    if cfg.showTimer then
        bar._timerText:Show()
        local tSize = cfg.timerSize or 11
        SetCDMFont(bar._timerText, GetCDMFont(), tSize)
        bar._timerText:ClearAllPoints()
        if isVert then
            bar._timerText:SetPoint("TOP", bar, "TOP", cfg.timerX or 0, -8 + (cfg.timerY or 0))
            bar._timerText:SetJustifyH("CENTER")
        else
            bar._timerText:SetPoint("RIGHT", bar, "RIGHT", -8 + (cfg.timerX or 0), cfg.timerY or 0)
            bar._timerText:SetJustifyH("RIGHT")
        end
    else
        bar._timerText:Hide()
    end

    -- Spark
    if cfg.showSpark then
        bar._spark:SetRotation(0)
        if isVert then
            bar._spark:SetSize(h, 8)
            bar._spark:SetRotation(math.pi / 2)
            bar._spark:ClearAllPoints()
            bar._spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "TOP", 0, 0)
        else
            bar._spark:SetSize(8, h)
            bar._spark:ClearAllPoints()
            bar._spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        end
        bar._spark:Show()
    else
        bar._spark:Hide()
    end

    -- Name text
    if cfg.showName ~= false then
        bar._nameText:Show()
        local nSize = cfg.nameSize or 11
        SetCDMFont(bar._nameText, GetCDMFont(), nSize)
        bar._nameText:ClearAllPoints()
        if isVert then
            bar._nameText:SetPoint("BOTTOM", bar, "BOTTOM", cfg.nameX or 0, 8 + (cfg.nameY or 0))
            bar._nameText:SetJustifyH("CENTER")
            bar._nameText:SetWidth(h - 4)
        else
            bar._nameText:SetPoint("LEFT", bar, "LEFT", 8 + (cfg.nameX or 0), cfg.nameY or 0)
            bar._nameText:SetJustifyH("LEFT")
            bar._nameText:SetWidth(w - 12 - (cfg.showTimer and 50 or 0))
        end
    else
        bar._nameText:Hide()
    end

    -- Icon
    local iconMode = cfg.iconDisplay or "none"
    if iconMode ~= "none" and bar._icon then
        local iSize = cfg.iconSize or h
        bar._icon:SetSize(iSize, iSize)
        bar._icon:ClearAllPoints()
        local ix, iy = cfg.iconX or 0, cfg.iconY or 0
        if isVert then
            -- Vertical: left/right icons go below/above the bar
            if iconMode == "left" then
                bar._icon:SetPoint("TOP", bar, "BOTTOM", ix, iy)
            elseif iconMode == "right" then
                bar._icon:SetPoint("BOTTOM", bar, "TOP", ix, iy)
            end
        else
            if iconMode == "left" then
                bar._icon:SetPoint("RIGHT", bar, "LEFT", ix, iy)
            elseif iconMode == "right" then
                bar._icon:SetPoint("LEFT", bar, "RIGHT", ix, iy)
            end
        end
        bar._icon:Show()

        -- Icon border
        if bar._iconBorder then
            local bSz = cfg.iconBorderSize or 0
            if bSz > 0 then
                local bR = cfg.borderR or 0
                local bG = cfg.borderG or 0
                local bB = cfg.borderB or 0
                if not bar._iconBorder._ppBorders then
                    local PP = EllesmereUI and EllesmereUI.PP
                    if PP then
                        PP.CreateBorder(bar._iconBorder, bR, bG, bB, 1, bSz)
                    end
                else
                    local PP = EllesmereUI and EllesmereUI.PP
                    if PP then
                        PP.UpdateBorder(bar._iconBorder, bSz, bR, bG, bB, 1)
                    end
                end
                bar._iconBorder:ClearAllPoints()
                bar._iconBorder:SetAllPoints(bar._icon)
                bar._iconBorder:Show()
            else
                bar._iconBorder:Hide()
            end
        end
    elseif bar._icon then
        bar._icon:Hide()
        if bar._iconBorder then bar._iconBorder:Hide() end
    end
end

-- Reusable helpers for secret-safe aura field access (avoids closure allocation per tick)
local _tbbAura
local function _TBBGetDuration() return _tbbAura.duration end
local function _TBBGetExpiration() return _tbbAura.expirationTime end
local function _TBBGetName() return _tbbAura.name end
local function _TBBGetSpellId() return _tbbAura.spellId end

-- Scan current player buffs OOC to cache the real aura spellID for each TBB bar.
local function RefreshTBBResolvedIDs()
    if InCombatLockdown() then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and cfg.enabled ~= false and cfg.spellID and cfg.spellID > 0 and cfg.name and cfg.name ~= "" then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, cfg.spellID)
            if ok and aura then
                bar._resolvedAuraID = cfg.spellID
            else
                for ai = 1, 40 do
                    local aData = C_UnitAuras.GetAuraDataByIndex("player", ai, "HELPFUL")
                    if not aData then break end
                    _tbbAura = aData
                    local nameOk, aName = pcall(_TBBGetName)
                    if nameOk and aName and aName == cfg.name then
                        local sidOk, sid = pcall(_TBBGetSpellId)
                        if sidOk and sid and sid > 0 then
                            bar._resolvedAuraID = sid
                        end
                        break
                    end
                end
            end
        end
    end
end
ns.RefreshTBBResolvedIDs = RefreshTBBResolvedIDs

function ns.BuildTrackedBuffBars()
    if not TBB_ENABLED then return end
    if not ECME or not ECME.db then return end
    if InCombatLockdown() then
        _tbbRebuildPending = true
        return
    end
    _tbbRebuildPending = false

    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local p = ECME.db.profile
    if not p.tbbPositions then p.tbbPositions = {} end

    -- Hide bars beyond current count
    for i = #bars + 1, #tbbFrames do
        if tbbFrames[i] then tbbFrames[i]:Hide() end
    end

    local anyEnabled = false
    for i, cfg in ipairs(bars) do
        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture
            if cfg.spellID and cfg.spellID > 0 and bar._icon then
                local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                if spInfo then bar._icon:SetTexture(spInfo.iconID) end
            end

            -- Name text
            if cfg.showName ~= false and bar._nameText then
                if cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    bar._nameText:SetText(spInfo and spInfo.name or cfg.name or "")
                else
                    bar._nameText:SetText(cfg.name or "")
                end
            end

            -- Saved position
            local posKey = tostring(i)
            local pos = p.tbbPositions[posKey]
            bar:ClearAllPoints()
            if pos and pos.point then
                if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            else
                bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
            end

            bar:Show()
        end
    end

    if anyEnabled then
        if not tbbTickFrame then
            tbbTickFrame = CreateFrame("Frame")
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                self._elapsed = (self._elapsed or 0) + elapsed
                if self._elapsed < 0.05 then return end
                self._elapsed = 0
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        tbbTickFrame:Show()
    elseif tbbTickFrame then
        tbbTickFrame:Hide()
    end
end

function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local now = GetTime()

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and bar:IsShown() and cfg.enabled ~= false and cfg.spellID and cfg.spellID > 0 then
            local aura
            local resolvedID = bar._resolvedAuraID or cfg.spellID
            local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedID)
            if ok and result then aura = result end

            if aura then
                local duration = aura.duration or 0
                local expiration = aura.expirationTime or 0
                if duration > 0 and expiration > 0 then
                    local remaining = expiration - now
                    if remaining < 0 then remaining = 0 end
                    bar:SetValue(remaining / duration)
                    if cfg.showTimer and bar._timerText then
                        local t
                        if remaining >= 3600 then t = format("%dh", floor(remaining / 3600))
                        elseif remaining >= 60 then t = format("%dm", floor(remaining / 60))
                        elseif remaining >= 10 then t = format("%d", floor(remaining))
                        else t = format("%.1f", remaining) end
                        bar._timerText:SetText(t)
                        bar._timerText:Show()
                    end
                else
                    bar:SetValue(1)
                    if bar._timerText then bar._timerText:Hide() end
                end
            else
                bar:SetValue(0)
                if bar._timerText then bar._timerText:SetText(""); bar._timerText:Hide() end
            end
        end
    end
end

function ns.IsTBBRebuildPending()
    return _tbbRebuildPending
end

-------------------------------------------------------------------------------
--  Register Tracked Buff Bars with unlock mode
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not TBB_ENABLED then return end
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars or #bars == 0 then return end

    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        if bar then
            elements[#elements + 1] = {
                key = "TBB_" .. posKey,
                label = "Buff Bar: " .. (cfg.name or ("Bar " .. idx)),
                group = "Cooldown Manager",
                order = 650,
                getFrame = function() return tbbFrames[idx] end,
                getSize = function()
                    local f = tbbFrames[idx]
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 200, 24
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    local p = ECME.db.profile
                    if not p.tbbPositions then p.tbbPositions = {} end
                    p.tbbPositions[posKey] = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    local f = tbbFrames[idx]
                    if f then
                        if scale then pcall(function() f:SetScale(scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x, y)
                    end
                    ns.BuildTrackedBuffBars()
                end,
                loadPosition = function()
                    local p = ECME.db.profile
                    return p.tbbPositions and p.tbbPositions[posKey]
                end,
                getScale = function()
                    local p = ECME.db.profile
                    local pos = p.tbbPositions and p.tbbPositions[posKey]
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    local p = ECME.db.profile
                    if p.tbbPositions then p.tbbPositions[posKey] = nil end
                end,
                applyPosition = function()
                    ns.BuildTrackedBuffBars()
                end,
            }
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements)
    end
end

--[[ BUFF BARS: DISABLED (untested uncomment to re-enable)
-------------------------------------------------------------------------------
--  Buff Bars: Custom aura tracking display
--  Shows player buffs as horizontal timer bars
-------------------------------------------------------------------------------
local FormatTime, UpdateBuffBars
do
local buffBarFrame       -- container
local buffBarPool = {}   -- reusable bar frames
local activeBuffBars = {}
local CLASS_COLORS_BUFF = {
    WARRIOR = {0.78,0.61,0.43}, PALADIN = {0.96,0.55,0.73}, HUNTER = {0.67,0.83,0.45},
    ROGUE = {1,0.96,0.41}, PRIEST = {1,1,1}, DEATHKNIGHT = {0.77,0.12,0.23},
    SHAMAN = {0,0.44,0.87}, MAGE = {0.25,0.78,0.92}, WARLOCK = {0.53,0.53,0.93},
    MONK = {0,1,0.60}, DRUID = {1,0.49,0.04}, DEMONHUNTER = {0.64,0.19,0.79},
    EVOKER = {0.20,0.58,0.50},
}

local function CreateBuffBar(parent, idx)
    local p = ECME.db.profile.buffBars
    local bar = CreateFrame("StatusBar", "ECME_BuffBar" .. idx, parent)
    bar:SetSize(p.width, p.height)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, p.bgAlpha)
    bar._bg = bg

    -- Border via unified PP system (outside the bar)
    local PP = EllesmereUI and EllesmereUI.PP
    local borderWrap = CreateFrame("Frame", nil, bar)
    borderWrap:SetFrameLevel(bar:GetFrameLevel())
    bar._borderWrap = borderWrap

    function bar:ApplyBorder(s, r, g, b, a)
        local bw = self._borderWrap
        if s and s > 0 then
            bw:ClearAllPoints()
            if PP then
                PP.SetOutside(bw, self, s, s)
            else
                bw:SetPoint("TOPLEFT", self, "TOPLEFT", -s, s)
                bw:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", s, -s)
            end
            if not bw._ppBorders then
                if PP then PP.CreateBorder(bw, r, g, b, a or 1, s, "OVERLAY", 7) end
            else
                if PP then PP.UpdateBorder(bw, s, r, g, b, a or 1) end
            end
            bw:Show()
        else
            bw:Hide()
        end
    end

    -- Icon
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(p.iconSize, p.iconSize)
    icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    bar._icon = icon

    -- Name text
    local nameText = bar:CreateFontString(nil, "OVERLAY")
    SetCDMFont(nameText, GetCDMFont(), 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetJustifyH("LEFT")
    bar._nameText = nameText

    -- Timer text
    local timerText = bar:CreateFontString(nil, "OVERLAY")
    SetCDMFont(timerText, GetCDMFont(), 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    bar._timerText = timerText

    bar:Hide()
    return bar
end

FormatTime = function(sec)
    local key = floor(sec * 10)
    local now = floor(GetTime())
    if now ~= _fmtCacheSec then
        wipe(_fmtCache)
        _fmtCacheSec = now
    end
    local cached = _fmtCache[key]
    if cached then return cached end
    local result
    if sec >= 3600 then result = format("%dh", floor(sec / 3600))
    elseif sec >= 60 then result = format("%dm", floor(sec / 60))
    elseif sec >= 10 then result = format("%d", floor(sec))
    else result = format("%.1f", sec)
    end
    _fmtCache[key] = result
    return result
end

local function MatchesFilter(name, filterMode, filterList)
    if filterMode == "all" then return true end
    if not filterList or filterList == "" then return filterMode == "blacklist" end
    local lower = name:lower()
    for entry in filterList:gmatch("[^,;]+") do
        entry = entry:match("^%s*(.-)%s*$"):lower()
        if entry ~= "" and lower:find(entry, 1, true) then
            return filterMode == "whitelist"
        end
    end
    return filterMode == "blacklist"
end

local _buffBarBuf = {}
local _buffSortNow = 0
local function _SortBuffsByRemaining(a, b)
    local ra = a.expires > 0 and (a.expires - _buffSortNow) or 9999
    local rb = b.expires > 0 and (b.expires - _buffSortNow) or 9999
    return ra < rb
end

UpdateBuffBars = function()
    if not ECME or not ECME.db then return end
    local p = ECME.db.profile.buffBars
    if not p.enabled then
        if buffBarFrame then buffBarFrame:Hide() end
        return
    end

    if not buffBarFrame then
        buffBarFrame = CreateFrame("Frame", "ECME_BuffBarFrame", UIParent)
        buffBarFrame:SetPoint("CENTER", UIParent, "CENTER", p.offsetX, p.offsetY)
        buffBarFrame:SetSize(p.width + 4, 200)
        buffBarFrame:SetFrameStrata("MEDIUM")
        buffBarFrame:SetMovable(true)
        buffBarFrame:SetClampedToScreen(true)
        if buffBarFrame.EnableMouseClicks then buffBarFrame:EnableMouseClicks(false) end
        buffBarFrame:RegisterForDrag("LeftButton")
        buffBarFrame:SetScript("OnDragStart", function(self)
            if not ECME.db.profile.buffBars.locked then self:StartMoving() end
        end)
        buffBarFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local _, _, _, x, y = self:GetPoint(1)
            if x then
                ECME.db.profile.buffBars.offsetX = x
                ECME.db.profile.buffBars.offsetY = y
            end
        end)
    end

    buffBarFrame:Show()
    buffBarTickFrame:Show()

    local _, classFile = UnitClass("player")
    local now = GetTime()
    local buffs = _buffBarBuf
    local buffCount = 0

    for i = 1, 40 do
        local auraData = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex("player", i)
        if not auraData then break end
        local name = auraData.name
        local iconTex = auraData.icon
        local duration = auraData.duration or 0
        local expirationTime = auraData.expirationTime or 0

        if name and MatchesFilter(name, p.filterMode, p.filterList) then
            buffCount = buffCount + 1
            local entry = buffs[buffCount]
            if not entry then
                entry = {}
                buffs[buffCount] = entry
            end
            entry.name = name
            entry.icon = iconTex
            entry.duration = duration
            entry.expires = expirationTime
        end
        if buffCount >= p.maxBars then break end
    end
    for i = buffCount + 1, #buffs do buffs[i] = nil end

    _buffSortNow = now
    table.sort(buffs, _SortBuffsByRemaining)

    local cr, cg, cb = p.barR, p.barG, p.barB
    if p.useClassColor then
        local cc = CLASS_COLORS_BUFF[classFile]
        if cc then cr, cg, cb = cc[1], cc[2], cc[3] end
    end

    for idx = 1, #buffs do
        local data = buffs[idx]
        local bar = buffBarPool[idx]
        if not bar then
            bar = CreateBuffBar(buffBarFrame, idx)
            buffBarPool[idx] = bar
        end

        bar:SetSize(p.width, p.height)
        bar:ClearAllPoints()
        local yDir = p.growUp and 1 or -1
        bar:SetPoint("TOPLEFT", buffBarFrame, "TOPLEFT", 0, yDir * (idx - 1) * (p.height + p.spacing))
        bar:ApplyBorder(p.borderSize, p.borderR, p.borderG, p.borderB, p.borderA)
        bar._bg:SetColorTexture(0, 0, 0, p.bgAlpha)
        bar:GetStatusBarTexture():SetVertexColor(cr, cg, cb, 1)

        if p.showIcon and data.icon then
            bar._icon:SetTexture(data.icon)
            bar._icon:SetSize(p.iconSize, p.iconSize)
            bar._icon:Show()
            bar._nameText:SetPoint("LEFT", bar._icon, "RIGHT", 4, 0)
        else
            bar._icon:Hide()
            bar._nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        end

        bar._nameText:SetText(data.name)
        bar._data = data
        bar._nameText:SetWidth(p.width - (p.showIcon and p.iconSize + 8 or 8) - (p.showTimer and 40 or 0))

        if data.duration > 0 and data.expires > 0 then
            local remaining = data.expires - now
            if remaining < 0 then remaining = 0 end
            bar:SetValue(remaining / data.duration)
            if p.showTimer then
                bar._timerText:SetText(FormatTime(remaining))
                bar._timerText:Show()
            else
                bar._timerText:Hide()
            end
        else
            bar:SetValue(1)
            if p.showTimer then
                bar._timerText:SetText("")
            end
            bar._timerText:Hide()
        end

        bar:Show()
        activeBuffBars[idx] = bar
    end

    for i = #buffs + 1, #buffBarPool do
        if buffBarPool[i] then buffBarPool[i]:Hide() end
    end
    for i = #buffs + 1, #activeBuffBars do activeBuffBars[i] = nil end

    local totalH = #buffs * (p.height + p.spacing)
    buffBarFrame:SetSize(p.width + 4, totalH > 0 and totalH or 1)
end

local buffBarTickFrame = CreateFrame("Frame")
buffBarTickFrame:Hide()
buffBarTickFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.05 then return end
    self.elapsed = 0
    if not ECME or not ECME.db or not ECME.db.profile.buffBars.enabled then
        self:Hide()
        return
    end
    local now = GetTime()
    for idx, bar in ipairs(activeBuffBars) do
        if bar and bar:IsShown() and bar._data then
            local data = bar._data
            if data.duration > 0 and data.expires > 0 then
                local remaining = data.expires - now
                if remaining < 0 then remaining = 0 end
                bar:SetValue(remaining / data.duration)
                if ECME.db.profile.buffBars.showTimer then
                    bar._timerText:SetText(FormatTime(remaining))
                end
            end
        end
    end
end)

end  -- do (Buff Bars scope)
--]] -- END BUFF BARS DISABLED
