-- Own X / Y / B / A on the top bar.
--
-- The top bar's face buttons hold the game's fixed functions (Interact,
-- Inspect, Back, Jump) and take no actions. With this option on, each of
-- them gets two cells of our own: a normal one, and one used while a living
-- enemy is targeted (empty: the normal cell). A button whose cells are both
-- empty, or that shows nothing for the moment (the enemy cell empty, no
-- normal one), stays the game's own press.
--
-- The cells are buttons from the game's own crossbar button template
-- (GamepadActionBarButtonTemplate), set up the way the game's bar sets up
-- its own (Blizzard_GamepadActionBars: GamepadActionBarMixin:
-- InitActionButtons and the left-square / right-circle style): same ring,
-- face glyph, cooldowns, range, proc glow and cast animations. Each sits
-- inside the game's button (its child, on all its points), so it follows its
-- size, collapse / expand, fade and visibility; the game's own art goes
-- transparent under it, its shadow stays.
--
-- Input: priority override bindings on PAD3 / PAD4 / PAD2 / PAD1 (the game's
-- crossbar binds them the same way, on UIParent) while only the game's core
-- binding set is active, so menus that take the face buttons keep them.
-- LT / RT (emulated modifiers) + a face button go back to the game's binding;
-- with LB or RB held the press goes to the game's own handler (its shortcut
-- layers), and so does a press on a button that shows nothing of ours.
local _, ns = ...

local Print = ns.Print

-- X, Y, B, A: the game's face group order (Right.ActionButton1..4) and keys.
local FACES = {
    { name = "X", key = "PAD3" },
    { name = "Y", key = "PAD4" },
    { name = "B", key = "PAD2" },
    { name = "A", key = "PAD1" },
}
local PRESSED_INSET = 2 -- the game's pushed style: 4 smaller, 2 lower
local PRESSED_ATLAS = "gamepad-actionbar-circleslot-border-pressed"
local NORMAL_ATLAS = "gamepad-actionbar-circleslot-border-normal"
-- The game's art under ours; its shadows stay (they follow its own states).
local NATIVE_ART = { "icon", "SlotArt", "SpecialActionIcon", "Border", "SlotBackground",
    "HighlightTexture", "CheckedTexture", "Flash", "NewActionTexture", "SpellHighlightTexture" }

local copies = {}
local status = "off"
local pending = false
local lastError
local errorShown = false
local loggedStatus

local function TopBar()
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    return bars and bars.topBar
end

local function Native(index)
    local bar = TopBar()
    return bar and bar.Right and bar.Right["ActionButton" .. index]
end

local function PadIndex(binding)
    local index = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(binding)
    return index and index + 1 or nil
end

