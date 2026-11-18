-- Game actions: the game's own controller functions and common commands as
-- things the player can drag onto any action slot.
--
-- Three kinds, all made into account-wide macros named "GB <name>":
--   * buttons: the crossbar's fixed buttons (the top bar's X interact,
--     Y inspect, B back, A jump, and the shortcut buttons of the LB / RB bars,
--     found at run time). They are secure buttons of the game: the macro
--     clicks them (press, then release). On a Gripbar slot they do better: the
--     press and the release reach the game's button separately (a held jump
--     keeps rising in water, inspect acts on the release) and the slot shows
--     the game button's live icon (the smart interact's pickaxe, hand...).
--   * commands with a slash command of the game (/targetenemy...).
--   * windows (bags, map...) opened through their plain toggle functions.
-- The game's controller-only bindings (the Start radial, the Select cursor,
-- ping, holding a bumper to target) have no macro form and are left out.
local _, ns = ...

local Print = ns.Print

local PREFIX = "GB "

-- The top bar's face group (index: 1 X, 2 Y, 3 B, 4 A).
local TOP_BUTTONS = {
    { key = "interact", label = "Interact", index = 1, icon = "INV_Misc_Gear_01", old = "Gripbar Interact",
        tip = "The game's smart interact (X): loot, talk, gather, attack the soft target." },
    { key = "inspect", label = "Inspect", index = 2, icon = "INV_Misc_Spyglass_02", old = "Gripbar Inspect",
        tip = "The game's inspect / target button (Y)." },
    { key = "back", label = "Back", index = 3, icon = "Spell_ChargeNegative", old = "Gripbar Back",
        tip = "The game's back / cancel button (B)." },
    { key = "jump", label = "Jump", index = 4, icon = "Ability_Rogue_Sprint", old = "Gripbar Jump",
        tip = "The game's jump (A). Held on a Gripbar slot it keeps rising in water." },
}

-- Names for the shortcut buttons found on the bumper bars, by their picture.
local SHORTCUT_NAMES = {
    ["gamepad-radial-icon-bags"] = "Bags button",
    ["gamepad-radial-icon-quests"] = "Quests button",
    ["gamepad-radial-icon-viewbuffs"] = "Buffs button",
    ["gamepad-targeting-last-hostile"] = "Last foe",
    ["gamepad-ability-icon-jump"] = "Jump",
    ["crosshair_inspect_32"] = "Inspect",
    ["crosshair_unableinspect_32"] = "Inspect",
    ["128-redbutton-exit"] = "Back",
}

-- A macro's icon must be an icon file, not an atlas: the closest icon for
-- each shortcut's picture (on Gripbar slots the live atlas is shown instead).
local SHORTCUT_ICONS = {
    ["gamepad-radial-icon-bags"] = "INV_Misc_Bag_08",
    ["gamepad-radial-icon-quests"] = "INV_Misc_Book_08",
    ["gamepad-radial-icon-viewbuffs"] = "Spell_Holy_WordFortitude",
    ["gamepad-targeting-last-hostile"] = "Ability_Hunter_SniperShot",
}

