-- A-Life: Reactive Survivors - number tuning through the public tables of
-- Project A-Life. Two layers: the defaults the base mod copies from at
-- configure time (BehaviorSettings) and the live tables it copies into
-- (Combat.settings, Endurance.settings, ...). Decisions.configure rebuilds
-- the live tables from defaults + sandbox adapters, so it is wrapped to
-- re-apply the live layer afterwards.

require "ALifeReactive/00_ALR_Core"

local A = ALifeReactive
local T = { configureHooked = false }
A.Tuning = T

local function copyInto(target, values, prefix)
    if type(target) ~= "table" or type(values) ~= "table" then return 0 end
    local count = 0
    for key, value in pairs(values) do
        if A.set(target, key, value, prefix .. key) then count = count + 1 end
    end
    return count
end

-- Layer 1: defaults (survive Decisions.configure on their own).
function T.applyDefaults(a)
    local s = A.settings
    local behavior = a.BehaviorSettings
    if type(behavior) ~= "table" then return false end
    copyInto(behavior.combat, s.combat, "BehaviorSettings.combat.")
    copyInto(behavior.endurance, s.endurance, "BehaviorSettings.endurance.")
    return true
end

-- Layer 2: live tables.
function T.applyLive(a)
    local s = A.settings
    local Combat = a.Combat
    if Combat ~= nil then
        copyInto(Combat.settings, s.combat, "Combat.settings.")
        if type(Combat.MELEE_TIMING) == "table" then
            for class, delay in pairs(s.meleeDelayMs) do
                local timing = Combat.MELEE_TIMING[class]
                if type(timing) == "table" then
                    A.set(timing, "delayMs", delay, "Combat.MELEE_TIMING." .. class .. ".delayMs")
                end
            end
        end
    end
    local Endurance = a.Endurance
    if Endurance ~= nil then copyInto(Endurance.settings, s.endurance, "Endurance.settings.") end
    local Survival = a.Survival
    if Survival ~= nil and tonumber(s.survival.flinchHealth) ~= nil then
        local floor = tonumber(Survival.retreatHealth) or 0.35
        A.set(Survival, "flinchHealth", math.max(floor, s.survival.flinchHealth), "Survival.flinchHealth")
    end
    local Decisions = a.DecisionLoop
    if Decisions ~= nil then copyInto(Decisions.lanes, s.lanes, "DecisionLoop.lanes.") end
    local Focus = a.ZombieFocus
    if Focus ~= nil then
        A.set(Focus, "ignoreMs", s.focus.ignoreMs, "ZombieFocus.ignoreMs")
        A.set(Focus, "closingRadius", s.focus.closingRadius, "ZombieFocus.closingRadius")
    end
    -- Jeem Extension runs its own ZombieFocus filter in front of A-Life's
    -- (wraps Perception.findThreat); give it the same numbers.
    local Jeem = ProjectALifeJimmy
    if type(Jeem) == "table" and type(Jeem.ZombieFocus) == "table" then
        A.set(Jeem.ZombieFocus, "ignoreMs", s.focus.ignoreMs, "Jeem.ZombieFocus.ignoreMs")
        A.set(Jeem.ZombieFocus, "closingRadius", s.focus.closingRadius, "Jeem.ZombieFocus.closingRadius")
    end
    local Fear = a.ModuleFear
    if Fear ~= nil then copyInto(Fear.settings, s.fear, "ModuleFear.settings.") end
    local Caution = a.Caution
    if Caution ~= nil then copyInto(Caution.settings, s.caution, "Caution.settings.") end
    local Gun = a.GunDiscipline
    if Gun ~= nil then A.set(Gun, "rollMs", s.gun.rollMs, "GunDiscipline.rollMs") end
    return true
end

function T.apply(a)
    local okDefaults, errDefaults = pcall(T.applyDefaults, a)
    local okLive, errLive = pcall(T.applyLive, a)
    if not okDefaults then
        A.metrics.errors = A.metrics.errors + 1
        A.log("tuning defaults failed:", errDefaults)
    end
    if not okLive then
        A.metrics.errors = A.metrics.errors + 1
        A.log("tuning live failed:", errLive)
    end
    return okDefaults and okLive
end

-- Decisions.configure runs in Runtime.start (SP / server) and Executor.start
-- (MP owner client); it rebuilds Combat.settings, Endurance.settings and the
-- Survival thresholds. Re-apply the live layer after it.
function T.hookConfigure(a)
    if T.configureHooked then return true end
    T.configureHooked = A.wrap(a.DecisionLoop, "configure", function(original)
        return function(...)
            original(...)
            A.metrics.configures = A.metrics.configures + 1
            T.apply(a)
            A.log("tuning re-applied after Decisions.configure")
        end
    end, "DecisionLoop.configure")
    return T.configureHooked
end

return T
