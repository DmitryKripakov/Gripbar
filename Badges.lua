-- offsets for the native crossbar's trigger badges: "LT" under the
-- left bar, "RT" under the right bar and "LT + RT" under the bottom bar.
--
-- The badges are Blizzard frames inside each bar's centred anchor. They are
-- found by their art (Gamepad-*-Trigger-LT / -RT atlases), the smallest frame
-- that holds the whole badge is moved, and a SetPoint hook keeps the offset
-- when the crossbar lays itself out again (focus, scaling, UI scale).
-- Purely cosmetic; protected frames are only touched out of combat.
local _, ns = ...

local Print = ns.Print
local SafeCall = ns.SafeCall

local BADGES = {
    { key = "lt", label = "LT (left bar)", anchorKey = "LeftCenteredAnchor" },
    { key = "rt", label = "RT (right bar)", anchorKey = "RightCenteredAnchor" },
    { key = "both", label = "LT + RT (bottom bar)", anchorKey = "BottomCenteredAnchor" },
}
local OFFSET_MIN, OFFSET_MAX = -200, 200

local found = {}       -- key -> info { frame, base = { {point, rel, relPoint, x, y}, ... } }
local hooked = {}      -- frame -> true

local function GetPageUnit()
    return _G.GamepadMainActionBarFramePageUnit
        or (_G.GamepadMainActionBarFrame and _G.GamepadMainActionBarFrame.PageUnit)
end

local function HasTriggerArt(frame, depth)
    for _, region in ipairs({ frame:GetRegions() }) do
        if type(region.GetAtlas) == "function" then
            local atlas = region:GetAtlas()
            if atlas and atlas:find("Trigger%-[LR]T%-") then
                return true
            end
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if HasTriggerArt(child, depth - 1) then
                return true
            end
        end
    end
    return false
end

local function CountDescendants(frame, limit)
    local count = 0
    for _, child in ipairs({ frame:GetChildren() }) do
        count = count + 1 + CountDescendants(child, limit)
        if count > limit then
            return count
        end
    end
    return count
end

