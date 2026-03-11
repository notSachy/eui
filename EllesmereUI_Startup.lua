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

    local pendingScale = nil   -- scale to apply once the world is ready

    local function ApplyScaleSafe(scale)
        if InCombatLockdown() then
            -- Defer until combat ends — UIParent:SetScale is protected in combat
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                UIParent:SetScale(scale)
                -- UI_SCALE_CHANGED may not fire if scale didn't change; update mult directly
                if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                    EllesmereUI.PP.UpdateMult()
                end
            end)
        else
            UIParent:SetScale(scale)
            -- UI_SCALE_CHANGED only fires when the value actually changes.
            -- Always update mult so PP.Scale() stays correct even when the
            -- scale was already set to this value.
            if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                EllesmereUI.PP.UpdateMult()
            end
        end
    end

    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("ADDON_LOADED")
    scaleFrame:RegisterEvent("PLAYER_LOGIN")
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

            -- Apply saved scale immediately for non-migration cases
            -- (returning users who already have ppUIScale set)
            if EllesmereUIDB.ppUIScale then
                pendingScale = EllesmereUIDB.ppUIScale
                ApplyScaleSafe(pendingScale)
            end

        elseif event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            -- Update PP.mult before child addon OnEnable handlers run.
            -- Child addons (UnitFrames, ActionBars) call PP.Scale/Size/Point
            -- during OnEnable (which fires on PLAYER_LOGIN). If PP.mult is
            -- still the file-load value at that point, all pixel-snapped
            -- geometry is wrong until the next reload.
            if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                EllesmereUI.PP.UpdateMult()
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
                pendingScale = clamped
            end

            -- Re-apply scale now that the world is loaded, then again
            -- after a short delay to beat any Blizzard resets
            local scale = EllesmereUIDB.ppUIScale
            if scale then
                -- Update PP.mult immediately so any frames built between now
                -- and the timer passes use the correct pixel multiplier.
                if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                    EllesmereUI.PP.UpdateMult()
                end
                ApplyScaleSafe(scale)
                C_Timer.After(2, function()
                    if InCombatLockdown() then return end
                    if EllesmereUIDB and EllesmereUIDB.ppUIScale then
                        ApplyScaleSafe(EllesmereUIDB.ppUIScale)
                    end
                    -- Always update PP.mult — UI_SCALE_CHANGED only fires when
                    -- the scale value changes, so if Blizzard reset and re-set
                    -- the same value the event never fires and mult stays stale.
                    if EllesmereUI and EllesmereUI.PP then
                        if EllesmereUI.PP.UpdateMult then EllesmereUI.PP.UpdateMult() end
                        if EllesmereUI.PP.ResnapAllBorders then EllesmereUI.PP.ResnapAllBorders() end
                    end
                end)
                -- Second pass: catch any borders created late (e.g. lazy-init frames)
                C_Timer.After(5, function()
                    if InCombatLockdown() then return end
                    if EllesmereUIDB and EllesmereUIDB.ppUIScale then
                        ApplyScaleSafe(EllesmereUIDB.ppUIScale)
                    end
                    if EllesmereUI and EllesmereUI.PP then
                        if EllesmereUI.PP.UpdateMult then EllesmereUI.PP.UpdateMult() end
                        if EllesmereUI.PP.ResnapAllBorders then EllesmereUI.PP.ResnapAllBorders() end
                    end
                end)
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

-- /rl reload shortcut -- only register if nothing else has claimed it
if not SlashCmdList["RL"] then
    SlashCmdList["RL"] = function() ReloadUI() end
    SLASH_RL1 = "/rl"
end
