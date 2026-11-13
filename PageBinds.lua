-- page binds.
--
-- Keys that fire the crossbar's page 2 and page 3 slots without switching to
-- those pages. Each of the twelve inputs (d-pad, A / B / X / Y, the four grips)
-- can get one key per page, for example sent by a Steam Input long press:
--
--   page 2 key of X          -> page 2, X slot of the bar the triggers select
--   LT + page 2 key of X     -> page 2, X slot of the LT bar (LT emulates a modifier)
--   page 3 key of L4 (grip)  -> page 3 of the paddle slot
--
-- LT / RT reach WoW as emulated Shift / Ctrl / Alt (GamePadEmulate* CVars),
-- so one key per input and page covers all four trigger layers: KEY,
-- LTMOD-KEY, RTMOD-KEY and both. Each (page, layer, input) gets a hidden
-- secure action button pointed at that page's native storage slot; the keys
-- are bound to them with override bindings, out of combat. The top bar's
-- A / B / X / Y hold locked system actions on pages 2-3 and are not bound.
local _, ns = ...

local Print = ns.Print
local SafeCall = ns.SafeCall

local PAGES = { 2, 3 }

-- The twelve inputs, in the order they are listed and assigned.
local INPUTS = {
    { key = "dpadup", label = "D-pad Up", group = "left", atlas = "dpadup", index = 2 },
    { key = "dpadright", label = "D-pad Right", group = "left", atlas = "dpadright", index = 3 },
    { key = "dpaddown", label = "D-pad Down", group = "left", atlas = "dpaddown", index = 4 },
    { key = "dpadleft", label = "D-pad Left", group = "left", atlas = "dpadleft", index = 1 },
    { key = "y", label = "Y", group = "right", atlas = "%-y%-", index = 6 },
    { key = "b", label = "B", group = "right", atlas = "%-b%-", index = 7 },
    { key = "a", label = "A", group = "right", atlas = "%-a%-", index = 8 },
    { key = "x", label = "X", group = "right", atlas = "%-x%-", index = 5 },
    { key = "grip1", paddle = 1 },
    { key = "grip2", paddle = 2 },
    { key = "grip3", paddle = 3 },
    { key = "grip4", paddle = 4 },
}

-- Layers in panel order: 1 no trigger (top bar), 2 LT (left bar), 3 RT
-- (right bar), 4 LT + RT (bottom bar).
local BAR_ANCHORS = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }
local BAR_KEYS = { "topBar", "leftBar", "rightBar", "bottomBar" }

local owner = CreateFrame("Frame", "GripbarPageBindOwner", UIParent)
local secureButtons = {} -- ["page:layer:index"] = button
local status = "not set up"

local function InputLabel(input)
    if input.paddle then
        local name = ns.GetPaddleName and ns.GetPaddleName(input.paddle) or ("P" .. input.paddle)
        return "Grip " .. name
    end
    return input.label
end

local function KeysForPage(page)
    local all = GripbarDB and GripbarDB.pageBindKeys
    return all and all[page]
end

local function GetKey(page, index)
    local keys = KeysForPage(page)
    local key = keys and keys[INPUTS[index].key]
    return type(key) == "string" and key ~= "" and key or nil
end

-- The emulated modifier ("SHIFT", "CTRL", "ALT") a trigger produces, or nil.
local function TriggerModifier(trigger)
    for _, m in ipairs({ { "GamePadEmulateShift", "SHIFT" }, { "GamePadEmulateCtrl", "CTRL" }, { "GamePadEmulateAlt", "ALT" } }) do
        local value = ns.GetGamepadEmulationCVar and ns.GetGamepadEmulationCVar(m[1])
        if value == trigger then
            return m[2]
        end
    end
    return nil
end

-- Binding strings for one key on each layer, in the client's canonical
-- modifier order (ALT, CTRL, SHIFT). nil where a trigger has no modifier.
local function LayerBindings(key)
    local lt, rt = TriggerModifier("PADLTRIGGER"), TriggerModifier("PADRTRIGGER")
    local function Join(mods)
        table.sort(mods)
        if #mods == 0 then
            return key
        end
        return table.concat(mods, "-") .. "-" .. key
    end
    return {
        Join({}),
        lt and Join({ lt }) or nil,
        rt and Join({ rt }) or nil,
        (lt and rt and lt ~= rt) and Join({ lt, rt }) or nil,
    }
end

