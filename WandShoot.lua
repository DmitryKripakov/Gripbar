-- "Swap melee and wand" (X shoots the wand, RB + X swings).
--
-- X (PAD3) is the game's Interact: on an enemy it swings the melee weapon,
-- and the wand's Shoot needs RB + X. With this option on, a wand in the
-- ranged slot and a living enemy targeted, X casts Shoot instead. On
-- anything else (a corpse to loot, an NPC, an object) X stays the game's own
-- press, and LT / RT + X still press that layer's crossbar X.
--
-- Shoot is looked up by its spell ID, so it works on every client language
-- (the localized name goes into the macro). Same idea as Improved Forever's
-- "Square shoots the wand", which looks the spell up by its English name and
-- so stays off on non-English clients.
--
-- A secure state driver binds X only while "[@target,harm,nodead]" holds,
-- so it follows the target in combat too. Settings change out of combat.
local _, ns = ...

local Print = ns.Print

local SHOOT_SPELL_ID = 5019
local RANGED_SLOT = 18
local KEY = "PAD3"
local LAYER_BARS = { LT = "leftBar", RT = "rightBar", LTRT = "bottomBar" }

local function Wielding()
    local id = GetInventoryItemID("player", RANGED_SLOT)
    if not id then
        return false
    end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local wand = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand or 19
    return class == weapon and subclass == wand
end

-- Shoot's name in the client's language, or nil when it is not known.
local function ShootName()
    if not (C_Spell and C_Spell.GetSpellInfo) then
        return nil
    end
    if IsPlayerSpell and not IsPlayerSpell(SHOOT_SPELL_ID) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(SHOOT_SPELL_ID)
    return info and info.name
end

-- The game's crossbar X button of a trigger layer's bar, by name (a /click
-- needs one): the first button of the bar's face-button group.
local function NativeX(layer)
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars[LAYER_BARS[layer]]
    local button = bar and bar.Right and bar.Right.ActionButton1
    return button and button.GetName and button:GetName()
end

local function PadIndex(binding)
    local index = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex(binding)
    return index and index + 1 or nil
end

