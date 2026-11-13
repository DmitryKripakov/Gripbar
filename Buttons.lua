-- The paddle action buttons: art, cooldowns, usability, range, secure
-- attributes, drag and drop, and tooltips.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT
local ATLAS = ns.ATLAS
local NATIVE_CVAR_PROMPTS = ns.NATIVE_CVAR_PROMPTS
local PANELS = ns.PANELS
local panelFrames = ns.panelFrames
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local Print = ns.Print
local GetMedia = ns.GetMedia
local GetPaddleTexture = ns.GetPaddleTexture

-- profiles with named buttons (Steam Controller: L4 / R4 / L5 /
-- R5) show the name as text instead of the Elite paddle glyph.
local function PaddleName(index)
    return ns.GetPaddleName and ns.GetPaddleName(index) or ("P" .. tostring(index))
end

local function UsesTextGlyph(index)
    local profile = ns.controllerProfile
    return profile ~= nil and profile.names ~= nil and profile.names[index] ~= nil
end

local function SetEmptyGlyphShown(button, shown)
    local visual = button.visual
    local text = UsesTextGlyph(button.paddleIndex)
    if visual.emptyLabel then
        local alpha = tonumber(GripbarDB and GripbarDB.emptyLabelOpacity) or 1
        local name = PaddleName(button.paddleIndex)
        -- engraved glyph art in the native A / B / X / Y style for
        -- every profile (Media\GlyphL4 ... for the Steam Controller names,
        -- Media\GlyphP1 ... for the paddles); text / the old glyph are fallbacks.
        local art = false
        if visual.emptyArt then
            local glyph = ns.GetPaddleGlyph and ns.GetPaddleGlyph(button.paddleIndex) or ("Glyph" .. name)
            if visual.emptyArt.glyphName ~= glyph then
                visual.emptyArt.glyphOk = visual.emptyArt:SetTexture(GetMedia(glyph)) ~= false
                visual.emptyArt.glyphName = glyph
            end
            art = visual.emptyArt.glyphOk == true
            visual.emptyArt:SetAlpha(alpha)
            visual.emptyArt:SetShown(shown and art)
        end
        visual.emptyLabel:SetText(name)
        visual.emptyLabel:SetAlpha(alpha)
        visual.emptyLabel:SetShown(shown and text and not art)
        visual.emptyGlyph:SetShown(shown and not text and not art and visual.emptyGlyph.artAvailable)
        return
    end
    visual.emptyGlyph:SetShown(shown and not text and visual.emptyGlyph.artAvailable)
end
local SafeCall = ns.SafeCall
local IsSecret = ns.IsSecret
local ApplyCooldown = ns.ApplyCooldown
local LegacyCooldownActive = ns.LegacyCooldownActive
local AtlasExists = ns.AtlasExists
local ApplyArt = ns.ApplyArt
local GetNativeCVarBool = ns.GetNativeCVarBool
local GetNativeSlot = ns.GetNativeSlot
local GetPaddleBehavior = ns.GetPaddleBehavior
local GetPaddleBehaviorIcon = ns.GetPaddleBehaviorIcon
local ApplySlotNavigation = ns.ApplySlotNavigation

-- Reading order: P1 and P2 on the top row, P3 and P4 on the bottom row.
local GRID_CELLS = {
    [1] = { col = 0, row = 0 },
    [2] = { col = 1, row = 0 },
    [3] = { col = 0, row = 1 },
    [4] = { col = 1, row = 1 },
}

local function ClearWidget(cooldown)
    if cooldown.Clear then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

local function ClearCooldown(button)
    ClearWidget(button.cooldown)
    ClearWidget(button.chargeCooldown)
    ClearWidget(button.lossOfControlCooldown)
end

-- Reads a "should replace" or "is active" flag that the API marks NeverSecret;
-- a secret value anyway counts as not set rather than raising an error.
local function PlainFlag(value)
    if IsSecret(value) then
        return false
    end
    return value == true
end

-- Picks the "active" flag of a SpellCooldownInfo, falling back to the legacy
-- triple on clients that do not report isActive.
local function CooldownInfoActive(info)
    local active = info.isActive
    if not IsSecret(active) and active == nil then
        active = LegacyCooldownActive(info.startTime, info.duration, info.isEnabled)
    end
    return active
end

-- Mirrors ActionButton_ApplyCooldown: the red loss-of-control swipe, the
-- recharge edge of charge spells and the normal swipe, where an active
-- loss-of-control lockout that outlasts the cooldown hides the other two.
-- Missing infos (older clients, items) clear their widget. "durations" holds
-- the matching duration objects (cooldown, charge, lossOfControl) when the
-- client has them; see ApplyCooldown.
local function ApplyActionCooldowns(button, cooldownInfo, chargeInfo, lossOfControlInfo, durations)
    local replaceNormal = type(lossOfControlInfo) == "table"
        and PlainFlag(lossOfControlInfo.shouldReplaceNormalCooldown)

    if type(lossOfControlInfo) == "table" then
        ApplyCooldown(button.lossOfControlCooldown, PlainFlag(lossOfControlInfo.isActive),
            lossOfControlInfo.startTime, lossOfControlInfo.duration, lossOfControlInfo.modRate,
            durations.lossOfControl)
    else
        ClearWidget(button.lossOfControlCooldown)
    end

    if type(chargeInfo) == "table" and not replaceNormal then
        ApplyCooldown(button.chargeCooldown, PlainFlag(chargeInfo.isActive),
            chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration, chargeInfo.chargeModRate,
            durations.charge)
    else
        ClearWidget(button.chargeCooldown)
    end

    if type(cooldownInfo) == "table" and not replaceNormal then
        ApplyCooldown(button.cooldown, CooldownInfoActive(cooldownInfo),
            cooldownInfo.startTime, cooldownInfo.duration, cooldownInfo.modRate,
            durations.cooldown)
    else
        ClearWidget(button.cooldown)
    end
end

local function GetFallbackActionDisplay(action)
    if not action then
        return nil, nil
    end

    if action.kind == "spell" then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(action.id)
        if info then
            return info.iconID, info.name
        end
        return nil, "Spell " .. tostring(action.id)
    elseif action.kind == "item" then
        local itemID, _, _, _, icon = C_Item.GetItemInfoInstant(action.id)
        local name = C_Item.GetItemInfo(action.id)
        if not name and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(action.id)
        end
        return icon, name or ("Item " .. tostring(itemID or action.id))
    elseif action.kind == "macro" then
        local name, icon = GetMacroInfo(action.id)
        return icon, name or ("Macro " .. tostring(action.id))
    end

    return nil, nil
end

local function UpdateFallbackCooldown(button)
    local action = button.actionData
    if not action then
        ClearCooldown(button)
        return
    end

    if action.kind == "spell" and C_Spell and C_Spell.GetSpellCooldown then
        ApplyActionCooldowns(button,
            SafeCall(C_Spell.GetSpellCooldown, action.id),
            SafeCall(C_Spell.GetSpellCharges, action.id),
            SafeCall(C_Spell.GetSpellLossOfControlCooldownInfo, action.id),
            {
                cooldown = SafeCall(C_Spell.GetSpellCooldownDuration, action.id),
                charge = SafeCall(C_Spell.GetSpellChargeDuration, action.id),
                lossOfControl = SafeCall(C_Spell.GetSpellLossOfControlCooldownDuration, action.id),
            })
    elseif action.kind == "item" and C_Item and C_Item.GetItemCooldown then
        local startTime, duration, enabled = SafeCall(C_Item.GetItemCooldown, action.id)
        ApplyCooldown(button.cooldown, LegacyCooldownActive(startTime, duration, enabled), startTime, duration)
        ClearWidget(button.chargeCooldown)
        ClearWidget(button.lossOfControlCooldown)
    else
        ClearCooldown(button)
    end