local COMMANDS = {
    { key = "tgtenemy", label = "Target enemy", body = "/targetenemy", icon = "Ability_Hunter_SniperShot",
        tip = "Targets the nearest enemy (next one on repeat)." },
    { key = "tgtfriend", label = "Target friend", body = "/targetfriend", icon = "Spell_Holy_HolyBolt",
        tip = "Targets the nearest friendly player." },
    { key = "tgtlast", label = "Last target", body = "/targetlasttarget", icon = "INV_Misc_Spyglass_03",
        tip = "Targets your previous target." },
    { key = "tgtlastfoe", label = "Last enemy", body = "/targetlastenemy", icon = "Ability_Warrior_Charge",
        tip = "Targets the last enemy you had targeted." },
    { key = "clear", label = "Clear target", body = "/cleartarget", icon = "Ability_Stealth",
        tip = "Clears your target." },
    { key = "assist", label = "Assist", body = "/assist", icon = "Ability_Warrior_BattleShout",
        tip = "Targets your target's target." },
    { key = "follow", label = "Follow", body = "/follow", icon = "Ability_Tracking",
        tip = "Follows your target." },
    { key = "attack", label = "Start attack", body = "/startattack", icon = "INV_Sword_04",
        tip = "Starts the melee auto attack on your target." },
    { key = "stopattack", label = "Stop attack", body = "/stopattack", icon = "INV_Shield_04",
        tip = "Stops the auto attack." },
    { key = "sit", label = "Sit / stand", body = "/sit", icon = "Spell_Nature_Sleep",
        tip = "Sits down (stands up from any move)." },
    { key = "dismount", label = "Dismount", body = "/dismount", icon = "Ability_Mount_RidingHorse",
        tip = "Gets off your mount." },
    { key = "petattack", label = "Pet attack", body = "/petattack", icon = "Ability_GhoulFrenzy",
        tip = "Sends your pet at your target." },
    { key = "petfollow", label = "Pet follow", body = "/petfollow", icon = "Ability_Hunter_BeastCall",
        tip = "Calls your pet back to you." },
}

local WINDOWS = {
    { key = "bags", label = "Bags", body = "/run ToggleAllBags()", icon = "INV_Misc_Bag_08",
        tip = "Opens or closes all bags." },
    { key = "map", label = "World map", body = "/run ToggleWorldMap()", icon = "INV_Misc_Map02",
        tip = "Opens or closes the world map." },
    { key = "quests", label = "Quest log", body = "/run ToggleQuestLog()", icon = "INV_Misc_Book_08",
        tip = "Opens or closes the quest log." },
    { key = "character", label = "Character", body = "/run ToggleCharacter(\"PaperDollFrame\")", icon = "INV_Chest_Cloth_17",
        tip = "Opens or closes the character window." },
    { key = "spellbook", label = "Spellbook", body = "/run ToggleSpellBook(BOOKTYPE_SPELL or \"spell\")", icon = "INV_Misc_Book_09",
        tip = "Opens or closes the spellbook." },
    { key = "screenshot", label = "Screenshot", body = "/screenshot", icon = "INV_Misc_Spyglass_02",
        tip = "Takes a screenshot." },
}

local function MacroName(def)
    return (PREFIX .. def.label):sub(1, 16)
end

---------------------------------------------------------------------------
-- The game's buttons
---------------------------------------------------------------------------
local function PageUnit()
    local main = _G.GamepadMainActionBarFrame
    return main and main.PageUnit
end

local function TopFace()
    local unit = PageUnit()
    local bars = unit and unit.actionBars
    local bar = bars and bars.topBar
    return bar and bar.Right
end

local function IconRegionOf(button)
    for _, key in ipairs({ "SpecialActionIcon", "icon" }) do
        local region = button[key]
        if region and region.IsShown and region:IsShown() then
            return region
        end
    end
    return nil
end

-- The game's button of a "button" action, or nil while the crossbar is not up.
local function NativeButton(def)
    if def.index then
        local face = TopFace()
        return face and face["ActionButton" .. def.index] or nil
    end
    return def.name and _G[def.name] or nil
end

-- Its global name (a /click needs one); the top bar's names are stable.
local function NativeName(def)
    local button = NativeButton(def)
    local name = button and button.GetName and button:GetName()
    if name then
        return name
    end
    if def.index then
        return "GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton" .. (4 + def.index)
    end
    return def.name
end

