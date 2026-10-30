-- Simulation test for the 0.2.0 reactions: vehicles, crowds, lines, bites,
-- hits (run by run_test.py through lupa; TRANSLATIONS holds the EN IG_UI.json).

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

CLOCK = 100000
function getTimestampMs() return CLOCK end
function instanceof(object, class) return type(object) == "table" and object.__class == class end
function isServer() return false end
function isClient() return false end
function getText(key) return TRANSLATIONS[key] or key end
function ZombRand(n) return 0 end
Vector3f = { new = function() return {} end }
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

-- world objects
local function body(class, x, y, z, extra)
    local object = { __class = class, _x = x, _y = y, _z = z or 0 }
    function object:getX() return self._x end
    function object:getY() return self._y end
    function object:getZ() return self._z end
    for k, v in pairs(extra or {}) do object[k] = v end
    return object
end
VEHICLES = {}
local vehicleList = {
    size = function() return #VEHICLES end,
    -- PZ 42.21 IsoCell.getVehicles() is a Java Set, not an indexable list.
    iterator = function()
        local index = 0
        return { hasNext = function() return index < #VEHICLES end,
            next = function() index = index + 1 return VEHICLES[index] end }
    end,
}
ROOM = nil
local shell = body("IsoZombie", 100, 100, 0, {
    getSquare = function() return { getRoom = function() return ROOM end } end,
    getModData = function() return {} end,
})
local function vehicle(x, y, kmh, fx, fy, driver)
    return body("BaseVehicle", x, y, 0, {
        getCurrentSpeedKmHour = function() return kmh end,
        getForwardVector = function() return { x = function() return fx end, z = function() return fy end } end,
        getDriver = function() return driver end,
    })
end
function getCell() return { getVehicles = function() return vehicleList end } end

-- Project A-Life stubs
local P = {}
ProjectALife = P
P.BehaviorSettings = { combat = { meleeReadyMs = 220 }, endurance = { reengageThreshold = 72 } }
P.Combat = { settings = {}, MELEE_TIMING = {}, xyzOf = function(b) return b:getX(), b:getY(), b:getZ() end,
    configure = function() end, leashFor = function() return nil end,
    weaponFor = function() return WEAPON end, isUnarmed = function(w) return w == nil end }
P.Endurance = { settings = {}, configure = function() end }
P.Survival = { retreatHealth = 0.35, flinchHealth = 0.6, configure = function() end,
    beginDisengage = function() return 0 end }
ZOMBIES, ACTORS = {}, {}
P.Perception = {
    snapshotFor = function(now) return { atMs = now, bodies = ZOMBIES, actors = ACTORS } end,
    closingSpeed = function(s, z) return z.closing or 0 end,
    visible = function(s, z) return z.visible ~= false end,
    ignore = function() end,
    noteAttacker = function() return true end,
    activeActorForShell = function(b) return b.actor end,
}
P.DecisionLoop = { states = {}, lanes = {}, panicHolds = { panic_stare = true }, configure = function() end,
    engagement = function(actor, s, threat, kind, state, now)
        actor.memory = actor.memory or {}
        actor.memory.engagementReason = "continue_mission"
        return "bypass", { mission = "travel" }
    end }
