-- Entry point, loaded last: state polling, slash commands, and events
local ADDON_NAME, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local NATIVE_CVAR_SCALING = ns.NATIVE_CVAR_SCALING
local NATIVE_CVAR_HIGHLIGHT = ns.NATIVE_CVAR_HIGHLIGHT
local NATIVE_CVAR_PROMPTS = ns.NATIVE_CVAR_PROMPTS
local PANELS = ns.PANELS
local addon = ns.addon
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local Print = ns.Print
local SafeCall = ns.SafeCall
local IsSecret = ns.IsSecret
local EnsureDatabase = ns.EnsureDatabase
local EnsureCharacterDatabase = ns.EnsureCharacterDatabase
local GetPaddleKey = ns.GetPaddleKey
local GetKeyDisplayName = ns.GetKeyDisplayName
local SetPanelPosition = ns.SetPanelPosition
local UpdatePanelVisibility = ns.UpdatePanelVisibility
local UpdatePanelVisibility = ns.UpdatePanelVisibility
local InitializeNativeStorage = ns.InitializeNativeStorage
local UpdateRangeIndicator = ns.UpdateRangeIndicator
local UpdateButtonVisual = ns.UpdateButtonVisual
local OnSpellAlertEvent = ns.OnSpellAlertEvent
local SetSpellAlertTest = ns.SetSpellAlertTest
local ClearButtonAction = ns.ClearButtonAction
local UpdateFocusFades = ns.UpdateFocusFades
local UpdatePanelVisualState = ns.UpdatePanelVisualState
local CreateUI = ns.CreateUI
local ForEachButton = ns.ForEachButton
local UpdateAllButtonVisuals = ns.UpdateAllButtonVisuals
local UpdateActionFlashes = ns.UpdateActionFlashes
local RefreshButtons = ns.RefreshButtons
local BindPaddlesToPanel = ns.BindPaddlesToPanel
local RegisterSecureFrameRefs = ns.RegisterSecureFrameRefs
local SetupSecurePanelDriver = ns.SetupSecurePanelDriver
local TryHookNativeTriggerDriver = ns.TryHookNativeTriggerDriver
local CacheGamepadButtonIndices = ns.CacheGamepadButtonIndices
local StopInputWatcher = ns.StopInputWatcher
local ClearLearnedPaddleMapping = ns.ClearLearnedPaddleMapping
local UpdateInputWatcher = ns.UpdateInputWatcher
local StartRawInputTest = ns.StartRawInputTest
local StartPaddleLearning = ns.StartPaddleLearning
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState
local ApplyPaddleKeys = ns.ApplyPaddleKeys
local SetPaddleKey = ns.SetPaddleKey
local StartKeyCapture = ns.StartKeyCapture
local ToggleGuideFrame = ns.ToggleGuideFrame
local ApplyAppearance = ns.ApplyAppearance
local PrintDiagnostics = ns.PrintDiagnostics
local ShowDiagnosticsFrame = ns.ShowDiagnosticsFrame
local RegisterSettings = ns.RegisterSettings
local OpenSettings = ns.OpenSettings
local RefreshControllerProfile = ns.RefreshControllerProfile
local HandleControllerCommand = ns.HandleControllerCommand
local GetPaddleBehavior = ns.GetPaddleBehavior
local ParsePaddleBehavior = ns.ParsePaddleBehavior
local SetPaddleBehavior = ns.SetPaddleBehavior

local statePollElapsed = 0
local rangePollElapsed = 0
local RANGE_POLL_INTERVAL = 0.25

local function OnNativeModifierStateChanged()
    UpdatePanelVisualState(GetVisualPanelFromGamepadState())
end

local function RegisterNativeModifierCallback()
    if ns.nativeModifierCallbackRegistered
        or type(GamepadMode) ~= "table"
        or type(GamepadMode.RegisterCrossBarModifierStateChanged) ~= "function" then
        return
    end

    local ok = pcall(GamepadMode.RegisterCrossBarModifierStateChanged, OnNativeModifierStateChanged, addon)
    ns.nativeModifierCallbackRegistered = ok == true