local function SetNativeArtAlpha(native, alpha)
    local textures = {
        native.NormalTexture or native:GetNormalTexture(),
        native.PushedTexture or native:GetPushedTexture(),
    }
    for _, key in ipairs(NATIVE_ART) do
        textures[#textures + 1] = native[key]
    end
    for _, texture in pairs(textures) do
        if texture and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

-- The header: the targeting state driver, the press wrappers, the bindings.
local header = CreateFrame("Frame", "GripbarTopFaceHeader", UIParent, "SecureHandlerStateTemplate")

-- Which cell each button shows: the enemy cell while a living enemy is
-- targeted and it holds something, else the normal cell when it holds
-- something, else none (the game's own button shows). While an action is
-- on the cursor every cell shows, so it can be dropped on (the enemy cell
-- while an enemy is targeted).
header:SetAttribute("gb-eval", [[
    local state = self:GetAttribute("gb-state") or "normal"
    local grid = self:GetAttribute("gb-grid")
    for i = 1, 4 do
        local copy = self:GetFrameRef("copy" .. i)
        if copy then
            local normal = copy:GetAttribute("gb-normal")
            local enemy = copy:GetAttribute("gb-enemy")
            local slot
            if state ~= "off" and self:GetAttribute("gb-on") then
                if state == "enemy" and enemy and (grid or HasAction(enemy)) then
                    slot = enemy
                elseif normal and (grid or HasAction(normal)) then
                    slot = normal
                end
            end
            if slot then
                copy:SetAttribute("action", slot)
                copy:SetAttribute("gb-route", "action")
                copy:SetAlpha(1)
            else
                if normal then
                    copy:SetAttribute("action", normal)
                end
                copy:SetAttribute("gb-route", "native")
                copy:SetAlpha(0)
            end
            copy:CallMethod("GBRouteChanged")
        end
    end
]])
header:SetAttribute("_onstate-gbface", [[
    self:SetAttribute("gb-state", newstate)
    self:RunAttribute("gb-eval")
]])

-- A press: with LB / RB held, or on a button that shows nothing of ours,
-- the game's own handler gets the press and the release (a held jump keeps
-- rising). Else our cell's action, on the press, with the game's pushed look.
local PRECLICK = [[
    local pad = GetGamePadState()
    pad = pad and pad.buttons
    local lb, rb = self:GetAttribute("gb-lb"), self:GetAttribute("gb-rb")
    local shoulder = pad and ((lb and pad[lb]) or (rb and pad[rb]))
    if down then
        self:SetAttribute("gb-relay", (shoulder or self:GetAttribute("gb-route") ~= "action") and true or nil)
    end
    if self:GetAttribute("gb-relay") then
        self:SetAttribute("type", "macro")
        self:SetAttribute("useOnKeyDown", down and true or false)
        self:SetAttribute("macrotext", "/click " .. self:GetAttribute("gb-native") .. " LeftButton" .. (down and " true" or ""))
        if not down then
            self:SetAttribute("gb-relay", nil)
        end
        return
    end
    self:SetAttribute("type", "action")
    self:SetAttribute("useOnKeyDown", true)
    local parent = self:GetParent()
    self:ClearAllPoints()
    if down then
        local inset = self:GetAttribute("gb-inset") or 2
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -2 * inset)
        self:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, 0)
    else
        self:SetAllPoints(parent)
    end
    self:CallMethod("GBPressed", down)
]]

local function CreateCopy(index)
    local native = Native(index)
    if not native then
        return nil
    end
    -- Made once per session: a frame by this name is ours already.
    local name = "GripbarTopFace" .. FACES[index].name
    local copy = _G[name] or CreateFrame("CheckButton", name, native,
        "GamepadActionBarButtonTemplate,SecureActionButtonTemplate")
    copy.gbIndex = index
    copy.gbNative = native
    copy:SetAllPoints(native)
    copy:SetFrameLevel(native:GetFrameLevel() + 2)
    -- The face glyph beside the button (X / Y / B / A, shown while the bar
    -- has focus) is the game's own: a frame its bar template gives each of
    -- its buttons. It stays the game's, drawn above ours.
    if native.ButtonIcon then
        native.ButtonIcon:SetFrameLevel(native:GetFrameLevel() + 6)
    end
    copy:RegisterForClicks("AnyDown", "AnyUp")
    copy:SetAttribute("type", "action")
    copy:SetAttribute("useOnKeyDown", true)
    copy:SetAttribute("gb-inset", PRESSED_INSET)

    -- As the game's bar does for its own face buttons.
    copy:SetButtonIndexOnActionBar(4 + index)
    copy:SetActionBarParent(TopBar())
    copy:SetAttribute("showgrid", 1)
    if copy.HotKey then
        copy.HotKey:Hide()
        copy.HotKey.Show = function() end
    end
    copy:UpdateButtonArt()
    copy:SetShapeToCircle()
    -- Whatever redraws it square (the base art update does), it stays round.
    hooksecurefunc(copy, "SetShapeToSquare", function(self)
        self:SetShapeToCircle()
        self.CircleShadow:SetAlpha(0)
        self.SquareShadow:SetAlpha(0)
    end)
    -- The game's shadow under ours is drawn by its button, in every state.
    copy.CircleShadow:SetAlpha(0)
    copy.SquareShadow:SetAlpha(0)
    if native.collapsed then
        copy:Collapse()
    else
        copy:Expand()
    end

    function copy:GBRouteChanged()
        local ours = self:GetAttribute("gb-route") == "action"
        SetNativeArtAlpha(native, ours and 0 or 1)
    end

    function copy:GBPressed(down)
        local normal = self:GetNormalTexture()
        if normal then
            normal:SetAtlas(down and PRESSED_ATLAS or NORMAL_ATLAS)
        end
    end

    header:WrapScript(copy, "OnClick", PRECLICK)
    header:SetFrameRef("copy" .. index, copy)
    return copy