P.ZombieFocus = { ignoreMs = 750, closingRadius = 15, radius = function() return 8 end }
P.ModuleFear = { settings = {} }
P.Caution = { settings = {}, zombieMode = function() return "default" end }
P.GunDiscipline = { rollMs = 30000, engagement = function(a, s, t, f, choice, reason) return choice, reason end }
P.Animations = { drawSequenceFor = function() return "reach", 420, "take", 750 end }
GUNFEAR_CALLS = 0
P.ModuleGunFear = { interrupt = function() GUNFEAR_CALLS = GUNFEAR_CALLS + 1; return nil end }
SAID = {}
P.Speech = { say = function(s, text, options) SAID[#SAID + 1] = text; return true end,
    display = function(s, text, color, kind, uid) SAID[#SAID + 1] = "pain:" .. text; return true end,
    quietReason = function() return nil end, refusedDead = function() return false end,
    variable = function() return "u1" end, colorFor = function() return { 1, 2, 3 } end }
REPORTED = {}
P.SquadTactics = { reportThreat = function(actor, target, kind, now) REPORTED[#REPORTED + 1] = kind; return true end }
P.VehicleRules = { riding = function() return nil end, strike = function(s, v, kmh, now) return STRIKE_RESULT end }
local npc = { uid = "npc-1", generation = 1, memory = {}, factionId = "f1" }
P.ActorRegistry = { read = function(uid) return uid == "npc-1" and npc or nil end }
P.Talk = { shellFor = function(uid) return uid == "npc-1" and shell or nil end }
P.Relations = { sameSide = function(a, b) return a.factionId == b.factionId end,
    playerStance = function(actor, player) return player.stance or "neutral" end }
P.PlayerLocator = { list = function() return PLAYERS or {} end }

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/ALR_Boot"
local A = ALifeReactive
A.settings.debug = false

local passed, failed = 0, 0
local function check(name, condition, detail)
    if condition then passed = passed + 1
    else failed = failed + 1; print("FAIL " .. name .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or "")) end
end
local function eq(name, got, want) check(name, got == want, tostring(got) .. " ~= " .. tostring(want)) end

Events.OnGameStart.fire()
check("installed", A.Boot.installed)
check("gunfear wrapped", A.wrapped["ModuleGunFear.interrupt"] ~= nil)
check("noteAttacker wrapped", A.wrapped["Perception.noteAttacker"] ~= nil)
check("strike wrapped", A.wrapped["VehicleRules.strike"] ~= nil)
check("panic holds registered", P.DecisionLoop.panicHolds.alr_dodge == true and P.DecisionLoop.panicHolds.panic_stare == true)

-- helpers the decision loop passes to the interrupt hook
MOVES = {}
local helpers = {
    startMovement = function(actor, s, target, intent, options)
        if BLOCKED and BLOCKED(target) then return nil end
        MOVES[#MOVES + 1] = { target = target, intent = intent, options = options }
        return { kind = options.kind or "movement", intent = intent, action = {}, cooldownUntilMs = 0 }
    end,
    startRetreat = function(actor, s, threat, kind, now, reason) RETREATED = reason; return { kind = "retreat", intent = "retreat" } end,
    setActivity = function() end, persistMemory = function() end,
}
local function interrupt(state) return P.ModuleGunFear.interrupt(npc, shell, state or { kind = "idle", intent = "idle_stand" }, CLOCK, helpers) end
local function reset() MOVES, SAID, REPORTED, VEHICLES, ZOMBIES, ACTORS, PLAYERS = {}, {}, {}, {}, {}, {}, {}
    A.Hazards.nextVehicleMs, A.Hazards.nextCrowdMs, A.Hazards.legs = {}, {}, {}
    A.Lines.lastAtMs = {}; A.Vehicles.refreshedAtMs = -1 end

-- 1. vehicle head-on from the east at 40 km/h (11 tiles/s), 13 tiles away (1.2 s): dodge sideways
reset()
VEHICLES[1] = vehicle(113, 100, 40, -1, 0)
local state = interrupt()
check("dodge returned a state", state ~= nil and state.intent == "alr_dodge", state and state.intent)
if state then
    local m = MOVES[1]
    local dx, dy = m.target.x - 100, m.target.y - 100
    check("dodge is perpendicular", math.abs(dx) < 0.01 and math.abs(math.abs(dy) - 3) < 0.01, dx .. "," .. dy)
    eq("dodge sprints", m.options.pace, "sprint")
    check("dodge line said", SAID[1] == TRANSLATIONS["IGUI_ALR_vehicle_dodge_1"], SAID[1])
end
eq("dodges counted", A.metrics.dodges, 1)
check("cooldown blocks a second dodge", interrupt() == nil)
eq("gunfear still consulted", GUNFEAR_CALLS, 1)

-- 2. the second sample gives the velocity from positions (car moved 1.1 tiles in 100 ms, same answer)
reset(); CLOCK = CLOCK + 100
VEHICLES[1] = vehicle(110, 100, 40, -1, 0); A.Vehicles.refresh(CLOCK)
CLOCK = CLOCK + 100; VEHICLES[1]._x = 108.9
local rows = A.Vehicles.refresh(CLOCK)
check("sampled velocity", rows[1] ~= nil and math.abs(rows[1].vx + 11) < 0.01, rows[1] and rows[1].vx)

-- 3. moving away, passing wide, far, in a room, riding
reset(); VEHICLES[1] = vehicle(110, 100, 40, 1, 0); check("moving away: nothing", interrupt() == nil)
reset(); VEHICLES[1] = vehicle(110, 104, 40, -1, 0); check("passing 4 tiles wide: nothing", interrupt() == nil)
reset(); VEHICLES[1] = vehicle(140, 100, 40, -1, 0); check("40 tiles away: nothing", interrupt() == nil)
reset(); VEHICLES[1] = vehicle(110, 100, 40, -1, 0); ROOM = {}; check("inside a room: nothing", interrupt() == nil); ROOM = nil
reset(); VEHICLES[1] = vehicle(110, 100, 40, -1, 0); P.VehicleRules.riding = function() return {} end
check("riding: nothing", interrupt() == nil); P.VehicleRules.riding = function() return nil end

-- 4. fast and close: dive, near miss remembered for a player driver
reset()
local driver = body("IsoPlayer", 0, 0, 0, { getUsername = function() return "Ivan" end })
VEHICLES[1] = vehicle(106, 100, 60, -1, 0, driver)
state = interrupt()
check("dive", state ~= nil and state.intent == "alr_dive", state and state.intent)
check("dive steps further", MOVES[1] and math.abs(math.abs(MOVES[1].target.y - 100) - 4.5) < 0.01)
check("near miss remembered", npc.memory.alrNearMiss and npc.memory.alrNearMiss.key == "Ivan" and npc.memory.alrNearMiss.count == 1)

-- 5. slow car, idle NPC: step aside at a walk; walking NPC: nothing
reset(); VEHICLES[1] = vehicle(103, 100, 10, -1, 0)
state = interrupt({ kind = "idle", intent = "idle_stand" })
check("step aside", state ~= nil and state.intent == "alr_step_aside" and MOVES[1].options.pace == "walk", state and state.intent)
reset(); VEHICLES[1] = vehicle(103, 100, 10, -1, 0)
check("walking NPC ignores a slow car", interrupt({ kind = "movement", intent = "travel" }) == nil)

-- 6. the first side blocked: the other side
reset(); VEHICLES[1] = vehicle(110, 100, 40, -1, 0)
BLOCKED = function(target) return target.y > 100 end
state = interrupt()
check("other side used", state ~= nil and MOVES[1].target.y < 100)
BLOCKED = nil

-- 7. our own intents are not interrupted, combat states are left alone
reset(); VEHICLES[1] = vehicle(110, 100, 40, -1, 0)
check("own dodge not interrupted", interrupt({ kind = "movement", intent = "alr_dodge" }) == nil)
check("combat left alone", interrupt({ kind = "combat", intent = "attack" }) == nil)

-- 8. crowd: four zombies east, three walking at us -> fall back west, squad told, line said
local function zombie(x, y, closing) return { body = body("IsoZombie", x, y, 0, { closing = closing }), x = x, y = y, z = 0 } end
reset()
ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1), zombie(103, 102, 0) }
state = interrupt()
check("fallback", state ~= nil and state.intent == "alr_fallback", state and state.intent)
check("fallback goes west", MOVES[1] and MOVES[1].target.x < 94 and math.abs(MOVES[1].target.y - 100) < 2, MOVES[1] and MOVES[1].target.x)
eq("fallback runs", MOVES[1] and MOVES[1].options.pace, "run")
eq("squad told", REPORTED[1], "zombie")
check("crowd line", SAID[1] == TRANSLATIONS["IGUI_ALR_crowd_1"], SAID[1])
check("crowd cooldown", interrupt() == nil)

-- 9. crowd with an ally to the north: regroup toward the ally, stopping short
reset()
ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1) }
local allyActor = { uid = "npc-2", factionId = "f1", memory = {} }
ACTORS = { { body = body("IsoZombie", 100, 90, 0, { actor = allyActor }), x = 100, y = 90, z = 0 } }
state = interrupt()
check("regroup", state ~= nil and state.intent == "alr_regroup", state and state.intent)
check("regroup stops short of the ally", MOVES[1] and math.abs(MOVES[1].target.y - 91.5) < 0.01 and math.abs(MOVES[1].target.x - 100) < 0.01)
check("regroup line", SAID[1] == TRANSLATIONS["IGUI_ALR_regroup_1"], SAID[1])