-- The secure button X runs while it shoots.
local button = CreateFrame("Button", "GripbarWandShoot", UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
button:SetAlpha(0)
button:EnableMouse(false)
button:SetAttribute("type", "macro")
button:SetAttribute("useOnKeyDown", true)
button:RegisterForClicks("AnyDown", "AnyUp")
-- Acts on the press. With a trigger held the press is that layer's crossbar
-- X (the game's bars read the triggers themselves), else Shoot.
SecureHandlerWrapScript(button, "OnClick", button, [[
    if not down then
        -- The release does nothing, but goes through so the icon's pressed
        -- look (an OnClick hook) can let go.
        self:SetAttribute("macrotext", "")
        return
    end
    local state = GetGamePadState()
    local pad = state and state.buttons
    -- Swap: RB + X swings the melee weapon (the game's RB + X shoots).
    local rb = self:GetAttribute("bx-rb")
    if pad and rb and pad[rb] then
        self:SetAttribute("bx-route", "melee")
        self:SetAttribute("macrotext", self:GetAttribute("bx-melee"))
        return
    end
    local lt, rt = self:GetAttribute("bx-lt"), self:GetAttribute("bx-rt")
    if pad and (lt or rt) then
        local layer = ((lt and pad[lt]) and "LT" or "") .. ((rt and pad[rt]) and "RT" or "")
        local held = layer ~= "" and self:GetAttribute("bx-layer-" .. layer)
        if held then
            self:SetAttribute("bx-route", "layer")
            self:SetAttribute("macrotext", held)
            return
        end
    end
    self:SetAttribute("bx-route", "shoot")
    self:SetAttribute("macrotext", self:GetAttribute("bx-shoot"))
]])

local driver = CreateFrame("Frame", "GripbarWandDriver", UIParent, "SecureHandlerStateTemplate")
driver:SetAttribute("bx-eval", [[
    self:ClearBindings()
    if self:GetAttribute("bx-on") and self:GetAttribute("state-wand") == "shoot" then
        self:SetBindingClick(true, self:GetAttribute("bx-key"), self:GetAttribute("bx-button"), "LeftButton")
        local rbKey = self:GetAttribute("bx-rbkey")
        if rbKey then
            self:SetBindingClick(true, rbKey, self:GetAttribute("bx-button"), "LeftButton")
        end
        local native = self:GetAttribute("bx-native")
        if native then
            for i = 1, tonumber(self:GetAttribute("bx-variants")) or 0 do
                local variant = self:GetAttribute("bx-variant-" .. i)
                if variant then
                    self:SetBinding(true, variant, native)
                end
            end
        end
    end
]])
driver:SetAttribute("_onstate-wand", [[ self:RunAttribute("bx-eval") ]])
RegisterStateDriver(driver, "wand", "[@target,harm,nodead] shoot; none")

local status = "off"

-- Icons that show what the swapped presses do, drawn over the game's own
-- buttons (plain frames of ours anchored to them; the game's buttons are not
-- touched, only their ring is made transparent while ours covers it):
--   * the top bar's X: Shoot, while X would shoot (pulses while the wand fires);
--   * the RB shortcut bar's X: the main-hand weapon, while RB + X swings.
-- Same build as the paddle slots: the icon under a round mask inset by 3, the
-- native circle-slot ring over it, the size following the button.
local wandActive = false
local overlays = {}
local rbOnTop = false

local function TopX()
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars.topBar
    return bar and bar.Right and bar.Right.ActionButton1
end

local function CreateOverlay(native)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata(native:GetFrameStrata())
    frame:SetFrameLevel(native:GetFrameLevel() + 6)
    frame:SetAllPoints(native)
    frame.native = native
    frame.texture = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    frame.texture:SetAllPoints()
    local mask = frame:CreateMaskTexture()
    mask:SetPoint("TOPLEFT", 3, -3)
    mask:SetPoint("BOTTOMRIGHT", -3, 3)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("CircleMask") then
        mask:SetAtlas("CircleMask")
    else
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    frame.texture:AddMaskTexture(mask)
    frame.ring = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.ring:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-normal") then
        frame.ring:SetAtlas("gamepad-actionbar-circleslot-border-normal")
    else
        frame.ring:Hide()
    end
    frame.pulse = frame:CreateAnimationGroup()
    frame.pulse:SetLooping("BOUNCE")
    local fade = frame.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.5)
    frame:Hide()
    return frame
end

local function SetNativeRingAlpha(native, alpha)
    if not native then
        return
    end
    local normal = native.NormalTexture or (native.GetNormalTexture and native:GetNormalTexture())
    local pushed = native.PushedTexture or (native.GetPushedTexture and native:GetPushedTexture())
    for _, texture in ipairs({ normal, pushed }) do
        if texture and texture.SetAlpha then
            texture:SetAlpha(alpha)
        end
    end
end

-- Shows an overlay over a native button with a texture, or hides it.
local function ShowOverlay(key, native, texture)
    local frame = overlays[key]
    if texture and native then
        if not frame or frame.native ~= native then
            if frame then
                frame:Hide()
                SetNativeRingAlpha(frame.native, 1)
            end
            frame = CreateOverlay(native)
            overlays[key] = frame
        end
        frame.texture:SetTexture(texture)
        frame:Show()
        SetNativeRingAlpha(native, 0)
        return frame
    elseif frame and frame:IsShown() then
        frame.pulse:Stop()
        frame:SetAlpha(1)
        frame:Hide()
        SetNativeRingAlpha(frame.native, 1)
    end
    return nil
end

local function EnemyTargeted()
    return UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
end

local function UpdateWandIcon()
    local shown = wandActive and EnemyTargeted() and not rbOnTop
    local frame = ShowOverlay("shoot", shown and TopX() or nil,
        shown and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SHOOT_SPELL_ID) or nil)
    if frame then
        local name = ShootName()
        local repeating = name and IsAutoRepeatSpell and IsAutoRepeatSpell(name)
        if repeating and not frame.pulse:IsPlaying() then
            frame.pulse:Play()
        elseif not repeating and frame.pulse:IsPlaying() then
            frame.pulse:Stop()
            frame:SetAlpha(1)
        end
    end
end

local iconEvents = CreateFrame("Frame")
iconEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
iconEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
iconEvents:RegisterUnitEvent("UNIT_FLAGS", "target")
iconEvents:RegisterEvent("START_AUTOREPEAT_SPELL")
iconEvents:RegisterEvent("STOP_AUTOREPEAT_SPELL")
iconEvents:SetScript("OnEvent", UpdateWandIcon)

-- The RB shortcut bar's X: while RB is held the game shows its shortcut bar,
-- whose X shoots (and shows Shoot's or the wand's icon). That button is
-- found by its icon, among the crossbar's visible buttons, and remembered.
local MAIN_HAND_SLOT = 16
local rbX

local function IconOf(native)
    for _, key in ipairs({ "icon", "Icon", "SpecialActionIcon" }) do
        local region = native[key]
        if region and region.IsShown and region:IsShown() and region.GetTexture then
            local texture = region:GetTexture()
            if texture then
                return texture
            end
        end
    end
    return nil
end

local function FindRBX()
    local main = _G.GamepadMainActionBarFrame
    local root = main and main.PageUnit
    if not root then
        return nil
    end
    local shoot = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SHOOT_SPELL_ID)
    local wand = GetInventoryItemTexture("player", RANGED_SLOT)
    local top = TopX()
    local found
    local function Scan(frame, depth)
        if found or depth > 8 or not frame:IsVisible() then
            return
        end
        if frame ~= top and frame:IsObjectType("Button") then
            local texture = IconOf(frame)
            if texture and (texture == shoot or texture == wand) then
                found = frame
                return
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            Scan(child, depth + 1)
        end
    end
    Scan(root, 0)
    return found
