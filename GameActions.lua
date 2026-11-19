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
local L = ns.L

local PREFIX = "GB "

-- The top bar's face group (index: 1 X, 2 Y, 3 B, 4 A).
local TOP_BUTTONS = {
    { key = "interact", label = "Interact", index = 1, icon = "INV_Misc_Gear_01", old = "Gripbar Interact",
        tip = "The game's smart interact (X): loot, talk, gather, attack the soft target." },
    { key = "inspect", label = "Inspect", index = 2, icon = "INV_Misc_Spyglass_02", old = "Gripbar Inspect",
        -- Drawn as the game draws it without a bumper held (with one, the
        -- game's button shows the raid marker it would set instead).
        live = function()
            return UnitExists("target") and "crosshair_inspect_32" or "crosshair_unableinspect_32"
        end,
        -- ...and placed as then: 3 past the button's edges (with a bumper
        -- held the game moves it 6 inside, for the marker).
        liveOffset = 3,
        tip = "The game's inspect / target button (Y)." },
    { key = "back", label = "Back", index = 3, icon = "Spell_ChargeNegative", old = "Gripbar Back",
        -- The red button reaches past the ring a little less than the game's
        -- 6 on our slots.
        liveOffset = 5,
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

-- Windows open through the game's own buttons (the micro menu, the backpack):
-- a /run from a macro marks what it opens as addon code ("ForceTaint"), and
-- the game then blocks closing that window.
local WINDOWS = {
    { key = "bags", label = "Bags", body = "/click MainMenuBarBackpackButton", icon = "INV_Misc_Bag_08",
        tip = "Opens or closes all bags." },
    { key = "map", label = "World map", body = "/click QuestLogMicroButton", icon = "INV_Misc_Map02",
        tip = "Opens or closes the world map (with the quest log, as the game's map button does)." },
    { key = "quests", label = "Quest log", body = "/click QuestLogMicroButton", icon = "INV_Misc_Book_08",
        tip = "Opens or closes the quest log." },
    { key = "character", label = "Character", body = "/click CharacterMicroButton", icon = "INV_Chest_Cloth_17",
        tip = "Opens or closes the character window." },
    { key = "spellbook", label = "Spellbook", body = "/click SpellbookMicroButton", icon = "INV_Misc_Book_09",
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
                    local number = #found + 1
                    -- label names the macro (English); shown is what the picker displays.
                    local label = SHORTCUT_NAMES[key] or ("Game button " .. number)
                    found[#found + 1] = {
                        key = "sc:" .. key, label = label, name = frame:GetName(), atlas = atlas,
                        shown = not SHORTCUT_NAMES[key] and string.format(L("Game button %d"), number) or nil,
                        icon = SHORTCUT_ICONS[key] or "INV_Misc_QuestionMark",
                        tip = string.format(L("A shortcut button of the game's LB / RB bars (%s)."), atlas),
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
        Print(L("Game actions cannot be created during combat."))
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
        Print(string.format(L("Could not create the macro \"%s\": the account's general macros may be full."), name))
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
    if def.live then
        return "atlas", def.live()
    end
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
                local l, r, t, b = region:GetTexCoord()
                -- The game's crop, part of the key so a new crop repaints.
                return "texture", texture .. string.format("|%.4f|%.4f|%.4f|%.4f", l, r, t, b), { l, r, t, b }
            end
        end
        if def.atlas then
            return "atlas", def.atlas
        end
    end
    return "texture", "Interface\\Icons\\" .. def.icon
end

-- Sets a live picture the way the game's button has it: an atlas (the
-- inspect crosshair is a sprite sheet: its first cell, as the game picks),
-- or a texture with the game's crop.
local function SetIcon(texture, kind, value, coords)
    if kind == "atlas" then
        texture:SetAtlas(value)
        if value:lower():find("^crosshair") and texture.SetSpriteSheetCell then
            texture:SetSpriteSheetCell(1, 1, 1)
        end
    else
        -- The key's suffix off; a file ID goes back as a number (the game
        -- gives some pictures by ID: Back on a taxi, the interact pictures),
        -- a string of digits is no texture path.
        local file = value:gsub("|.*$", "")
        texture:SetTexture(tonumber(file) or file)
        if coords then
            texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    end
end

-- A game button's picture drawn as that button draws it: on a black disc
-- (its slot's dark background, not a slot's glyph art), with the offset the
-- game gave the picture (the inspect crosshair 3 past the edges, Back 6),
-- scaled to our slot.
local function StyleSpecialIcon(visual, native, region, offset)
    if not visual.specialBackground then
        local background = visual:CreateTexture(nil, "BACKGROUND", nil, 0)
        local inset = visual.slotInset or 3
        background:SetPoint("TOPLEFT", inset, -inset)
        background:SetPoint("BOTTOMRIGHT", -inset, inset)
        background:SetColorTexture(0, 0, 0, 1)
        if visual.iconMask then
            background:AddMaskTexture(visual.iconMask)
        end
        visual.specialBackground = background
    end
    visual.slotArt:Hide()
    visual.specialBackground:Show()
    local x, y = 0, 0
    local ratio = native and (visual:GetWidth() or 0) / math.max(1, native:GetWidth() or 1) or 1
    if offset then
        -- A fixed placement (past the edges by this much).
        x, y = -offset * ratio, offset * ratio
    elseif native and region and region.GetPoint then
        local _, _, _, ox, oy = region:GetPoint(1)
        x, y = (tonumber(ox) or 0) * ratio, (tonumber(oy) or 0) * ratio
    end
    visual.icon:ClearAllPoints()
    visual.icon:SetPoint("TOPLEFT", visual, "TOPLEFT", x, y)
    visual.icon:SetPoint("BOTTOMRIGHT", visual, "BOTTOMRIGHT", -x, -y)
    -- Cut round inside the ring when the game's picture is; else (Back's
    -- red button) at the ring's outer edge, so it reaches over the ring
    -- without its corners showing past it.
    local masked = not region or not region.GetNumMaskTextures or region:GetNumMaskTextures() > 0
    if visual.iconMask then
        -- Masks that are black past their edges: an atlas mask repeats its
        -- edge pixels outward, and a circle touches its square's edges at
        -- four points, so a picture reaching past the mask (these do) showed
        -- there in four strips.
        local function ClampedMask(inset)
            local mask = visual:CreateMaskTexture()
            mask:SetPoint("TOPLEFT", inset, -inset)
            mask:SetPoint("BOTTOMRIGHT", -inset, inset)
            mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            return mask
        end
        visual.specialMasks = visual.specialMasks or { inside = ClampedMask(visual.slotInset or 3), outer = ClampedMask(0) }
        local want = masked and "inside" or "outer"
        -- The slot's icon starts with the slot's own mask (BuildSlotVisual).
        local current = visual.iconMaskKind or "slot"
        if want ~= current then
            visual.icon:RemoveMaskTexture(current == "slot" and visual.iconMask or visual.specialMasks[current])
            visual.icon:AddMaskTexture(visual.specialMasks[want])
            visual.iconMaskKind = want
        end
    end
    visual.specialStyled = true
end

-- Back to a plain slot (an action's own icon on the slot art).
local function ResetSpecialIcon(visual)
    if not visual.specialStyled then
        return
    end
    visual.specialStyled = false
    visual.slotArt:Show()
    if visual.specialBackground then
        visual.specialBackground:Hide()
    end
    visual.icon:ClearAllPoints()
    visual.icon:SetAllPoints(visual)
    if visual.iconMaskKind and visual.iconMaskKind ~= "slot" then
        visual.icon:RemoveMaskTexture(visual.specialMasks[visual.iconMaskKind])
        visual.icon:AddMaskTexture(visual.iconMask)
        visual.iconMaskKind = "slot"
    end
end

-- A Gripbar slot holding a clicked game button: the live icon on it.
local function ApplySlotIcon(button)
    local def = button.gameAction
    if not def or not button.visual then
        return
    end
    local kind, value, coords = LiveIcon(def)
    if button.gameIconKind ~= kind or button.gameIconValue ~= value then
        button.gameIconKind, button.gameIconValue = kind, value
        SetIcon(button.visual.icon, kind, value, coords)
    end
    if not def.body then
        local native = NativeButton(def)
        StyleSpecialIcon(button.visual, native, native and IconRegionOf(native), def.liveOffset)
    end
end

local function UpdateSlotIcons()
    if not ns.ForEachButton then
        return
    end
    ns.ForEachVisualButton(function(button)
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
-- The crossbar's buttons are listed again only when something may have
-- moved (a slot, a page, a stance, macros, entering the world; and a slow
-- safety pass); in between, every 0.1 s only the few slots that hold one of
-- our buttons are looked at.
local swapped = {}          -- game button -> the picture we put in
local watched = {}          -- { button = game button, slot = its slot }
local dirty = true
local sinceRebuild = 0

local function MarkDirty()
    dirty = true
end

local function NativeActionButtons()
    local list = {}
    local unit = PageUnit()
    if not unit then
        return list
    end
    local function Scan(frame, depth)
        if depth > 8 then
            return
        end
        if frame:IsObjectType("Button") and frame.icon and frame.icon.SetTexture then
            list[#list + 1] = frame
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            Scan(child, depth + 1)
        end
    end
    Scan(unit, 0)
    return list
end

local function CurrentPicture(region, kind)
    if kind == "atlas" then
        return region.GetAtlas and region:GetAtlas()
    end
    return region:GetTexture()
end

-- Lets go of a game button: its own picture comes back with its next
-- redraw, with its own crop.
local function Release(button)
    local mark = swapped[button]
    swapped[button] = nil
    if mark and mark.coords and #mark.coords >= 4 then
        button.icon:SetTexCoord(unpack(mark.coords))
    end
end

local function Rebuild()
    dirty = false
    sinceRebuild = 0
    local keep = {}
    wipe(watched)
    for _, button in ipairs(NativeActionButtons()) do
        local slot = button.action
        local def = type(slot) == "number" and slot > 0 and ForSlot(slot) or nil
        if def and def.body == nil then
            watched[#watched + 1] = { button = button, slot = slot, def = def }
            keep[button] = true
        end
    end
    for button in pairs(swapped) do
        if not keep[button] then
            Release(button)
        end
    end
end

local function Paint(entry)
    local button, region = entry.button, entry.button.icon
    local kind, value, coords = LiveIcon(entry.def)
    local mark = swapped[button]
    if not mark or mark.value ~= value or mark.applied ~= CurrentPicture(region, kind) then
        -- The game's own crop of the icon, put back when we let go.
        local saved = mark and mark.coords or { region:GetTexCoord() }
        SetIcon(region, kind, value, coords)
        swapped[button] = { value = value, applied = CurrentPicture(region, kind), coords = saved }
    end
end

local nativeElapsed = 0
local function UpdateNativeIcons(elapsed)
    nativeElapsed = nativeElapsed + (elapsed or 0)
    sinceRebuild = sinceRebuild + (elapsed or 0)
    if nativeElapsed < 0.1 then
        return
    end
    nativeElapsed = 0
    if dirty or sinceRebuild > 10 then
        Rebuild()
    end
    for _, entry in ipairs(watched) do
        -- A slot that moved (a page turned without an event we saw): list again.
        if entry.button.action ~= entry.slot then
            dirty = true
            return
        end
        Paint(entry)
    end
end

local nativeFrame = CreateFrame("Frame")
nativeFrame:SetScript("OnUpdate", function(_, elapsed)
    UpdateNativeIcons(elapsed)
end)
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD" }) do
    pcall(nativeFrame.RegisterEvent, nativeFrame, event)
end
nativeFrame:SetScript("OnEvent", MarkDirty)

-- Every page turn of the crossbar goes through SetCurrentPage.
local pageHooked = false
local function HookPages()
    local unit = PageUnit()
    if not pageHooked and unit and type(unit.SetCurrentPage) == "function" then
        hooksecurefunc(unit, "SetCurrentPage", MarkDirty)
        pageHooked = true
    end
end
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", HookPages)

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
        b.label:SetText(def.shown or L(def.label))
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
            GameTooltip:AddLine(def.shown or L(def.label))
            GameTooltip:AddLine(L(def.tip), 1, 1, 1, true)
            GameTooltip:AddLine(string.format(L("Macro: %s"), MacroName(def)), 0.7, 0.7, 0.7)
            if not def.body then
                GameTooltip:AddLine(L("On Gripbar slots: the game's live icon, and holding works."), 0.7, 0.7, 0.7, true)
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
    frame.title:SetText(L("Gripbar game actions"))
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", 0, -36)
    hint:SetText(L("Drag onto any action slot (or click, then click the slot)."))

    frame.buttons = {}
    local buttons = {}
    for _, def in ipairs(TOP_BUTTONS) do
        buttons[#buttons + 1] = def
    end
    for _, def in ipairs(FindShortcuts()) do
        buttons[#buttons + 1] = def
    end
    local y = Section(frame, L("The game's buttons"), buttons, -58)
    y = Section(frame, L("Targeting and combat"), COMMANDS, y)
    y = Section(frame, L("Windows"), WINDOWS, y)
    frame:SetSize(COLUMNS * CELL + 32, -y + 16)
    frame:SetPoint("CENTER", 0, 60)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    frame:SetScript("OnShow", function(self)
        for _, b in ipairs(self.buttons) do
            local kind, value, coords = LiveIcon(b.def)
            SetIcon(b.icon, kind, value, coords)
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
        Print(L("The game actions window opens after combat."))
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
    -- The window and command macros made earlier: their body (the first
    -- spellbook macro called a function Forever does not have).
    for _, list in ipairs({ WINDOWS, COMMANDS }) do
        for _, def in ipairs(list) do
            local index = GetMacroIndexByName(MacroName(def))
            if index and index > 0 then
                EnsureMacro(def)
            end
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
ns.StyleSpecialIcon = StyleSpecialIcon
ns.ResetSpecialIcon = ResetSpecialIcon
ns.UpdateGameActionIcons = UpdateSlotIcons
ns.ToggleGameActions = TogglePicker