end

-- The game's crossbar collapses and expands its buttons (LT / RT, focus):
-- ours update their cast and interrupt animation anchors the same way.
local styleHooked = false
local function HookStyle()
    if styleHooked or not (GamepadActionBarStyleUtil and GamepadActionBarStyleUtil.ApplyExtraButtonStyles) then
        return
    end
    styleHooked = true
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyExtraButtonStyles", function(button)
        for _, copy in pairs(copies) do
            if copy.gbNative == button then
                if button.collapsed then
                    copy:Collapse()
                else
                    copy:Expand()
                end
            end
        end
    end)
end

-- The emulated modifier ("SHIFT", "CTRL", "ALT") an input produces, or nil.
local function EmulatedModifier(input)
    for _, m in ipairs({ { "GamePadEmulateShift", "SHIFT" }, { "GamePadEmulateCtrl", "CTRL" }, { "GamePadEmulateAlt", "ALT" } }) do
        local value = ns.GetGamepadEmulationCVar and ns.GetGamepadEmulationCVar(m[1])
        if value == input then
            return m[2]
        end
    end
    return nil
end

-- A face key with the triggers (and shoulders, when they emulate modifiers)
-- held: those go back to the game's binding.
local function ModifiedVariants(key)
    local mods = {}
    for _, input in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER" }) do
        local mod = EmulatedModifier(input)
        if mod and not tContains(mods, mod) then
            mods[#mods + 1] = mod
        end
    end
    table.sort(mods)
    local variants = {}
    -- Every non-empty combination, in the client's order (ALT-CTRL-SHIFT).
    for mask = 1, 2 ^ #mods - 1 do
        local parts = {}
        for i, mod in ipairs(mods) do
            if bit.band(mask, 2 ^ (i - 1)) ~= 0 then
                parts[#parts + 1] = mod
            end
        end
        variants[#variants + 1] = table.concat(parts, "-") .. "-" .. key
    end
    return variants
end

local function Enabled()
    return GripbarDB and GripbarDB.topFace == true and ns.topFaceSlots ~= nil
end

local function CoreBindingsOnly()
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if manager and manager.IsOnlyCoreBindingSetActive then
        local ok, only = pcall(manager.IsOnlyCoreBindingSetActive, manager)
        return not ok or only
    end
    return true
end

local function CellsFilled(index)
    local slots = ns.topFaceSlots
    return slots and (C_ActionBar.HasAction(slots[index]) or C_ActionBar.HasAction(slots[4 + index]))
end

local gridShown = false

-- Out of combat: copies, cell slots, bindings.
local function ApplyTopFace()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    ClearOverrideBindings(header)

    local on = Enabled()
    if on then
        HookStyle()
        for index in ipairs(FACES) do
            if not copies[index] and not lastError then
                local ok, result = pcall(CreateCopy, index)
                if ok then
                    copies[index] = result
                else
                    lastError = FACES[index].name .. ": " .. tostring(result)
                end
            end
        end
    end
    header:SetAttribute("gb-on", on or nil)
    header:SetAttribute("gb-grid", (on and gridShown) or nil)

    local taken = 0
    for index, face in ipairs(FACES) do
        local copy = copies[index]
        local ok, err = pcall(function()
        if copy then
            copy:SetAttribute("gb-normal", ns.topFaceSlots and ns.topFaceSlots[index] or nil)
            copy:SetAttribute("gb-enemy", ns.topFaceSlots and ns.topFaceSlots[4 + index] or nil)
            copy:SetAttribute("gb-native", "InputFunctionBindingButton_" .. face.key)
            copy:SetAttribute("gb-lb", PadIndex("PADLSHOULDER"))
            copy:SetAttribute("gb-rb", PadIndex("PADRSHOULDER"))
            if on then
                copy:Show()
            else
                copy:Hide()
                SetNativeArtAlpha(copy.gbNative, 1)
            end
            -- Bound while a cell holds something (or an action is being
            -- dragged), and only while the game's core bindings are on top.
            if on and (gridShown or CellsFilled(index)) and CoreBindingsOnly() then
                SetOverrideBindingClick(header, true, face.key, copy:GetName(), "LeftButton")
                local native = "CLICK InputFunctionBindingButton_" .. face.key .. ":LeftButton"
                for _, variant in ipairs(ModifiedVariants(face.key)) do
                    SetOverrideBinding(header, true, variant, native)
                end
                taken = taken + 1
            end
        end
        end)
        if not ok then
            lastError = face.name .. ": " .. tostring(err)
        end
    end
    SecureHandlerExecute(header, [[ self:RunAttribute("gb-eval") ]])

    if not GripbarDB or GripbarDB.topFace ~= true then
        status = "off"
    elseif not ns.topFaceSlots then
        status = "on, but no free action slots for the cells (" .. tostring(ns.topFaceStatus) .. ")"
    elseif not copies[1] then
        status = "on, but the game's top bar was not found"
    else
        status = string.format("on: %d of 4 buttons with actions%s", taken,
            CoreBindingsOnly() and "" or " (a menu holds the face buttons)")
    end
    if status ~= loggedStatus and ns.Log then
        loggedStatus = status
        ns.Log("topface", status)
    end
    if lastError then
        status = status .. "; error " .. lastError
        if not errorShown then
            errorShown = true
            Print("Own X / Y / B / A: " .. status)
        end
    end
end

-- The targeting state: the enemy cell while a living enemy is targeted; the
-- game's own buttons in a vehicle, possessing or on an override bar.
RegisterStateDriver(header, "gbface", "[vehicleui][possessbar][overridebar] off; [@target,harm,nodead] enemy; normal")

local function Toggle()
    GripbarDB.topFace = GripbarDB.topFace ~= true
    ApplyTopFace()
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
    Print("Own X / Y / B / A: " .. status .. ".")
end

-- The game binds its face keys again when a menu closes (a binding set
-- leaves its stack): ours go back on top afterwards.
local function HookBindingStack()
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if not manager then
        return
    end
    local queued = false
    local function Later()
        if Enabled() and not queued then
            queued = true
            C_Timer.After(0, function()
                queued = false
                ApplyTopFace()
            end)
        end
    end
    for _, method in ipairs({ "AddBindingSet", "RemoveSet", "ClearBindings", "SetCoreBindingSet" }) do
        if type(manager[method]) == "function" then
            hooksecurefunc(manager, method, Later)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:RegisterEvent("ACTIONBAR_SHOWGRID")
events:RegisterEvent("ACTIONBAR_HIDEGRID")
events:SetScript("OnEvent", function(_, event, slot)
    if event == "PLAYER_LOGIN" then
        HookBindingStack()
    elseif event == "PLAYER_REGEN_ENABLED" and not pending then
        return
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        local slots = ns.topFaceSlots
        if slot ~= 0 and not (slots and tContains(slots, slot)) then
            return
        end
    elseif event == "ACTIONBAR_SHOWGRID" then
        gridShown = true
    elseif event == "ACTIONBAR_HIDEGRID" then
        gridShown = false
    end
    if GripbarDB then
        ApplyTopFace()
    end
end)

ns.ApplyTopFace = ApplyTopFace
ns.ToggleTopFace = Toggle
ns.GetTopFaceStatus = function()
    return status
end