end

local function UpdateNativeCooldown(button)
    local slot = button.actionSlot
    if not slot or not C_ActionBar.HasAction(slot) then
        ClearCooldown(button)
        return
    end

    -- Mirrors ActionButton_UpdateCooldown: the client's isActive flags decide
    -- which swipes are shown, and the (possibly secret) timing values are
    -- handed to the Cooldown widgets without being inspected.
    local info = C_ActionBar.GetActionCooldown and SafeCall(C_ActionBar.GetActionCooldown, slot) or nil
    if type(info) == "table" then
        ApplyActionCooldowns(button, info,
            SafeCall(C_ActionBar.GetActionCharges, slot),
            SafeCall(C_ActionBar.GetActionLossOfControlCooldownInfo, slot),
            {
                cooldown = SafeCall(C_ActionBar.GetActionCooldownDuration, slot),
                charge = SafeCall(C_ActionBar.GetActionChargeDuration, slot),
                lossOfControl = SafeCall(C_ActionBar.GetActionLossOfControlCooldownDuration, slot),
            })
        return
    end

    local startTime, duration, enable, modRate = SafeCall(GetActionCooldown, slot)
    ApplyCooldown(button.cooldown, LegacyCooldownActive(startTime, duration, enable), startTime, duration, modRate)
    ClearWidget(button.chargeCooldown)
    ClearWidget(button.lossOfControlCooldown)
end

-- Native action buttons tint the icon when the action cannot be used
-- (ActionBarActionButtonMixin:UpdateUsable).
local function UpdateUsableTint(button, hasAction)
    local icon = button.visual.icon
    if not hasAction then
        icon:SetVertexColor(1, 1, 1)
        return
    end

    local isUsable, notEnoughMana
    if button.actionSlot then
        if C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
            isUsable, notEnoughMana = SafeCall(C_ActionBar.IsUsableAction, button.actionSlot)
        elseif type(IsUsableAction) == "function" then
            isUsable, notEnoughMana = SafeCall(IsUsableAction, button.actionSlot)
        end
    else
        local action = button.actionData
        if action and action.kind == "spell" and C_Spell and type(C_Spell.IsSpellUsable) == "function" then
            isUsable, notEnoughMana = SafeCall(C_Spell.IsSpellUsable, action.id)
        elseif action and action.kind == "item" and C_Item and type(C_Item.IsUsableItem) == "function" then
            isUsable, notEnoughMana = SafeCall(C_Item.IsUsableItem, action.id)
        end
    end

    -- Usability may be secret in combat; a secret answer cannot be tested, so
    -- the icon is left untinted rather than guessed.
    if IsSecret(isUsable) or IsSecret(notEnoughMana) or isUsable == nil then
        isUsable = true
        notEnoughMana = false
    end

    if isUsable then
        icon:SetVertexColor(1, 1, 1)
    elseif notEnoughMana then
        icon:SetVertexColor(0.5, 0.5, 1.0)
    else
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

-- Checked, flashing and equipped states, as ActionBarActionButtonMixin's
-- UpdateState, UpdateFlash and Update (green Border) set them. These may be
-- secret in combat; a secret answer cannot be tested, so it counts as off
-- like an untinted icon above.
local FLASH_INTERVAL = ATTACK_BUTTON_FLASH_TIME or 0.4

local function IsReadableTrue(value)
    return not IsSecret(value) and value ~= nil and value ~= false
end

local function CallQuery(namespace, name, globalName, arg)
    local func = namespace and namespace[name]
    if type(func) ~= "function" then
        func = globalName and _G[globalName]
    end
    if type(func) ~= "function" then
        return false
    end
    return IsReadableTrue(SafeCall(func, arg))
end

local function GetNativeActionState(slot)
    local current = CallQuery(C_ActionBar, "IsCurrentAction", "IsCurrentAction", slot)
    local autoRepeat = CallQuery(C_ActionBar, "IsAutoRepeatAction", "IsAutoRepeatAction", slot)
    local checked = (current or autoRepeat)
        and not CallQuery(C_ActionBar, "IsAutoCastPetAction", "IsAutoCastPetAction", slot)
    local flashing = (current and CallQuery(C_ActionBar, "IsAttackAction", "IsAttackAction", slot)) or autoRepeat
    return checked, flashing, CallQuery(C_ActionBar, "IsEquippedAction", "IsEquippedAction", slot)
end

local function GetFallbackSpellState(spellID)
    local current = CallQuery(C_Spell, "IsCurrentSpell", "IsCurrentSpell", spellID)
    local autoRepeat = CallQuery(C_Spell, "IsAutoRepeatSpell", nil, spellID)
    local flashing = (current and CallQuery(C_Spell, "IsAutoAttackSpell", nil, spellID)) or autoRepeat
    return current or autoRepeat, flashing, false
end

local function GetFallbackItemState(item)
    return CallQuery(C_Item, "IsCurrentItem", "IsCurrentItem", item), false,
        CallQuery(C_Item, "IsEquippedItem", "IsEquippedItem", item)
end

local function GetFallbackActionState(action)
    if not action then
        return false, false, false
    end

    if action.kind == "spell" then
        return GetFallbackSpellState(action.id)
    elseif action.kind == "item" then
        return GetFallbackItemState(action.id)
    elseif action.kind == "macro" then
        -- A macro shows the state of the spell or item it currently casts.
        -- In combat these may be secret, so each value is checked with
        -- IsSecret before any boolean test.
        if type(GetMacroSpell) == "function" then
            local spellID = SafeCall(GetMacroSpell, action.id)
            if not IsSecret(spellID) and type(spellID) == "number" then
                return GetFallbackSpellState(spellID)
            end
        end
        if type(GetMacroItem) == "function" then
            local itemName, itemLink = SafeCall(GetMacroItem, action.id)
            if not IsSecret(itemLink) and type(itemLink) == "string" then
                return GetFallbackItemState(itemLink)
            elseif not IsSecret(itemName) and type(itemName) == "string" then
                return GetFallbackItemState(itemName)
            end
        end
    end

    return false, false, false
end

local function SetFlashing(button, flashing)
    flashing = flashing == true
    if button.flashing == flashing then
        return
    end
    button.flashing = flashing
    -- Like StartFlash: the first tick shows the flash right away.
    button.flashTime = 0
    if not flashing then
        button.visual.flash:Hide()
    end
end

local function UpdateActionState(button)
    local visual = button.visual
    local checked, flashing, equipped = false, false, false
    if button.hasAction then
        if button.actionSlot then
            checked, flashing, equipped = GetNativeActionState(button.actionSlot)
        else
            checked, flashing, equipped = GetFallbackActionState(button.actionData)
        end
    end

    visual.checked:SetShown(checked and visual.checked.artAvailable)
    visual.equippedBorder:SetShown(equipped and visual.equippedBorder.artAvailable)
    SetFlashing(button, flashing and visual.flash.artAvailable)
end

-- Auto Attack and Auto Shot blink at ATTACK_BUTTON_FLASH_TIME, like
-- ActionBarActionButtonMixin:OnUpdate. Driven by the addon's OnUpdate.
local function UpdateActionFlashes(elapsed)
    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button and button.flashing then
                local flashTime = button.flashTime - elapsed
                if flashTime <= 0 then
                    local overtime = -flashTime
                    if overtime >= FLASH_INTERVAL then
                        overtime = 0
                    end
                    flashTime = FLASH_INTERVAL - overtime
                    local flash = button.visual.flash
                    flash:SetShown(not flash:IsShown())
                end
                button.flashTime = flashTime
            end
        end
    end
end

