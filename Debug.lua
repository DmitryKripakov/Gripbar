-- Debug log, kept in the GripbarDebugLog saved variable. The game writes it to
-- WTF\Account\<account>\SavedVariables\Gripbar.lua on /reload and on logout,
-- where it can be read outside the game. On with /grip debug.
--
--   problems  Lua errors (any addon's), blocked / forbidden protected actions
--             and Lua warnings: one record per distinct problem, with a
--             count, first / last time, the session and a stack. Chatter in
--             the timeline can never push these out.
--   lines     a timeline of everything (the last MAX_LINES; the same line
--             repeated in a row is kept once with a count).
--   sessions  the last MAX_SESSIONS logins (client and Gripbar version).
local _, ns = ...
local L = ns.L

local MAX_LINES = 3000
local MAX_PROBLEMS = 200
local MAX_SESSIONS = 20
local PROBLEM_KINDS = { error = true, blocked = true, warning = true }

-- Values the game keeps secret (a unit's name while its own targeting runs,
-- for one) cannot be compared or looked at by addon code: logged as a mark.
local IsSecret = _G.issecretvalue
local function Plain(value)
    if IsSecret and IsSecret(value) then
        return "(secret value)"
    end
    return tostring(value)
end

local function On()
    return type(GripbarDebugLog) == "table" and GripbarDebugLog.enabled == true
end

local function Stamp()
    return string.format("%s %s %.3f", date("%Y-%m-%d"), date("%H:%M:%S"), GetTime())
end

-- A problem's identity: its first line (the stack and counts differ).
local function ProblemKey(kind, text)
    return kind .. ": " .. (tostring(text):match("^[^\n]*") or "")
end

local function RecordProblem(kind, text, stack)
    local problems = GripbarDebugLog.problems
    local key = ProblemKey(kind, text)
    for _, record in ipairs(problems) do
        if record.key == key then
            record.count = record.count + 1
            record.last = Stamp()
            record.lastSession = GripbarDebugLog.session
            return
        end
    end
    problems[#problems + 1] = {
        key = key,
        kind = kind,
        text = tostring(text),
        stack = stack,
        count = 1,
        first = Stamp(),
        last = Stamp(),
        firstSession = GripbarDebugLog.session,
        lastSession = GripbarDebugLog.session,
    }
    while #problems > MAX_PROBLEMS do
        table.remove(problems, 1)
    end
end

local function LogRaw(kind, text, stack)
    if not On() then
        return
    end
    text = Plain(text)
    if stack ~= nil then
        stack = Plain(stack)
    end
    if PROBLEM_KINDS[kind] then
        RecordProblem(kind, text, stack)
    end
    local lines = GripbarDebugLog.lines
    local body = "[" .. kind .. "] " .. text
    -- The same line again: counted on the last one, not added.
    local last = lines[#lines]
    if last and GripbarDebugLog.lastBody == body then
        local count = (GripbarDebugLog.lastCount or 1) + 1
        GripbarDebugLog.lastCount = count
        lines[#lines] = string.format("%s %s (x%d)", Stamp(), body, count)
        return
    end
    GripbarDebugLog.lastBody, GripbarDebugLog.lastCount = body, 1
    lines[#lines + 1] = Stamp() .. " " .. body
    while #lines > MAX_LINES do
        table.remove(lines, 1)
    end
end

-- Logging never throws: it is called from handlers that run inside the
-- game's own code.
local function Log(kind, text, stack)
    pcall(LogRaw, kind, text, stack)
end

local function LogDiagnostics(reason)
    if On() and ns.BuildDiagnosticLines then
        local ok, lines = pcall(ns.BuildDiagnosticLines)
        Log("diag", reason .. "\n" .. (ok and table.concat(lines, "\n") or tostring(lines)))
    end
end

-- Lua errors: the handler in place (the game's, or BugGrabber's) still runs.
local function HookErrors()
    local previous = geterrorhandler()
    seterrorhandler(function(message, ...)
        if On() then
            local ok, stack = pcall(debugstack, 3, 12, 0)
            Log("error", tostring(message), ok and stack or nil)
        end
        if previous then
            return previous(message, ...)
        end
    end)
end

local function StartSession()
    local version, build, _, interface = GetBuildInfo()
    GripbarDebugLog.session = (tonumber(GripbarDebugLog.session) or 0) + 1
    local sessions = GripbarDebugLog.sessions
    sessions[#sessions + 1] = {
        session = GripbarDebugLog.session,
        start = Stamp(),
        client = string.format("%s (%s, %s)", tostring(version), tostring(build), tostring(interface)),
        gripbar = tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Gripbar", "Version")),
    }
    while #sessions > MAX_SESSIONS do
        table.remove(sessions, 1)
    end
    Log("session", string.format("login #%d: client %s, Gripbar %s", GripbarDebugLog.session,
        sessions[#sessions].client, sessions[#sessions].gripbar))
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", ns.Guard(function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "Gripbar" then
            GripbarDebugLog = type(GripbarDebugLog) == "table" and GripbarDebugLog or {}
            for _, key in ipairs({ "lines", "problems", "sessions" }) do
                GripbarDebugLog[key] = type(GripbarDebugLog[key]) == "table" and GripbarDebugLog[key] or {}
            end
            -- Off on a fresh install (/grip debug turns it on).
            if GripbarDebugLog.enabled == nil then
                GripbarDebugLog.enabled = false
            end
            HookErrors()
        end
    elseif event == "PLAYER_LOGIN" then
        if On() then
            StartSession()
            C_Timer.After(5, function()
                LogDiagnostics("5 s after login")
            end)
        end
    else
        local addon, action = ...
        Log(event == "LUA_WARNING" and "warning" or "blocked", event .. ": " .. tostring(addon) .. " " .. tostring(action),
            debugstack and debugstack(2, 24, 0) or nil)
    end
end, "Gripbar debug events"))

local function SetEnabled(enabled)
    GripbarDebugLog.enabled = enabled and true or false
    if enabled then
        Log("session", "debug log on")
        LogDiagnostics("snapshot")
    end
end

local function ToggleDebug(args)
    local option = (args and args[2] or ""):lower()
    if option == "clear" then
        GripbarDebugLog.lines = {}
        GripbarDebugLog.problems = {}
        GripbarDebugLog.lastBody = nil
        ns.Print(L("Debug log cleared."))
        return
    elseif option == "status" then
        local problems = GripbarDebugLog.problems or {}
        local total = 0
        for _, record in ipairs(problems) do
            total = total + record.count
        end
        ns.Print(string.format(L("Debug log %s: %d distinct problems (%d in all), %d timeline lines, session #%s."),
            On() and L("on") or L("off"), #problems, total, #(GripbarDebugLog.lines or {}), tostring(GripbarDebugLog.session)))
        return
    end
    SetEnabled(not On())
    ns.Print(On() and L("Debug log on: errors, blocked actions and Gripbar messages go to SavedVariables/Gripbar.lua (written on /reload or logout). /grip debug status, /grip debug clear.")
        or L("Debug log off."))
end

ns.Log = Log
ns.Plain = Plain
ns.LogDiagnostics = LogDiagnostics
ns.IsDebugLogOn = On
ns.SetDebugLogEnabled = SetEnabled
ns.ToggleDebug = ToggleDebug
