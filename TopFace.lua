-- Own X / Y / B / A on the top bar, and on the LB / RB targeting bars.
--
-- The top bar's face buttons hold the game's fixed functions (Interact,
-- Inspect, Back, Jump), and the bars the game shows while LB or RB is held
-- (friendly / hostile targeting) hold its targeting shortcuts. With this
-- option on, each face button gets cells of our own:
--   * normal: the top bar;
--   * enemy: the top bar while a living enemy is targeted (empty: normal);
--   * LB, RB: the targeting bar while that bumper is held.
-- A cell that holds nothing leaves the game's own button and press.
--
-- The art is drawn the way Gripbar's paddle slots are (Buttons.lua: the
-- game's own ring, glyph, cooldown, count and glow atlases on plain frames),
-- over the game's buttons, whose own art goes transparent under ours. Nothing
-- of the game's crossbar is created from its templates or touched by
-- addon code in combat, so its secure code stays untainted.
--
-- Input: one secure button per face, bound with priority override bindings
-- on PAD3 / PAD4 / PAD2 / PAD1 (and LB's / RB's emulated modifier with them)
-- while only the game's core bindings are active, so menus keep their keys.
-- LT / RT + a face button go back to the game's binding. A press that finds
-- no action of ours clicks the game's own button of that layer instead.
local _, ns = ...

local Print = ns.Print

-- X, Y, B, A: the game's face group order (Right.ActionButton1..4), keys and
-- the targeting bars' fields for the same buttons.
local FACES = {
    { name = "X", key = "PAD3", field = "faceLeftButton" },
    { name = "Y", key = "PAD4", field = "faceTopButton" },
    { name = "B", key = "PAD2", field = "faceRightButton" },
    { name = "A", key = "PAD1", field = "faceBottomButton" },
}
local LAYER_BARS = { lb = "friendlyTargetingBar", rb = "hostileTargetingBar" }
local TRIGGER_BARS = { lt = "leftBar", rt = "rightBar", ltrt = "bottomBar" }
-- Both bumpers held: the game's shortcuts bar (no cells of ours there).
local BOTH_BUMPERS_BAR = "shortcutsBar"
local CELL_OFFSET = { normal = 0, enemy = 4, lb = 8, rb = 12 }
local EDIT_MODES = { "normal", "enemy", "lb", "rb" }
local EDIT_LABELS = { normal = "normal cells", enemy = "enemy cells", lb = "LB cells", rb = "RB cells" }
local PRESSED_OFFSET = 4 -- the game's pushed style: 4 smaller, 2 lower
-- The game's art under ours; its shadows stay (they follow its own states).
local NATIVE_ART = { "icon", "SlotArt", "SpecialActionIcon", "IconOverlay", "Border", "SlotBackground",
    "HighlightTexture", "CheckedTexture", "Flash", "NewActionTexture", "SpellHighlightTexture" }

local faces = {}       -- per face: { secure, top = display, lb = display, rb = display }
local status = "off"
local pending = false
local gridShown = false
local lastError
local loggedStatus

local function Bars()
    local main = _G.GamepadMainActionBarFrame
    return main and main.PageUnit and main.PageUnit.actionBars
end

local function NativeButton(layer, index)
    local bars = Bars()
    if not bars then
        return nil
    end
    if layer == "top" or TRIGGER_BARS[layer] then
        local bar = layer == "top" and bars.topBar or bars[TRIGGER_BARS[layer]]
        return bar and bar.Right and bar.Right["ActionButton" .. index], bar
    end
    local bar = bars[layer == "lbrb" and BOTH_BUMPERS_BAR or LAYER_BARS[layer]]
    return bar and bar[FACES[index].field], bar
end

local function Cell(index, kind)
    return ns.topFaceSlots and ns.topFaceSlots[CELL_OFFSET[kind] + index]
end

local function PadIndex(binding)
    local index = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(binding)
    return index and index + 1 or nil
end

