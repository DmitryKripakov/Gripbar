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

local function InitializeNativeStorage()
    InitializePageOneStorage()
    ReservePageSlots()
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

ns.DiscoverNativeStorageSlots = DiscoverNativeStorageSlots
ns.InitializeNativeStorage = InitializeNativeStorage
ns.GetNativeSlot = GetNativeSlot
ns.ForEachReservedSlot = ForEachReservedSlot