-- Range feedback is polled with IsActionInRange instead of asking the client
-- to push ACTION_RANGE_CHECK_UPDATE for our slots: on Forever build 69913,
-- C_ActionBar.EnableActionRangeCheck trips a client assert (a hard crash that
-- pcall cannot catch) for gamepad storage slots that are not owned by a
-- native action button. The event handler is kept in case the client sends
-- updates for a slot anyway.
local function SetRangeCheckEnabled(button, enabled)
    enabled = enabled == true and button.actionSlot ~= nil
    if button.rangeCheckEnabled == enabled then
        return
    end

    button.rangeCheckEnabled = enabled
    if not enabled then
        button.visual.rangeIndicator:Hide()
    end
end

local function UpdateRangeIndicator(button, checksRange, inRange)
    local visual = button.visual
    if not checksRange or not button.hasAction then
        visual.rangeIndicator:Hide()
        visual.prompt:SetVertexColor(1, 1, 1)
        return
    end

    visual.rangeIndicator:Show()
    if inRange then
        local color = ACTIONBAR_HOTKEY_FONT_COLOR
        if color and color.GetRGB then
            visual.rangeIndicator:SetTextColor(color:GetRGB())
        else
            visual.rangeIndicator:SetTextColor(0.6, 0.6, 0.6)
        end
        visual.prompt:SetVertexColor(1, 1, 1)
    else
        local color = RED_FONT_COLOR
        if color and color.GetRGB then
            visual.rangeIndicator:SetTextColor(color:GetRGB())
        else
            visual.rangeIndicator:SetTextColor(1, 0.1, 0.1)
        end
        visual.prompt:SetVertexColor(0.55, 0.55, 0.55)
    end
end