-- 10. an ally behind the crowd is not used; a friendly player is
reset()
ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1) }
ACTORS = { { body = body("IsoZombie", 112, 100, 0, { actor = allyActor }), x = 112, y = 100, z = 0 } }
state = interrupt()
check("ally behind the crowd ignored", state ~= nil and state.intent == "alr_fallback", state and state.intent)
reset()
ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1) }
PLAYERS = { body("IsoPlayer", 100, 112, 0, { stance = "friendly" }) }
state = interrupt()
check("friendly player as regroup target", state ~= nil and state.intent == "alr_regroup" and MOVES[1].target.y > 109, state and state.intent)

-- 11. too few closing, leashed guard, legs budget
reset(); ZOMBIES = { zombie(104, 100, 0), zombie(105, 101, 0), zombie(105, 99, 1) }
check("only one closing: nothing", interrupt() == nil)
reset(); ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1) }
P.Combat.leashFor = function() return {} end; check("leashed guard: nothing", interrupt() == nil); P.Combat.leashFor = function() return nil end
reset(); ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 1), zombie(105, 99, 1) }
A.Hazards.legs["npc-1"] = { sinceMs = CLOCK, count = 3 }
check("legs budget: nothing", interrupt() == nil)

-- 12. engagement: crowd gate and unarmed gate
reset()
local function engage(threat)
    local actor = { uid = "npc-1", memory = {} }
    return (P.DecisionLoop.engagement(actor, shell, threat, "zombie", nil, CLOCK))
