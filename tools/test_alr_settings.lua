-- Focused sandbox/tuning lifecycle tests; hooks are stubs, not a second AI suite.
local ROOT, loaded = MOD_ROOT .. "/42/media/lua/", {}
local installs, flushes = 0, 0
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local short = name:match("ALifeReactive/ALR_(.+)")
    if short == "Hooks" or short == "Hazards" or short == "Reactions" then
        local stub = { pending = {}, install = function() installs = installs + 1 end,
            flush = function() flushes = flushes + 1 end }
        ALifeReactive[short], loaded[name] = stub, stub
        return stub
    end
    local chunk = loadfile(ROOT .. "shared/" .. name .. ".lua") or loadfile(ROOT .. "server/" .. name .. ".lua")
    loaded[name] = assert(chunk, name)() or true
    return loaded[name]
end
CLOCK = 100000
function getTimestampMs() return CLOCK end
function isServer() return true end
function isClient() return false end
Events = setmetatable({}, { __index = function(t, name)
    local event = { handlers = {} }
    function event.Add(fn) event.handlers[#event.handlers + 1] = fn end
    function event.Remove(fn)
        for i = #event.handlers, 1, -1 do if event.handlers[i] == fn then table.remove(event.handlers, i) end end
    end
    function event.fire()
        local copy = {}; for i, fn in ipairs(event.handlers) do copy[i] = fn end
        for _, fn in ipairs(copy) do fn() end
    end
    rawset(t, name, event); return event
end })
local passed, failed = 0, 0
local function check(name, yes)
    if yes then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name) end
end
local function eq(name, got, want) check(name .. ": " .. tostring(got) .. " expected " .. tostring(want), got == want) end
require "ALifeReactive/03_ALR_Sandbox"
local A, S = ALifeReactive, ALifeReactive.Sandbox
local seen, options = {}, {}
local file = assert(io.open(MOD_ROOT .. "/42/media/sandbox-options.txt", "r"))
local definitions = file:read("*a"); file:close()
for _, entry in ipairs(S.entries) do
    local path = entry.group .. "." .. entry.key
    check("unique mapping " .. path, not seen[path] and not options[entry.option])
    seen[path], options[entry.option] = true, true
    eq("default " .. path, S.value(entry, nil), entry.default)
    check("UI option " .. path, definitions:find("option " .. S.namespace .. "." .. entry.option .. " =", 1, true) ~= nil)
    if entry.kind == "boolean" then
        eq("boolean type " .. path, S.value(entry, "false"), entry.default)
        eq("boolean false " .. path, S.value(entry, false), false)
    else
        eq("numeric lower bound " .. path, S.value(entry, entry.min - 100), entry.min)
        eq("numeric upper bound " .. path, S.value(entry, entry.max + 100), entry.max)
        eq("numeric NaN " .. path, S.value(entry, 0 / 0), entry.default)
        eq("numeric infinity " .. path, S.value(entry, math.huge), entry.default)
    end
end
for group, value in pairs(A.settings) do
    if type(value) == "table" then
        for key in pairs(value) do check("setting exposed " .. group .. "." .. key, seen[group .. "." .. key]) end
    else check("setting exposed " .. group, seen["." .. group]) end
end
local P = {
    BehaviorSettings = { combat = { meleeReadyMs = 220, untouched = 17 }, endurance = { reengageThreshold = 72 } },
    Combat = { settings = { meleeReadyMs = 220 }, MELEE_TIMING = { oneHanded = { delayMs = 400 } } },
    Endurance = { settings = { reengageThreshold = 72 } }, Survival = { retreatHealth = 0.35, flinchHealth = 0.6 },
    DecisionLoop = { lanes = { passiveHotMs = 250 } }, Perception = {}, GunDiscipline = { rollMs = 30000 },
}
ProjectALife = P
function P.DecisionLoop.configure(ready)
    P.Combat.settings = { meleeReadyMs = ready or P.BehaviorSettings.combat.meleeReadyMs }
    P.Endurance.settings = { reengageThreshold = P.BehaviorSettings.endurance.reengageThreshold }
    P.Survival.flinchHealth = 0.6
    return "configured", nil, 13
