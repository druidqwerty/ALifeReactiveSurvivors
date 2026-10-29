-- Simulation test for A-Life: Reactive Survivors (run by run_test.py through lupa).
-- Stubs the Project A-Life tables the addon touches, loads the addon, fires the
-- game-start event and checks every hook and every tuned number.

local ROOT = MOD_ROOT .. "/42/media/lua/"
local loaded = {}
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local chunk = loadfile(ROOT .. "shared/" .. name .. ".lua") or loadfile(ROOT .. "server/" .. name .. ".lua")
    assert(chunk, "require failed: " .. name)
    local result = chunk()
    loaded[name] = result == nil and true or result
    return loaded[name]
end

-- PZ globals
CLOCK = 100000
function getTimestampMs() return CLOCK end
function instanceof(object, class) return type(object) == "table" and object.__class == class end
function isServer() return false end
function isClient() return false end
Events = setmetatable({}, { __index = function(t, name)
    local event = { handlers = {} }
    function event.Add(fn) event.handlers[#event.handlers + 1] = fn end
    function event.Remove(fn)
        for index = #event.handlers, 1, -1 do
            if event.handlers[index] == fn then table.remove(event.handlers, index) end
        end
    end
    function event.fire(...)
        local copy = {}
        for index, fn in ipairs(event.handlers) do copy[index] = fn end
        for _, fn in ipairs(copy) do fn(...) end
    end
    rawset(t, name, event)
    return event
end })

-- Project A-Life stubs
local P = {}
ProjectALife = P
P.BehaviorSettings = {
    combat = { meleeReadyMs = 220, meleeWindupMs = 150, meleeRecoveryMs = 680, attackIntervalMs = 650,
        unreachableCooldownMs = 1200, leashSelfDefenceReach = 1.5, closingRunChancePercent = 80,
        closingRunMinimumDistance = 5.5, meleeRange = 1.1 },
    endurance = { retreatThreshold = 24, reengageThreshold = 72, minimumRetreatMs = 2200, damageRetreatMs = 2600 },
}
P.Combat = { settings = {}, adapters = {},
    MELEE_TIMING = { oneHanded = { delayMs = 400 }, twoHanded = { delayMs = 400 }, knife = { delayMs = 267 } },
    xyzOf = function(body) return body.x, body.y, body.z end }
function P.Combat.configure(adapters)
    P.Combat.adapters = adapters or {}
    P.Combat.settings = {}
    for name, value in pairs(P.BehaviorSettings.combat) do
        P.Combat.settings[name] = tonumber(P.Combat.adapters[name]) or value
    end
end
P.Endurance = { settings = {} }
function P.Endurance.configure(adapters)
    P.Endurance.settings = {}
    for name, value in pairs(P.BehaviorSettings.endurance) do
        P.Endurance.settings[name] = tonumber((adapters or {})[name]) or value
    end
end
LAST_LEASE = nil
P.Survival = { retreatHealth = 0.35, flinchHealth = 0.6, reengageHealth = 0.45 }
function P.Survival.configure(adapters) P.Survival.flinchHealth = 0.6 end
function P.Survival.beginDisengage(actor, shell, threat, now, durationMs)
    LAST_LEASE = durationMs
    return now + durationMs
end
LAST_IGNORE = nil
P.Perception = {}
function P.Perception.closingSpeed(shell, candidate) return candidate.closing or 0 end
function P.Perception.visible(shell, candidate) return candidate.visible ~= false end
function P.Perception.ignore(uid, target, holdMs) LAST_IGNORE = holdMs end
BASE_CHOICE, BASE_REASON = "bypass", "continue_mission"
P.DecisionLoop = { states = {},
    lanes = { passiveHotMs = 250, passiveMidMs = 1000, passiveFarMs = 2500, passiveCloseRadius = 12, hot = {} } }
function P.DecisionLoop.configure(adapters)
    adapters = adapters or {}
    P.Combat.configure(adapters.combat)
    P.Endurance.configure(adapters.endurance)
    P.Survival.configure(adapters.survival)
end
function P.DecisionLoop.engagement(actor, shell, threat, threatKind, state, now)
    actor.memory = actor.memory or {}
    actor.memory.engagementDecision, actor.memory.engagementReason = BASE_CHOICE, BASE_REASON
    return BASE_CHOICE, { mission = "travel", targetKind = threatKind }
end
FOCUS_RADIUS = 8
P.ZombieFocus = { ignoreMs = 750, closingRadius = 15, radius = function() return FOCUS_RADIUS end }
P.ModuleFear = { settings = { ignoreMs = 1000, farTiles = 8 } }
ZMODE = "default"
P.Caution = { settings = { waitMs = 3500, lightWaitMs = 2500 }, zombieMode = function() return ZMODE end }
GUN_REFUSE = false
P.GunDiscipline = { rollMs = 30000, noted = 0 }
function P.GunDiscipline.engagement(actor, shell, threat, facts, choice, reason, now)
    if GUN_REFUSE then return "bypass", "gun_discipline" end
    return choice, reason
end
function P.GunDiscipline.noteAvoid() P.GunDiscipline.noted = P.GunDiscipline.noted + 1 end
P.Animations = { drawSequenceFor = function() return "reach", 420, "take", 750 end }
-- Jeem Extension's own focus filter table
ProjectALifeJimmy = { ZombieFocus = { ignoreMs = 750, closingRadius = 15, postRadius = 12 } }

-- the base mod configures once at start, before or after us
P.DecisionLoop.configure({ combat = { meleeReadyMs = 999 } })

-- load the addon; Project A-Life is hidden until the first ticks to exercise
-- the OnTick fallback (our files load before ProjectALife/ alphabetically).
require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/ALR_Boot"
local A = ALifeReactive
local realALife = ProjectALife
ProjectALife = nil
Events.OnGameStart.fire()
if A.Boot.installed then error("installed without Project A-Life") end
Events.OnTick.fire()
Events.OnTick.fire()
if A.Boot.installed or A.Boot.tries ~= 3 then error("tick fallback miscounted: " .. tostring(A.Boot.tries)) end
ProjectALife = realALife

local passed, failed = 0, 0
local function check(name, condition, detail)
    if condition then passed = passed + 1
    else failed = failed + 1; print("FAIL " .. name .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or "")) end