end
WEAPON = { name = "bat" }
local lone = body("IsoZombie", 104, 100, 0, { closing = 1 })
eq("lone zombie: commit", engage(lone), "commit")
check("spot line", SAID[1] == TRANSLATIONS["IGUI_ALR_spot_1"], SAID[1])
reset(); ZOMBIES = { zombie(104, 100, 1), zombie(105, 101, 0), zombie(105, 99, 0) }
eq("crowd gate: bypass", engage(lone), "bypass")
eq("crowd refused counted", A.metrics.crowdRefused, 1)
reset(); WEAPON = nil
eq("unarmed: bypass", engage(lone), "bypass")
check("unarmed line", SAID[1] == TRANSLATIONS["IGUI_ALR_unarmed_1"], SAID[1])
WEAPON = { name = "bat" }

-- 13. bitten: delayed pain line through Speech.display, once per 5 s
reset(); A.Reactions.pending = {}
P.Perception.noteAttacker("npc-1", lone, 6000, "zombie")
eq("bite counted", A.metrics.bites, 1)
eq("line pending, not yet said", #SAID, 0)
A.Reactions.flush(CLOCK + 1000); eq("still pending at 1 s", #SAID, 0)
A.Reactions.flush(CLOCK + 1600)
check("bitten line via display", SAID[1] == "pain:" .. TRANSLATIONS["IGUI_ALR_bitten_1"], SAID[1])
P.Perception.noteAttacker("npc-1", lone, 6000, "zombie"); A.Reactions.flush(CLOCK + 4000)
eq("bitten cooldown", #SAID, 1)
P.Perception.noteAttacker("npc-1", { __class = "IsoPlayer" }, 6000, "player"); A.Reactions.flush(CLOCK + 9000)
eq("player attacker: no bite line", #SAID, 1)

-- 14. hit by a car: line after a delay; the same player twice -> the warning line
reset(); A.Reactions.pending = {}
shell.actor = npc
STRIKE_RESULT = true
local car = vehicle(100, 100, 30, -1, 0, driver)
check("strike passes through", P.VehicleRules.strike(shell, car, 30, CLOCK) == true)
A.Reactions.flush(CLOCK + 2000)
check("hit line", SAID[1] == "pain:" .. TRANSLATIONS["IGUI_ALR_vehicle_hit_1"], SAID[1])
A.Lines.lastAtMs = {}
P.VehicleRules.strike(shell, car, 30, CLOCK + 10000); A.Reactions.flush(CLOCK + 12000)
check("second hit: warning line", SAID[2] == "pain:" .. TRANSLATIONS["IGUI_ALR_vehicle_hit_again_1"], SAID[2])
STRIKE_RESULT = false
P.VehicleRules.strike(shell, car, 30, CLOCK + 20000); A.Reactions.flush(CLOCK + 22000)
eq("miss: nothing", #SAID, 2)

-- 15. lines: cooldown and missing translation
reset()
check("line said", A.say(npc, shell, "crowd", 1000))
check("line cooldown", not A.say(npc, shell, "crowd", 1000))
local saved = TRANSLATIONS["IGUI_ALR_regroup_1"]; TRANSLATIONS["IGUI_ALR_regroup_1"] = nil
check("missing translation: no line", not A.say(npc, shell, "regroup"))
TRANSLATIONS["IGUI_ALR_regroup_1"] = saved
eq("no errors", A.metrics.errors, 0)

Events.EveryOneMinute.fire()
print(string.format("RESULT passed=%d failed=%d", passed, failed))
return failed