-- Native crossbar button for a layer's bar and an input, found by its slot
-- art (gamepad-actionbar-*slot-*-dpadup-normal, ...-xbox-a-normal) with the
-- known button order as the fallback.
local function FindNativeButton(layer, input)
    local pageUnit = _G.GamepadMainActionBarFramePageUnit
        or (_G.GamepadMainActionBarFrame and _G.GamepadMainActionBarFrame.PageUnit)
    local anchor = pageUnit and pageUnit[BAR_ANCHORS[layer]]
    local bars = pageUnit and pageUnit.actionBars
    local bar = (bars and bars[BAR_KEYS[layer]]) or (anchor and anchor.Bar)
    if not bar or type(bar.GetActionButtonByIndex) ~= "function" then
        return nil
    end
    for i = 1, 8 do
        local button = bar:GetActionButtonByIndex(i)
        local art = button and button.SlotArt
        local atlas = art and type(art.GetAtlas) == "function" and art:GetAtlas()
        if atlas then
            local slotKind = input.group == "left" and "squareslot" or "circleslot"
            if atlas:find(slotKind, 1, true) and atlas:find(input.atlas) then
                return button
            end
        end
    end
    return bar:GetActionButtonByIndex(input.index)
end

-- The action slot a bind fires for a page, layer and input, or nil.
local function ResolveSlot(layer, input, page)
    if input.paddle then
        if not ns.nativeStorageEnabled or page > (ns.pageCount or 1) then
            return nil
        end
        return ns.GetNativeSlot(layer, input.paddle, page)
    end
    local util = _G.GamepadActionBarBindingUtil
    local button = FindNativeButton(layer, input)
    if not util or not button or not button.pageUnitSlotID then
        return nil
    end
    return SafeCall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, page, button.pageUnitSlotID)
end

local function GetSecureButton(page, layer, index)
    local id = page .. ":" .. layer .. ":" .. index
    local button = secureButtons[id]
    if not button then
        button = CreateFrame("Button", string.format("GripbarPage%d_%d_%d", page, layer, index), UIParent, "SecureActionButtonTemplate")
        button:SetSize(1, 1)
        button:SetAlpha(0)
        button:EnableMouse(false)
        button:RegisterForClicks("AnyUp", "AnyDown")
        -- Steam sends the key when its activator fires: act on the press.
        button:SetAttribute("useOnKeyDown", true)
        button:SetAttribute("type", "action")
        secureButtons[id] = button
    end
    return button
end

local function ApplyPageBinds()
    if InCombatLockdown() then
        ns.pendingPageBinds = true
        return
    end
    ns.pendingPageBinds = false
    ClearOverrideBindings(owner)

    local parts = {}
    for _, page in ipairs(PAGES) do
        local bound, missing = 0, 0
        for index, input in ipairs(INPUTS) do
            local key = GetKey(page, index)
            if key then
                local bindings = LayerBindings(key)
                for layer = 1, 4 do
                    local binding = bindings[layer]
                    -- The top bar's A / B / X / Y are locked system actions
                    -- (jump, interact, ...) on pages past the first.
                    local locked = layer == 1 and input.group == "right"
                    local slot = not locked and ResolveSlot(layer, input, page) or nil
                    if binding and slot then
                        local button = GetSecureButton(page, layer, index)
                        button:SetAttribute("action", slot)
                        SetOverrideBindingClick(owner, true, binding, button:GetName(), "LeftButton")
                        bound = bound + 1
                    elseif binding and not locked then
                        missing = missing + 1
                    end
                end
            end
        end
        parts[#parts + 1] = string.format("page %d: %d bindings%s", page, bound,
            missing > 0 and string.format(" (%d slots not found)", missing) or "")
    end
    status = table.concat(parts, "; ")
end

local function SetPageBindKey(page, index, key)
    GripbarDB.pageBindKeys = GripbarDB.pageBindKeys or {}
    GripbarDB.pageBindKeys[page] = GripbarDB.pageBindKeys[page] or {}
    GripbarDB.pageBindKeys[page][INPUTS[index].key] = key
    ApplyPageBinds()
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
end

-- Press-to-assign: one input at a time, or all twelve of a page in order.
local capture
local function StopCapture(message)
    if capture then
        capture.frame:Hide()
        capture.active = false
    end
    if message then
        Print(message)
    end
end

local IGNORED = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

local function UpdateCaptureText()
    local input = INPUTS[capture.index]
    capture.frame.text:SetText(string.format(
        "Page %d bind: |cffffd100%s|r\nPress its key (or the controller input Steam Input maps to it).\nCurrently: %s.  Esc skips / cancels, Delete clears.",
        capture.page, InputLabel(input), GetKey(capture.page, capture.index) or "not set"))