end

-- Polls IsActionInRange for native-storage slots that hold an action. See
-- SetRangeCheckEnabled for why the client's push-based range checks are not used.
local function PollRangeIndicators()
    if type(IsActionInRange) ~= "function" then
        return
    end
    ForEachButton(function(button)
        if button.rangeCheckEnabled and button.hasAction and button.actionSlot then
            local inRange = SafeCall(IsActionInRange, button.actionSlot)
            if IsSecret(inRange) then
                -- Range is secret for this action right now; hide the dot
                -- rather than compare a value the addon may not read.
                UpdateRangeIndicator(button, false, false)
            else
                UpdateRangeIndicator(button, inRange ~= nil, inRange == true)
            end
        end
    end)
end

local function StartStatePoller()
    addon:SetScript("OnUpdate", function(_, elapsed)
        UpdateFocusFades()
        ns.UpdateNativeFades()
        UpdateActionFlashes(elapsed)

        rangePollElapsed = rangePollElapsed + elapsed
        if rangePollElapsed >= RANGE_POLL_INTERVAL then
            rangePollElapsed = 0
            PollRangeIndicators()
        end

        statePollElapsed = statePollElapsed + elapsed
        if statePollElapsed < 0.035 then
            return
        end
        statePollElapsed = 0

        if ns.inputWatcher then
            UpdateInputWatcher()
        end

        local panelIndex = GetVisualPanelFromGamepadState()
        UpdatePanelVisualState(panelIndex)

        -- If Forever is not exposing LT/RT as emulated secure modifiers, we
        -- can still follow the real controller state outside combat.
        if not ns.securePanelDriverRegistered and not focusRouting.enabled and not InCombatLockdown() and panelIndex ~= ns.lastBoundPanel then
            BindPaddlesToPanel(panelIndex)
        end
    end)
end

local function ParsePanelArgument(value)
    value = value and value:upper() or ""
    if value == "1" or value == "BASE" or value == "NONE" then
        return 1
    elseif value == "2" or value == "LT" then
        return 2
    elseif value == "3" or value == "RT" then
        return 3
    elseif value == "4" or value == "BOTH" or value == "LTRT" or value == "LT+RT" then
        return 4
    end
    return nil
end

local function ClearSlot(panelArg, paddleArg)
    local panelIndex = ParsePanelArgument(panelArg)
    local paddleIndex = tonumber(paddleArg)
    if not panelIndex or not paddleIndex or paddleIndex ~= math.floor(paddleIndex)
        or paddleIndex < 1 or paddleIndex > PADDLE_COUNT then
        Print("Usage: /grip clear <base|lt|rt|both> <1-4>")
        return
    end

    ClearButtonAction(buttons[panelIndex][paddleIndex])
    Print(string.format("Cleared %s P%d.", PANELS[panelIndex].label, paddleIndex))
end

-- /grip paddle [1-4] [actions|prev|next]
local function HandlePaddleCommand(paddleArg, behaviorArg)
    local paddleIndex = tonumber(paddleArg)
    if paddleArg and (not paddleIndex or paddleIndex ~= math.floor(paddleIndex)
        or paddleIndex < 1 or paddleIndex > PADDLE_COUNT) then
        Print("Usage: /grip paddle [1-4] [actions|prev|next]")
        return
    end

    if paddleIndex and behaviorArg then
        local value = ParsePaddleBehavior(behaviorArg)
        if not value then
            Print("Usage: /grip paddle [1-4] [actions|prev|next]")
            return
        end
        SetPaddleBehavior(paddleIndex, value)
        if InCombatLockdown() then
            Print("The new paddle behavior applies after combat.")
        end
    end

    for index = 1, PADDLE_COUNT do
        if not paddleIndex or index == paddleIndex then
            Print(string.format("%s: %s", PaddleName(index), GetPaddleBehavior(index).label))
        end
    end