end

local rbIndex

-- Is RB held? Plain (insecure) code has no GetGamePadState, so this asks the
-- client the same ways the layer detection does: the key, then the mapped
-- controller state.
local function RBHeld()
    if IsKeyDown then
        local ok, down = pcall(IsKeyDown, "PADRSHOULDER")
        if ok and down then
            return true
        end
    end
    local state = ns.GetMappedState and ns.GetMappedState()
    local raw = C_GamePad and C_GamePad.ButtonBindingToIndex and C_GamePad.ButtonBindingToIndex("PADRSHOULDER")
    local index = state and raw and ns.GetMappedButtonArrayIndex and ns.GetMappedButtonArrayIndex(state, raw)
    return index ~= nil and state.buttons[index] == true
end

local rbPoll = CreateFrame("Frame")
local rbElapsed = 0
rbPoll:SetScript("OnUpdate", function(_, elapsed)
    rbElapsed = rbElapsed + elapsed
    if rbElapsed < 0.05 then
        return
    end
    rbElapsed = 0
    local held = wandActive and EnemyTargeted() and RBHeld()
    local native
    if held then
        if not (rbX and rbX:IsVisible()) then
            -- The shortcut bar's own X, or the top bar's X when the game
            -- shows the shortcut on that same button.
            rbX = FindRBX() or TopX()
        end
        native = rbX
    end
    -- While RB + X swings, the weapon replaces the Shoot icon (the shortcut
    -- button sits right over the top X).
    local onTop = native ~= nil
    if onTop ~= rbOnTop then
        rbOnTop = onTop
        UpdateWandIcon()
    end
    local weapon = native and (GetInventoryItemTexture("player", MAIN_HAND_SLOT)
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(6603)))
    ShowOverlay("melee", native, weapon)
end)

-- Pressed look while X is held, like the native slots and the paddles: 4
-- smaller, 2 lower, the pressed ring. Our button gets these presses, so the
-- game's own button never sees them.
local PRESSED_OFFSET = 4

local function SetPressed(frame, pressed)
    if not frame or not frame.native then
        return
    end
    local native = frame.native
    frame:ClearAllPoints()
    if pressed and frame:IsShown() then
        local width, height = native:GetSize()
        frame:SetPoint("CENTER", native, "CENTER", 0, -PRESSED_OFFSET / 2)
        frame:SetSize(width - PRESSED_OFFSET, height - PRESSED_OFFSET)
        if C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-pressed") then
            frame.ring:SetAtlas("gamepad-actionbar-circleslot-border-pressed")
        end
    else
        frame:SetAllPoints(native)
        if C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-normal") then
            frame.ring:SetAtlas("gamepad-actionbar-circleslot-border-normal")
        end
    end