-- The shallowest small frame under the bar anchor that holds trigger art:
-- the whole badge (both icons and the plus for LT + RT), not a single icon
-- and not the bar with its action buttons.
local function FindBadgeFrame(anchor)
    local queue, depths = { anchor }, { [anchor] = 0 }
    local head = 1
    while queue[head] do
        local frame = queue[head]
        head = head + 1
        local depth = depths[frame]
        if frame ~= anchor and CountDescendants(frame, 12) <= 12 and HasTriggerArt(frame, 3) then
            return frame
        end
        if depth < 6 then
            for _, child in ipairs({ frame:GetChildren() }) do
                depths[child] = depth + 1
                queue[#queue + 1] = child
            end
        end
    end
    return nil
end

local function GetOffset(key)
    local db = GripbarDB or {}
    return tonumber(db["badge_" .. key .. "_x"]) or 0, tonumber(db["badge_" .. key .. "_y"]) or 0
end

local function CapturePoints(frame)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        points[i] = { point, rel, relPoint, x or 0, y or 0 }
    end
    return points
end

local function ApplyOne(info)
    local frame = info.frame
    if info.applying or #info.base == 0 then
        return
    end
    if InCombatLockdown() and SafeCall(frame.IsProtected, frame) then
        ns.pendingBadgeRefresh = true
        return
    end
    local dx, dy = GetOffset(info.key)
    info.applying = true
    frame:ClearAllPoints()
    info.applied = {}
    for i, p in ipairs(info.base) do
        local x, y = p[4] + dx, p[5] + dy
        frame:SetPoint(p[1], p[2], p[3], x, y)
        info.applied[i] = { p[1], x, y }
    end
    info.applying = false
end

-- Blizzard re-anchored the badge: take its new points as the base (minus our
-- offset where a point is still one we set) and apply the offset again.
local function OnNativeSetPoint(info)
    if info.applying then
        return
    end
    local dx, dy = GetOffset(info.key)
    local base = CapturePoints(info.frame)
    for _, p in ipairs(base) do
        for _, a in ipairs(info.applied or {}) do
            if a[1] == p[1] and math.abs(a[2] - p[4]) < 0.01 and math.abs(a[3] - p[5]) < 0.01 then
                p[4], p[5] = p[4] - dx, p[5] - dy
                break
            end
        end
    end
    info.base = base
    ApplyOne(info)
end

local function Discover()
    local pageUnit = GetPageUnit()
    if not pageUnit then
        return
    end
    for _, badge in ipairs(BADGES) do
        if not found[badge.key] then
            local anchor = pageUnit[badge.anchorKey]
            local frame = anchor and FindBadgeFrame(anchor)
            if frame then
                local info = { key = badge.key, frame = frame, base = CapturePoints(frame) }
                found[badge.key] = info
                if not hooked[frame] then
                    hooked[frame] = true
                    hooksecurefunc(frame, "SetPoint", function()
                        OnNativeSetPoint(info)
                    end)
                end
            end
        end
    end
end

local function ApplyBadgeOffsets()
    Discover()
    ns.pendingBadgeRefresh = false
    for _, badge in ipairs(BADGES) do
        local info = found[badge.key]
        if info then
            ApplyOne(info)
        end
    end
end

local function SetBadgeOffset(key, x, y)
    GripbarDB["badge_" .. key .. "_x"] = math.max(OFFSET_MIN, math.min(OFFSET_MAX, x))
    GripbarDB["badge_" .. key .. "_y"] = math.max(OFFSET_MIN, math.min(OFFSET_MAX, y))
    ApplyBadgeOffsets()
end

local function GetBadgeDiagnostic()
    Discover()
    local parts = {}
    for _, badge in ipairs(BADGES) do
        local info = found[badge.key]
        local x, y = GetOffset(badge.key)
        local name = info and (info.frame:GetDebugName() or "?") or "not found"
        parts[#parts + 1] = string.format("%s %+d/%+d (%s)", badge.key, x, y, name)
    end
    return table.concat(parts, "; ")
end

-- /grip badge [lt|rt|both] [x y | reset]
local function HandleBadgeCommand(args)
    local key = (args[2] or ""):lower()
    -- Defaults: the user's tuned layout (LT + RT 22 lower, the rest untouched).
    local DEFAULT_Y = { lt = 0, rt = 0, both = -22 }
    if key == "reset" then
        for _, badge in ipairs(BADGES) do
            GripbarDB["badge_" .. badge.key .. "_x"] = 0
            GripbarDB["badge_" .. badge.key .. "_y"] = DEFAULT_Y[badge.key]
        end
        ApplyBadgeOffsets()
    elseif key == "lt" or key == "rt" or key == "both" then
        if (args[3] or ""):lower() == "reset" then
            SetBadgeOffset(key, 0, DEFAULT_Y[key])
        else
            local x, y = tonumber(args[3]), tonumber(args[4])
            if not x or not y then
                Print("Usage: /grip badge <lt|rt|both> <x> <y>  (-200..200), /grip badge <lt|rt|both> reset, /grip badge reset")
                return
            end
            SetBadgeOffset(key, x, y)
        end
    elseif key ~= "" then
        Print("Usage: /grip badge <lt|rt|both> <x> <y>  (-200..200), /grip badge <lt|rt|both> reset, /grip badge reset")
        return
    end
    Print("Native trigger badges: " .. GetBadgeDiagnostic())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not ns.pendingBadgeRefresh then
        return
    end
    ApplyBadgeOffsets()
end)

ns.BADGES = BADGES
ns.ApplyBadgeOffsets = ApplyBadgeOffsets
ns.HandleBadgeCommand = HandleBadgeCommand
ns.GetBadgeDiagnostic = GetBadgeDiagnostic