end

local function PaddleName(index)
    return ns.GetPaddleName and ns.GetPaddleName(index) or ("P" .. tostring(index))
end

local function PrintHelp()
    Print("Commands (/gripbar works the same as /grip):")
    Print("/grip spread [top|bottom] [x y] | reset - show or set how far the paddles sit from their bar centre (default top 26 32, bottom 26 32)")
    Print("/grip clear <base|lt|rt|both> <1-4> - clear one paddle action")
    Print("/grip or /grip options - open native settings")
    Print("/grip diag - show native gamepad integration diagnostics")
    Print("/grip diag copy - open the diagnostics as copyable text")
    Print("/grip badge [lt|rt|both] [x y | reset] - move the native LT / RT / LT + RT badges under the crossbar bars")
    Print("/grip binds [assign <2|3> | clear [2|3] | <2|3> <button> <KEY>] - keys that fire a button's slot on crossbar page 2 or 3 without switching to it")
    Print("/grip wand - toggle: swap melee and wand (X shoots the wand, RB + X swings) on a living enemy")
    Print("/grip atlas - copyable report of the native crossbar art (to match the L4 / R4 / L5 / R5 glyphs)")
    Print("/grip guide - open the setup guide (Xbox Accessories / Steam Input steps, live input readout)")
    Print("/grip assign [1-4] - assign one paddle, or all four in order, by pressing it")
    Print("/grip keys [P1 P2 P3 P4 | reset] - show or set the inputs, e.g. /grip keys F13 F14 F15 F16")
    Print("/grip controller [auto|elite|edge|steam|razer|generic] - show or set the controller profile (button names and glyphs)")
    Print("/grip paddle [1-4] [actions|prev|next] - show or set what a paddle does: its actions, or crossbar paging")
    Print("/grip test - print which raw controller buttons fire when you press the paddles")
    Print("/grip glowtest - toggle the proc glow on every filled slot, to check that it draws")
    Print("/grip learn - press P1-P4 in order to map them to PADPADDLE1-4 in the client's gamepad config")
    Print("/grip learn clear - remove the addon's device config again")
    Print("/grip learn force - allow rebinding raw buttons the client already uses (steals them from the native UI)")
end

