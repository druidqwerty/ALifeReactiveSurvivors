-- A-Life: Reactive Survivors - hazards that interrupt what a passive NPC is
-- doing: a vehicle coming at it, a group of zombies walking at it. Chained in
-- front of ModuleGunFear.interrupt, the hook the decision loop calls on every
-- think of an idle / walking / scavenging / recovering NPC, with the loop's
-- own helpers (startMovement, startRetreat, setActivity, persistMemory).

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/02_ALR_Lines"
require "ALifeReactive/ALR_Vehicles"
require "ALifeReactive/ALR_Crowd"

local A = ALifeReactive
local H = { installed = false, nextVehicleMs = {}, nextCrowdMs = {}, legs = {} }
A.Hazards = H

-- Our movement intents: the loop leaves them alone (Decisions.panicHolds).
H.intents = { alr_dodge = true, alr_dive = true, alr_step_aside = true, alr_fallback = true, alr_regroup = true }
local PASSIVE = { idle = true, movement = true, scavenging = true, recovering = true }

local function inRoom(shell)
    local ok, inside = pcall(function()
        local square = shell:getSquare()
        return square ~= nil and square:getRoom() ~= nil
    end)
    return ok and inside == true
end

local function riding(shell)
    local rules = ProjectALife.VehicleRules
    if rules == nil or type(rules.riding) ~= "function" then return false end
    local ok, vehicle = pcall(rules.riding, shell)
    return ok and vehicle ~= nil
end

-- Robbery, orders, a post, a leash, one of our own legs: leave it to A-Life.
local function busy(actor, state)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if type(memory.robbery) == "table" or type(memory.orderedTo) == "table" or memory.holdPost == true then
        return true
    end
    if type(state) == "table" and H.intents[tostring(state.intent)] then return true end
    return false
end

local function move(helpers, actor, shell, target, intent, options)
    if type(helpers) ~= "table" or type(helpers.startMovement) ~= "function" then return nil end
    local ok, state = pcall(helpers.startMovement, actor, shell, target, intent, options)
    if not ok then
        A.fail("startMovement", state)
        return nil
    end
    return state
end

function H.noteNearMiss(actor, vehicle, now)
    local ok, err = pcall(function()
        local driver = vehicle:getDriver()
        if driver == nil or not A.isPlayer(driver) or type(actor.memory) ~= "table" then return end
        local key = tostring(driver:getUsername())
        local mark = actor.memory.alrNearMiss
        if type(mark) ~= "table" or mark.key ~= key or now - (tonumber(mark.atMs) or 0) > 120000 then
            mark = { key = key, count = 0 }
        end
        mark.count, mark.atMs = mark.count + 1, now
        actor.memory.alrNearMiss = mark
    end)
    if not ok then A.fail("near miss", err) end
end

-- Vehicle ladder: step aside (slow car, idle NPC) / dodge (coming at us) /
-- dive (fast and about to hit).
function H.vehicle(actor, shell, state, now, helpers)
    local s = A.settings.vehicle
    if type(s) ~= "table" or not s.enabled then return nil end
    local uid = actor.uid
    if now < (H.nextVehicleMs[uid] or 0) then return nil end
    local row, geo = A.Vehicles.threat(shell, now)
    if row == nil or inRoom(shell) or riding(shell) then return nil end
    local stage, tiles, pace, line
    if geo.t <= (tonumber(s.diveS) or 1) and row.kmh >= (tonumber(s.diveKmh) or 25) then
        stage, tiles, pace, line = "dive", tonumber(s.diveTiles) or 4.5, "sprint", "vehicle_dive"
    elseif row.kmh >= (tonumber(s.slowKmh) or 12) then
        stage, tiles, pace, line = "dodge", tonumber(s.dodgeTiles) or 3, "sprint", "vehicle_dodge"
    else
        if geo.dist > (tonumber(s.courtesyTiles) or 5) or (type(state) == "table" and state.kind ~= "idle") then
            return nil
        end
        stage, tiles, pace, line = "step_aside", tonumber(s.courtesyStep) or 2, "walk", "vehicle_slow"
    end
    local sx, sy, sz = A.xyz(shell)
    if sx == nil then return nil end
    local options = { activity = "moving", pace = pace, timeoutMs = tonumber(s.timeoutMs) or 2500,
        cautionSkip = true, tolerance = 0.6 }
    local moved = move(helpers, actor, shell, { x = sx + geo.nx * tiles, y = sy + geo.ny * tiles, z = sz },
        "alr_" .. stage, options)
    if moved == nil then
        moved = move(helpers, actor, shell, { x = sx - geo.nx * tiles, y = sy - geo.ny * tiles, z = sz },
            "alr_" .. stage, options)
    end
    H.nextVehicleMs[uid] = now + (tonumber(s.cooldownMs) or 1500)
    if moved == nil then return nil end
    moved.reason = "alr_vehicle"
    if stage == "dive" then
        A.metrics.dives = A.metrics.dives + 1
        H.noteNearMiss(actor, row.vehicle, now)
    elseif stage == "dodge" then
        A.metrics.dodges = A.metrics.dodges + 1
    else
        A.metrics.courtesies = A.metrics.courtesies + 1
    end
    A.say(actor, shell, line, stage == "step_aside" and 15000 or 4000)
    if A.settings.debug then
        A.log("vehicle", stage, uid, string.format("t=%.1f d=%.1f kmh=%.0f", geo.t, geo.d, row.kmh))
    end
    return moved
