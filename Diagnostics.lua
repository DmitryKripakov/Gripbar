-- /grip diag: the diagnostics report and its copyable viewer
local ADDON_NAME, ns = ...

local NATIVE_CVAR_SCALING = ns.NATIVE_CVAR_SCALING
local NATIVE_CVAR_HIGHLIGHT = ns.NATIVE_CVAR_HIGHLIGHT
local NATIVE_CVAR_PROMPTS = ns.NATIVE_CVAR_PROMPTS
local PANELS = ns.PANELS
local secureDriver = ns.secureDriver
local panelFrames = ns.panelFrames
local focusRouting = ns.focusRouting
local missingAtlases = ns.missingAtlases
local Print = ns.Print
local SafeCall = ns.SafeCall
local GetNativeCVarBool = ns.GetNativeCVarBool
local GetPaddleKey = ns.GetPaddleKey
local IsGamepadInterfaceActive = ns.IsGamepadInterfaceActive
local DiscoverNativeStorageSlots = ns.DiscoverNativeStorageSlots
local GetGamepadEmulationCVar = ns.GetGamepadEmulationCVar
local GetMappedButtonArrayIndex = ns.GetMappedButtonArrayIndex
local GetMappedState = ns.GetMappedState
local GetPaddleRawMappingDiagnostic = ns.GetPaddleRawMappingDiagnostic
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState
local IsNativeCrossbarFocused = ns.IsNativeCrossbarFocused
local GetControllerDiagnosticLines = ns.GetControllerDiagnosticLines
local GetSpellAlertDiagnosticLines = ns.GetSpellAlertDiagnosticLines

local function GetMappedDiagnosticValues()
    local state = GetMappedState()
    if not state then
        return "unavailable"
    end

    local ltLuaIndex = GetMappedButtonArrayIndex(state, ns.ltButtonIndex)
    local rtLuaIndex = GetMappedButtonArrayIndex(state, ns.rtButtonIndex)
    local ltValue = ltLuaIndex ~= nil and state.buttons and state.buttons[ltLuaIndex]
    local rtValue = rtLuaIndex ~= nil and state.buttons and state.buttons[rtLuaIndex]
    local tableBase = state.buttons and state.buttons[0] ~= nil and 0 or 1

    return string.format(
        "tableBase=%d   LT index=%s/lua=%s/value=%s   RT index=%s/lua=%s/value=%s",
        tableBase,
        tostring(ns.ltButtonIndex), tostring(ltLuaIndex), tostring(ltValue),
        tostring(ns.rtButtonIndex), tostring(rtLuaIndex), tostring(rtValue)
    )
end

local function GetModifierDiagnosticValues()
    return string.format(
        "Shift=%s   Ctrl=%s   Alt=%s",
        tostring(GetGamepadEmulationCVar("GamePadEmulateShift")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateCtrl")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateAlt"))
    )
end

local function GetNativeArtDiagnostic()
    local missing = missingAtlases.count or 0
    if missing == 0 then
        return "all native crossbar atlases found"
    end

    local names = {}
    for name, flagged in pairs(missingAtlases) do
        if flagged == true and name ~= "count" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return string.format("%d native atlases missing (using bundled art): %s", missing, table.concat(names, ", "))
end

local function GetNativeStyleDiagnostic()
    return string.format(
        "scaling=%s   highlight=%s   prompts=%s",
        tostring(GetNativeCVarBool(NATIVE_CVAR_SCALING, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_PROMPTS, true))
    )
end

-- Crossbar buttons fire their slot plus 12 per action-bar page past the
-- first, so any page but 1 shifts the native crossbar by one bar per page.
-- An unreleased build paged paddles that way and could leave it on page 2.
local function GetActionBarPageDiagnostic()
    local get = (C_ActionBar and C_ActionBar.GetActionBarPage) or GetActionBarPage
    local page = get and SafeCall(get)
    if type(page) ~= "number" then
        return "Action bar page: unknown"
    elseif page == 1 then
        return "Action bar page: 1"
    end
    return string.format("Action bar page: %d (should be 1: every crossbar button fires the slot %d further on; switch back with Shift+1 or /run ChangeActionBarPage(1))", page, (page - 1) * 12)