SLASH_GRIPBAR1 = "/grip"
SLASH_GRIPBAR2 = "/gripbar"
SlashCmdList.GRIPBAR = function(message)
    local args = {}
    for token in message:gmatch("%S+") do
        args[#args + 1] = token
    end

    local command = (args[1] or ""):lower()
    if command == "" or command == "options" or command == "settings" then
        OpenSettings()
    elseif command == "badge" or command == "badges" then
        ns.HandleBadgeCommand(args)
    elseif command == "wand" or command == "wandshoot" then
        ns.ToggleWandShoot()
    elseif command == "binds" or command == "bind" or command == "long" then
        ns.HandleBindsCommand(args)
    elseif command == "atlas" or command == "art" then
        ns.ShowAtlasReport()
    elseif command == "spread" then
        -- /grip spread [top|bottom] <x> <y>, or /grip spread reset
        local option = (args[2] or ""):lower()
        local L = ns.LAYOUT
        local function Clamp(value)
            return math.max(0, math.min(L.PADDLE_SPREAD_MAX, value))
        end
        if option == "reset" then
            GripbarDB.spreadTopX, GripbarDB.spreadTopY = L.SPREAD_TOP_X, L.SPREAD_TOP_Y
            GripbarDB.spreadBottomX, GripbarDB.spreadBottomY = L.SPREAD_BOTTOM_X, L.SPREAD_BOTTOM_Y
        elseif args[2] then
            local rows = { top = true, bottom = true }
            local first = 2
            if option == "top" then
                rows.bottom = false
                first = 3
            elseif option == "bottom" then
                rows.top = false
                first = 3
            end
            local x, y = tonumber(args[first]), tonumber(args[first + 1] or args[first])
            if not x or not y then
                Print("Usage: /grip spread [top|bottom] <x> <y>  (0-200, default top 26 32, bottom 26 32), or /grip spread reset")
                return
            end
            if rows.top then
                GripbarDB.spreadTopX, GripbarDB.spreadTopY = Clamp(x), Clamp(y)
            end
            if rows.bottom then
                GripbarDB.spreadBottomX, GripbarDB.spreadBottomY = Clamp(x), Clamp(y)
            end
        end
        if args[2] then
            if InCombatLockdown() then
                ns.pendingAppearanceRefresh = true
                Print("The new spread applies after combat.")
            else
                ApplyAppearance()
            end
        end
        Print(string.format("Paddle spread: top row %d / %d, bottom row %d / %d (horizontal / vertical).",
            GripbarDB.spreadTopX, GripbarDB.spreadTopY, GripbarDB.spreadBottomX, GripbarDB.spreadBottomY))
    elseif command == "clear" then
        ClearSlot(args[2], args[3])
    elseif command == "diag" or command == "diagnostics" then
        local option = (args[2] or ""):lower()
        if option == "copy" or option == "window" then
            ShowDiagnosticsFrame()
        else
            PrintDiagnostics()
        end
    elseif command == "guide" or command == "setup" then
        ToggleGuideFrame()
    elseif command == "assign" then
        local paddleIndex = tonumber(args[2])
        if paddleIndex and paddleIndex >= 1 and paddleIndex <= PADDLE_COUNT then
            StartKeyCapture(paddleIndex, false)
        else
            StartKeyCapture(1, true)
        end
    elseif command == "keys" then
        local option = (args[2] or ""):lower()
        if option == "" then
            for paddleIndex = 1, PADDLE_COUNT do
                Print(string.format("%s: %s", PaddleName(paddleIndex), GetKeyDisplayName(GetPaddleKey(paddleIndex))))
            end
        elseif option == "reset" then
            for paddleIndex = 1, PADDLE_COUNT do
                SetPaddleKey(paddleIndex, "PADPADDLE" .. paddleIndex, true)
            end
            ApplyPaddleKeys(true)
            Print("Paddle inputs reset to the native paddle keys.")
        else
            for paddleIndex = 1, PADDLE_COUNT do
                if args[paddleIndex + 1] then
                    SetPaddleKey(paddleIndex, args[paddleIndex + 1], true)
                end
            end
            ApplyPaddleKeys(true)
            for paddleIndex = 1, PADDLE_COUNT do
                Print(string.format("%s: %s", PaddleName(paddleIndex), GetKeyDisplayName(GetPaddleKey(paddleIndex))))
            end
        end
    elseif command == "paddle" or command == "behavior" then
        HandlePaddleCommand(args[2], args[3])
    elseif command == "controller" then
        HandleControllerCommand(args[2])
    elseif command == "glowtest" then
        ns.spellAlertTestEnabled = not ns.spellAlertTestEnabled
        local shown, failed = SetSpellAlertTest(ns.spellAlertTestEnabled)
        if ns.spellAlertTestEnabled then
            Print(string.format("Glow test on: %d slot(s) glowing, %d failed to create the glow. Type /grip glowtest again to stop.", shown, failed))
        else
            Print("Glow test off.")
        end
    elseif command == "test" then
        StartRawInputTest()
    elseif command == "learn" then
        local option = (args[2] or ""):lower()
        if option == "cancel" or option == "stop" then
            StopInputWatcher("Learning cancelled; nothing was changed.")
        elseif option == "clear" or option == "reset" then
            StopInputWatcher(nil)
            ClearLearnedPaddleMapping()
        else
            StartPaddleLearning(option == "force")
        end
    else
        PrintHelp()
    end
end

local NATIVE_STYLE_CVARS = {
    [NATIVE_CVAR_SCALING] = true,
    [NATIVE_CVAR_HIGHLIGHT] = true,
    [NATIVE_CVAR_PROMPTS] = true,
}

local MODIFIER_EMULATION_CVARS = {
    GamePadEmulateShift = true,
    GamePadEmulateCtrl = true,
    GamePadEmulateAlt = true,
}

-- The reserved paddle slots were picked because they were empty, not because
-- the native crossbar can never address them. Stance bars have their own
-- storage blocks and the client only reveals the active one, so check each
-- stance as it becomes active and warn once if it shares slots with a paddle.
local stanceOverlapWarned = {}
local function CheckStanceOverlap()
    if not ns.nativeStorageEnabled or not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance) ~= "function" then
        return
    end
    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    if type(first) ~= "number" or stanceOverlapWarned[first] then
        return
    end
    local constants = Constants and Constants.GamepadActionBarConstants or {}
    local last = first + (constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8) - 1
    local overlap
    ns.ForEachReservedSlot(function(slot)
        if not overlap and slot >= first and slot <= last then
            overlap = slot
        end
    end)
    if overlap then
        stanceOverlapWarned[first] = true
        Print(string.format(
            "Warning: this stance bar uses action slots %d-%d, which include paddle slot %d. Actions placed on either may replace each other. Please report this with /grip diag output.",
            first, last, overlap
        ))
    end
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
addon:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
addon:RegisterEvent("ACTIONBAR_UPDATE_STATE")
addon:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
addon:RegisterEvent("SPELL_UPDATE_USABLE")
addon:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
addon:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
addon:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
addon:RegisterEvent("UPDATE_MACROS")
addon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addon:RegisterEvent("SPELL_UPDATE_CHARGES")
addon:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
addon:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
addon:RegisterEvent("BAG_UPDATE_COOLDOWN")
addon:RegisterEvent("BAG_UPDATE_DELAYED")
addon:RegisterEvent("ITEM_DATA_LOAD_RESULT")
-- Active, auto-repeat and equipped states (ActionBarActionButtonMixin:OnEvent).
addon:RegisterEvent("START_AUTOREPEAT_SPELL")
addon:RegisterEvent("STOP_AUTOREPEAT_SPELL")
addon:RegisterEvent("PLAYER_ENTER_COMBAT")
addon:RegisterEvent("PLAYER_LEAVE_COMBAT")
addon:RegisterEvent("TRADE_SKILL_SHOW")
addon:RegisterEvent("TRADE_SKILL_CLOSE")
addon:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
addon:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
addon:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
addon:RegisterEvent("GAME_PAD_CONFIGS_CHANGED")
addon:RegisterEvent("GAME_PAD_CONNECTED")
addon:RegisterEvent("GAME_PAD_DISCONNECTED")
addon:RegisterEvent("CVAR_UPDATE")
addon:RegisterEvent("GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED")
addon:RegisterEvent("GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED")

