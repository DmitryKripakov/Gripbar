-- Game actions: the four fixed functions of the crossbar's top bar (X
-- interact, Y inspect, B back, A jump) as things the player can drag
-- anywhere.
--
-- The top bar's A / B / X / Y are ordinary secure buttons of the game: a
-- "/click" on one runs its function, in combat too. Gripbar makes one
-- account-wide macro per function ("Gripbar Jump"...) that clicks the game's
-- button (press, then release), so it works on any action slot of the game or
-- of other addons. On a Gripbar slot it is recognised and does better than a
-- macro: the press and the release reach the game's button separately (so a
-- held jump keeps rising in water and inspect acts on the release), and the
-- slot shows the game's button's live icon (the smart interact's pickaxe,
-- hand, gear...).
local _, ns = ...

local Print = ns.Print

-- index: the button's place in the top bar's face group (1 X, 2 Y, 3 B, 4 A)
local ACTIONS = {
    { key = "interact", label = "Interact", index = 1, macro = "Gripbar Interact", icon = "INV_Misc_Gear_01",
        tip = "The game's smart interact (X): loot, talk, gather, attack the soft target." },
    { key = "inspect", label = "Inspect", index = 2, macro = "Gripbar Inspect", icon = "INV_Misc_Spyglass_02",
        tip = "The game's inspect / target button (Y)." },
    { key = "back", label = "Back", index = 3, macro = "Gripbar Back", icon = "Spell_ChargeNegative",
        tip = "The game's back / cancel button (B)." },
    { key = "jump", label = "Jump", index = 4, macro = "Gripbar Jump", icon = "Ability_Rogue_Sprint",
        tip = "The game's jump (A). Held on a Gripbar slot it keeps rising in water." },
}

local byMacro = {}
for _, def in ipairs(ACTIONS) do
    byMacro[def.macro] = def
end

local function TopFace()
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars.topBar
    return bar and bar.Right
end

-- The game's button of an action, or nil while the crossbar is not up.
local function NativeButton(def)
    local face = TopFace()
    return face and face["ActionButton" .. def.index] or nil
end

-- Its global name (a /click needs one). The crossbar's names are stable;
-- the fallback keeps the macros right while the gamepad UI is off.
local function NativeName(def)
    local button = NativeButton(def)
    local name = button and button.GetName and button:GetName()
    return name or ("GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton" .. (4 + def.index))
end

local function MacroBody(def)
    local name = NativeName(def)
    return "/click " .. name .. " LeftButton true\n/click " .. name .. " LeftButton"
end

local function IconFileID(def)
    local path = "Interface\\Icons\\" .. def.icon
    local id = type(GetFileIDFromPath) == "function" and GetFileIDFromPath(path) or nil
    return id or 134400
end

-- Creates (or refreshes) the action's macro. Out of combat. Returns its index.
local function EnsureMacro(def)
    if InCombatLockdown() then
        Print("Game actions cannot be created during combat.")
        return nil
    end
    local index = GetMacroIndexByName(def.macro)
    local body = MacroBody(def)
    if index and index > 0 then
        local _, _, current = GetMacroInfo(index)
        if current ~= body then
            EditMacro(index, def.macro, nil, body)
        end
        return index
    end
    local ok, created = pcall(CreateMacro, def.macro, IconFileID(def), body, false)
    if not ok or not created or created == 0 then
        Print("Could not create the macro \"" .. def.macro .. "\": the account's general macros may be full.")
        return nil
    end
    return created
end

local function Pickup(def)
    local index = EnsureMacro(def)
    if index then
        PickupMacro(index)
    end
end

-- The game action a native action slot holds (one of our macros), or nil.
local function ForSlot(slot)
    if not slot or not C_ActionBar.HasAction(slot) then
        return nil
    end
    local kind, id = GetActionInfo(slot)
    if kind ~= "macro" or not id then
        return nil
    end
    local name = GetMacroInfo(id)
    return name and byMacro[name] or nil
end

-- The game's button's current picture: ("atlas", name) or ("texture", file),
-- else the macro's own icon.
local function LiveIcon(def)
    local button = NativeButton(def)
    if button then
        for _, key in ipairs({ "SpecialActionIcon", "icon" }) do
            local region = button[key]
            if region and region.IsShown and region:IsShown() then
                local atlas = region.GetAtlas and region:GetAtlas()
                if atlas then
                    return "atlas", atlas
                end
                local texture = region.GetTexture and region:GetTexture()
                if texture then
                    return "texture", texture
                end
            end
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

-- A Gripbar slot holding a game action: the live icon on it.
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

-- From the state poller: the interact icon follows the soft target.
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

-- The picker: four icons to drag (or click) onto any slot.
local picker
local function CreatePicker()
    local frame = CreateFrame("Frame", "GripbarGameActions", UIParent, "BackdropTemplate")
    frame:SetSize(4 * 52 + 36, 112)
    frame:SetPoint("CENTER", 0, 120)
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
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, -16)
    frame.title:SetText("Gripbar game actions: drag onto a slot")

    frame.buttons = {}
    for i, def in ipairs(ACTIONS) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(40, 40)
        b:SetPoint("TOPLEFT", 18 + (i - 1) * 52, -38)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
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
            GameTooltip:AddLine("Drag it onto any action slot. On Gripbar slots it shows the game's live icon and handles holding.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        b.def = def
        frame.buttons[i] = b
    end

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
    picker = picker or CreatePicker()
    picker:SetShown(not picker:IsShown())
end

-- Macros made earlier follow the crossbar's button names.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if InCombatLockdown() then
        return
    end
    for _, def in ipairs(ACTIONS) do
        local index = GetMacroIndexByName(def.macro)
        if index and index > 0 then
            EnsureMacro(def)
        end
    end
end)

ns.GAME_ACTIONS = ACTIONS
ns.GameActionForSlot = ForSlot
ns.GameActionNativeName = NativeName
ns.ApplyGameActionIcon = ApplySlotIcon
ns.UpdateGameActionIcons = UpdateSlotIcons
ns.ToggleGameActions = TogglePicker
