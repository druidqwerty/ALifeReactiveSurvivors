-- A-Life: Reactive Survivors - reactions to things that already happened:
-- a zombie got hold of the NPC, a vehicle hit it. The line comes a moment
-- later (A-Life's own pain bark goes first, and a freshly hit NPC is quiet
-- for a second anyway).

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/02_ALR_Lines"

local A = ALifeReactive
local R = { installed = false, pending = {}, delayMs = 1800 }
A.Reactions = R

function R.later(actor, shell, situation, cooldownMs, delayMs)
    R.pending[#R.pending + 1] = { atMs = A.now() + (tonumber(delayMs) or R.delayMs), actor = actor, shell = shell,
        situation = situation, cooldownMs = cooldownMs }
end

function R.flush(now)
    if #R.pending == 0 then return 0 end
    local keep, said = {}, 0
    for _, item in ipairs(R.pending) do
        if now >= item.atMs then
            local ok, shown = pcall(A.say, item.actor, item.shell, item.situation, item.cooldownMs)
            if ok and shown == true then said = said + 1 end
        else
            keep[#keep + 1] = item
        end
    end
    R.pending = keep
    return said
end

local function remember(memory, field, key, now)
    local mark = memory[field]
    if type(mark) ~= "table" or mark.key ~= key or now - (tonumber(mark.atMs) or 0) > 120000 then
        mark = { key = key, count = 0 }
    end
    mark.count, mark.atMs = mark.count + 1, now
    memory[field] = mark
    return mark.count
end

-- Perception.noteAttacker(victimUid, attacker, holdMs, kind): a zombie got
-- its teeth in.
function R.installBite(a)
    A.wrap(a.Perception, "noteAttacker", function(original)
        return function(victimUid, attacker, holdMs, kind)
            local result = original(victimUid, attacker, holdMs, kind)
            if A.settings.enabled and type(victimUid) == "string" and (kind == "zombie" or A.isZombie(attacker)) then
                local ok, err = pcall(function()
                    local registry = a.ActorRegistry
                    local actor = registry ~= nil and type(registry.read) == "function" and registry.read(victimUid) or nil
                    local shell = A.shellFor(victimUid)
                    if type(actor) ~= "table" or shell == nil then return end
                    A.metrics.bites = A.metrics.bites + 1
                    R.later(actor, shell, "bitten", 5000, 1500)
                end)
                if not ok then A.fail("bite reaction", err) end
            end
            return result
        end
    end, "Perception.noteAttacker")
end

-- VehicleRules.strike(shell, vehicle, speedKmh, now): hit by a vehicle. A
-- player who does it twice within two minutes hears about it.
function R.installVehicleHit(a)
    A.wrap(a.VehicleRules, "strike", function(original)
        return function(shell, vehicle, speedKmh, now)
            local struck = original(shell, vehicle, speedKmh, now)
            if struck == true and A.settings.enabled then
                local ok, err = pcall(function()
                    local perception = a.Perception
                    local actor = perception ~= nil and type(perception.activeActorForShell) == "function"
                        and perception.activeActorForShell(shell) or nil
                    if type(actor) ~= "table" then return end
                    A.metrics.hits = A.metrics.hits + 1
                    local situation = "vehicle_hit"
                    local driver = type(vehicle.getDriver) == "function" and vehicle:getDriver() or nil
                    if driver ~= nil and A.isPlayer(driver) and type(actor.memory) == "table" then
                        local count = remember(actor.memory, "alrHitBy", tostring(driver:getUsername()),
                            tonumber(now) or A.now())
                        if count >= 2 then situation = "vehicle_hit_again" end
                    end
                    R.later(actor, shell, situation, 3000, R.delayMs)
                end)
                if not ok then A.fail("vehicle hit reaction", err) end
            end
            return struck
        end
    end, "VehicleRules.strike")
end

function R.install(a)
    if R.installed then return true end
    R.installed = true
    if a.Perception ~= nil then R.installBite(a) end
    if a.VehicleRules ~= nil then R.installVehicleHit(a) end
    return true
end

return R