addon:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        EnsureDatabase()
        EnsureCharacterDatabase()
        RefreshControllerProfile()
        InitializeNativeStorage()
        CreateUI()
        RegisterSecureFrameRefs()
        CacheGamepadButtonIndices()
        BindPaddlesToPanel(GetVisualPanelFromGamepadState())
        SetupSecurePanelDriver()
        RegisterNativeModifierCallback()
        UpdatePanelVisibility()
        ApplyAppearance()
        RegisterSettings()
        StartStatePoller()
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if not ns.settingsRegistered then
            RegisterSettings()
        end
        -- Re-anchor to the native crossbar in case it did not exist yet when
        -- the panels were created and they fell back to screen coordinates.
        if not InCombatLockdown() then
            for panelIndex = 1, PANEL_COUNT do
                SetPanelPosition(panelIndex)
            end
        end
        CacheGamepadButtonIndices()
        RefreshControllerProfile()
        CheckStanceOverlap()
        RegisterNativeModifierCallback()
        if not InCombatLockdown() then
            BindPaddlesToPanel(GetVisualPanelFromGamepadState())
            C_Timer.After(0.5, function()
                TryHookNativeTriggerDriver()
            end)
        end
        UpdateAllButtonVisuals()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingSecureRefresh then
            ns.pendingSecureRefresh = false
            RefreshButtons()
            RegisterSecureFrameRefs()
            BindPaddlesToPanel(GetVisualPanelFromGamepadState())
        else
            -- Button states that were secret in combat showed as off;
            -- read them again now that they are readable.
            UpdateAllButtonVisuals()
        end
        if ns.pendingAppearanceRefresh then
            ApplyAppearance()
        end
        TryHookNativeTriggerDriver()
        return
    end

    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        UpdatePanelVisibility()
        return
    end

    if event == "GAME_PAD_CONNECTED" or event == "GAME_PAD_DISCONNECTED" then
        RefreshControllerProfile()
        return
    end

    if event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONFIGS_CHANGED" then
        CacheGamepadButtonIndices()
        RefreshControllerProfile()
        UpdatePanelVisibility()
        C_Timer.After(0.2, function()
            if not InCombatLockdown() then
                BindPaddlesToPanel(GetVisualPanelFromGamepadState())
            end
            TryHookNativeTriggerDriver()
        end)
        return
    end

    if event == "CVAR_UPDATE" then
        local cvarName = tostring(arg1 or "")
        if MODIFIER_EMULATION_CVARS[cvarName] then
            TryHookNativeTriggerDriver()
        elseif NATIVE_STYLE_CVARS[cvarName] then
            ApplyAppearance()
        end
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        local changedSlot = tonumber(arg1) or 0
        if ns.nativeStorageEnabled and changedSlot > 0 then
            ForEachButton(function(button)
                if button.actionSlot == changedSlot then
                    UpdateButtonVisual(button)
                end
            end)
        elseif ns.nativeStorageEnabled then
            -- Slot 0 means every slot changed.
            UpdateAllButtonVisuals()
        else
            RefreshButtons()
        end
        return
    end

    if event == "ACTION_RANGE_CHECK_UPDATE" then
        local changedSlot = not IsSecret(arg1) and tonumber(arg1) or nil
        if changedSlot then
            local secret = IsSecret(arg2) or IsSecret(arg3)
            ForEachButton(function(button)
                if button.actionSlot == changedSlot then
                    if secret then
                        UpdateRangeIndicator(button, false, false)
                    else
                        UpdateRangeIndicator(button, arg3 == true, arg2 == true)
                    end
                end
            end)
        end
        return
    end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnSpellAlertEvent(arg1, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        return
    end

    if event == "GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED" or event == "GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED" then
        RefreshButtons()
        CheckStanceOverlap()
        return
    end

    if event == "UPDATE_MACROS" then
        -- Macro bodies feed the secure attributes of fallback slots.
        RefreshButtons()
        return
    end

    if event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "ACTIONBAR_UPDATE_STATE"
        or event == "ACTIONBAR_UPDATE_USABLE"
        or event == "SPELL_UPDATE_USABLE"
        or event == "SPELL_UPDATE_COOLDOWN"
        or event == "SPELL_UPDATE_CHARGES"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE"
        or event == "BAG_UPDATE_COOLDOWN"
        or event == "BAG_UPDATE_DELAYED"
        or event == "ITEM_DATA_LOAD_RESULT"
        or event == "START_AUTOREPEAT_SPELL"
        or event == "STOP_AUTOREPEAT_SPELL"
        or event == "PLAYER_ENTER_COMBAT"
        or event == "PLAYER_LEAVE_COMBAT"
        or event == "TRADE_SKILL_SHOW"
        or event == "TRADE_SKILL_CLOSE"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateAllButtonVisuals()
    end
end)