-- The shortcut buttons of the bumper bars: every protected, named button of
-- the crossbar that shows a fixed function's picture (an atlas on its
-- SpecialActionIcon) and is not one of the top bar's four.
local function FindShortcuts()
    local found, seen = {}, {}
    local unit = PageUnit()
    if not unit then
        return found
    end
    local top = {}
    for _, def in ipairs(TOP_BUTTONS) do
        local b = NativeButton(def)
        if b then
            top[b] = true
        end
    end
    local function Scan(frame, depth)
        if depth > 8 then
            return
        end
        if frame:IsObjectType("Button") and not top[frame] and frame.GetName and frame:GetName() then
            local region = frame.SpecialActionIcon
            local atlas = region and region.GetAtlas and region:GetAtlas()
            local key = atlas and atlas:lower()
            -- The top bar's own functions (jump, inspect, back) are there already.
            local duplicate = key and (key:find("jump", 1, true) or key:find("inspect", 1, true) or key:find("redbutton%-exit"))
            if atlas and not duplicate and frame.IsProtected and frame:IsProtected() then
                if not seen[key] then
                    seen[key] = true
                    local label = SHORTCUT_NAMES[key] or ("Game button " .. (#found + 1))
                    found[#found + 1] = {
                        key = "sc:" .. key, label = label, name = frame:GetName(), atlas = atlas,
                        icon = SHORTCUT_ICONS[key] or "INV_Misc_QuestionMark",
                        tip = "A shortcut button of the game's LB / RB bars (" .. atlas .. ").",
                    }
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            Scan(child, depth + 1)
        end
    end
    Scan(unit, 0)
    return found
end

---------------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------------
local byMacro = {}         -- macro name -> button def (only the clicked kind)

local function Body(def)
    if def.body then
        return def.body
    end
    local name = NativeName(def)
    return "/click " .. name .. " LeftButton true\n/click " .. name .. " LeftButton"
end

local function IconFileID(def)
    local path = "Interface\\Icons\\" .. def.icon
    local id = type(GetFileIDFromPath) == "function" and GetFileIDFromPath(path) or nil
    return id or 134400
end

-- Creates (or refreshes) a def's macro, out of combat. Returns its index.
local function EnsureMacro(def)
    if InCombatLockdown() then
        Print("Game actions cannot be created during combat.")
        return nil
    end
    local name = MacroName(def)
    local body = Body(def)
    local index = GetMacroIndexByName(name)
    -- The first build named the top four "Gripbar Jump"...: take those over.
    if (not index or index == 0) and def.old then
        index = GetMacroIndexByName(def.old)
        if index and index > 0 then
            EditMacro(index, name, nil, body)
        end
    end
    local icon = IconFileID(def)
    if index and index > 0 then
        local _, currentIcon, current = GetMacroInfo(index)
        -- Body and icon kept up to date (the first build gave the bumper
        -- shortcuts a question mark).
        if current ~= body or (currentIcon ~= icon and icon ~= 134400) then
            EditMacro(index, name, icon, body)
        end
        return index
    end
    local ok, created = pcall(CreateMacro, name, icon, body, false)
    if not ok or not created or created == 0 then
        Print("Could not create the macro \"" .. name .. "\": the account's general macros may be full.")
        return nil
    end
    -- A slot the macro is dropped on reads it fresh (it was only picked up
    -- after a reload otherwise), Gripbar's slots included.
    C_Timer.After(0, function()
        if ns.RefreshButtons and not InCombatLockdown() then
            ns.RefreshButtons()
        end
    end)
    return created
end

local function Pickup(def)
    local index = EnsureMacro(def)
    if index then
        PickupMacro(index)
    end
end

local function Register(def)
    if not def.body then
        byMacro[MacroName(def)] = def
        if def.old then
            byMacro[def.old] = def
        end
    end
end

for _, def in ipairs(TOP_BUTTONS) do
    Register(def)
end

-- The clicked game button a native action slot holds (one of our macros), or nil.
local function ForSlot(slot)
    if not slot or not C_ActionBar.HasAction(slot) then
        return nil
    end
    local kind, id = GetActionInfo(slot)
    if kind ~= "macro" or not id then
        return nil
    end
    local name, _, body = GetMacroInfo(id)
    if not name then
        return nil
    end
    local def = byMacro[name]
    if def then
        return def
    end
    -- Any GB macro clicking a game button (a bumper bar's shortcut put on a
    -- slot before the picker was opened this session).
    local native = name:sub(1, #PREFIX) == PREFIX and body and body:match("^/click (%S+) LeftButton true")
    if native then
        def = { key = "click:" .. native, label = name:sub(#PREFIX + 1), name = native, icon = "INV_Misc_QuestionMark" }
        byMacro[name] = def
        return def
    end
    return nil
end

---------------------------------------------------------------------------
-- Live icons
---------------------------------------------------------------------------
local function LiveIcon(def)
    if not def.body then
        local button = NativeButton(def)
        local region = button and IconRegionOf(button)
        if region then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas then
                return "atlas", atlas
            end
            local texture = region.GetTexture and region:GetTexture()
            if texture then
                return "texture", texture
            end
        end
        if def.atlas then
            return "atlas", def.atlas
        end
    end
    return "texture", "Interface\\Icons\\" .. def.icon
end

local function SetIcon(texture, kind, value)
    if kind == "atlas" then
        texture:SetAtlas(value)
    else
        texture:SetTexture(value)
    end
end

-- A Gripbar slot holding a clicked game button: the live icon on it.
local function ApplySlotIcon(button)
    local def = button.gameAction
    if not def or not button.visual then
        return
    end
    local kind, value = LiveIcon(def)
    if button.gameIconKind ~= kind or button.gameIconValue ~= value then
        button.gameIconKind, button.gameIconValue = kind, value
        SetIcon(button.visual.icon, kind, value)
        button.visual.icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function UpdateSlotIcons()
    if not ns.ForEachButton then
        return
    end
    ns.ForEachButton(function(button)
        if button.gameAction then
            ApplySlotIcon(button)
        end
    end)
end

---------------------------------------------------------------------------
-- The game's own crossbar slots holding a GB button macro: only the picture
-- inside the game's button is swapped for the live one. Everything else (the
-- range dot, cooldowns, the pressed look, the ring) stays the game's own.
-- When the game redraws the button it gets the live picture again; when the
-- slot holds something else the game draws its own as usual.
---------------------------------------------------------------------------
local nativeButtons, lastScan = nil, -10
local swapped = {}          -- game button -> the picture we put in

local function NativeActionButtons()
    local now = GetTime()
    if nativeButtons and now - lastScan < 5 then
        return nativeButtons
    end
    lastScan = now
    nativeButtons = {}
    local unit = PageUnit()
    if not unit then
        return nativeButtons
    end
    local function Scan(frame, depth)
        if depth > 8 then
            return
        end
        if frame:IsObjectType("Button") and frame.icon and frame.icon.SetTexture then
            nativeButtons[#nativeButtons + 1] = frame
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            Scan(child, depth + 1)
        end
    end
    Scan(unit, 0)
    return nativeButtons
end

local function CurrentPicture(region, kind)
    if kind == "atlas" then
        return region.GetAtlas and region:GetAtlas()
    end
    return region:GetTexture()
end

local nativeElapsed = 0
local function UpdateNativeIcons(elapsed)
    nativeElapsed = nativeElapsed + (elapsed or 0)
    if nativeElapsed < 0.1 then
        return
    end
    nativeElapsed = 0
    for _, button in ipairs(NativeActionButtons()) do
        local slot = button.action
        local def = type(slot) == "number" and slot > 0 and ForSlot(slot) or nil
        local region = button.icon
        if def and def.body == nil then
            local kind, value = LiveIcon(def)
            local mark = swapped[button]
            local current = CurrentPicture(region, kind)
            if not mark or mark.value ~= value or mark.applied ~= current then
                -- The game's own crop of the icon, put back when we let go.
                local coords = mark and mark.coords or { region:GetTexCoord() }
                SetIcon(region, kind, value)
                region:SetTexCoord(0, 1, 0, 1)
                swapped[button] = { value = value, applied = CurrentPicture(region, kind), coords = coords }
            end
        elseif swapped[button] then
            -- Not ours any more: the game's own picture comes back with its
            -- next redraw, with its own crop.
            local coords = swapped[button].coords
            swapped[button] = nil
            if coords and #coords >= 4 then
                region:SetTexCoord(unpack(coords))
            end
        end
    end
end

local nativeFrame = CreateFrame("Frame")
nativeFrame:SetScript("OnUpdate", function(_, elapsed)
    UpdateNativeIcons(elapsed)
end)

---------------------------------------------------------------------------
-- The picker: every action as an icon to drag (or click) onto a slot
---------------------------------------------------------------------------
local COLUMNS, CELL = 8, 46
local picker

local function Section(frame, title, defs, y)
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 20, y)
    header:SetText(title)
    y = y - 20
    for i, def in ipairs(defs) do
        Register(def)
        local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(36, 36)
        b:SetPoint("TOPLEFT", 20 + col * CELL, y - row * (CELL + 12))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
        b.label:SetWidth(CELL + 4)
        b.label:SetMaxLines(1)
        b.label:SetText(def.label)
        b:RegisterForDrag("LeftButton")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnDragStart", function()
            Pickup(def)
        end)
        b:SetScript("OnClick", function()
            Pickup(def)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(def.label)
            GameTooltip:AddLine(def.tip, 1, 1, 1, true)
            GameTooltip:AddLine("Macro: " .. MacroName(def), 0.7, 0.7, 0.7)
            if not def.body then
                GameTooltip:AddLine("On Gripbar slots: the game's live icon, and holding works.", 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        b.def = def
        frame.buttons[#frame.buttons + 1] = b
    end
    local rows = math.max(1, math.ceil(#defs / COLUMNS))
    return y - rows * (CELL + 12) - 6
end

local function CreatePicker()
    local frame = CreateFrame("Frame", "GripbarGameActions", UIParent, "BackdropTemplate")
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
    frame.title:SetPoint("TOP", 0, -16)
    frame.title:SetText("Gripbar game actions")
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", 0, -36)
    hint:SetText("Drag onto any action slot (or click, then click the slot).")

    frame.buttons = {}
    local buttons = {}
    for _, def in ipairs(TOP_BUTTONS) do
        buttons[#buttons + 1] = def
    end
    for _, def in ipairs(FindShortcuts()) do
        buttons[#buttons + 1] = def
    end
    local y = Section(frame, "The game's buttons", buttons, -58)
    y = Section(frame, "Targeting and combat", COMMANDS, y)
    y = Section(frame, "Windows", WINDOWS, y)
    frame:SetSize(COLUMNS * CELL + 32, -y + 16)
    frame:SetPoint("CENTER", 0, 60)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    frame:SetScript("OnShow", function(self)
        for _, b in ipairs(self.buttons) do
            local kind, value = LiveIcon(b.def)
            SetIcon(b.icon, kind, value)
        end
    end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "GripbarGameActions")
    end
    frame:Hide()
    return frame
end

local function TogglePicker()
    if not picker and InCombatLockdown() then
        Print("The game actions window opens after combat.")
        return
    end
    picker = picker or CreatePicker()
    picker:SetShown(not picker:IsShown())
end

-- Macros made earlier follow the game's button names (and the new names).
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if InCombatLockdown() then
        return
    end
    for _, def in ipairs(TOP_BUTTONS) do
        local index = GetMacroIndexByName(MacroName(def))
        local old = GetMacroIndexByName(def.old)
        if (index and index > 0) or (old and old > 0) then
            EnsureMacro(def)
        end
    end
    -- The bumper shortcuts' macros made earlier: their icon and button name.
    for _, def in ipairs(FindShortcuts()) do
        Register(def)
        local index = GetMacroIndexByName(MacroName(def))
        if index and index > 0 then
            EnsureMacro(def)
        end
    end
end)

ns.GAME_ACTIONS = TOP_BUTTONS
ns.GameActionForSlot = ForSlot
ns.GameActionNativeName = NativeName
ns.ApplyGameActionIcon = ApplySlotIcon
ns.UpdateGameActionIcons = UpdateSlotIcons
ns.ToggleGameActions = TogglePicker
