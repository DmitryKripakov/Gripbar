-- Panel positions and the SavedVariables (account-wide GripbarDB, per
-- character GripbarCharDB): defaults and value checks.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT

-- Native crossbar geometry (Blizzard_GamepadActionBars). GamepadMainActionBarFrame
-- is 656 x 202 and sits 25 units above the bottom of the screen; its four bars
-- form a cross around its centre: top (no trigger) at (0, 58), LT left at
-- (-195, 0), RT right at (195, 0) and LT + RT at the bottom (0, -58). Every
-- panel is centred on its own bar; the paddle slots are spread around that
-- centre (GetButtonCenter in Buttons.lua).
local NATIVE_CROSSBAR_FRAME = "GamepadMainActionBarFrame"
local NATIVE_CROSSBAR_CENTER_Y = 25 + (202 / 2)
local BAR_CENTERS = {
    [1] = { x = 0, y = 58 },        -- no trigger: top bar
    [2] = { x = -195, y = 0 },      -- LT: left bar
    [3] = { x = 195, y = 0 },       -- RT: right bar
    [4] = { x = 0, y = -58 },       -- LT + RT: bottom bar
}

local function DefaultPanelPosition(panelIndex)
    local center = BAR_CENTERS[panelIndex] or BAR_CENTERS[1]
    return {
        point = "CENTER",
        relativeTo = NATIVE_CROSSBAR_FRAME,
        relativePoint = "CENTER",
        x = center.x,
        y = center.y - LAYOUT.GRID_CENTER_Y,
    }
end

-- Resolves a position to something SetPoint accepts: relative to the native
-- crossbar so it follows it, or the same spot relative to the bottom of the
-- screen while that frame does not exist yet.
local function ResolvePanelAnchor(pos)
    local relativeTo = pos.relativeTo and _G[pos.relativeTo] or nil
    if relativeTo and type(relativeTo.GetObjectType) == "function" then
        return pos.point or "CENTER", relativeTo, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0
    end
    if pos.relativeTo == NATIVE_CROSSBAR_FRAME then
        return pos.point or "CENTER", UIParent, "BOTTOM", pos.x or 0, (pos.y or 0) + NATIVE_CROSSBAR_CENTER_Y
    end
    return pos.point or "BOTTOM", UIParent, pos.relativePoint or "BOTTOM", pos.x or 0, pos.y or 40
end

local function Clamp(value, low, high, fallback)
    return math.max(low, math.min(high, tonumber(value) or fallback))
end

local function Default(db, key, value)
    if db[key] == nil then
        db[key] = value
    end
end

local function EnsureDatabase()
    GripbarDB = type(GripbarDB) == "table" and GripbarDB or {}
    local db = GripbarDB
    db.version = 1

    -- HUD
    db.hudScale = Clamp(db.hudScale, 0.65, 1.50, LAYOUT.DEFAULT_HUD_SCALE)
    db.inactiveOpacity = Clamp(db.inactiveOpacity, 0.10, 1.0, 1.0)
    db.spreadTopX = Clamp(db.spreadTopX, 0, LAYOUT.PADDLE_SPREAD_MAX, LAYOUT.SPREAD_TOP_X)
    db.spreadTopY = Clamp(db.spreadTopY, 0, LAYOUT.PADDLE_SPREAD_MAX, LAYOUT.SPREAD_TOP_Y)
    db.spreadBottomX = Clamp(db.spreadBottomX, 0, LAYOUT.PADDLE_SPREAD_MAX, LAYOUT.SPREAD_BOTTOM_X)
    db.spreadBottomY = Clamp(db.spreadBottomY, 0, LAYOUT.PADDLE_SPREAD_MAX, LAYOUT.SPREAD_BOTTOM_Y)
    -- Offsets of the native LT / RT / LT + RT badges (Badges.lua); the LT + RT
    -- badge sits 22 lower by default.
    for _, key in ipairs({ "lt", "rt", "both" }) do
        for _, axis in ipairs({ "x", "y" }) do
            local name = "badge_" .. key .. "_" .. axis
            db[name] = Clamp(db[name], -200, 200, (name == "badge_both_y") and -22 or 0)
        end
    end
    Default(db, "gamepadOnly", true)
    -- The native bar under each panel draws its own focus highlight.
    Default(db, "highlightActivePanel", false)
    Default(db, "showPaddleBadges", true)
    Default(db, "showPageArrows", true)
    -- Fixed: slots fully opaque, engraved glyphs at full strength, no name
    -- drawn over a slot that holds an action.
    db.slotOpacity = 1
    db.emptyLabelOpacity = 1
    db.promptLabelOpacity = 0

    -- Combat
    Default(db, "wandShoot", false)

    -- Controller and paddles
    if type(db.controllerProfile) ~= "string" then
        db.controllerProfile = "auto"
    end
    db.paddleKeys = type(db.paddleKeys) == "table" and db.paddleKeys or {}
    db.paddleBehaviors = type(db.paddleBehaviors) == "table" and db.paddleBehaviors or {}
    for paddleIndex = 1, PADDLE_COUNT do
        local key = db.paddleKeys["P" .. paddleIndex]
        if type(key) ~= "string" or key == "" then
            db.paddleKeys["P" .. paddleIndex] = "PADPADDLE" .. paddleIndex
        end
        -- What each paddle does: its slots ("action") unless the player picks
        -- crossbar paging.
        if type(db.paddleBehaviors["P" .. paddleIndex]) ~= "string" then
            db.paddleBehaviors["P" .. paddleIndex] = "action"
        end
    end

    -- Page binds (PageBinds.lua): one key table per crossbar page (2, 3).
    db.pageBindKeys = type(db.pageBindKeys) == "table" and db.pageBindKeys or {}
    for _, page in ipairs({ 2, 3 }) do
        if type(db.pageBindKeys[page]) ~= "table" then
            db.pageBindKeys[page] = {}
        end
    end
end

-- Actions and reserved native slots are per character: a spell one class
-- knows is nothing another class can cast.
local function EnsureCharacterDatabase()
    GripbarCharDB = type(GripbarCharDB) == "table" and GripbarCharDB or {}
    local db = GripbarCharDB
    db.version = 1
    db.nativeSlots = type(db.nativeSlots) == "table" and db.nativeSlots or {}
    db.nativePageSlots = type(db.nativePageSlots) == "table" and db.nativePageSlots or {}
    db.fallbackActions = type(db.fallbackActions) == "table" and db.fallbackActions or {}
    for panelIndex = 1, PANEL_COUNT do
        db.fallbackActions[panelIndex] = db.fallbackActions[panelIndex] or {}
    end
end

ns.NATIVE_CROSSBAR_FRAME = NATIVE_CROSSBAR_FRAME
ns.DefaultPanelPosition = DefaultPanelPosition
ns.ResolvePanelAnchor = ResolvePanelAnchor
ns.EnsureDatabase = EnsureDatabase
ns.EnsureCharacterDatabase = EnsureCharacterDatabase
