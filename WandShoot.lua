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

-- Shoot's icon over the top bar's X while X would shoot (option on, wand
-- wielded, a living enemy targeted), so the bar shows what X does. A plain
-- frame of ours anchored to the game's button: nothing of the game's button
-- is touched. It pulses while the wand fires (auto-repeat).
local wandActive = false
local iconFrame

local function TopX()
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars.topBar
    return bar and bar.Right and bar.Right.ActionButton1
end

local function EnsureIcon()
    if iconFrame then
        return iconFrame
    end
    local native = TopX()
    if not native then
        return nil
    end
    iconFrame = CreateFrame("Frame", nil, UIParent)
    iconFrame:SetFrameStrata(native:GetFrameStrata())
    iconFrame:SetFrameLevel(native:GetFrameLevel() + 6)
    -- Same build as the paddle slots: the icon fills the button under a round
    -- mask inset by 3, and the native circle-slot ring is drawn over it, so
    -- the ring stays visible and the size follows the button (focus, bumper).
    iconFrame:SetAllPoints(native)
    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK", nil, 0)
    iconFrame.texture:SetAllPoints()
    local mask = iconFrame:CreateMaskTexture()
    mask:SetPoint("TOPLEFT", 3, -3)
    mask:SetPoint("BOTTOMRIGHT", -3, 3)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("CircleMask") then
        mask:SetAtlas("CircleMask")
    else
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    iconFrame.texture:AddMaskTexture(mask)
    iconFrame.ring = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    iconFrame.ring:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-normal") then
        iconFrame.ring:SetAtlas("gamepad-actionbar-circleslot-border-normal")
    else
        iconFrame.ring:Hide()
    end
    iconFrame.pulse = iconFrame:CreateAnimationGroup()
    iconFrame.pulse:SetLooping("BOUNCE")
    local fade = iconFrame.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.5)
    iconFrame:Hide()
    return iconFrame
end

local function SetNativeRingAlpha(alpha)
    local native = TopX()
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

local function UpdateWandIcon()
    local shown = wandActive and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
    local frame = (shown or iconFrame) and EnsureIcon()
    if not frame then
        return
    end
    if shown then
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SHOOT_SPELL_ID)
        frame.texture:SetTexture(texture)
        frame:Show()
        SetNativeRingAlpha(0)
        local name = ShootName()
        local repeating = name and IsAutoRepeatSpell and IsAutoRepeatSpell(name)
        if repeating and not frame.pulse:IsPlaying() then
            frame.pulse:Play()
        elseif not repeating and frame.pulse:IsPlaying() then
            frame.pulse:Stop()
            frame:SetAlpha(1)
        end
    else
        frame.pulse:Stop()
        frame:SetAlpha(1)
        frame:Hide()
        SetNativeRingAlpha(1)
    end
end

local iconEvents = CreateFrame("Frame")
iconEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
iconEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
iconEvents:RegisterUnitEvent("UNIT_FLAGS", "target")
iconEvents:RegisterEvent("START_AUTOREPEAT_SPELL")
iconEvents:RegisterEvent("STOP_AUTOREPEAT_SPELL")
iconEvents:SetScript("OnEvent", UpdateWandIcon)

-- Pressed look while X is held, like the native slots and the paddles: 4
-- smaller, 2 lower, the pressed ring. X goes to our button while it shoots,
-- so the game's own button never sees the press.
local PRESSED_OFFSET = 4

local function SetWandPressed(pressed)
    local native = TopX()
    if not iconFrame or not native then
        return
    end
    iconFrame:ClearAllPoints()
    if pressed and iconFrame:IsShown() then
        local width, height = native:GetSize()
        iconFrame:SetPoint("CENTER", native, "CENTER", 0, -PRESSED_OFFSET / 2)
        iconFrame:SetSize(width - PRESSED_OFFSET, height - PRESSED_OFFSET)
        if C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-pressed") then
            iconFrame.ring:SetAtlas("gamepad-actionbar-circleslot-border-pressed")
        end
    else
        iconFrame:SetAllPoints(native)
        if C_Texture.GetAtlasInfo("gamepad-actionbar-circleslot-border-normal") then
            iconFrame.ring:SetAtlas("gamepad-actionbar-circleslot-border-normal")
        end
    end
end

button:HookScript("OnClick", function(self, _, down)
    -- A press routed to a trigger layer's own button does not press the top X.
    if down and self:GetAttribute("bx-route") ~= "shoot" then
        return
    end
    SetWandPressed(down == true)
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