end

local function StartCapture(page, index, sequence)
    if InCombatLockdown() then
        Print("Page binds cannot be assigned during combat.")
        return
    end
    if not capture then
        local frame = CreateFrame("Frame", "GripbarPageBindCapture", UIParent, "BackdropTemplate")
        frame:SetSize(480, 130)
        frame:SetPoint("CENTER", 0, 140)
        frame:SetFrameStrata("TOOLTIP")
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.text:SetPoint("CENTER")
        frame.text:SetWidth(440)
        frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if not capture or not capture.active or IGNORED[key] then
                return
            end
            local page, current = capture.page, capture.index
            if key == "ESCAPE" then
                if capture.sequence and current < #INPUTS then
                    capture.index = current + 1
                    UpdateCaptureText()
                else
                    StopCapture("Page bind assignment finished.")
                end
                return
            end
            if key == "DELETE" or key == "BACKSPACE" then
                SetPageBindKey(page, current, nil)
                Print(string.format("%s: page %d bind cleared.", InputLabel(INPUTS[current]), page))
            else
                local existing = GetBindingAction and GetBindingAction(key, false)
                SetPageBindKey(page, current, key)
                Print(string.format("%s: page %d bind = %s%s", InputLabel(INPUTS[current]), page, key,
                    (existing and existing ~= "") and (" (overrides " .. existing .. ")") or ""))
            end
            if capture.sequence and current < #INPUTS then
                capture.index = current + 1
                UpdateCaptureText()
            else
                StopCapture()
            end
        end)
        capture = { frame = frame }
    end
    capture.page = page
    capture.index = index or 1
    capture.sequence = sequence == true
    capture.active = true
    UpdateCaptureText()
    capture.frame:Show()
end

local function PrintStatus()
    ApplyPageBinds()
    Print("Page binds: " .. status .. ". Keys (page 2 / page 3; each also works with LT, RT, LT+RT):")
    for index, input in ipairs(INPUTS) do
        Print(string.format("  %s: %s / %s", InputLabel(input), GetKey(2, index) or "-", GetKey(3, index) or "-"))
    end
end

local USAGE = "Usage: /grip binds [assign <2|3> [1-12] | clear [2|3] | <2|3> <dpadup|dpadright|dpaddown|dpadleft|y|b|a|x|grip1-4> <KEY|clear>]"

-- /grip binds [assign <page> [n] | clear [page] | <page> <input> <KEY|clear>]
local function HandleBindsCommand(args)
    local sub = (args[2] or ""):lower()
    if sub == "assign" then
        local page = tonumber(args[3]) or 2
        if page ~= 2 and page ~= 3 then
            Print(USAGE)
            return
        end
        local n = tonumber(args[4])
        if n and INPUTS[n] then
            StartCapture(page, n, false)
        else
            StartCapture(page, 1, true)
        end
        return
    elseif sub == "clear" then
        local page = tonumber(args[3])
        GripbarDB.pageBindKeys = GripbarDB.pageBindKeys or {}
        for _, p in ipairs(PAGES) do
            if not page or page == p then
                GripbarDB.pageBindKeys[p] = {}
            end
        end
    elseif sub == "2" or sub == "3" then
        local page = tonumber(sub)
        local name = (args[3] or ""):lower()
        for index, input in ipairs(INPUTS) do
            if input.key == name then
                local value = args[4] and args[4]:upper() or nil
                SetPageBindKey(page, index, (value and value ~= "CLEAR") and value or nil)
                PrintStatus()
                return
            end
        end
        Print(USAGE)
        return
    elseif sub ~= "" then
        Print(USAGE)
        return
    end
    PrintStatus()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" and not ns.pendingPageBinds then
        return
    end
    if event == "CVAR_UPDATE" and not (type(name) == "string" and name:find("GamePadEmulate")) then
        return
    end
    ApplyPageBinds()
end)

ns.PAGE_BIND_PAGES = PAGES
ns.PAGE_BIND_INPUTS = INPUTS
ns.PageBindInputLabel = InputLabel
ns.GetPageBindKey = GetKey
ns.StartPageBindCapture = StartCapture
ns.ApplyPageBinds = ApplyPageBinds
ns.HandleBindsCommand = HandleBindsCommand
ns.GetPageBindStatus = function()
    return status
end