end

local function GetDiagnosticLines(separator)
    local firstStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    local stanceStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    local petStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local ltAction = GetBindingAction("PADLTRIGGER", true)
    local rtAction = GetBindingAction("PADRTRIGGER", true)
    local securePanelIndex = tonumber(secureDriver:GetAttribute("activePanel")) or 1
    local visualPanelIndex = GetVisualPanelFromGamepadState()
    local securePanelText = PANELS[securePanelIndex].label
    if focusRouting.enabled then
        local focusPanel = focusRouting.GetPanel()
        securePanelText = (focusPanel and PANELS[focusPanel].label or "native crossbar missing") .. " (from native crossbar focus)"
    end

    local lines = {
        "Storage mode: " .. (ns.nativeStorageEnabled and "native C_GamepadUI action slots" or "SavedVariables fallback"),
        "Storage detail: " .. ns.nativeStorageStatus,
        "Storage scope: actions and reserved slots are per character; crossbar pages: " .. tostring(ns.nativePageStatus),
        "Swap melee and wand: " .. (ns.GetWandShootStatus and ns.GetWandShootStatus() or "?"),
        "Page binds: " .. (ns.GetPageBindStatus and ns.GetPageBindStatus() or "?"),
        "Native badges: " .. (ns.GetBadgeDiagnostic and ns.GetBadgeDiagnostic() or "?"),
        string.format("Gamepad storage: first=%s%sstance=%s%spet=%s", tostring(firstStorage), separator, tostring(stanceStorage), separator, tostring(petStorage)),
        "Panel driver: " .. ns.nativeHookStatus,
        string.format("LT binding: %s%sRT binding: %s", tostring(ltAction), separator, tostring(rtAction)),
        "Modifier CVars: " .. GetModifierDiagnosticValues(),
        "Mapped state: " .. GetMappedDiagnosticValues(),
        "Paddle raw mapping: " .. GetPaddleRawMappingDiagnostic(),
        string.format("Paddle inputs: P1=%s   P2=%s   P3=%s   P4=%s",
            tostring(GetPaddleKey(1)), tostring(GetPaddleKey(2)), tostring(GetPaddleKey(3)), tostring(GetPaddleKey(4))),
        "Paddle behaviors: " .. ns.GetPageNavigationDiagnostic(),
        GetActionBarPageDiagnostic(),
        "Interface style: " .. tostring(C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" and SafeCall(C_InputInterfaceStyle.GetCurrentStyle) or "unknown")
            .. " (CVar InputDeviceInterfaceStyle=" .. tostring(GetGamepadEmulationCVar("InputDeviceInterfaceStyle")) .. ")",
        "Panels shown: " .. tostring(panelFrames[1] and panelFrames[1]:IsShown()) .. " (gamepad interface=" .. tostring(IsGamepadInterfaceActive()) .. ", gamepad only=" .. tostring(GripbarDB.gamepadOnly ~= false) .. ")",
        "Visual detection: " .. ns.visualDetectionMethod .. (ns.nativeModifierCallbackRegistered and " (+ native crossbar callback)" or ""),
        "Visual panel: " .. PANELS[visualPanelIndex].label,
        "Native crossbar focused: " .. (IsNativeCrossbarFocused() and "yes" or "no (a menu has gamepad focus)"),
        "Visual expanded: " .. (panelFrames[visualPanelIndex] and panelFrames[visualPanelIndex].expanded and "yes" or "no"),
        "Secure panel: " .. securePanelText,
        "Native style CVars: " .. GetNativeStyleDiagnostic(),
        "Native art: " .. GetNativeArtDiagnostic(),
    }

    -- Next to the raw paddle mapping, which reads the same device.
    for offset, line in ipairs(GetControllerDiagnosticLines(separator)) do
        table.insert(lines, 8 + offset, line)
    end

    if ns.nativeStorageEnabled then
        local values = {}
        for _, slot in ipairs(ns.nativeStorageSlots) do
            values[#values + 1] = tostring(slot)
        end
        lines[#lines + 1] = "Reserved native slots: " .. table.concat(values, ", ")

        -- Checks the reservation against the slots the native crossbar
        -- addresses (GamepadActionBarBindingUtil): the standard pages, each
        -- with its reserved UI slots removed, plus the active stance bar.
        local constants = Constants and Constants.GamepadActionBarConstants or {}
        local pageSlots = (constants.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE or 32)
            - (constants.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 4)
        local pageCount = constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 3
        local barSlots = constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
        local ranges = {}
        if type(firstStorage) == "number" then
            ranges[#ranges + 1] = { label = "pages", first = firstStorage, last = firstStorage + pageSlots * pageCount - 1 }
        end
        if type(stanceStorage) == "number" then
            ranges[#ranges + 1] = { label = "active stance", first = stanceStorage, last = stanceStorage + barSlots - 1 }
        end

        local conflicts = {}
        for _, slot in ipairs(ns.nativeStorageSlots) do
            for _, range in ipairs(ranges) do
                if slot >= range.first and slot <= range.last then
                    conflicts[#conflicts + 1] = string.format("%d (%s)", slot, range.label)
                end
            end
        end

        local rangeText = {}
        for _, range in ipairs(ranges) do
            rangeText[#rangeText + 1] = string.format("%s %d-%d", range.label, range.first, range.last)
        end
        local pool = DiscoverNativeStorageSlots()
        if pool and #pool > 0 then
            rangeText[#rangeText + 1] = string.format("valid pool %d-%d", pool[1], pool[#pool])
        end
        if type(stanceStorage) ~= "number" then
            rangeText[#rangeText + 1] = "no stance active"
        end

        lines[#lines + 1] = string.format("Native slot check: %s%s%s",
            #conflicts == 0 and "OK" or ("CONFLICT " .. table.concat(conflicts, ", ")),
            separator,
            table.concat(rangeText, ", "))
    end

    for _, line in ipairs(GetSpellAlertDiagnosticLines()) do
        lines[#lines + 1] = line
    end

    return lines
end

-- Removes chat markup (colors, textures, atlases, hyperlinks) so the report
-- pastes cleanly into GitHub issues and Discord.
local function StripMarkup(text)
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|n", " ")
    text = text:gsub("||", "|")
    return text
end

-- Shared by /grip diag and the diagnostics viewer so both stay identical.
local function BuildDiagnosticLines()
    local version = C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function"
        and SafeCall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
        or (type(GetAddOnMetadata) == "function" and SafeCall(GetAddOnMetadata, ADDON_NAME, "Version"))
    local gameVersion, build, _, interfaceVersion
    if type(GetBuildInfo) == "function" then
        gameVersion, build, _, interfaceVersion = GetBuildInfo()
    end

    local lines = {
        string.format("Gripbar %s diagnostics", tostring(version or "unknown")),
        string.format("Client: %s (build %s, interface %s)", tostring(gameVersion), tostring(build), tostring(interfaceVersion)),
    }
    for _, line in ipairs(GetDiagnosticLines(" | ")) do
        lines[#lines + 1] = StripMarkup(line)
    end
    return lines
end

local function BuildDiagnostics()
    return table.concat(BuildDiagnosticLines(), "\n")
end

local function PrintDiagnostics()
    for _, line in ipairs(BuildDiagnosticLines()) do
        Print(line)
    end
end

local diagnosticsFrame

local function EnsureDiagnosticsFrame()
    if diagnosticsFrame then
        return diagnosticsFrame
    end

    local frame = CreateFrame("Frame", "GripbarDiagnosticsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 460)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -18)
    frame.title:SetText("Gripbar diagnostics")

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", 24, -44)
    frame.hint:SetWidth(592)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetText("Click Select All, then press Ctrl+C to copy the report. Paste it into a GitHub issue or support message.")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 24, -66)
    scrollFrame:SetPoint("BOTTOMRIGHT", -44, 48)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(566)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Read-only: typing into the box restores the report.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.text then
            self:SetText(frame.text)
            self:HighlightText()
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Clicking anywhere in the text area focuses the box and selects everything.
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    function frame:Refresh()
        self.text = (self.builder or BuildDiagnostics)()
        self.editBox:SetText(self.text)
        self.editBox:SetCursorPosition(0)
        if self.editBox:HasFocus() then
            self.editBox:HighlightText()
        end
    end

    frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refresh:SetSize(100, 22)
    frame.refresh:SetPoint("BOTTOMLEFT", 22, 16)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function()
        frame:Refresh()
    end)

    frame.selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAll:SetSize(100, 22)
    frame.selectAll:SetPoint("LEFT", frame.refresh, "RIGHT", 8, 0)
    frame.selectAll:SetText("Select All")
    frame.selectAll:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(100, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -22, 16)
    frame.close:SetText("Close")
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetScript("OnHide", function()
        editBox:ClearFocus()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GripbarDiagnosticsFrame")
    end

    frame:Hide()
    diagnosticsFrame = frame
    return frame
end

local function ShowDiagnosticsFrame()
    local frame = EnsureDiagnosticsFrame()
    frame.builder = nil
    frame.title:SetText("Gripbar diagnostics")
    frame:Show()
    frame:Refresh()
end

-- /grip atlas. Lists the atlases the native crossbar draws (to find
-- the empty-slot glyph style) and tests likely atlas names for paddle / grip
-- buttons, so the L4 / R4 / L5 / R5 slots can use native-looking art.
local GLYPH_TOKENS = { "A", "B", "X", "Y" }
local CANDIDATE_TOKENS = {
    "L4", "R4", "L5", "R5", "P1", "P2", "P3", "P4",
    "Paddle1", "Paddle2", "Paddle3", "Paddle4", "PADDLE1", "PADDLE2", "PADDLE3", "PADDLE4",
    "LeftPaddle1", "RightPaddle1", "LeftGrip", "RightGrip", "Share", "Social", "Back", "Forward",
}
local FIXED_CANDIDATES = {
    "Gamepad_Gen_Paddle1_64", "Gamepad_Gen_Paddle1_32", "Gamepad_Gen_P1_64", "Gamepad_Gen_P1_32",
    "Gamepad_Gen_L4_64", "Gamepad_Gen_L4_32", "Gamepad_Gen_R4_64", "Gamepad_Gen_L5_64",
    "Gamepad_Ltr_A_64", "Gamepad_Shp_Cross_64", "Gamepad_Gen_A_64", "Gamepad_Gen_A_32",
}

local function AtlasExists(name)
    return C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(name) ~= nil
end

local function RegionName(region)
    local key = type(region.GetParentKey) == "function" and region:GetParentKey()
    if key then
        return key
    end
    local name = type(region.GetDebugName) == "function" and region:GetDebugName() or nil
    return name and name:match("[^%.]+$") or "?"
end

local function BuildAtlasReport()
    local lines = {}
    local pageUnit = _G.GamepadMainActionBarFramePageUnit or (_G.GamepadMainActionBarFrame and _G.GamepadMainActionBarFrame.PageUnit)
    if not pageUnit then
        return "Native crossbar (GamepadMainActionBarFrame.PageUnit) not found. Turn on the gamepad interface and try again."
    end

    -- Every atlas used anywhere in the crossbar, with one region that uses it.
    local seen, found = {}, {}
    local function Scan(frame, depth)
        if not frame or depth > 8 then
            return
        end
        for _, region in ipairs({ frame:GetRegions() }) do
            if type(region.GetAtlas) == "function" then
                local atlas = region:GetAtlas()
                if atlas and not seen[atlas] then
                    seen[atlas] = true
                    found[#found + 1] = string.format("%s  (%s.%s, shown=%s)", atlas, RegionName(frame), RegionName(region), tostring(region:IsShown()))
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            Scan(child, depth + 1)
        end
    end
    Scan(pageUnit, 0)
    table.sort(found)
    lines[#lines + 1] = string.format("== Atlases in the native crossbar (%d) ==", #found)
    for _, line in ipairs(found) do
        lines[#lines + 1] = line
    end

    -- Every region of the top bar's first button, atlas or texture file.
    local bar = pageUnit.actionBars and pageUnit.actionBars.topBar
    local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(1)
    if button then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "== Top bar, button 1 regions =="
        local function Dump(frame, prefix, depth)
            if depth > 3 then
                return
            end
            for _, region in ipairs({ frame:GetRegions() }) do
                local atlas = type(region.GetAtlas) == "function" and region:GetAtlas() or nil
                local texture = not atlas and type(region.GetTexture) == "function" and region:GetTexture() or nil
                local text = type(region.GetText) == "function" and region:GetText() or nil
                lines[#lines + 1] = string.format("%s%s [%s] atlas=%s tex=%s text=%s shown=%s",
                    prefix, RegionName(region), region:GetObjectType(), tostring(atlas), tostring(texture), tostring(text), tostring(region:IsShown()))
            end
            for _, child in ipairs({ frame:GetChildren() }) do
                lines[#lines + 1] = prefix .. "+ " .. RegionName(child) .. " [" .. child:GetObjectType() .. "]"
                Dump(child, prefix .. "  ", depth + 1)
            end
        end
        Dump(button, "", 0)
    end

    -- Native glyph atlases with A / B / X / Y in their name, re-tried with
    -- paddle / grip tokens in place of the letter.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Paddle / grip variants of glyph atlases =="
    local tried, triedCount, hits = {}, 0, 0
    local function Try(name)
        if tried[name] then
            return
        end
        tried[name] = true
        triedCount = triedCount + 1
        if AtlasExists(name) then
            hits = hits + 1
            lines[#lines + 1] = "FOUND " .. name
        end
    end
    for atlas in pairs(seen) do
        local padded = "_" .. atlas .. "_"
        for _, letter in ipairs(GLYPH_TOKENS) do
            for _, form in ipairs({ letter, letter:lower() }) do
                local pattern = "([^%w])" .. form .. "([^%w])"
                if padded:find(pattern) then
                    for _, token in ipairs(CANDIDATE_TOKENS) do
                        for _, t in ipairs({ token, token:lower() }) do
                            local replaced = padded:gsub(pattern, "%1" .. t .. "%2", 1)
                            Try(replaced:sub(2, -2))
                        end
                    end
                end
            end
        end
    end
    for _, name in ipairs(FIXED_CANDIDATES) do
        Try(name)
    end
    if hits == 0 then
        lines[#lines + 1] = string.format("(none of %d candidates exist)", triedCount)
    end

    -- What Blizzard's own input prompt draws for paddle keys.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== InputIconTextureFrameTemplate prompts =="
    for _, key in ipairs({ "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4", "PAD1", "PAD2", "PADLSHOULDER", "PADSOCIAL" }) do
        local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent, "InputIconTextureFrameTemplate")
        if ok and frame and type(frame.SetInputKey) == "function" then
            pcall(frame.SetInputKey, frame, key)
            local parts = {}
            for _, region in ipairs({ frame:GetRegions() }) do
                local atlas = type(region.GetAtlas) == "function" and region:GetAtlas() or nil
                local texture = not atlas and type(region.GetTexture) == "function" and region:GetTexture() or nil
                if atlas or texture then
                    parts[#parts + 1] = RegionName(region) .. "=" .. tostring(atlas or texture)
                end
            end
            lines[#lines + 1] = key .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "(nothing)")
            frame:Hide()
        else
            lines[#lines + 1] = key .. ": template unavailable"
        end
    end

    return table.concat(lines, "\n")
end

local function ShowAtlasReport()
    local frame = EnsureDiagnosticsFrame()
    frame.builder = BuildAtlasReport
    frame.title:SetText("Gripbar native art report")
    frame:Show()
    frame:Refresh()
end



ns.PrintDiagnostics = PrintDiagnostics
ns.ShowDiagnosticsFrame = ShowDiagnosticsFrame
ns.ShowAtlasReport = ShowAtlasReport