end
SandboxVars = { ALifeReactiveSurvivors = { Enabled = false } }
require "ALifeReactive/ALR_Boot"
eq("two initial tick handlers", #Events.OnTick.handlers, 2)
Events.OnGameStart.fire()
eq("initially disabled", A.settings.enabled, false)
eq("hooks installed while disabled", installs, 3)
eq("disabled leaves defaults", P.BehaviorSettings.combat.meleeReadyMs, 220)
eq("disabled leaves live", P.Combat.settings.meleeReadyMs, 220)
Events.OnTick.fire()
eq("one persistent tick after install", #Events.OnTick.handlers, 1)
local vars, combatRef = SandboxVars.ALifeReactiveSurvivors, A.settings.combat
local function tick(delta) CLOCK = CLOCK + (delta or 2000); Events.OnTick.fire() end
vars.Enabled, vars.Combat_MeleeReadyMs = true, 180
tick(1999)
eq("poll throttled", A.settings.enabled, false)
tick(1)
eq("enabled live", A.settings.enabled, true)
eq("live tuning applied", P.Combat.settings.meleeReadyMs, 180)
eq("defaults tuned", P.BehaviorSettings.combat.meleeReadyMs, 180)
eq("settings table retained", A.settings.combat, combatRef)
eq("other setting retained", P.BehaviorSettings.combat.untouched, 17)
vars.Combat_MeleeReadyMs = 200; tick()
eq("numeric change applied", P.Combat.settings.meleeReadyMs, 200)
P.Combat.settings.meleeReadyMs = 777
P.BehaviorSettings.combat.meleeReadyMs = 888
P.GunDiscipline.rollMs = 444
A.Reactions.pending = { { atMs = CLOCK + 10000 } }
vars.Enabled = false; tick()
eq("external live write preserved", P.Combat.settings.meleeReadyMs, 777)
eq("external defaults write preserved", P.BehaviorSettings.combat.meleeReadyMs, 888)
eq("external other module write preserved", P.GunDiscipline.rollMs, 444)
eq("owned endurance restored", P.Endurance.settings.reengageThreshold, 72)
eq("previously absent key removed", P.Combat.settings.attackIntervalMs, nil)
eq("pending speech discarded", #A.Reactions.pending, 0)
vars.Enabled = true; tick()
local previousLive = P.Combat.settings
local first, second, third = P.DecisionLoop.configure(999)
eq("configure result one", first, "configured")
eq("configure result nil", second, nil)
eq("configure result three", third, 13)
eq("configure re-applies", P.Combat.settings.meleeReadyMs, 200)
eq("abandoned table restored", previousLive.meleeReadyMs, 777)
vars.Enabled = false; tick()
eq("new configured baseline restored", P.Combat.settings.meleeReadyMs, 999)
eq("default baseline not poisoned", P.BehaviorSettings.combat.meleeReadyMs, 888)
P.DecisionLoop.configure(666)
eq("disabled configure stays base", P.Combat.settings.meleeReadyMs, 666)
vars.Enabled = true; tick()
P.Combat.settings.meleeReadyMs = 543
vars.Combat_MeleeReadyMs = 201; tick()
eq("settings refresh updates overlay", P.Combat.settings.meleeReadyMs, 201)
vars.Enabled = false; tick()
eq("refresh remembers external baseline", P.Combat.settings.meleeReadyMs, 543)
vars.Enabled, vars.Crowd_SafeRetreat = true, false
vars.Crowd_FallbackCount, vars.Vehicle_DiveS = 3.6, -500
vars.Draw_Scale, vars.UnknownValue = "0.7", 1234
tick()
eq("new planner toggle mapped", A.settings.crowd.safeRetreat, false)
eq("integer rounded", A.settings.crowd.fallbackCount, 4)
eq("number bounded", A.settings.vehicle.diveS, 0.1)
eq("serialized number accepted", A.settings.draw.scale, 0.7)
eq("unknown option ignored", A.settings.UnknownValue, nil)
vars.Crowd_SafeRetreat, vars.Vehicle_DiveS = nil, "not-a-number"
tick()
eq("missing option default", A.settings.crowd.safeRetreat, true)
eq("malformed number default", A.settings.vehicle.diveS, 1)
eq("unchanged refresh", S.refresh(), false)
eq("no lifecycle errors", A.metrics.errors, 0)
print("Settings:", passed, "passed,", failed, "failed")
return failed
