-------------------------------------------------------------------------------
--  EllesmereUI_Startup.lua
--  Runs as early as possible (first file after the Lite framework).
--  Applies settings that the WoW engine caches at login time, before
--  other addon files or PLAYER_LOGIN handlers have a chance to run.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Pixel-Perfect UI Scale
--
--  SavedVariables (EllesmereUIDB) aren't available at file scope — they load
--  at ADDON_LOADED. So we use events:
--    ADDON_LOADED  → DB is available. If we have a saved scale, apply it.
--                    If migrating from old system, convert and apply.
--    PLAYER_ENTERING_WORLD → Blizzard has applied the user's CVar scale.
--                    If no saved scale yet (first install / reset), snapshot
--                    the user's current Blizzard scale and save it.
-------------------------------------------------------------------------------
do
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local dbReady = false

    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("ADDON_LOADED")
    scaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    scaleFrame:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" then
            if addonName ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
            dbReady = true

            if not EllesmereUIDB then EllesmereUIDB = {} end

            local _, physH = GetPhysicalScreenSize()
            local perfect = 768 / physH
            local function PixelBestSize()
                return max(0.4, min(perfect, 1.15))
            end

            -- Migration from old percentage-based blizzUIScale
            if EllesmereUIDB.ppUIScale == nil and EllesmereUIDB.blizzUIScale then
                EllesmereUIDB.ppUIScale = PixelBestSize()
                EllesmereUIDB.ppUIScaleAuto = true
            end

            -- Apply saved scale immediately
            if EllesmereUIDB.ppUIScale then
                UIParent:SetScale(EllesmereUIDB.ppUIScale)
            end

        elseif event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")

            -- If ADDON_LOADED hasn't fired yet (shouldn't happen, but safety)
            if not dbReady then return end
            if not EllesmereUIDB then EllesmereUIDB = {} end

            -- First install or reset: snapshot the user's Blizzard scale
            if EllesmereUIDB.ppUIScale == nil then
                local blizzScale = UIParent:GetScale()
                local clamped = max(0.4, min(blizzScale, 1.15))
                EllesmereUIDB.ppUIScale = clamped
                EllesmereUIDB.ppUIScaleAuto = false
            end
        end
    end)
end

-- Apply the saved combat text font immediately at file scope.
-- DAMAGE_TEXT_FONT must be set before the engine caches it at login.
-- CombatTextFont may not exist yet here, so we also hook ADDON_LOADED
-- to catch it as soon as it becomes available.
do
    -- Migrate old media path if needed
    if EllesmereUIDB and EllesmereUIDB.fctFont and type(EllesmereUIDB.fctFont) == "string" then
        EllesmereUIDB.fctFont = EllesmereUIDB.fctFont:gsub("\\media\\Expressway", "\\media\\fonts\\Expressway")
    end

    local function ApplyCombatTextFont()
        local saved = EllesmereUIDB and EllesmereUIDB.fctFont
        if not saved or type(saved) ~= "string" or saved == "" then return end
        _G.DAMAGE_TEXT_FONT = saved
        if _G.CombatTextFont then
            _G.CombatTextFont:SetFont(saved, 120, "")
        end
    end

    -- Apply immediately (sets DAMAGE_TEXT_FONT before engine caches it)
    ApplyCombatTextFont()

    -- Re-apply on ADDON_LOADED (our addon or Blizzard_CombatText), PLAYER_LOGIN,
    -- and PLAYER_ENTERING_WORLD to cover all timing windows where the engine
    -- may cache or reset the combat text font.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" then
            if addonName ~= ADDON_NAME and addonName ~= "Blizzard_CombatText" then
                return
            end
        end

        ApplyCombatTextFont()

        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        elseif event == "ADDON_LOADED" then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