-- Slash commands whose spell changes from cast to cast, in English and in
-- every localized alias the client registers (SLASH_CASTSEQUENCE1, 2, ...).
local spellChangingCommands
local function GetSpellChangingCommands()
    if not spellChangingCommands then
        spellChangingCommands = { "/castsequence", "/castrandom", "/userandom" }
        for _, key in ipairs({ "SLASH_CASTSEQUENCE", "SLASH_CASTRANDOM", "SLASH_USERANDOM" }) do
            local index = 1
            while type(_G[key .. index]) == "string" do
                spellChangingCommands[#spellChangingCommands + 1] = _G[key .. index]:lower()
                index = index + 1
            end
        end
    end
    return spellChangingCommands
end

-- A macro without conditionals, alternatives or sequences always casts the
-- same spell. Macros cannot be edited in combat, so its spell can be kept
-- like a plain spell's.
local function IsStaticMacroBody(body)
    if type(body) ~= "string" or IsSecret(body) then
        return false
    end
    local lower = body:lower()
    if lower:find("[", 1, true) or lower:find(";", 1, true) then
        return false
    end
    for _, command in ipairs(GetSpellChangingCommands()) do
        if lower:find(command, 1, true) then
            return false
        end
    end
    return true
end

-- Native slots only expose the macro's name. Two macros may share it, and
-- then GetMacroIndexByName may pick the other one, so a name is only trusted
-- when exactly one account or character macro has it.
local function IsUniqueMacroName(name)
    local numAccount, numCharacter = SafeCall(GetNumMacros)
    if type(numAccount) ~= "number" or type(numCharacter) ~= "number" then
        return false
    end
    local characterBase = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    local count = 0
    for index = 1, numAccount do
        if SafeCall(GetMacroInfo, index) == name then
            count = count + 1
        end
    end
    for index = characterBase + 1, characterBase + numCharacter do
        if SafeCall(GetMacroInfo, index) == name then
            count = count + 1
        end
    end
    return count == 1
end

-- Classifying a macro reads every macro, and the spell lookup runs on each
-- cooldown event, so the result is kept per slot until the slot's macro or
-- spell changes or macros are edited (RefreshButtons, on UPDATE_MACROS).
local macroCacheGeneration = 0

local function GetButtonMacroBody(button)
    local macroIndex
    if button.actionSlot then
        local name = SafeCall(GetActionText, button.actionSlot)
        if type(name) == "string" and not IsSecret(name) and IsUniqueMacroName(name) then
            macroIndex = SafeCall(GetMacroIndexByName, name)
        end
    elseif button.actionData then
        macroIndex = button.actionData.id
    end
    if type(macroIndex) ~= "number" or IsSecret(macroIndex) or macroIndex == 0 then
        return nil
    end
    local _, _, body = SafeCall(GetMacroInfo, macroIndex)
    return body
end

-- The spell behind a slot, as the native button resolves it for spell alerts
-- (ActionBarActionButtonMixin:UpdateSpellAlert): the spell itself, or the
-- spell a macro currently casts. In combat the client may answer with secret
-- values. Slot contents cannot change then, so the last readable ID of a
-- plain spell or a macro without conditionals is kept; a conditional macro's
-- is not, because [mod], [stance], [@target,harm], ... can switch the spell
-- it casts mid-fight.
local function GetButtonSpellID(button)
    if not button.hasAction then
        button.spellAlertSpellID = nil
        return nil
    end

    local spellID, isPlainSpell, isMacro
    if button.actionSlot then
        local actionType, id, subType = SafeCall(GetActionInfo, button.actionSlot)
        if IsSecret(actionType) or IsSecret(id) or IsSecret(subType) then
            return button.spellAlertSpellID
        end
        isPlainSpell = actionType == "spell"
        isMacro = actionType == "macro"
        if isPlainSpell or (isMacro and subType == "spell") then
            spellID = id
        end
    else
        local action = button.actionData
        if action and action.kind == "spell" then
            spellID = action.id
            isPlainSpell = true
        elseif action and action.kind == "macro" and type(GetMacroSpell) == "function" then
            spellID = SafeCall(GetMacroSpell, action.id)
            isMacro = true
        end
    end

    if IsSecret(spellID) then
        -- Fallback macros: nil unless the macro was static (see above).
        return button.spellAlertSpellID
    end
    if type(spellID) ~= "number" then
        spellID = nil
    end
    local keep = isPlainSpell
    if isMacro and spellID ~= nil then
        local macroKey = button.actionSlot and SafeCall(GetActionText, button.actionSlot) or button.actionData.id
        if IsSecret(macroKey) then
            macroKey = nil
        end
        if button.spellAlertMacroGeneration ~= macroCacheGeneration
            or button.spellAlertMacroKey ~= macroKey
            or button.spellAlertMacroSpell ~= spellID then
            button.spellAlertMacroGeneration = macroCacheGeneration
            button.spellAlertMacroKey = macroKey
            button.spellAlertMacroSpell = spellID
            button.spellAlertMacroStatic = IsStaticMacroBody(GetButtonMacroBody(button))
        end
        keep = button.spellAlertMacroStatic
    end
    button.spellAlertSpellID = keep and spellID or nil
    return spellID
end

-- Native spell alerts are sized 1.4x the button (ActionButtonSpellAlerts.lua).
local SPELL_ALERT_SCALE = 1.4

local function ResumeSpellAlertLoop(frame)
    if not frame.ProcStartAnim:IsPlaying() and not frame.ProcLoop:IsPlaying() then
        frame.ProcLoop:Play()
    end
end

-- Uses the same template and animations as the native action buttons, but on
-- our own frame instead of through ActionButtonSpellAlertManager, so no
-- Blizzard state is written from addon code.
local function GetSpellAlertFrame(button)
    local visual = button.visual
    if visual.spellAlert or visual.spellAlertUnavailable then
        return visual.spellAlert
    end

    local ok, frame = pcall(CreateFrame, "Frame", nil, visual, "ActionButtonSpellAlertTemplate")
    if not ok or not frame or not frame.ProcStartAnim or not frame.ProcLoop then
        visual.spellAlertUnavailable = true
        return nil
    end

    frame:SetPoint("CENTER")
    local width, height = visual:GetSize()
    frame:SetSize(width * SPELL_ALERT_SCALE, height * SPELL_ALERT_SCALE)
    frame:SetFrameLevel(visual.cooldown:GetFrameLevel() + 1)
    -- Animations stop while the panels are hidden (gamepadOnly, interface
    -- transitions); resume an active glow when they are shown again.
    frame:HookScript("OnShow", function(self)
        if button.spellAlertShown then
            ResumeSpellAlertLoop(self)
        end
    end)
    visual.spellAlert = frame
    return frame
end

-- shown may be a secret boolean (IsSpellOverlayed in combat). Addon code
-- cannot test it, so the glow keeps looping and the client applies it as
-- the frame's alpha through SetAlphaFromBoolean.
local function SetSpellAlertShown(button, shown)
    if IsSecret(shown) then
        local frame = GetSpellAlertFrame(button)
        if not frame or type(frame.SetAlphaFromBoolean) ~= "function" then
            return
        end
        frame:SetAlphaFromBoolean(shown, 1, 0)
        frame:Show()
        button.spellAlertShown = true
        ResumeSpellAlertLoop(frame)
        button.spellAlertSecret = true
        return
    end

    local frame = shown and GetSpellAlertFrame(button) or button.visual.spellAlert
    if not frame then
        return
    end

    if button.spellAlertSecret then
        -- Back to a readable answer: drop the secret alpha. A glow that was
        -- already looping continues without the birth animation.
        button.spellAlertSecret = false
        frame:SetAlpha(1)
    end

    if not shown then
        if button.spellAlertShown then
            frame:Hide()
            frame.ProcStartAnim:Stop()
            frame.ProcLoop:Stop()
            button.spellAlertShown = false
        end
        return
    end

    if not button.spellAlertShown then
        -- Shown before the flag is set, so the OnShow hook does not start the
        -- loop on top of the birth animation.
        frame:Show()
        button.spellAlertShown = true
        frame.ProcStartAnim:Play()
    else
        -- The loop stops while the panel is hidden; resume it without the
        -- birth animation, like ShowAlert with skipBirth.
        ResumeSpellAlertLoop(frame)
    end
end

-- Proc state reported by SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / _HIDE, keyed by
-- spell ID like the native OnEvent matches it. It takes precedence over
-- IsSpellOverlayed, which may answer with a secret value in combat; the query
-- covers procs that were already active before the addon loaded. An event
-- with a secret spell ID cannot be recorded, so it clears the table and every
-- slot falls back to the live query instead of a state that may be stale.
local overlayedSpells = {}
local spellAlertStats = { events = 0, secretEvents = 0, secretQueries = 0, history = {} }
local SPELL_ALERT_HISTORY_SIZE = 6

local function GetSpellName(spellID)
    local name
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        name = SafeCall(C_Spell.GetSpellName, spellID)
    elseif type(GetSpellInfo) == "function" then
        name = SafeCall(GetSpellInfo, spellID)
    end
    if IsSecret(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

local function IsSpellAlertActive(button, spellID)
    if not spellID then
        return false
    end
    if overlayedSpells[spellID] ~= nil then
        return overlayedSpells[spellID]
    end
    local overlayed = C_SpellActivationOverlay
        and SafeCall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
    if IsSecret(overlayed) then
        spellAlertStats.secretQueries = spellAlertStats.secretQueries + 1
        return overlayed
    end
    if overlayed == true then
        spellAlertStats.lastOverlayed = string.format("%s (%s)", tostring(spellID), tostring(GetSpellName(spellID) or "unknown"))
    end
    return overlayed == true
end

local spellAlertTest = false

local function UpdateSpellAlert(button)
    if GetPaddleBehaviorIcon(button.paddleIndex) then
        SetSpellAlertShown(button, false)
        return
    end
    if spellAlertTest then
        SetSpellAlertShown(button, button.hasAction == true)
        return
    end
    SetSpellAlertShown(button, IsSpellAlertActive(button, GetButtonSpellID(button)))
end

-- /grip glowtest: shows the glow on every filled slot regardless of procs,
-- to tell a drawing problem apart from a proc detection problem. Returns how
-- many slots show it and how many failed to create the template.
local function SetSpellAlertTest(enabled)
    spellAlertTest = enabled == true
    local shown, failed = 0, 0
    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button then
                UpdateSpellAlert(button)
                if button.spellAlertShown then
                    shown = shown + 1
                elseif spellAlertTest and button.hasAction and button.visual.spellAlertUnavailable then
                    failed = failed + 1
                end
            end
        end
    end
    return shown, failed
end

local function OnSpellAlertEvent(spellID, shown)
    spellAlertStats.events = spellAlertStats.events + 1
    if IsSecret(spellID) then
        spellAlertStats.secretEvents = spellAlertStats.secretEvents + 1
        spellAlertStats.last = (shown and "show" or "hide") .. " (secret spell)"
        wipe(overlayedSpells)
    else
        local name = type(spellID) == "number" and GetSpellName(spellID) or nil
        spellAlertStats.last = string.format("%s %s (%s)", shown and "show" or "hide",
            tostring(spellID), tostring(name or "unknown"))
        if type(spellID) == "number" then
            overlayedSpells[spellID] = shown
        end
    end
    local history = spellAlertStats.history
    table.insert(history, 1, spellAlertStats.last)
    history[SPELL_ALERT_HISTORY_SIZE + 1] = nil

    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button then
                UpdateSpellAlert(button)
            end
        end
    end
end

-- Lines for /grip diag: what each filled slot resolves to and whether
-- its glow is showing.
local function GetSpellAlertDiagnosticLines()
    local lines = {}
    local template = (C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and SafeCall(C_XMLUtil.GetTemplateInfo, "ActionButtonSpellAlertTemplate")) and "yes" or "unknown"
    lines[1] = string.format("Proc glow: %stemplate=%s, IsSpellOverlayed=%s, events=%d (secret %d), secret queries=%d, last overlayed=%s",
        spellAlertTest and "TEST MODE, " or "", template,
        tostring(C_SpellActivationOverlay ~= nil and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function"),
        spellAlertStats.events, spellAlertStats.secretEvents, spellAlertStats.secretQueries,
        tostring(spellAlertStats.lastOverlayed or "none"))
    lines[2] = "  Recent proc events (newest first): "
        .. (#spellAlertStats.history > 0 and table.concat(spellAlertStats.history, "; ") or "none")

    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button and button.hasAction then
                local actionText = "fallback"
                if button.actionSlot then
                    local actionType, id, subType = SafeCall(GetActionInfo, button.actionSlot)
                    if IsSecret(actionType) or IsSecret(id) or IsSecret(subType) then
                        actionText = "slot " .. button.actionSlot .. " secret"
                    else
                        actionText = string.format("slot %d %s/%s/%s", button.actionSlot,
                            tostring(actionType), tostring(id), tostring(subType))
                    end
                end
                local spellID = GetButtonSpellID(button)
                local overlayed = spellID and C_SpellActivationOverlay
                    and SafeCall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
                lines[#lines + 1] = string.format("  %s P%d: %s, spell=%s (%s), overlayed=%s, event=%s, glow=%s%s",
                    PANELS[panelIndex].label, paddleIndex, actionText, tostring(spellID),
                    tostring(spellID and GetSpellName(spellID) or "-"),
                    IsSecret(overlayed) and "secret" or tostring(overlayed),
                    spellID and tostring(overlayedSpells[spellID]) or "nil",
                    button.spellAlertSecret and "secret" or (button.spellAlertShown and "shown" or "hidden"),
                    button.visual.spellAlertUnavailable and " (template failed)" or "")
            end
        end
    end
    return lines
end

local function ShouldShowPrompts()
    return GripbarDB.showPaddleBadges ~= false and GetNativeCVarBool(NATIVE_CVAR_PROMPTS, true)
end

local function UpdatePromptVisibility(button)
    local panel = panelFrames[button.panelIndex]
    local shown = panel ~= nil and panel.isFocused == true and button.hasAction == true and ShouldShowPrompts()
    local text = UsesTextGlyph(button.paddleIndex)
    button.visual.prompt:SetShown(shown and not text and button.visual.prompt.artAvailable)
    if button.visual.promptLabel then
        local alpha = tonumber(GripbarDB and GripbarDB.promptLabelOpacity) or 0
        button.visual.promptLabel:SetText(PaddleName(button.paddleIndex))
        button.visual.promptLabel:SetAlpha(alpha)
        button.visual.promptLabel:SetShown(shown and text)
    end
end

-- A paddle set to page the crossbar never fires its slots. They show only
-- the paging arrow, or nothing at all with showPageArrows off (the slots
-- still page when clicked); the actions stored in them are kept, without
-- their cooldowns, counts or states, for when it goes back to paddle
-- actions. The visual frame is not secure, so this is safe in combat.
local function UpdateNavigationVisual(button, navIcon)
    local visual = button.visual
    visual:SetShown(GripbarDB.showPageArrows ~= false)
    button.hasAction = false
    ClearCooldown(button)
    visual.icon:SetTexture(navIcon)
    visual.icon:SetVertexColor(1, 1, 1)
    visual.icon:Show()
    SetEmptyGlyphShown(button, false)
    visual.count:SetText("")
    UpdateActionState(button)
    SetRangeCheckEnabled(button, false)
    UpdateRangeIndicator(button, false, false)
    UpdateSpellAlert(button)
    UpdatePromptVisibility(button)
end

local function UpdateButtonVisual(button)
    local navIcon = GetPaddleBehaviorIcon(button.paddleIndex)
    if navIcon then
        UpdateNavigationVisual(button, navIcon)
        return
    end

    local visual = button.visual
    visual:Show()
    local icon
    local hasAction = false

    if button.actionSlot then
        hasAction = C_ActionBar.HasAction(button.actionSlot)
        if hasAction then
            icon = GetActionTexture(button.actionSlot)
        end
        UpdateNativeCooldown(button)
    else
        icon = GetFallbackActionDisplay(button.actionData)
        hasAction = icon ~= nil
        UpdateFallbackCooldown(button)
    end

    button.hasAction = hasAction

    if icon then
        visual.icon:SetTexture(icon)
        visual.icon:Show()
        SetEmptyGlyphShown(button, false)
    else
        visual.icon:SetTexture(nil)
        visual.icon:Hide()
        SetEmptyGlyphShown(button, true)
    end

    UpdateUsableTint(button, hasAction)
    UpdateActionState(button)

    local count
    if button.actionSlot and hasAction then
        if C_ActionBar and type(C_ActionBar.GetActionDisplayCount) == "function" then
            count = SafeCall(C_ActionBar.GetActionDisplayCount, button.actionSlot)
        else
            count = GetActionCount(button.actionSlot)
        end
    elseif button.actionData and button.actionData.kind == "item" and C_Item and type(C_Item.GetItemCount) == "function" then
        count = SafeCall(C_Item.GetItemCount, button.actionData.id)
    elseif button.actionData and button.actionData.kind == "spell" and C_Spell then
        -- Charges or use count, the same text GetActionDisplayCount gives.
        count = SafeCall(C_Spell.GetSpellDisplayCount, button.actionData.id)
    end
    if IsSecret(count) or type(count) == "string" then
        -- GetActionDisplayCount and GetSpellDisplayCount already return
        -- display-ready text (including "0" or "1" charges); the native buttons
        -- pass it straight to SetText, which accepts secret values.
        visual.count:SetText(count)
    else
        if type(count) == "number" and count <= 1 then
            count = nil
        end
        visual.count:SetText(count and tostring(count) or "")
    end

    SetRangeCheckEnabled(button, hasAction)
    if not hasAction then
        UpdateRangeIndicator(button, false, false)
    end
    UpdateSpellAlert(button)
    UpdatePromptVisibility(button)
end

local function ApplyFallbackSecureAction(button)
    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", nil)

    local action = button.actionData
    if not action then
        return
    end

    if action.kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", action.id)
    elseif action.kind == "item" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. tostring(action.id))
    elseif action.kind == "macro" then
        local _, _, body = GetMacroInfo(action.id)
        if body and body ~= "" then
            button:SetAttribute("type", "macro")
            button:SetAttribute("macrotext", body)
        end
    end
end

local function ConfigureSecureAction(button)
    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    if button.actionSlot then
        button:SetAttribute("type", "action")
        -- one slot per crossbar page; the page pre-click picks one.
        for page = 1, ns.pageCount or 1 do
            button:SetAttribute("action-page" .. page, GetNativeSlot(button.panelIndex, button.paddleIndex, page))
        end
        button:SetAttribute("action", button.actionSlot)
    else
        ApplyFallbackSecureAction(button)
    end
    -- A navigation paddle's slots page instead (overrides the type).
    ApplySlotNavigation(button, GetPaddleBehavior(button.paddleIndex))
    focusRouting.SyncAttributes(button)
end

local function ConvertCursorToFallbackAction()
    local cursorType, a, b, c = GetCursorInfo()
    if not cursorType then
        return nil
    end

    if cursorType == "spell" then
        local spellID = c or a
        if spellID then
            return { kind = "spell", id = spellID }
        end
    elseif cursorType == "item" and a then
        return { kind = "item", id = a }
    elseif cursorType == "macro" and a then
        return { kind = "macro", id = a }
    elseif cursorType == "action" then
        local actionType, id, subType = GetActionInfo(a)
        if actionType == "spell" and id then
            return { kind = "spell", id = id }
        elseif actionType == "item" and id then
            return { kind = "item", id = id }
        elseif actionType == "macro" and id then
            return { kind = "macro", id = id }
        elseif actionType == "companion" and subType == "MOUNT" and id then
            return { kind = "spell", id = id }
        end
    end

    return nil
end

local function SetFallbackAction(button, action)
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    GripbarCharDB.fallbackActions[button.panelIndex][button.paddleIndex] = action
    button.actionData = action
    ConfigureSecureAction(button)
    UpdateButtonVisual(button)
end

local function PutCursorIntoButton(button)
    -- Slots of a paddle that pages the crossbar show only the arrow.
    if GetPaddleBehaviorIcon(button.paddleIndex) then
        return
    end
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    if button.actionSlot then
        local cursorType = GetCursorInfo()
        if not cursorType then
            return
        end

        local ok = pcall(C_ActionBar.PutActionInSlot, button.actionSlot)
        if not ok then
            Print("The client rejected that action for native gamepad storage.")
            return
        end
        UpdateButtonVisual(button)
        return
    end

    local action = ConvertCursorToFallbackAction()
    if not action then
        Print("That cursor payload is not supported by fallback storage.")
        return
    end

    SetFallbackAction(button, action)
    ClearCursor()
end

local function PickupButtonAction(button)
    if GetPaddleBehaviorIcon(button.paddleIndex) then
        return
    end
    if InCombatLockdown() then
        return
    end
    -- Like ActionButton OnDragStart: locked bars only give up actions with the
    -- pickup modifier held. Edit Mode and the addon's unlock count as unlocked.
    if GetNativeCVarBool("lockActionBars", false)
        and not (type(IsModifiedClick) == "function" and IsModifiedClick("PICKUPACTION")) then
        return
    end

    if button.actionSlot then
        if C_ActionBar.HasAction(button.actionSlot) then
            PickupAction(button.actionSlot)
            UpdateButtonVisual(button)
        end
        return
    end

    local action = button.actionData
    if not action then
        return
    end

    if action.kind == "spell" then
        if C_Spell and C_Spell.PickupSpell then
            C_Spell.PickupSpell(action.id)
        elseif PickupSpell then
            PickupSpell(action.id)
        end
    elseif action.kind == "item" then
        if C_Item and C_Item.PickupItem then
            C_Item.PickupItem(action.id)
        elseif PickupItem then
            PickupItem(action.id)
        end
    elseif action.kind == "macro" then
        PickupMacro(action.id)
    end
end

local function ClearButtonAction(button)
    if InCombatLockdown() then
        Print("Actions cannot be changed during combat.")
        return
    end

    if button.actionSlot then
        if C_ActionBar.HasAction(button.actionSlot) then
            PickupAction(button.actionSlot)
            ClearCursor()
        end
        UpdateButtonVisual(button)
    else
        SetFallbackAction(button, nil)
    end
end

local function ShowTooltip(button)
    button.visual.highlight:SetShown(button.visual.highlight.artAvailable)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    local behavior = GetPaddleBehavior(button.paddleIndex)
    if behavior.icon then
        GameTooltip:AddLine("Paddle " .. PaddleName(button.paddleIndex) .. ": " .. behavior.label)
        GameTooltip:AddLine("This paddle pages the native crossbar on every layer. Change it on the Gripbar settings page or with /grip paddle.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end

    if button.actionSlot and C_ActionBar.HasAction(button.actionSlot) then
        if GameTooltip.SetAction then
            GameTooltip:SetAction(button.actionSlot)
            return
        end
    elseif button.actionData then
        local action = button.actionData
        if action.kind == "spell" then
            GameTooltip:SetHyperlink("spell:" .. tostring(action.id))
            return
        elseif action.kind == "item" then
            GameTooltip:SetHyperlink("item:" .. tostring(action.id))
            return
        elseif action.kind == "macro" then
            local name, _, body = GetMacroInfo(action.id)
            GameTooltip:AddLine(name or "Macro")
            if body and body ~= "" then
                GameTooltip:AddLine(body, 1, 1, 1, true)
            end
            GameTooltip:Show()
            return
        end
    end

    local panel = PANELS[button.panelIndex]
    GameTooltip:AddLine(panel.label .. " · Paddle " .. PaddleName(button.paddleIndex))
    GameTooltip:AddLine("Drop an action here.", 1, 1, 1, true)
    if ns.nativeStorageEnabled then
        GameTooltip:AddLine("Native gamepad action storage", 0.55, 0.8, 1.0, true)
    end
    GameTooltip:Show()
end

local function HideTooltip(button)
    button.visual.highlight:Hide()
    GameTooltip:Hide()
end

-- Layout: GRID_CELLS keeps the original reading order (P1 top-left,
-- P2 top-right, P3 bottom-left, P4 bottom-right); the cells are spread to the
-- corners of a rectangle around the bar centre instead of a tight 2 x 2 grid.
-- the HUD scale only resizes each slot around its own centre; the
-- slot positions (spread) are not scaled.
local function GetHudScale()
    local scale = tonumber(GripbarDB and GripbarDB.hudScale) or 1
    if scale <= 0 then
        scale = 1
    end
    return scale
end

-- the top row (P1 / P2, L4 / R4) and the bottom row (P3 / P4,
-- L5 / R5) have their own horizontal and vertical distance from the bar
-- centre. row: 0 = top, 1 = bottom.
local function GetPaddleSpread(row)
    local db = GripbarDB or {}
    if row == 1 then
        return tonumber(db.spreadBottomX) or LAYOUT.SPREAD_BOTTOM_X,
            tonumber(db.spreadBottomY) or LAYOUT.SPREAD_BOTTOM_Y
    end
    return tonumber(db.spreadTopX) or LAYOUT.SPREAD_TOP_X,
        tonumber(db.spreadTopY) or LAYOUT.SPREAD_TOP_Y
end

local function GetButtonCenter(paddleIndex, expanded)
    local cell = GRID_CELLS[paddleIndex]
    local spreadX, spreadY = GetPaddleSpread(cell.row)
    local factor = expanded and LAYOUT.EXPAND_RATIO or 1
    local signX = cell.col == 0 and -1 or 1
    local signY = cell.row == 0 and 1 or -1
    return signX * spreadX * factor, LAYOUT.GRID_CENTER_Y + signY * spreadY * factor
end

-- Panel size that holds the expanded rectangle (edit overlay, clamping).
local function GetPanelSize()
    local topX, topY = GetPaddleSpread(0)
    local bottomX, bottomY = GetPaddleSpread(1)
    local spreadX, spreadY = math.max(topX, bottomX), math.max(topY, bottomY)
    local half = LAYOUT.BUTTON_SIZE_EXPANDED * GetHudScale() / 2 + LAYOUT.PANEL_MARGIN
    return 2 * (spreadX * LAYOUT.EXPAND_RATIO + half), 2 * (spreadY * LAYOUT.EXPAND_RATIO + half)
end

-- Positions and sizes the non-secure art of a slot. The secure click target
-- itself never moves, so this is safe to call during combat.
local function LayoutButtonVisual(button)
    local panel = panelFrames[button.panelIndex]
    local visual = button.visual
    if not panel or not visual then
        return
    end

    local expanded = panel.expanded == true
    local hudScale = GetHudScale()
    local size = (expanded and LAYOUT.BUTTON_SIZE_EXPANDED or LAYOUT.BUTTON_SIZE_COLLAPSED) * hudScale
    local x, y = GetButtonCenter(button.paddleIndex, expanded)
    if button.pushed then
        size = size - LAYOUT.BUTTON_PRESSED_SIZE_OFFSET * hudScale
        y = y - (LAYOUT.BUTTON_PRESSED_SIZE_OFFSET * hudScale * 0.5)
    end

    visual:SetSize(size, size)
    visual:SetAlpha(tonumber(GripbarDB and GripbarDB.slotOpacity) or 1)
    visual:ClearAllPoints()
    visual:SetPoint("CENTER", panel, "CENTER", x, y)
    visual.emptyGlyph:SetSize(size * LAYOUT.EMPTY_GLYPH_RATIO, size * LAYOUT.EMPTY_GLYPH_RATIO)
    -- the stack / charge count scales with the slot (HUD scale and
    -- focus), like the native buttons whose text scales with them.
    if visual.count and visual.countFont then
        local ratio = size / LAYOUT.BUTTON_SIZE_EXPANDED
        -- 1.15: a touch larger than the base count font, for readability.
        local fontSize = visual.countFontSize * ratio * LAYOUT.COUNT_TEXT_SCALE
        visual.count:SetFont(visual.countFont, math.max(7, math.floor(fontSize + 0.5)), visual.countFontFlags)
        visual.count:ClearAllPoints()
        visual.count:SetPoint("BOTTOMRIGHT", -5 * ratio, 5 * ratio)
    end

    if visual.emptyLabel and visual.labelFont then
        local fontSize = math.max(8, math.floor(size * 0.36 + 0.5))
        visual.emptyLabel:SetFont(visual.labelFont, fontSize, "OUTLINE")
        visual.emptyLabel:SetSize(size, size)
        visual.emptyLabel:SetAlpha(tonumber(GripbarDB and GripbarDB.emptyLabelOpacity) or 1)
        if visual.emptyArt then
            visual.emptyArt:SetSize(size, size)
            visual.emptyArt:SetAlpha(tonumber(GripbarDB and GripbarDB.emptyLabelOpacity) or 1)
        end
        if visual.promptLabel then
            visual.promptLabel:SetFont(visual.labelFont, fontSize, "OUTLINE")
            visual.promptLabel:SetSize(size, size)
            visual.promptLabel:SetAlpha(tonumber(GripbarDB and GripbarDB.promptLabelOpacity) or 0)
        end
    end
    if visual.spellAlert then
        visual.spellAlert:SetSize(size * SPELL_ALERT_SCALE, size * SPELL_ALERT_SCALE)
    end

    local shadowDistance = (expanded and LAYOUT.SHADOW_DISTANCE_EXPANDED or LAYOUT.SHADOW_DISTANCE_COLLAPSED) * hudScale
    for _, shadow in ipairs({ visual.shadow, visual.shadowFocus }) do
        shadow:ClearAllPoints()
        shadow:SetPoint("TOPLEFT", -shadowDistance, shadowDistance)
        shadow:SetPoint("BOTTOMRIGHT", shadowDistance, -shadowDistance)
    end
    visual.shadow:SetShown(not expanded and visual.shadow.artAvailable)
    visual.shadowFocus:SetShown(expanded and visual.shadowFocus.artAvailable)

    local showPressed = button.pushed and visual.borderPressed.artAvailable
    visual.borderPressed:SetShown(showPressed)
    visual.border:SetShown(not showPressed)
end

local function SetButtonPushed(button, pushed)
    pushed = pushed == true
    if button.pushed == pushed then
        return
    end
    button.pushed = pushed
    LayoutButtonVisual(button)
end

local function CreateActionButton(panelIndex, paddleIndex, panel)
    local name = string.format("GripbarButton%d_%d", panelIndex, paddleIndex)
    local button = CreateFrame("Button", name, panel, "SecureActionButtonTemplate")
    button.panelIndex = panelIndex
    button.paddleIndex = paddleIndex
    button.pushed = false
    button.hasAction = false
    button.flashing = false
    button.flashTime = 0
    button:SetSize(LAYOUT.BUTTON_SIZE_EXPANDED, LAYOUT.BUTTON_SIZE_EXPANDED)
    button:SetFrameLevel(panel:GetFrameLevel() + 10)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    -- Native gamepad action buttons trigger on press rather than on release.
    button:SetAttribute("useOnKeyDown", true)

    -- The secure button is only the click target. All art lives on a plain
    -- frame so it can be resized and re-anchored while in combat.
    local visual = CreateFrame("Frame", nil, panel)
    visual:SetFrameLevel(panel:GetFrameLevel() + 5)
    visual:SetSize(LAYOUT.BUTTON_SIZE_COLLAPSED, LAYOUT.BUTTON_SIZE_COLLAPSED)
    button.visual = visual

    visual.shadow = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
    ApplyArt(visual.shadow, ATLAS.shadow, nil)
    visual.shadow:Hide()

    visual.shadowFocus = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
    ApplyArt(visual.shadowFocus, ATLAS.shadowFocus, nil)
    visual.shadowFocus:Hide()

    visual.slotArt = visual:CreateTexture(nil, "BACKGROUND", nil, 0)
    visual.slotArt:SetAllPoints()
    visual.slotArt:SetTexture(GetMedia("SlotBase"))

    visual.icon = visual:CreateTexture(nil, "BACKGROUND", nil, 1)
    visual.icon:SetAllPoints()
    visual.icon:Hide()

    if visual.CreateMaskTexture and visual.icon.AddMaskTexture then
        visual.iconMask = visual:CreateMaskTexture()
        visual.iconMask:SetPoint("TOPLEFT", 3, -3)
        visual.iconMask:SetPoint("BOTTOMRIGHT", -3, 3)
        if AtlasExists(ATLAS.circleMask) then
            visual.iconMask:SetAtlas(ATLAS.circleMask)
        else
            visual.iconMask:SetTexture(GetMedia("CircleMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        visual.icon:AddMaskTexture(visual.iconMask)
    end

    -- Empty slots show the paddle glyph the way native slots show their face button.
    visual.emptyGlyph = visual:CreateTexture(nil, "ARTWORK", nil, 0)
    visual.emptyGlyph:SetPoint("CENTER")
    visual.emptyGlyph:SetTexture(GetPaddleTexture(paddleIndex))
    visual.emptyGlyph.artAvailable = true
    visual.emptyGlyph:SetAlpha(0.9)

    -- text glyph for named buttons (L4, R5, ...).
    visual.labelFont = (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"
    -- the labels sit on their own layer above the slot, so the
    -- slot opacity (visual alpha) and the label opacity are independent.
    visual.labelLayer = CreateFrame("Frame", nil, panel)
    visual.labelLayer:SetAllPoints(visual)
    visual.labelLayer:SetFrameLevel(visual:GetFrameLevel() + 20)
    visual.emptyLabel = visual.labelLayer:CreateFontString(nil, "ARTWORK", nil, 0)
    visual.emptyLabel:SetPoint("CENTER", visual, "CENTER", 0, 0)
    visual.emptyLabel:SetJustifyH("CENTER")
    visual.emptyLabel:SetJustifyV("MIDDLE")
    visual.emptyLabel:SetWordWrap(false)
    visual.emptyLabel:SetFont(visual.labelFont, 14, "OUTLINE")
    visual.emptyLabel:SetTextColor(0.85, 0.85, 0.85, 0.9)
    visual.emptyLabel:Hide()

    visual.emptyArt = visual.labelLayer:CreateTexture(nil, "ARTWORK", nil, 0)
    visual.emptyArt:SetPoint("CENTER", visual, "CENTER", 0, 0)
    visual.emptyArt:Hide()

    -- Auto Attack / Auto Shot flash, masked to the icon like the native Flash.
    visual.flash = visual:CreateTexture(nil, "ARTWORK", nil, 0)
    visual.flash:SetAllPoints()
    ApplyArt(visual.flash, ATLAS.flash, nil)
    if visual.iconMask then
        visual.flash:AddMaskTexture(visual.iconMask)
    end
    visual.flash:Hide()

    visual.cooldown = CreateFrame("Cooldown", nil, visual, "CooldownFrameTemplate")
    visual.cooldown:SetPoint("TOPLEFT", 3, -3)
    visual.cooldown:SetPoint("BOTTOMRIGHT", -3, 3)
    if visual.cooldown.SetSwipeTexture then
        visual.cooldown:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        visual.cooldown:SetSwipeColor(0, 0, 0, 0.64)
    end
    if visual.cooldown.SetDrawBling then
        visual.cooldown:SetDrawBling(false)
    end
    if visual.cooldown.SetDrawEdge then
        visual.cooldown:SetDrawEdge(false)
    end

    -- Red lockout swipe while stunned, silenced or school-locked, like the
    -- native lossOfControlCooldown (round swipe to match the icon mask).
    visual.lossOfControlCooldown = CreateFrame("Cooldown", nil, visual, "CooldownFrameTemplate")
    visual.lossOfControlCooldown:SetPoint("TOPLEFT", 3, -3)
    visual.lossOfControlCooldown:SetPoint("BOTTOMRIGHT", -3, 3)
    visual.lossOfControlCooldown:SetFrameLevel(visual.cooldown:GetFrameLevel())
    if visual.lossOfControlCooldown.SetSwipeTexture then
        visual.lossOfControlCooldown:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        visual.lossOfControlCooldown:SetSwipeColor(0.17, 0, 0, 0.64)
    end
    if visual.lossOfControlCooldown.SetEdgeTexture then
        visual.lossOfControlCooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-LoC")
    end
    if visual.lossOfControlCooldown.SetDrawBling then
        visual.lossOfControlCooldown:SetDrawBling(false)
    end
    if visual.lossOfControlCooldown.SetHideCountdownNumbers then
        visual.lossOfControlCooldown:SetHideCountdownNumbers(true)
    end

    -- Recharge edge for charge spells: no swipe, only the moving edge, like
    -- the native chargeCooldown.
    visual.chargeCooldown = CreateFrame("Cooldown", nil, visual, "CooldownFrameTemplate")
    visual.chargeCooldown:SetPoint("TOPLEFT", 2, -2)
    visual.chargeCooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    visual.chargeCooldown:SetFrameLevel(visual.cooldown:GetFrameLevel())
    if visual.chargeCooldown.SetDrawSwipe then
        visual.chargeCooldown:SetDrawSwipe(false)
    end
    if visual.chargeCooldown.SetHideCountdownNumbers then
        visual.chargeCooldown:SetHideCountdownNumbers(true)
    end

    visual.border = visual:CreateTexture(nil, "ARTWORK", nil, 1)
    visual.border:SetAllPoints()
    ApplyArt(visual.border, ATLAS.border, GetMedia("SlotRing"))

    visual.borderPressed = visual:CreateTexture(nil, "ARTWORK", nil, 1)
    visual.borderPressed:SetAllPoints()
    ApplyArt(visual.borderPressed, ATLAS.borderPressed, GetMedia("PressedOverlay"))
    visual.borderPressed:Hide()

    -- Active (current or auto-repeating) action, like the native CheckedTexture.
    visual.checked = visual:CreateTexture(nil, "ARTWORK", nil, 2)
    visual.checked:SetPoint("TOPLEFT", -LAYOUT.CHECKED_DISTANCE, LAYOUT.CHECKED_DISTANCE)
    visual.checked:SetPoint("BOTTOMRIGHT", LAYOUT.CHECKED_DISTANCE, -LAYOUT.CHECKED_DISTANCE)
    ApplyArt(visual.checked, ATLAS.borderChecked, GetMedia("SlotHighlight"))
    visual.checked:Hide()

    -- Equipped items get the native green icon frame border.
    visual.equippedBorder = visual:CreateTexture(nil, "OVERLAY", nil, -1)
    visual.equippedBorder:SetAllPoints()
    ApplyArt(visual.equippedBorder, ATLAS.iconFrameBorder, GetMedia("SlotRing"))
    visual.equippedBorder:SetVertexColor(0, 1.0, 0, 0.5)
    visual.equippedBorder:Hide()

    visual.highlight = visual:CreateTexture(nil, "OVERLAY", nil, 0)
    visual.highlight:SetAllPoints()
    ApplyArt(visual.highlight, ATLAS.borderHover, GetMedia("SlotHighlight"))
    visual.highlight:Hide()

    -- Button prompt shown on the focused bar, like the native ButtonIcon.
    visual.prompt = visual:CreateTexture(nil, "OVERLAY", nil, 2)
    visual.prompt:SetSize(LAYOUT.PROMPT_ICON_SIZE, LAYOUT.PROMPT_ICON_SIZE)
    visual.prompt:SetPoint("TOPRIGHT", -1, -1)
    visual.prompt:SetTexture(GetPaddleTexture(paddleIndex))
    visual.prompt.artAvailable = true
    visual.prompt:Hide()

    -- Centred on the slot like the empty-slot label; hidden by default
    -- (Filled slot label opacity 0).
    visual.promptLabel = visual.labelLayer:CreateFontString(nil, "OVERLAY", nil, 2)
    visual.promptLabel:SetPoint("CENTER", visual, "CENTER", 0, 0)
    visual.promptLabel:SetJustifyH("CENTER")
    visual.promptLabel:SetJustifyV("MIDDLE")
    visual.promptLabel:SetWordWrap(false)
    visual.promptLabel:SetFont(visual.labelFont, 10, "OUTLINE")
    visual.promptLabel:SetTextColor(1, 1, 1)
    visual.promptLabel:Hide()

    visual.count = visual:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    visual.count:SetPoint("BOTTOMRIGHT", -5, 5)
    visual.count:SetJustifyH("RIGHT")
    visual.countFont, visual.countFontSize, visual.countFontFlags = visual.count:GetFont()
    visual.countFontSize = tonumber(visual.countFontSize) or 14

    visual.rangeIndicator = visual:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    visual.rangeIndicator:SetPoint("CENTER", 10, 10)
    visual.rangeIndicator:SetText(RANGE_INDICATOR or "●")
    visual.rangeIndicator:Hide()

    -- Aliases used by the shared cooldown helpers.
    button.icon = visual.icon
    button.cooldown = visual.cooldown
    button.chargeCooldown = visual.chargeCooldown
    button.lossOfControlCooldown = visual.lossOfControlCooldown
    button.count = visual.count

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function(self)
        HideTooltip(self)
        SetButtonPushed(self, false)
    end)
    button:SetScript("PostClick", function(self, _, down)
        SetButtonPushed(self, down == true)
    end)
    button:SetScript("OnHide", function(self)
        SetButtonPushed(self, false)
    end)
    button:SetScript("OnReceiveDrag", PutCursorIntoButton)
    button:SetScript("OnDragStart", PickupButtonAction)

    if ns.nativeStorageEnabled then
        button.actionSlot = GetNativeSlot(panelIndex, paddleIndex, ns.currentPage or 1)
        if ns.WrapPagedButton then
            ns.WrapPagedButton(button)
        end
    else
        button.actionData = GripbarCharDB.fallbackActions[panelIndex][paddleIndex]
    end

    buttons[panelIndex][paddleIndex] = button
    ConfigureSecureAction(button)
    LayoutButtonVisual(button)
    UpdateButtonVisual(button)
    return button
end

local function ForEachButton(func)
    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            local button = buttons[panelIndex] and buttons[panelIndex][paddleIndex]
            if button then
                func(button, panelIndex, paddleIndex)
            end
        end
    end
end

-- Visual-only refresh; safe to run in combat and on high-frequency events.
local function UpdateAllButtonVisuals()
    ForEachButton(UpdateButtonVisual)
end

-- Full refresh including secure attributes. Deferred while in combat.
local function RefreshButtons()
    macroCacheGeneration = macroCacheGeneration + 1
    ForEachButton(function(button, panelIndex, paddleIndex)
        if not button.actionSlot then
            button.actionData = GripbarCharDB.fallbackActions[panelIndex][paddleIndex]
        end
        ConfigureSecureAction(button)
        UpdateButtonVisual(button)
    end)
end

ns.UpdateRangeIndicator = UpdateRangeIndicator
ns.UpdatePromptVisibility = UpdatePromptVisibility
ns.UpdateButtonVisual = UpdateButtonVisual
ns.UpdateActionFlashes = UpdateActionFlashes
ns.OnSpellAlertEvent = OnSpellAlertEvent
ns.GetSpellAlertDiagnosticLines = GetSpellAlertDiagnosticLines
ns.SetSpellAlertTest = SetSpellAlertTest
ns.ClearButtonAction = ClearButtonAction
ns.GetButtonCenter = GetButtonCenter
ns.GetPanelSize = GetPanelSize
ns.GetHudScale = GetHudScale
ns.LayoutButtonVisual = LayoutButtonVisual
ns.SetButtonPushed = SetButtonPushed
ns.CreateActionButton = CreateActionButton
ns.ForEachButton = ForEachButton
ns.UpdateAllButtonVisuals = UpdateAllButtonVisuals
ns.RefreshButtons = RefreshButtons

-- point every slot at the current crossbar page. The icons follow
-- at once; the secure "action" attribute follows out of combat here and, in
-- combat, through the page pre-click (PageNavigation.lua).
function ns.ApplyCurrentPage()
    if not ns.nativeStorageEnabled then
        return
    end
    local page = ns.currentPage or 1
    ForEachButton(function(button, panelIndex, paddleIndex)
        button.actionSlot = GetNativeSlot(panelIndex, paddleIndex, page)
        if not InCombatLockdown() then
            ConfigureSecureAction(button)
        end
        UpdateButtonVisual(button)
    end)
end
