-- Controller profile: which paddle controller is in use (Xbox Elite, DualSense
-- Edge or anything else), detected from the active gamepad or chosen in the
-- settings. The profile only describes the controller; nothing here changes
-- paddle keys or actions.
local _, ns = ...

local Print = ns.Print
local SafeCall = ns.SafeCall
local FindRawInputDevice = ns.FindRawInputDevice

-- names = what the slots, settings and chat call each slot (P1 top
-- left, P2 top right, P3 bottom left, P4 bottom right); glyphs = the
-- engraved Media\Glyph* texture each empty slot shows (default "Glyph" ..
-- name, then "GlyphP1".."GlyphP4").
local PROFILES = {
    xboxElite = { key = "xboxElite", label = "Xbox Elite / Scuf", maxPaddles = 4 },
    -- Front Fn buttons on the top row, the two back buttons on the bottom row
    -- (drawn with the lower paddle shapes).
    dualsenseEdge = { key = "dualsenseEdge", label = "DualSense Edge", maxPaddles = 4,
        names = { "Fn L", "Fn R", "Back L", "Back R" },
        glyphs = { "GlyphFn", "GlyphFn", "GlyphP3", "GlyphP4" } },
    -- Razer Wolverine / Kishi / Raiju: multi-function buttons M1-M4.
    razer = { key = "razer", label = "Razer (M1-M4)", maxPaddles = 4, names = { "M1", "M2", "M3", "M4" } },
    -- Steam Controller / Steam Deck grip buttons. Names follow the
    -- slot layout: L4 / L5 by the d-pad (upper / lower), R4 / R5 by the face
    -- buttons.
    steamController = { key = "steamController", label = "Steam Controller", maxPaddles = 4, names = { "L4", "R4", "L5", "R5" } },
    custom = { key = "custom", label = "Generic", maxPaddles = 4 },
}

-- Order of the choices in the settings and /grip controller.
local PROFILE_CHOICES = { "auto", "xboxElite", "dualsenseEdge", "steamController", "razer", "custom" }

local VENDOR_MICROSOFT = 0x045E
local VENDOR_SONY = 0x054C
local VENDOR_VALVE = 0x28DE
local VENDOR_RAZER = 0x1532

-- Product IDs differ by transport and firmware, so there is a list per
-- controller and the device name is checked as well. 0x02FF is what the
-- client's own Elite Series 2 config uses (README); Windows reports other
-- Xbox pads with it too, which is harmless because the generic profile has
-- the same four paddles. Steam Input presents every controller as an Xbox 360
-- pad (0x028E), so behind Steam only the manual choice can tell them apart.
local KNOWN_DEVICES = {
    [VENDOR_MICROSOFT] = {
        [0x02E3] = "xboxElite", -- Elite (first generation)
        [0x02FF] = "xboxElite", -- client's Elite Series 2 config
        [0x0B00] = "xboxElite", -- Elite Series 2, USB
        [0x0B05] = "xboxElite", -- Elite Series 2, Bluetooth
        [0x0B22] = "xboxElite", -- Elite Series 2, Bluetooth (newer firmware)
    },
    [VENDOR_SONY] = {
        [0x0DF2] = "dualsenseEdge",
    },
    [VENDOR_VALVE] = {
        [0x1102] = "steamController", -- Steam Controller, USB
        [0x1142] = "steamController", -- Steam Controller, wireless dongle
        [0x1205] = "steamController", -- Steam Deck
    },
}

local function DetectProfileKey(device)
    local byVendor = device.vendorID and KNOWN_DEVICES[device.vendorID]
    local key = byVendor and device.productID and byVendor[device.productID]
    if key then
        return key
    end
    local name = type(device.name) == "string" and device.name:lower() or ""
    if name:find("elite", 1, true) then
        return "xboxElite"
    end
    if name:find("dualsense edge", 1, true) then
        return "dualsenseEdge"
    end
    if device.vendorID == VENDOR_VALVE or name:find("steam", 1, true) then
        return "steamController"
    end
    if device.vendorID == VENDOR_RAZER or name:find("razer", 1, true) or name:find("wolverine", 1, true) then
        return "razer"
    end
    return "custom"
end

-- Reads the active (or first available) gamepad. Returns nil when no
-- controller is connected.
local function ReadDevice()
    local deviceID, raw = FindRawInputDevice()
    if not raw then
        return nil
    end
    local mapped = C_GamePad and type(C_GamePad.GetDeviceMappedState) == "function"
        and SafeCall(C_GamePad.GetDeviceMappedState, deviceID) or nil
    return {
        deviceID = deviceID,
        name = raw.name,
        vendorID = tonumber(raw.vendorID),
        productID = tonumber(raw.productID),
        labelStyle = type(mapped) == "table" and mapped.labelStyle or nil,
    }
end

local function GetProfileSetting()
    local setting = GripbarDB and GripbarDB.controllerProfile
    if setting == "auto" or PROFILES[setting] then
        return setting
    end
    return "auto"
end

-- The last controller seen. Kept while no controller is connected so the
-- profile does not flip back to generic every time the pad goes to sleep.
local lastDevice

