-- A-Life: Reactive Survivors - bootstrap. Installs the tuning and the hooks
-- once Project A-Life is loaded (OnGameStart / OnServerStarted, with an OnTick
-- fallback), flushes delayed lines, and prints the counters every minute.

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/01_ALR_Settings"
require "ALifeReactive/02_ALR_Lines"
require "ALifeReactive/03_ALR_Sandbox"
require "ALifeReactive/ALR_Tuning"
require "ALifeReactive/ALR_Hooks"
require "ALifeReactive/ALR_Hazards"
require "ALifeReactive/ALR_Reactions"

local A = ALifeReactive
local B = { installed = false, tries = 0, lastReport = nil, minute = 0, lastSettingsMs = nil }
A.Boot = B

local function side()
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    if server then return "server" end
    if client then return "client" end
    return "singleplayer"
end

function B.install()
    if B.installed then return true end
    if A.now() < (B.retryAtMs or 0) then return false end
    local a = ProjectALife
    if type(a) ~= "table" or a.DecisionLoop == nil or a.Perception == nil or a.Combat == nil then
        B.tries = B.tries + 1
        if B.tries == 1 then A.log("Project A-Life not loaded yet, waiting") end
        return false
    end
    if A.isIntegratedInBase(a) then
        B.installed = true
        B.obsolete = true
        A.settings.enabled = false
        A.log("v" .. A.VERSION .. " auto-disabled (safe no-op): Project A-Life 1.5+ already integrates early reactions, melee combat, crowd retreat, and VehicleEvasion (" .. side() .. ")")
        return true
    end
    local ok, err = pcall(function()
        A.Sandbox.refresh()
        B.lastSettingsMs = A.now()
        A.Tuning.hookConfigure(a)
        A.Tuning.apply(a)
        -- Wrappers check enabled at call time. Install even when initially
        -- disabled so an admin can enable the mod without reloading the world.
        A.Hooks.install(a)
        A.Hazards.install(a)
        A.Reactions.install(a)
    end)
    if not ok then
        A.metrics.errors = A.metrics.errors + 1
        A.log("install failed:", err)
        B.tries = B.tries + 1
        B.retryAtMs = A.now() + 1000
        return false
    end
    B.installed = true
    A.log("v" .. A.VERSION .. " installed (" .. side() .. ")")
    return true
end

function B.pollSettings(now)
    if not B.installed or B.obsolete then return false end
    now = tonumber(now) or A.now()
    local last = B.lastSettingsMs
    if last ~= nil and now >= last and now - last < A.Sandbox.pollMs then return false end
    B.lastSettingsMs = now
    local changed, tuningChanged, enabledChanged = A.Sandbox.refresh()
    if not changed then return false end
    if enabledChanged or tuningChanged then A.Tuning.apply(ProjectALife) end
    if enabledChanged and not A.settings.enabled and A.Reactions ~= nil then
        A.Reactions.pending = {}
    end
    if A.settings.debug then A.log("world settings updated; enabled=" .. tostring(A.settings.enabled)) end
    return true
end

function B.report()
    local every = tonumber(A.settings.report.everyMinutes) or 0
    if every <= 0 or not B.installed or B.obsolete then return end
    B.minute = B.minute + 1
    if B.minute % every ~= 0 then return end
    local current = A.counters()
    if current == B.lastReport then return end
    B.lastReport = current
    A.log(current)
end

local function add(name, callback)
    local event = type(Events) == "table" and Events[name] or nil
    if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
end

local function remove(name, callback)
    local event = type(Events) == "table" and Events[name] or nil
    if event ~= nil and type(event.Remove) == "function" then pcall(event.Remove, callback) end
end

if not A.bootRegistered then
    A.bootRegistered = true
    add("OnGameStart", function() pcall(B.install) end)
    add("OnServerStarted", function() pcall(B.install) end)
    -- Fallback: keep trying for a while after the first tick if the events ran
    -- before Project A-Life finished loading; the handler removes itself.
    local tick
    tick = function()
        if not B.installed and B.tries <= 600 then pcall(B.install) end
        if B.installed or B.tries > 600 then remove("OnTick", tick) end
    end
    add("OnTick", tick)
    -- Shared world settings and delayed lines use the existing persistent tick.
    add("OnTick", function()
        local now = A.now()
        local ok, err = pcall(B.pollSettings, now)
        if not ok then A.fail("sandbox refresh", err) end
        if B.installed and A.Reactions ~= nil and #A.Reactions.pending > 0 then
            pcall(A.Reactions.flush, now)
        end
    end)
    add("EveryOneMinute", function() pcall(B.report) end)
end

return B
