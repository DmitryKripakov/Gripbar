-- Debug log: Lua errors (any addon's), blocked protected actions and
-- Gripbar's own messages, kept in the GripbarDebugLog saved variable. The
-- game writes it to WTF\Account\<account>\SavedVariables\Gripbar.lua on
-- /reload and on logout, where it can be read outside the game.
-- On with /grip debug (or the Diagnostics button); the last MAX_LINES stay.
local _, ns = ...

local MAX_LINES = 800

local function On()
    return type(GripbarDebugLog) == "table" and GripbarDebugLog.enabled == true
end

local function Log(kind, text)
    if not On() then
        return
    end
    local lines = GripbarDebugLog.lines
    lines[#lines + 1] = string.format("%s %.3f [%s] %s", date("%H:%M:%S"), GetTime(), kind, tostring(text))
    local extra = #lines - MAX_LINES
    if extra > 0 then
        for _ = 1, extra do
            table.remove(lines, 1)
        end
    end
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
            Log("error", tostring(message) .. (ok and stack and ("\n" .. stack) or ""))
        end
        if previous then
            return previous(message, ...)
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "Gripbar" then
            GripbarDebugLog = type(GripbarDebugLog) == "table" and GripbarDebugLog or {}
            GripbarDebugLog.lines = type(GripbarDebugLog.lines) == "table" and GripbarDebugLog.lines or {}
            -- On until switched off (a fresh install starts logging).
            if GripbarDebugLog.enabled == nil then
                GripbarDebugLog.enabled = true
            end
            HookErrors()
        end
    elseif event == "PLAYER_LOGIN" then
        local version, build, _, interface = GetBuildInfo()
        Log("session", string.format("login: client %s (%s, %s), Gripbar %s", tostring(version), tostring(build),
            tostring(interface), tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Gripbar", "Version"))))
        C_Timer.After(5, function()
            LogDiagnostics("5 s after login")
        end)
    else
        local addon, action = ...
        Log(event == "LUA_WARNING" and "warning" or "blocked", event .. ": " .. tostring(addon) .. " " .. tostring(action))
    end
end)

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
        ns.Print("Debug log cleared.")
        return
    end
    SetEnabled(not On())
    ns.Print(On() and "Debug log on: errors and Gripbar messages go to SavedVariables\\Gripbar.lua (written on /reload or logout). /grip debug clear empties it."
        or "Debug log off.")
end

ns.Log = Log
ns.LogDiagnostics = LogDiagnostics
ns.IsDebugLogOn = On
ns.SetDebugLogEnabled = SetEnabled
ns.ToggleDebug = ToggleDebug
