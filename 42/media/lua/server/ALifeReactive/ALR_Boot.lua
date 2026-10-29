-- A-Life: Reactive Survivors - bootstrap. Installs the tuning and the hooks
-- once Project A-Life is loaded (OnGameStart / OnServerStarted, with an OnTick
-- fallback), and prints the counters every minute.

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/ALR_Tuning"
require "ALifeReactive/ALR_Hooks"

local A = ALifeReactive
local B = { installed = false, tries = 0, lastReport = nil, minute = 0 }
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
    local a = ProjectALife
    if type(a) ~= "table" or a.DecisionLoop == nil or a.Perception == nil or a.Combat == nil then
        B.tries = B.tries + 1
        if B.tries == 1 then A.log("Project A-Life not loaded yet, waiting") end
        return false
    end
    B.installed = true
    if not A.settings.enabled then
        A.log("disabled in settings")
        return true
    end
    local ok, err = pcall(function()
        A.Tuning.hookConfigure(a)
        A.Tuning.apply(a)
        A.Hooks.install(a)
    end)
    if not ok then
        A.metrics.errors = A.metrics.errors + 1
        A.log("install failed:", err)
        return true
    end
    A.log("v" .. A.VERSION .. " installed (" .. side() .. ")")
    return true
end

local function snapshot()
    local m = A.metrics
    return m.reactiveChecks .. "/" .. m.reactiveCommits .. "/" .. m.reactiveRefused .. "/"
        .. m.leaseCaps .. "/" .. m.ignoreCaps .. "/" .. m.draws .. "/" .. m.configures .. "/" .. m.errors
end

function B.report()
    local every = tonumber(A.settings.report.everyMinutes) or 0
    if every <= 0 or not B.installed then return end
    B.minute = B.minute + 1
    if B.minute % every ~= 0 then return end
    local current = snapshot()
    if current == B.lastReport then return end
    B.lastReport = current
    local m = A.metrics
    A.log("checks=" .. m.reactiveChecks, "commits=" .. m.reactiveCommits, "refused=" .. m.reactiveRefused,
        "leaseCaps=" .. m.leaseCaps, "ignoreCaps=" .. m.ignoreCaps, "draws=" .. m.draws,
        "configures=" .. m.configures, "errors=" .. m.errors)
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
    add("EveryOneMinute", function() pcall(B.report) end)
end

return B
