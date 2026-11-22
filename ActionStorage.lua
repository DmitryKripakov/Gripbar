-- Reserves native C_GamepadUI action slots for the paddle buttons, or falls
-- back to actions stored in SavedVariables.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local SafeCall = ns.SafeCall

local STORAGE_SCAN_LIMIT = 512
local STORAGE_STOP_AFTER_INVALID = 32
local MIN_NATIVE_STORAGE_POOL = 48

local function IsValidNativeStorageSlot(slot)
    if not C_GamepadUI or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return false
    end
    return SafeCall(C_GamepadUI.IsValidGamepadActionStorageSlotIndex, slot) == true
end

local function DiscoverNativeStorageSlots()
    if not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex) ~= "function"
        or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return nil
    end

    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    if type(first) ~= "number" then
        return nil
    end

    local petStart = SafeCall(C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local valid = {}
    local seenValid = false
    local invalidRun = 0

    for slot = first, first + STORAGE_SCAN_LIMIT do
        -- Pet storage is a separate range on Forever (for example pet=11 while
        -- general gamepad storage starts around 181). Only treat it as an upper
        -- boundary when it actually follows the general storage range.
        if type(petStart) == "number" and petStart > first and slot >= petStart then
            break
        end

        if IsValidNativeStorageSlot(slot) then
            valid[#valid + 1] = slot
            seenValid = true
            invalidRun = 0
        elseif seenValid then
            invalidRun = invalidRun + 1
            if invalidRun >= STORAGE_STOP_AFTER_INVALID then
                break
            end
        end
    end

    return valid
end

local function SavedNativeSlotsAreUsable()
    local saved = GripbarCharDB.nativeSlots
    if type(saved) ~= "table" or #saved ~= PANEL_COUNT * PADDLE_COUNT then
        return false
    end

    local seen = {}
    for _, slot in ipairs(saved) do
        if type(slot) ~= "number" or not IsValidNativeStorageSlot(slot) or seen[slot] then
            return false
        end
        seen[slot] = true
    end

    return true
end

local function HasFallbackActions()
    for panelIndex = 1, PANEL_COUNT do
        local panelActions = GripbarCharDB.fallbackActions and GripbarCharDB.fallbackActions[panelIndex]
        if panelActions then
            for paddleIndex = 1, PADDLE_COUNT do
                if panelActions[paddleIndex] then
                    return true
                end
            end
        end
    end
    return false
end

local function InitializePageOneStorage()
    ns.nativeStorageEnabled = false
    ns.nativeStorageSlots = {}
    ns.nativeStorageStatus = "unavailable"

    if SavedNativeSlotsAreUsable() then
        for i, slot in ipairs(GripbarCharDB.nativeSlots) do
            ns.nativeStorageSlots[i] = slot
        end
        ns.nativeStorageEnabled = true
        ns.nativeStorageStatus = "using previously reserved C_GamepadUI slots"
        return
    end

    -- Do not silently switch an existing SavedVariables profile to native action
    -- slots; doing so would make already assigned fallback actions appear empty.
    -- New/empty profiles can use native storage immediately.
    if HasFallbackActions() then
        ns.nativeStorageStatus = "preserving existing SavedVariables actions"
        return
    end

    local valid = DiscoverNativeStorageSlots()
    if not valid then
        ns.nativeStorageStatus = "C_GamepadUI action storage API unavailable"
        return
    end
    if #valid < MIN_NATIVE_STORAGE_POOL then
        ns.nativeStorageStatus = string.format("native pool too small (%d valid slots)", #valid)
        return
    end

    -- Reserve empty slots from the high end of the dedicated gamepad storage pool.
    -- This deliberately avoids overwriting anything Blizzard/the player already uses.
    local chosen = {}
    for i = #valid, 1, -1 do
        local slot = valid[i]
        if not C_ActionBar.HasAction(slot) then
            table.insert(chosen, 1, slot)
            if #chosen == PANEL_COUNT * PADDLE_COUNT then
                break
            end
        end
    end

    if #chosen ~= PANEL_COUNT * PADDLE_COUNT then
        ns.nativeStorageStatus = string.format("only %d unused native slots found", #chosen)
        return
    end

    GripbarCharDB.nativeSlots = chosen
    for i, slot in ipairs(chosen) do
        ns.nativeStorageSlots[i] = slot
    end
    ns.nativeStorageEnabled = true
    ns.nativeStorageStatus = "using newly reserved C_GamepadUI slots"
end

local function FlatButtonIndex(panelIndex, paddleIndex)
    return ((panelIndex - 1) * PADDLE_COUNT) + paddleIndex
end

-- crossbar pages. Page 1 uses the slots above (nativeSlots); every
-- further standard crossbar page gets its own block of 16 native slots
-- (GripbarCharDB.nativePageSlots[page]), so each page has its own paddle
-- actions. Fewer pages are used when the pool runs out of free slots.
local SLOTS_PER_PAGE = PANEL_COUNT * PADDLE_COUNT
local MAX_PAGES = 6

local function GetWantedPageCount()
    local constants = Constants and Constants.GamepadActionBarConstants
    local pages = constants and tonumber(constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT)
    if not pages or pages < 1 then
        pages = 3
    end
    return math.min(pages, MAX_PAGES)
end

-- Slots the native crossbar itself can address on its standard pages, so a
-- new paddle page never takes a slot a native bar would show.
local function GetNativeCrossbarSlots(pages)
    local used = {}
    local util = _G.GamepadActionBarBindingUtil
    if not util or type(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID) ~= "function" then
        return used
    end
    for page = 1, pages do
        for unitSlot = 1, 64 do
            local slot = SafeCall(util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID, page, unitSlot)
            if type(slot) == "number" then
                used[slot] = true
            end
        end
    end
    return used
end

local function ReservePageSlots()
    ns.nativePageSlots = { [1] = ns.nativeStorageSlots }
    ns.pageCount = 1
    ns.nativePageStatus = "1 page"
    if not ns.nativeStorageEnabled then
        ns.nativePageStatus = "paging needs native storage"
        return
    end

    local wanted = GetWantedPageCount()
    if wanted <= 1 then
        return
    end

    GripbarCharDB.nativePageSlots = type(GripbarCharDB.nativePageSlots) == "table" and GripbarCharDB.nativePageSlots or {}
    local saved = GripbarCharDB.nativePageSlots
    local used = {}
    for _, slot in ipairs(ns.nativeStorageSlots) do
        used[slot] = true
    end

    local valid, nativeUsed
    for page = 2, wanted do
        local list = saved[page]
        local ok = type(list) == "table" and #list == SLOTS_PER_PAGE
        if ok then
            for _, slot in ipairs(list) do
                if type(slot) ~= "number" or used[slot] or not IsValidNativeStorageSlot(slot) then
                    ok = false
                    break
                end
            end
        end

        if not ok then
            valid = valid or DiscoverNativeStorageSlots()
            if not valid then
                ns.nativePageStatus = "native storage API unavailable for extra pages"
                break
            end
            nativeUsed = nativeUsed or GetNativeCrossbarSlots(wanted)
            list = {}
            for i = #valid, 1, -1 do
                local slot = valid[i]
                if not used[slot] and not nativeUsed[slot] and not C_ActionBar.HasAction(slot) then
                    table.insert(list, 1, slot)
                    if #list == SLOTS_PER_PAGE then
                        break
                    end
                end
            end
            if #list ~= SLOTS_PER_PAGE then
                ns.nativePageStatus = string.format("not enough free native slots for page %d", page)
                break
            end
            saved[page] = list
        end

        for _, slot in ipairs(list) do
            used[slot] = true
        end
        ns.nativePageSlots[page] = list
        ns.pageCount = page
    end

    if ns.pageCount == wanted then
        ns.nativePageStatus = string.format("%d pages", wanted)
    else
        ns.nativePageStatus = string.format("%d of %d pages (%s)", ns.pageCount, wanted, ns.nativePageStatus)
    end
end

local function GetNativeSlot(panelIndex, paddleIndex, page)
    local list = ns.nativePageSlots and ns.nativePageSlots[page or 1] or ns.nativeStorageSlots
    return list[FlatButtonIndex(panelIndex, paddleIndex)]
end

-- Every reserved slot on every page, for overlap checks.
local function ForEachReservedSlot(callback)
    for page = 1, ns.pageCount or 1 do
        local list = ns.nativePageSlots and ns.nativePageSlots[page] or (page == 1 and ns.nativeStorageSlots) or {}
        for _, slot in ipairs(list) do
            callback(slot, page)
        end
    end
end

-- The cells of our own top bar X / Y / B / A (TopFace.lua), per face button
-- in X, Y, B, A order: 1-4 normal, 5-8 while a living enemy is targeted,
-- 9-12 with LB held, 13-16 with RB held, 17-20 with both held. Kept once chosen (a shorter list
-- from an older version keeps its cells and grows); new ones are free slots
-- no crossbar page or paddle uses.
local TOP_FACE_SLOT_COUNT = 20

local function ReserveTopFaceSlots()
    ns.topFaceSlots = nil
    if not ns.nativeStorageEnabled then
        ns.topFaceStatus = "needs native storage"
        return
    end
    -- Slots the game's crossbar shows on any page, the special (S) page
    -- included: the game fills that one with consumables by itself.
    local nativeUsed = GetNativeCrossbarSlots(GetWantedPageCount())
    -- Slots the game filled by itself (the S page's consumables live outside
    -- the standard pages' formula): kept off our list once seen.
    local avoid = type(GripbarCharDB.avoidSlots) == "table" and GripbarCharDB.avoidSlots or {}
    for slot in pairs(avoid) do
        nativeUsed[slot] = true
    end
    local used = {}
    ForEachReservedSlot(function(slot)
        used[slot] = true
    end)
    -- Each cell keeps its slot while that slot is still ours to use; a cell
    -- whose slot is not (or that is new) gets a free one.
    local saved = type(GripbarCharDB.topFaceSlots) == "table" and GripbarCharDB.topFaceSlots or {}
    -- Version 1 chose the LB / RB cells before the game had loaded the slots'
    -- contents, so they could land on slots holding actions: chosen again.
    if GripbarCharDB.topFaceSlotsVersion ~= 2 then
        for i = 9, #saved do
            saved[i] = nil
        end
        GripbarCharDB.topFaceSlotsVersion = 2
    end
    local cells, missing = {}, 0
    for i = 1, TOP_FACE_SLOT_COUNT do
        local slot = saved[i]
        if type(slot) == "number" and not used[slot] and not nativeUsed[slot] and IsValidNativeStorageSlot(slot) then
            cells[i] = slot
            used[slot] = true
        else
            missing = missing + 1
        end
    end
    if missing > 0 then
        local valid = DiscoverNativeStorageSlots()
        if not valid then
            ns.topFaceStatus = "native storage API unavailable"
            return
        end
        local free = {}
        for i = #valid, 1, -1 do
            local slot = valid[i]
            if not used[slot] and not nativeUsed[slot] and not C_ActionBar.HasAction(slot) then
                free[#free + 1] = slot
                if #free == missing then
                    break
                end
            end
        end
        if #free ~= missing then
            ns.topFaceStatus = "not enough free native slots"
            return
        end
        for i = 1, TOP_FACE_SLOT_COUNT do
            if not cells[i] then
                cells[i] = table.remove(free)
            end
        end
        GripbarCharDB.topFaceSlots = cells
    end
    ns.topFaceSlots = cells
    ns.topFaceStatus = "ok"
end

local function InitializeNativeStorage()
    InitializePageOneStorage()
    ReservePageSlots()
end

---------------------------------------------------------------------------
-- Flyouts (the game's menus of spells: portals, teleports, pet calls...)
---------------------------------------------------------------------------
-- A flyout cannot work on a slot of ours. The game's secure action code
-- opens it with flyout:Toggle(<the button pressed>, ...), and that calls the
-- game's flyout-button methods on the button (TogglePopup,
-- GetPopupDirection...): ours has none (a Lua error on every press). Giving
-- ours those methods would not help: the game's flyout would run them as
-- addon code and its spells would be refused (a tainted flyout cannot cast),
-- and on the gamepad it pushes a binding set from there. So a flyout dropped
-- on a slot of ours goes back onto the cursor, with a note.
local flyoutScanPending = false
local lastFlyoutNote = 0

local function IsOwnSlot(slot)
    local own = false
    ForEachReservedSlot(function(reserved)
        if reserved == slot then
            own = true
        end
    end)
    if not own and ns.topFaceSlots then
        own = tContains(ns.topFaceSlots, slot)
    end
    return own
end

-- Returns true when the slot held a flyout (now taken out).
local function RejectFlyout(slot, keepOnCursor)
    if not slot or not C_ActionBar.HasAction(slot) then
        return false
    end
    local kind = GetActionInfo(slot)
    if (issecretvalue and issecretvalue(kind)) or kind ~= "flyout" then
        return false
    end
    if InCombatLockdown() then
        flyoutScanPending = true
        return false
    end
    -- With an action on the cursor (the one this drop replaced) the pickup
    -- swaps it back into the slot.
    PickupAction(slot)
    if not keepOnCursor then
        ClearCursor()
    end
    if GetTime() - lastFlyoutNote > 2 then
        lastFlyoutNote = GetTime()
        ns.Print(ns.L("Spell menus (portals, teleports, pet calls...) open only from the game's own crossbar slots; a Gripbar slot cannot open one. Put it on a crossbar slot."))
    end
    if ns.Log then
        ns.Log("storage", "flyout taken out of slot " .. tostring(slot))
    end
    return true
end

local function ScanForFlyouts()
    if InCombatLockdown() then
        flyoutScanPending = true
        return
    end
    flyoutScanPending = false
    ForEachReservedSlot(function(slot)
        RejectFlyout(slot, false)
    end)
    for _, slot in pairs(ns.topFaceSlots or {}) do
        RejectFlyout(slot, false)
    end
end

local flyoutEvents = CreateFrame("Frame")
flyoutEvents:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
flyoutEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
flyoutEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
flyoutEvents:SetScript("OnEvent", ns.Guard(function(_, event, slot)
    if not ns.nativeStorageEnabled then
        return
    end
    if event == "ACTIONBAR_SLOT_CHANGED" then
        slot = tonumber(slot) or 0
        if slot > 0 and IsOwnSlot(slot) then
            -- A drop just now: back onto the cursor, to put elsewhere.
            RejectFlyout(slot, true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The slots' contents are loaded a moment after login.
        C_Timer.After(6, ns.Guard(ScanForFlyouts, "Gripbar flyout scan"))
    elseif flyoutScanPending then
        ScanForFlyouts()
    end
end, "Gripbar flyout events"))

ns.DiscoverNativeStorageSlots = DiscoverNativeStorageSlots
ns.InitializeNativeStorage = InitializeNativeStorage
ns.GetNativeSlot = GetNativeSlot
ns.ForEachReservedSlot = ForEachReservedSlot
-- Once the game has loaded the slots' contents (PLAYER_ENTERING_WORLD): an
-- empty-looking slot is then really empty.
ns.ReserveTopFaceSlots = ReserveTopFaceSlots