end

-- Crowd ladder: run from a group walking at us, to an ally when there is one,
-- and tell the squad where the zombies are.
function H.crowd(actor, shell, state, now, helpers)
    local s = A.settings.crowd
    if type(s) ~= "table" or not s.enabled then return nil end
    local uid = actor.uid
    if now < (H.nextCrowdMs[uid] or 0) then return nil end
    H.nextCrowdMs[uid] = now + 500
    local a = ProjectALife
    if a.Combat ~= nil and type(a.Combat.leashFor) == "function" then
        local ok, leash = pcall(a.Combat.leashFor, actor)
        if ok and leash ~= nil then return nil end
    end
    local crowd = A.Crowd.scan(actor, shell, now)
    if crowd.count < (tonumber(s.fallbackCount) or 3) or crowd.closing < (tonumber(s.fallbackClosing) or 2) then
        return nil
    end
    local legs = H.legs[uid]
    if legs == nil or now - legs.sinceMs > 60000 then
        legs = { sinceMs = now, count = 0 }
        H.legs[uid] = legs
    end
    if legs.count >= (tonumber(s.legsPerMinute) or 3) then return nil end
    local ally = A.Crowd.ally(actor, shell, now, tonumber(s.regroupTiles) or 20)
    local target, kind = A.Crowd.fallbackPoint(shell, crowd, ally, tonumber(s.fallbackTiles) or 8)
    if target == nil then return nil end
    local moved = move(helpers, actor, shell, target, kind == "regroup" and "alr_regroup" or "alr_fallback",
        { activity = "moving", pace = "run", timeoutMs = tonumber(s.timeoutMs) or 4500, cautionSkip = true,
            threat = crowd.nearest, threatKind = "zombie" })
    if moved == nil and type(helpers) == "table" and type(helpers.startRetreat) == "function"
            and crowd.nearest ~= nil then
        local ok, retreat = pcall(helpers.startRetreat, actor, shell, crowd.nearest, "zombie", now, "alr_crowd")
        if ok then moved = retreat end
    end
    H.nextCrowdMs[uid] = now + (tonumber(s.cooldownMs) or 6000)
    if moved == nil then return nil end
    legs.count = legs.count + 1
    moved.reason = "alr_crowd"
    if kind == "regroup" then A.metrics.regroups = A.metrics.regroups + 1 else A.metrics.fallbacks = A.metrics.fallbacks + 1 end
    A.say(actor, shell, kind == "regroup" and "regroup" or "crowd", 6000)
    local tactics = a.SquadTactics
    if tactics ~= nil and type(tactics.reportThreat) == "function" and crowd.nearest ~= nil then
        pcall(tactics.reportThreat, actor, crowd.nearest, "zombie", now)
    end
    if A.settings.debug then A.log("crowd", kind, uid, crowd.count, crowd.closing) end
    return moved
end

function H.interrupt(actor, shell, state, now, helpers)
    if not A.settings.enabled or type(actor) ~= "table" or actor.uid == nil or shell == nil then return nil end
    if type(state) == "table" and not PASSIVE[state.kind] then return nil end
    if busy(actor, state) then return nil end
    A.noteShell(actor, shell)
    local ok, result = pcall(H.vehicle, actor, shell, state, now, helpers)
    if not ok then A.fail("vehicle hook", result) elseif result ~= nil then return result end
    ok, result = pcall(H.crowd, actor, shell, state, now, helpers)
    if not ok then A.fail("crowd hook", result) elseif result ~= nil then return result end
    return nil
end

function H.install(a)
    if H.installed then return true end
    local gunFear = a.ModuleGunFear
    if type(gunFear) ~= "table" or type(gunFear.interrupt) ~= "function" then
        A.log("hook skipped: ModuleGunFear.interrupt")
        return false
    end
    H.installed = true
    local decisions = a.DecisionLoop
    if type(decisions) == "table" and type(decisions.panicHolds) == "table" then
        for intent in pairs(H.intents) do decisions.panicHolds[intent] = true end
    end
    A.wrap(gunFear, "interrupt", function(original)
        return function(actor, shell, state, now, helpers)
            local fled = H.interrupt(actor, shell, state, now, helpers)
            if fled ~= nil then return fled end
            return original(actor, shell, state, now, helpers)
        end
    end, "ModuleGunFear.interrupt")
    return true
end

return H