-- Rebuilds ns.controllerProfile from the setting and the active controller.
local function RefreshControllerProfile()
    local device = ReadDevice()
    if device then
        lastDevice = device
    end
    local known = device or lastDevice or {}

    local setting = GetProfileSetting()
    local detectedKey = DetectProfileKey(known)
    local key = setting == "auto" and detectedKey or setting
    local profile = PROFILES[key]

    local previous = ns.controllerProfile
    ns.controllerProfile = {
        key = key,
        label = profile.label,
        maxPaddles = profile.maxPaddles,
        names = profile.names,
        glyphs = profile.glyphs,
        detectedKey = detectedKey,
        manual = setting ~= "auto",
        connected = device ~= nil,
        deviceID = known.deviceID,
        name = known.name,
        vendorID = known.vendorID,
        productID = known.productID,
        labelStyle = known.labelStyle,
    }

    -- The Settings button shows the mode as well as the profile ("Auto (Xbox
    -- Elite)"), so switching between Auto and a manual setting that resolves
    -- to the same profile must refresh it too.
    local changed = not previous
        or previous.key ~= key
        or previous.manual ~= ns.controllerProfile.manual
        or previous.detectedKey ~= detectedKey
    if changed and ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
    if changed and previous and ns.UpdateAllButtonVisuals then
        ns.UpdateAllButtonVisuals()
    end
    return ns.controllerProfile
end

local function GetControllerProfile()
    return ns.controllerProfile or RefreshControllerProfile()
end

-- the paddle's name in the active profile ("L4" on the Steam
-- Controller), or "P1".."P4".
local function GetPaddleName(paddleIndex)
    local profile = ns.controllerProfile
    local names = profile and profile.names
    return (names and names[paddleIndex]) or ("P" .. tostring(paddleIndex))
end

-- the engraved glyph texture for a slot's empty state.
local function GetPaddleGlyph(paddleIndex)
    local profile = ns.controllerProfile
    local glyph = profile and profile.glyphs and profile.glyphs[paddleIndex]
    if glyph then
        return glyph
    end
    return "Glyph" .. GetPaddleName(paddleIndex)
end

local function GetProfileChoiceLabel(setting)
    if setting == "auto" then
        local profile = GetControllerProfile()
        return "Auto (" .. PROFILES[profile.detectedKey].label .. ")"
    end
    return PROFILES[setting].label
end

local function SetControllerProfileSetting(setting)
    GripbarDB.controllerProfile = setting
    RefreshControllerProfile()
end

-- Steps the setting to the next choice, for the settings button.
local function CycleControllerProfileSetting()
    local current = GetProfileSetting()
    for index, setting in ipairs(PROFILE_CHOICES) do
        if setting == current then
            SetControllerProfileSetting(PROFILE_CHOICES[index % #PROFILE_CHOICES + 1])
            return
        end
    end
    SetControllerProfileSetting("auto")
end

local function FormatID(value)
    if type(value) ~= "number" then
        return "?"
    end
    return string.format("%d (0x%04X)", value, value)
end

local function GetControllerDiagnosticLines(separator)
    local profile = RefreshControllerProfile()
    local deviceText
    if profile.vendorID then
        deviceText = string.format("%s%sdevice %s%svendor %s%sproduct %s%slabelStyle=%s",
            tostring(profile.name), separator,
            tostring(profile.deviceID), separator,
            FormatID(profile.vendorID), separator,
            FormatID(profile.productID), separator,
            tostring(profile.labelStyle))
        if not profile.connected then
            deviceText = deviceText .. " (last seen, none connected now)"
        end
    else
        deviceText = "none connected"
    end
    return {
        "Controller: " .. deviceText,
        string.format("Controller profile: %s, %d paddles (%s)",
            profile.label, profile.maxPaddles,
            profile.manual and ("set manually; auto-detect says " .. PROFILES[profile.detectedKey].label) or "auto-detected"),
    }
end

-- /grip controller [auto|elite|edge|generic]
local PROFILE_ARGUMENTS = {
    auto = "auto",
    elite = "xboxElite", xbox = "xboxElite", xboxelite = "xboxElite",
    edge = "dualsenseEdge", dualsense = "dualsenseEdge", dualsenseedge = "dualsenseEdge",
    steam = "steamController", steamcontroller = "steamController", deck = "steamController", steamdeck = "steamController",
    razer = "razer", wolverine = "razer", kishi = "razer", m = "razer",
    scuf = "xboxElite",
    generic = "custom", custom = "custom",
}

local function HandleControllerCommand(argument)
    if argument and argument ~= "" then
        local setting = PROFILE_ARGUMENTS[argument:lower()]
        if not setting then
            Print("Usage: /grip controller [auto|elite|edge|steam|razer|generic]")
            return
        end
        SetControllerProfileSetting(setting)
    end
    local profile = RefreshControllerProfile()
    Print(string.format("Controller profile: %s (%s).", profile.label,
        profile.manual and "set manually" or "auto-detected"))
end

ns.RefreshControllerProfile = RefreshControllerProfile
ns.GetControllerProfile = GetControllerProfile
ns.GetPaddleName = GetPaddleName
ns.GetPaddleGlyph = GetPaddleGlyph
ns.GetProfileChoiceLabel = GetProfileChoiceLabel
ns.GetProfileSetting = GetProfileSetting
ns.CycleControllerProfileSetting = CycleControllerProfileSetting
ns.GetControllerDiagnosticLines = GetControllerDiagnosticLines
ns.HandleControllerCommand = HandleControllerCommand