local function SetNativeArtAlpha(native, alpha)
    if not native then
        return
    end
    local textures = { native:GetNormalTexture(), native:GetPushedTexture() }
    for _, key in ipairs(NATIVE_ART) do
        textures[#textures + 1] = native[key]
    end
    for _, texture in pairs(textures) do
        if texture and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

---------------------------------------------------------------------------
-- Displays: our art over one of the game's buttons.
---------------------------------------------------------------------------

local function LayoutDisplay(display)
    local holder, visual = display.holder, display.visual
    local width, height = holder:GetSize()
    if not width or width < 1 then
        return
    end
    visual:ClearAllPoints()
    if display.pushed then
        visual:SetPoint("CENTER", holder, "CENTER", 0, -PRESSED_OFFSET / 2)
        visual:SetSize(width - PRESSED_OFFSET, height - PRESSED_OFFSET)
    else
        visual:SetAllPoints(holder)
    end
    if visual.count and visual.countFont then
        local ratio = width / ns.LAYOUT.BUTTON_SIZE_EXPANDED
        local fontSize = visual.countFontSize * ratio * ns.LAYOUT.COUNT_TEXT_SCALE
        visual.count:SetFont(visual.countFont, math.max(7, math.floor(fontSize + 0.5)), visual.countFontFlags)
        visual.count:ClearAllPoints()
        visual.count:SetPoint("BOTTOMRIGHT", -5 * ratio, 5 * ratio)
    end
    if visual.spellAlert then
        visual.spellAlert:SetSize(width * 1.4, height * 1.4)
    end
    local pressed = display.pushed and visual.borderPressed.artAvailable
    visual.borderPressed:SetShown(pressed)
    visual.border:SetShown(not pressed)
end

local function CreateDisplay(native, bar, mini)
    -- On the bar (not the button): the targeting bars dim their disabled
    -- buttons, which must not dim ours.
    local holder = CreateFrame("Frame", nil, bar)
    if mini then
        -- The small cell in the button's lower right corner: from its centre
        -- to a little past its corner, so it follows the button's size.
        holder:SetPoint("TOPLEFT", native, "CENTER", 3, -3)
        holder:SetPoint("BOTTOMRIGHT", native, "BOTTOMRIGHT", 5, -5)
    else
        holder:SetAllPoints(native)
        holder:SetFrameLevel(native:GetFrameLevel() + 3)
    end
    holder:Hide()
    local display = { isFace = true, isMini = mini, native = native, holder = holder, hasAction = false, flashing = false, flashTime = 0, pushed = false }
    local visual = ns.BuildSlotVisual(display, holder, nil)
    display.visual = visual
    visual:SetFrameLevel(holder:GetFrameLevel() + 1)
    -- The game's own slot art (its face glyph) under the icon; the shadow is
    -- the game's button's own.
    local glyph = not mini and native.SlotArt and native.SlotArt:GetAtlas()
    if glyph then
        visual.slotArt:SetAtlas(glyph)
    end
    visual.shadow:SetAlpha(0)
    visual.shadowFocus:SetAlpha(0)
    visual.emptyGlyph:Hide()
    holder:SetScript("OnSizeChanged", function()
        LayoutDisplay(display)
    end)
    LayoutDisplay(display)
    ns.RegisterExtraDisplay(display)
    return display
end

-- Shows a display with a slot (ours), or hides it (the game's button shows).
local function ShowDisplay(display, slot)
    if not display then
        return
    end
    local ours = slot ~= nil
    if slot then
        display.actionSlot = slot
    end
    display.holder:SetShown(ours)
    if not display.isMini then
        display.holder:SetFrameLevel(display.native:GetFrameLevel() + 3)
        SetNativeArtAlpha(display.native, ours and 0 or 1)
    end
    if ours then
        ns.UpdateButtonVisual(display)
    end
end

local function SetDisplayPushed(display, pushed)
    if display and display.pushed ~= pushed then
        display.pushed = pushed
        LayoutDisplay(display)
    end
end

-- The targeting bars' cells: shown while they hold something.
local function RefreshLayerDisplays()
    for index, face in pairs(faces) do
        for layer in pairs(LAYER_BARS) do
            local slot = Cell(index, layer)
            ShowDisplay(face[layer], (GripbarDB.topFace == true and slot and C_ActionBar.HasAction(slot)) and slot or nil)
        end
    end
end

---------------------------------------------------------------------------
-- Secure side: the header (target state, cells shown), one button per face.
---------------------------------------------------------------------------

local header = CreateFrame("Frame", "GripbarTopFaceHeader", UIParent, "SecureHandlerStateTemplate")

-- The top bar's cell of each face: the enemy cell while a living enemy is
-- targeted and it holds something, else the normal cell when it holds
-- something, else none. With an action on the cursor every top cell shows
-- (to drop it on); the cells shown setting shows one kind, empty or not.
header:SetAttribute("gb-eval", [[
    local state = self:GetAttribute("gb-state") or "normal"
    local edit = self:GetAttribute("gb-edit")
    local grid = self:GetAttribute("gb-grid")
    for i = 1, 4 do
        local face = self:GetFrameRef("face" .. i)
        if face then
            local normal = face:GetAttribute("gb-normal")
            local enemy = face:GetAttribute("gb-enemy")
            local slot
            if self:GetAttribute("gb-on") and state ~= "off" then
                if edit == "lb" or edit == "rb" or edit == "normal" then
                    slot = face:GetAttribute("gb-" .. edit)
                elseif (edit == "enemy" or state == "enemy") and enemy and (edit or grid or HasAction(enemy)) then
                    slot = enemy
                elseif normal and (grid or HasAction(normal)) then
                    slot = normal
                end
            end
            face:SetAttribute("gb-top", slot)
            face:CallMethod("GBRoute")
        end
    end
]])
header:SetAttribute("_onstate-gbface", [[
    self:SetAttribute("gb-state", newstate)
    self:RunAttribute("gb-eval")
]])

-- A press: the layer is the bumper held (LB friendly, RB hostile) or the top
-- bar. Its cell's action when it holds one, on the press; else the game's
-- own button of that layer gets the press and the release.
local PRECLICK = [[
    -- A click that put the cursor's action into a cell does nothing else.
    if self:GetAttribute("gb-drop") then
        self:SetAttribute("gb-drop", nil)
        return false
    end
    if down then
        local pad = GetGamePadState()
        pad = pad and pad.buttons
        local lb, rb = self:GetAttribute("gb-lbi"), self:GetAttribute("gb-rbi")
        local lt, rt = self:GetAttribute("gb-lti"), self:GetAttribute("gb-rti")
        local ltHeld, rtHeld = pad and lt and pad[lt], pad and rt and pad[rt]
        -- A bumper that emulates a modifier may not show in the pad state.
        local lbm, rbm = self:GetAttribute("gb-lbmod"), self:GetAttribute("gb-rbmod")
        local lbHeld = (pad and lb and pad[lb]) or (lbm == "CTRL" and IsControlKeyDown())
            or (lbm == "SHIFT" and IsShiftKeyDown()) or (lbm == "ALT" and IsAltKeyDown())
        local rbHeld = (pad and rb and pad[rb]) or (rbm == "CTRL" and IsControlKeyDown())
            or (rbm == "SHIFT" and IsShiftKeyDown()) or (rbm == "ALT" and IsAltKeyDown())
        local layer = "top"
        if ltHeld or rtHeld then
            -- A trigger layer is the game's own bar: left, right or both.
            layer = (ltHeld and rtHeld) and "ltrt" or (ltHeld and "lt" or "rt")
            self:SetAttribute("gb-layer", layer)
            self:SetAttribute("gb-use", nil)
        elseif lbHeld and rbHeld then
            layer = "lbrb"
            self:SetAttribute("gb-layer", layer)
            self:SetAttribute("gb-use", nil)
        elseif lbHeld then
            layer = "lb"
        elseif rbHeld then
            layer = "rb"
        end
        if layer == "top" or layer == "lb" or layer == "rb" then
            local slot = self:GetAttribute(layer == "top" and "gb-top" or ("gb-" .. layer))
            if slot and not HasAction(slot) then
                slot = nil
            end
            self:SetAttribute("gb-layer", layer)
            self:SetAttribute("gb-use", slot)
        end
    end
    local slot = self:GetAttribute("gb-use")
    if slot then
        self:SetAttribute("type", "action")
        self:SetAttribute("action", slot)
        self:SetAttribute("useOnKeyDown", true)
        return
    end
    local native = self:GetAttribute("gb-native-" .. (self:GetAttribute("gb-layer") or "top"))
    if not native then
        return false
    end
    self:SetAttribute("type", "macro")
    self:SetAttribute("useOnKeyDown", down and true or false)
    self:SetAttribute("macrotext", "/click " .. native .. " LeftButton" .. (down and " true" or ""))
]]

local function TopSlot(face)
    return face.secure:GetAttribute("gb-top")
end

-- The bumper held right now (insecure code has no GetGamePadState): "lb",
-- "rb" or nil.
local function BumperDown(key)
    local ok, down = pcall(IsKeyDown, key)
    if ok and down then
        return true
    end
    local state = ns.GetMappedState and ns.GetMappedState()
    local raw = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(key)
    local index = state and raw and ns.GetMappedButtonArrayIndex and ns.GetMappedButtonArrayIndex(state, raw)
    return index ~= nil and state.buttons[index] == true
end

local function HeldBumper()
    local lb, rb = BumperDown("PADLSHOULDER"), BumperDown("PADRSHOULDER")
    if lb and rb then
        return "lbrb"
    end
    return (lb and "lb") or (rb and "rb") or nil
end

-- The cell the mouse works on: the held bumper's, else the top cell shown.
local function MouseSlot(face, index)
    local bumper = HeldBumper()
    if bumper == "lbrb" then
        -- The game's shortcuts bar: no cells of ours.
        return nil
    elseif bumper then
        return Cell(index, bumper)
    end
    return TopSlot(face)
end

local function CreateFace(index)
    local topNative, topBar = NativeButton("top", index)
    if not topNative then
        return nil
    end
    local face = {}
    face.top = CreateDisplay(topNative, topBar)
    face.mini = CreateDisplay(topNative, topBar, true)
    for layer in pairs(LAYER_BARS) do
        local native, bar = NativeButton(layer, index)
        if native and bar then
            face[layer] = CreateDisplay(native, bar)
        end
    end

    local secure = CreateFrame("Button", "GripbarFace" .. FACES[index].name, UIParent, "SecureActionButtonTemplate")
    face.secure = secure
    secure:SetAllPoints(topNative)
    -- Above the targeting bars too (they cover the top bar while a bumper is
    -- held), so the mouse reaches the held bumper's cell.
    secure:SetFrameStrata("HIGH")
    secure:RegisterForClicks("AnyDown", "AnyUp")
    secure:RegisterForDrag("LeftButton")
    secure:SetAttribute("useOnKeyDown", true)

    -- The mini cell shows the other one of normal / enemy: the enemy cell
    -- while the button shows its normal one (or the game's own), the normal
    -- cell while it shows the enemy one. They swap when a living enemy is
    -- targeted. With an action on the cursor the enemy cell shows even empty,
    -- to drop it on.
    function secure:GBRoute()
        local top = TopSlot(face)
        ShowDisplay(face.top, top)
        local normal, enemy = Cell(index, "normal"), Cell(index, "enemy")
        local mini
        if GripbarDB.topFace == true and not GripbarDB.topFaceEdit then
            if top and top == enemy then
                mini = normal and C_ActionBar.HasAction(normal) and normal or nil
            elseif enemy and (gridShown or C_ActionBar.HasAction(enemy)) then
                mini = enemy
            end
        end
        face.miniSlot = mini
        ShowDisplay(face.mini, mini)
    end

    -- The pressed look on the cell that fired (ours only).
    secure:SetScript("PostClick", function(self, _, down)
        local display = face[self:GetAttribute("gb-layer") or "top"]
        if not (display and display.holder) then
            display = nil
        end
        if down then
            SetDisplayPushed(display, self:GetAttribute("gb-use") ~= nil)
        else
            for _, each in ipairs({ face.top, face.lb, face.rb }) do
                SetDisplayPushed(each, false)
            end
        end
    end)

    -- Mouse: the top cell shown takes drops, gives up its action, has a tooltip.
    -- Dropping an action (drag released, or a click with it on the cursor)
    -- puts it into the cell the mouse works on.
    local function Drop(how)
        local cursor = GetCursorInfo()
        local slot = MouseSlot(face, index)
        if ns.Log then
            ns.Log("topface", string.format("%s on %s: cursor %s, cell %s, combat %s", how, FACES[index].name,
                tostring(cursor), tostring(slot), tostring(InCombatLockdown())))
        end
        if InCombatLockdown() or not slot or not cursor or GetTime() - (face.lastDrop or 0) < 0.3 then
            return false
        end
        face.lastDrop = GetTime()
        local ok, err = pcall(C_ActionBar.PutActionInSlot, slot)
        if not ok and ns.Log then
            ns.Log("topface", "drop failed: " .. tostring(err))
        end
        return true
    end
    secure:SetScript("OnReceiveDrag", function()
        Drop("drag")
    end)
    secure:SetScript("PreClick", function(self, mouseButton, down)
        if InCombatLockdown() or not GetCursorInfo() or not mouseButton:find("Button") then
            return
        end
        if Drop("click") then
            self:SetAttribute("gb-drop", true)
        end
    end)
    secure:SetScript("OnDragStart", function()
        local slot = MouseSlot(face, index)
        if InCombatLockdown() or not slot or not C_ActionBar.HasAction(slot) then
            return
        end
        if GetCVarBool("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
            return
        end
        PickupAction(slot)
    end)
    secure:SetScript("OnEnter", function(self)
        local slot = MouseSlot(face, index)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if slot and C_ActionBar.HasAction(slot) then
            GameTooltip:SetAction(slot)
            return
        end
        GameTooltip:AddLine("Top bar " .. FACES[index].name)
        GameTooltip:AddLine("Drop an action here (Gripbar: own X / Y / B / A).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    secure:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- The mini cell takes drops, gives up its action and has a tooltip (a
    -- plain frame: nothing secure is needed to change an action out of
    -- combat). It sits above the button's own mouse area.
    local mini = face.mini.holder
    mini:SetFrameStrata("HIGH")
    mini:SetFrameLevel(secure:GetFrameLevel() + 5)
    mini:EnableMouse(true)
    mini:RegisterForDrag("LeftButton")
    local function MiniDrop()
        local slot = face.miniSlot
        -- One drop per release (a release can fire both handlers; a second
        -- put would swap the action back).
        if InCombatLockdown() or not slot or not GetCursorInfo() or GetTime() - (face.lastDrop or 0) < 0.3 then
            return
        end
        face.lastDrop = GetTime()
        pcall(C_ActionBar.PutActionInSlot, slot)
    end
    mini:SetScript("OnReceiveDrag", MiniDrop)
    mini:SetScript("OnMouseUp", MiniDrop)
    mini:SetScript("OnDragStart", function()
        local slot = face.miniSlot
        if InCombatLockdown() or not slot or not C_ActionBar.HasAction(slot) then
            return
        end
        if GetCVarBool("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
            return
        end
        PickupAction(slot)
    end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local slot = face.miniSlot
        if slot and C_ActionBar.HasAction(slot) then
            GameTooltip:SetAction(slot)
            return
        end
        GameTooltip:AddLine(FACES[index].name .. " with a living enemy targeted")
        GameTooltip:AddLine("Drop an action here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    header:WrapScript(secure, "OnClick", PRECLICK)
    header:SetFrameRef("face" .. index, secure)
    return face
end

---------------------------------------------------------------------------
-- Bindings
---------------------------------------------------------------------------

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

-- A face key with modifiers held, as binding strings: those with a trigger
-- (LT / RT) go back to the game; those with only bumpers come to us.
local function ModifiedVariants(key)
    local mods, isTrigger = {}, {}
    for _, input in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER" }) do
        local mod = EmulatedModifier(input)
        if mod then
            if not tContains(mods, mod) then
                mods[#mods + 1] = mod
            end
            if input == "PADLTRIGGER" or input == "PADRTRIGGER" then
                isTrigger[mod] = true
            end
        end
    end
    table.sort(mods)
    local game, ours = {}, {}
    for mask = 1, 2 ^ #mods - 1 do
        local parts, trigger = {}, false
        for i, mod in ipairs(mods) do
            if bit.band(mask, 2 ^ (i - 1)) ~= 0 then
                parts[#parts + 1] = mod
                trigger = trigger or isTrigger[mod] == true
            end
        end
        local variant = table.concat(parts, "-") .. "-" .. key
        if trigger then
            game[#game + 1] = variant
        else
            ours[#ours + 1] = variant
        end
    end
    return game, ours
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

local function AnyCellFilled(index)
    for kind in pairs(CELL_OFFSET) do
        local slot = Cell(index, kind)
        if slot and C_ActionBar.HasAction(slot) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Apply (out of combat)
---------------------------------------------------------------------------

local function ApplyTopFace()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    ClearOverrideBindings(header)

    local on = Enabled()
    if on then
        for index in ipairs(FACES) do
            if not faces[index] and not lastError then
                local ok, result = pcall(CreateFace, index)
                if ok then
                    faces[index] = result
                else
                    lastError = FACES[index].name .. ": " .. tostring(result)
                    if ns.Log then
                        ns.Log("topface", "error " .. lastError)
                    end
                end
            end
        end
    end
    local edit = on and GripbarDB.topFaceEdit or nil
    header:SetAttribute("gb-on", on or nil)
    header:SetAttribute("gb-grid", (on and gridShown) or nil)
    header:SetAttribute("gb-edit", edit)

    local taken = 0
    local lbIndex, rbIndex = PadIndex("PADLSHOULDER"), PadIndex("PADRSHOULDER")
    for index, def in ipairs(FACES) do
        local face = faces[index]
        if face then
            local secure = face.secure
            for kind in pairs(CELL_OFFSET) do
                secure:SetAttribute("gb-" .. kind, Cell(index, kind))
            end
            secure:SetAttribute("gb-lbi", lbIndex)
            secure:SetAttribute("gb-rbi", rbIndex)
            secure:SetAttribute("gb-lti", PadIndex("PADLTRIGGER"))
            secure:SetAttribute("gb-rti", PadIndex("PADRTRIGGER"))
            secure:SetAttribute("gb-lbmod", EmulatedModifier("PADLSHOULDER"))
            secure:SetAttribute("gb-rbmod", EmulatedModifier("PADRSHOULDER"))
            for _, layer in ipairs({ "top", "lb", "rb", "lbrb", "lt", "rt", "ltrt" }) do
                local native = NativeButton(layer, index)
                secure:SetAttribute("gb-native-" .. layer, native and native:GetName() or nil)
            end
            secure:SetShown(on)
            if not on then
                for _, display in ipairs({ face.top, face.mini, face.lb, face.rb }) do
                    ShowDisplay(display, nil)
                end
            end
            -- Bound while a cell holds something (or cells are shown to set
            -- up), and only while the game's core bindings are on top.
            if on and (gridShown or edit or AnyCellFilled(index)) and CoreBindingsOnly() then
                SetOverrideBindingClick(header, true, def.key, secure:GetName(), "LeftButton")
                local game, ours = ModifiedVariants(def.key)
                for _, variant in ipairs(ours) do
                    SetOverrideBindingClick(header, true, variant, secure:GetName(), "LeftButton")
                end
                local nativeAction = "CLICK InputFunctionBindingButton_" .. def.key .. ":LeftButton"
                for _, variant in ipairs(game) do
                    SetOverrideBinding(header, true, variant, nativeAction)
                end
                taken = taken + 1
            end
        end
    end
    SecureHandlerExecute(header, [[ self:RunAttribute("gb-eval") ]])
    if faces[1] then
        RefreshLayerDisplays()
    end

    if not GripbarDB or GripbarDB.topFace ~= true then
        status = "off"
    elseif not ns.topFaceSlots then
        status = "on, but no free action slots for the cells (" .. tostring(ns.topFaceStatus) .. ")"
    elseif not faces[1] then
        status = "on, but the game's top bar was not found"
    else
        status = string.format("on: %d of 4 buttons bound%s%s", taken,
            CoreBindingsOnly() and "" or " (a menu holds the face buttons)",
            edit and ("; showing " .. EDIT_LABELS[edit]) or "")
    end
    if status ~= loggedStatus and ns.Log then
        loggedStatus = status
        ns.Log("topface", status)
    end
    if lastError then
        status = status .. "; error " .. lastError
    end
end

-- The targeting state: the enemy cell while a living enemy is targeted; the
-- game's own buttons in a vehicle, possessing or on an override bar.
RegisterStateDriver(header, "gbface", "[vehicleui][possessbar][overridebar] off; [@target,harm,nodead] enemy; normal")

local function Toggle()
    GripbarDB.topFace = GripbarDB.topFace ~= true
    if not GripbarDB.topFace then
        GripbarDB.topFaceEdit = nil
    end
    ApplyTopFace()
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
    Print("Own X / Y / B / A: " .. status .. ".")
end

-- Which cells the top bar shows to set them up: off (as in play), normal,
-- enemy (no target needed), LB, RB (no bumper needed). nil cycles.
local function SetEditMode(mode)
    if InCombatLockdown() then
        Print("Change the cells shown out of combat.")
        return
    end
    if mode == nil then
        local current = GripbarDB.topFaceEdit
        local nextIndex = 1
        for i, value in ipairs(EDIT_MODES) do
            if value == current then
                nextIndex = i + 1
            end
        end
        mode = EDIT_MODES[nextIndex]
    elseif mode == "off" or mode == "" then
        mode = nil
    end
    if mode and not CELL_OFFSET[mode] then
        Print("/grip face edit [normal | enemy | lb | rb | off]")
        return
    end
    if mode then
        GripbarDB.topFace = true
    end
    GripbarDB.topFaceEdit = mode
    ApplyTopFace()
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
    Print(mode and ("The top bar shows the " .. EDIT_LABELS[mode] .. " of X / Y / B / A: drop actions on them. /grip face edit off when done.")
        or "The top bar's X / Y / B / A are back to play.")
end

-- Empties one cell: the game's own button shows there again.
local function ClearCell(kind, faceName)
    kind, faceName = (kind or ""):lower(), (faceName or ""):upper()
    local index
    for i, def in ipairs(FACES) do
        if def.name == faceName then
            index = i
        end
    end
    if not CELL_OFFSET[kind] or not index then
        Print("/grip face clear <normal | enemy | lb | rb> <x | y | b | a>")
        return
    end
    if InCombatLockdown() then
        Print("Change the cells out of combat.")
        return
    end
    local slot = Cell(index, kind)
    if slot and C_ActionBar.HasAction(slot) then
        PickupAction(slot)
        ClearCursor()
    end
    Print("Cleared the " .. kind .. " cell of " .. faceName .. ".")
end

local function HandleCommand(args)
    local option = (args and args[2] or ""):lower()
    if option == "edit" or option == "show" then
        SetEditMode(args[3] and args[3]:lower() or nil)
    elseif option == "clear" then
        ClearCell(args[3], args[4])
    else
        Toggle()
    end
end

-- The game binds its face keys again when a menu closes (a binding set
-- leaves its stack): ours go back on top afterwards.
local function HookBindingStack()
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if not manager then
        return
    end
    local queued, lastCore = false, nil
    local function Later()
        if Enabled() and not queued then
            queued = true
            C_Timer.After(0, function()
                queued = false
                local core = CoreBindingsOnly()
                -- The bumpers' stick bindings come and go as core ones: only
                -- a change, or the core set bound again, needs ours again.
                if core ~= lastCore or core then
                    lastCore = core
                    ApplyTopFace()
                end
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
        return
    elseif event == "PLAYER_ENTERING_WORLD" and not ns.topFaceSlots and ns.ReserveTopFaceSlots then
        ns.ReserveTopFaceSlots()
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
ns.HandleTopFaceCommand = HandleCommand
ns.SetTopFaceEditMode = SetEditMode
ns.GetTopFaceEditLabel = function()
    local mode = GripbarDB and GripbarDB.topFaceEdit
    return mode and EDIT_LABELS[mode] or "as in play"
end
ns.GetTopFaceStatus = function()
    return status
end