end
local function eq(name, got, want) check(name, got == want, tostring(got) .. " ~= " .. tostring(want)) end

-- 1. boot (third tick finds Project A-Life and installs; the tick handler leaves)
eq("tick handler registered", #Events.OnTick.handlers, 1)
Events.OnTick.fire()
check("installed", A.Boot.installed)
eq("tick handler removed", #Events.OnTick.handlers, 0)
local wrappedCount = 0
for _ in pairs(A.wrapped) do wrappedCount = wrappedCount + 1 end
eq("wrapped count", wrappedCount, 6)
eq("jeem focus ignore", ProjectALifeJimmy.ZombieFocus.ignoreMs, 400)
eq("jeem focus closing", ProjectALifeJimmy.ZombieFocus.closingRadius, 18)
eq("jeem focus other key kept", ProjectALifeJimmy.ZombieFocus.postRadius, 12)

-- 2. tuning, both layers (sandbox adapter 999 must lose to the live write)
eq("defaults meleeReadyMs", P.BehaviorSettings.combat.meleeReadyMs, 120)
eq("live meleeReadyMs", P.Combat.settings.meleeReadyMs, 120)
eq("untouched meleeRange", P.Combat.settings.meleeRange, 1.1)
eq("lanes hot", P.DecisionLoop.lanes.passiveHotMs, 150)
eq("lanes state kept", type(P.DecisionLoop.lanes.hot), "table")
eq("focus ignore", P.ZombieFocus.ignoreMs, 400)
eq("fear ignore", P.ModuleFear.settings.ignoreMs, 500)
eq("caution wait", P.Caution.settings.waitMs, 1500)
eq("gun rollMs", P.GunDiscipline.rollMs, 10000)
eq("melee delay one", P.Combat.MELEE_TIMING.oneHanded.delayMs, 250)
eq("melee delay knife kept", P.Combat.MELEE_TIMING.knife.delayMs, 267)
eq("flinch", P.Survival.flinchHealth, 0.45)
eq("reengage", P.Endurance.settings.reengageThreshold, 50)
eq("original recorded", A.originals["Combat.settings.meleeReadyMs"].was, 999)

-- 3. configure re-apply (Executor.start / Runtime.start run it again)
P.DecisionLoop.configure({ combat = { meleeReadyMs = 999 }, endurance = { reengageThreshold = 80 } })
eq("re-applied meleeReadyMs", P.Combat.settings.meleeReadyMs, 120)
eq("re-applied reengage", P.Endurance.settings.reengageThreshold, 50)
eq("re-applied flinch", P.Survival.flinchHealth, 0.45)
eq("configures counted", A.metrics.configures, 1)

-- 4. engagement
local shell = { x = 100, y = 100, z = 0 }
local function zombie(dx, dy, z, closing, visible)
    return { __class = "IsoZombie", x = 100 + dx, y = 100 + dy, z = z or 0, closing = closing, visible = visible }
end
local function engage(threat, kind, state)
    local actor = { uid = "npc-1", memory = {} }
    local choice = P.DecisionLoop.engagement(actor, shell, threat, kind or "zombie", state, CLOCK)
    return choice, actor.memory.engagementReason
end
local choice, reason = engage(zombie(5, 0, 0, 1, true))
eq("closing 5 tiles -> commit", choice, "commit"); eq("closing reason", reason, "alr_closing")
eq("not closing -> bypass", (engage(zombie(5, 0, 0, 0, true))), "bypass")
eq("7 tiles -> bypass", (engage(zombie(7, 0, 0, 1, true))), "bypass")
choice, reason = engage(zombie(2, 0, 0, 0, false))
eq("near 2 tiles -> commit", choice, "commit"); eq("near reason", reason, "alr_near")
eq("other floor -> bypass", (engage(zombie(2, 0, 1, 1, true))), "bypass")
eq("unseen closing -> bypass", (engage(zombie(4, 3, 0, 1, false))), "bypass")
A.settings.react.needVisible = false
eq("unseen closing, no sight check -> commit", (engage(zombie(4, 3, 0, 1, false))), "commit")
A.settings.react.needVisible = true
eq("player kind untouched", (engage({ x = 102, y = 100, z = 0 }, "player")), "bypass")
eq("retreat state -> bypass", (engage(zombie(2, 0, 0, 1, true), "zombie", { kind = "retreat" })), "bypass")
eq("recovering state -> bypass", (engage(zombie(2, 0, 0, 1, true), "zombie", { kind = "recovering" })), "bypass")
eq("movement state -> commit", (engage(zombie(2, 0, 0, 1, true), "zombie", { kind = "movement" })), "commit")
BASE_REASON = "recent_disengagement"
eq("recent_disengagement kept", (engage(zombie(2, 0, 0, 1, true))), "bypass")
BASE_REASON = "continue_mission"
BASE_CHOICE = "watch"
eq("watch kept", (engage(zombie(2, 0, 0, 1, true))), "watch")
BASE_CHOICE = "commit"
eq("commit kept", (engage(zombie(2, 0, 0, 1, true))), "commit")
BASE_CHOICE = "bypass"
local refusedBefore = A.metrics.reactiveRefused
ZMODE = "avoid"
eq("avoid mode -> bypass", (engage(zombie(2, 0, 0, 1, true))), "bypass")
ZMODE = "default"
GUN_REFUSE = true
eq("gun discipline -> bypass", (engage(zombie(2, 0, 0, 1, true))), "bypass")
eq("gun noteAvoid called", P.GunDiscipline.noted, 1)
GUN_REFUSE = false
eq("refused counted", A.metrics.reactiveRefused, refusedBefore + 2)
A.settings.react.enabled = false
eq("react disabled -> bypass", (engage(zombie(2, 0, 0, 1, true))), "bypass")
A.settings.react.enabled = true
eq("commits counted", A.metrics.reactiveCommits, 4)
eq("checks counted", A.metrics.reactiveChecks, 10)
eq("no errors", A.metrics.errors, 0)

-- 5. lease cap
local actor = { uid = "npc-1", generation = 1 }
P.Survival.beginDisengage(actor, shell, zombie(1, 0), CLOCK, 25000); eq("lease zombie 25000 -> 8000", LAST_LEASE, 8000)
P.Survival.beginDisengage(actor, shell, zombie(1, 0), CLOCK, 5000); eq("lease zombie 5000 kept", LAST_LEASE, 5000)
P.Survival.beginDisengage(actor, shell, { x = 1, y = 1, z = 0 }, CLOCK, 25000); eq("lease player kept", LAST_LEASE, 25000)

-- 6. ignore cap
P.Perception.ignore("u", zombie(1, 0), 15000); eq("ignore zombie 15000 -> 4000", LAST_IGNORE, 4000)
P.Perception.ignore("u", zombie(1, 0), nil); eq("ignore zombie nil -> 4000", LAST_IGNORE, 4000)
P.Perception.ignore("u", zombie(1, 0), 2000); eq("ignore zombie 2000 kept", LAST_IGNORE, 2000)
P.Perception.ignore("u", { x = 1 }, 15000); eq("ignore player kept", LAST_IGNORE, 15000)

-- 7. draw scale
local r1, ms1, r2, ms2 = P.Animations.drawSequenceFor(shell, {})
eq("draw reach preset", r1, "reach"); eq("draw reach ms", ms1, 336); eq("draw take ms", ms2, 600)

-- 8. focus radius
eq("focus radius lifted", P.ZombieFocus.radius(), 10)
FOCUS_RADIUS = 12
eq("focus radius larger kept", P.ZombieFocus.radius(), 12)

-- 9. report / status / idempotent install
Events.EveryOneMinute.fire(); Events.EveryOneMinute.fire()
A.status()
Events.OnServerStarted.fire()
local again = 0
for _ in pairs(A.wrapped) do again = again + 1 end
eq("second install adds no wrappers", again, 6)
eq("still no errors", A.metrics.errors, 0)

print(string.format("RESULT passed=%d failed=%d", passed, failed))
return failed