end

button:HookScript("OnClick", function(self, _, down)
    local route = self:GetAttribute("bx-route")
    if down then
        -- Only our own presses: a trigger layer's press is the game's button.
        if route == "shoot" then
            SetPressed(overlays.shoot, true)
        elseif route == "melee" then
            SetPressed(overlays.melee, true)
        end
    else
        SetPressed(overlays.shoot, false)
        SetPressed(overlays.melee, false)
    end
end)

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

-- X with LT / RT / both held, as binding strings: those go back to the game.
local function TriggerVariants()
    local lt, rt = TriggerModifier("PADLTRIGGER"), TriggerModifier("PADRTRIGGER")
    local variants = {}
    local function Add(mods)
        table.sort(mods)
        variants[#variants + 1] = table.concat(mods, "-") .. "-" .. KEY
    end
    if lt then
        Add({ lt })
    end
    if rt then
        Add({ rt })
    end
    if lt and rt and lt ~= rt then
        Add({ lt, rt })
    end
    return variants
end

-- The game's own binding of X (its crossbar's), read while ours is not on it.
local nativeAction
local function NativeAction()
    local action = GetBindingAction and GetBindingAction(KEY, true)
    if action and action ~= "" and not action:find(button:GetName(), 1, true) then
        nativeAction = action
    end
    return nativeAction
end

local function ApplyWandShoot()
    if InCombatLockdown() then
        ns.pendingWandShoot = true
        return
    end
    ns.pendingWandShoot = false

    local on = GripbarDB and GripbarDB.wandShoot == true
    local name = on and ShootName()
    local active = on and name ~= nil and Wielding()
    if active then
        button:SetAttribute("bx-shoot", "/cast [@target,harm,nodead] !" .. name)
        button:SetAttribute("bx-melee", "/startattack [@target,harm,nodead]")
        button:SetAttribute("bx-rb", PadIndex("PADRSHOULDER"))
        rbIndex = PadIndex("PADRSHOULDER")
        button:SetAttribute("bx-lt", PadIndex("PADLTRIGGER"))
        button:SetAttribute("bx-rt", PadIndex("PADRTRIGGER"))
        for layer in pairs(LAYER_BARS) do
            local native = NativeX(layer)
            button:SetAttribute("bx-layer-" .. layer, native and ("/click " .. native .. " LeftButton true") or nil)
        end
        driver:SetAttribute("bx-key", KEY)
        driver:SetAttribute("bx-button", button:GetName())
        local variants = TriggerVariants()
        driver:SetAttribute("bx-native", NativeAction())
        driver:SetAttribute("bx-variants", #variants)
        for i, variant in ipairs(variants) do
            driver:SetAttribute("bx-variant-" .. i, variant)
        end
        local rbModifier = TriggerModifier("PADRSHOULDER")
        driver:SetAttribute("bx-rbkey", rbModifier and (rbModifier .. "-" .. KEY) or nil)
        driver:SetAttribute("bx-on", true)
        status = string.format("on (%s; LT / RT + X: %s)", name,
            (nativeAction and #variants > 0) and ("game binding " .. nativeAction) or "routed by the addon")
        wandActive = true
    else
        wandActive = false
        driver:SetAttribute("bx-on", nil)
        if not on then
            status = "off"
        elseif not name then
            status = "on, but Shoot is not known on this character"
        else
            status = "on, waiting for a wand in the ranged slot"
        end
    end
    SecureHandlerExecute(driver, [[ self:RunAttribute("bx-eval") ]])
    UpdateWandIcon()
end

local function ToggleWandShoot()
    GripbarDB.wandShoot = GripbarDB.wandShoot ~= true
    ApplyWandShoot()
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
    Print("Swap melee and wand: " .. status .. ".")
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not ns.pendingWandShoot then
        return
    end
    ApplyWandShoot()
end)

ns.ApplyWandShoot = ApplyWandShoot
ns.ToggleWandShoot = ToggleWandShoot
ns.GetWandShootStatus = function()
    return status
end
