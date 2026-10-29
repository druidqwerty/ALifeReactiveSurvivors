-- A-Life: Reactive Survivors - wrappers around public Project A-Life
-- functions. Installed once at game start by ALR_Boot.

require "ALifeReactive/00_ALR_Core"
require "ALifeReactive/01_ALR_Settings"
require "ALifeReactive/02_ALR_Lines"
require "ALifeReactive/ALR_Crowd"

local A = ALifeReactive
local H = { installed = false }
A.Hooks = H

-- Is zombie `threat` worth leaving the route for? Within nearTiles (no sight
-- check: it is right there), or within closingTiles, walking at the NPC and
-- in sight. Same floor only.
function H.closingZombie(a, shell, threat)
    local s = A.settings.react
    local Combat, Perception = a.Combat, a.Perception
    if Combat == nil or Perception == nil or type(Combat.xyzOf) ~= "function" then
        return false, "no_api"
    end
    local sx, sy, sz = Combat.xyzOf(shell)
    local tx, ty, tz = Combat.xyzOf(threat)
    if sx == nil or tx == nil or sz == nil or tz == nil then return false, "no_position" end
    if math.abs(sz - tz) >= 0.4 then return false, "other_floor" end
    local flat = (sx - tx) * (sx - tx) + (sy - ty) * (sy - ty)
    local near = tonumber(s.nearTiles) or 0
    if flat <= near * near then return true, "near" end
    local closing = tonumber(s.closingTiles) or 0
    if flat > closing * closing then return false, "far" end
    local speed = 0
    if type(Perception.closingSpeed) == "function" then
        local ok, value = pcall(Perception.closingSpeed, shell, threat)
        if ok then speed = tonumber(value) or 0 end
    end
    if speed <= 0 then return false, "not_closing" end
    if s.needVisible and type(Perception.visible) == "function" then
        local ok, seen = pcall(Perception.visible, shell, threat)
        if not (ok and seen == true) then return false, "unseen" end
    end
    return true, "closing"
end

-- No weapon at all: A-Life shoves at contact; we do not send it in early.
local function unarmed(a, shell)
    local Combat = a.Combat
    if Combat == nil or type(Combat.weaponFor) ~= "function" or type(Combat.isUnarmed) ~= "function" then
        return false
    end
    local ok, weapon = pcall(Combat.weaponFor, shell)
    if not ok then return false end
    local okBare, bare = pcall(Combat.isUnarmed, weapon)
    return okBare and bare == true
end

-- Base verdict "bypass / continue_mission" for a closing zombie becomes
-- "commit". Kept as in the base: retreating / recovering NPCs, zombie-avoid
-- mode, the gun discipline (gun user without a melee weapon), unarmed NPCs,
-- and a crowd (gateCount zombies within the crowd radius).
function H.installEngagement(a)
    A.wrap(a.DecisionLoop, "engagement", function(original)
        return function(actor, shell, threat, threatKind, state, now)
            local choice, facts = original(actor, shell, threat, threatKind, state, now)
            if choice ~= "bypass" or threatKind ~= "zombie" or not A.settings.enabled
                    or not A.settings.react.enabled then
                return choice, facts
            end
            local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
            if memory == nil or memory.engagementReason ~= "continue_mission" then return choice, facts end
            if type(state) == "table" and (state.kind == "retreat" or state.kind == "recovering") then
                return choice, facts
            end
            A.noteShell(actor, shell)
            A.metrics.reactiveChecks = A.metrics.reactiveChecks + 1
            local ok, danger, why = pcall(H.closingZombie, a, shell, threat)
            if not ok then
                A.fail("closingZombie", danger)
                return choice, facts
            end
            if not danger then return choice, facts end
            if A.settings.react.unarmedSkip and unarmed(a, shell) then
                A.metrics.unarmedRefused = A.metrics.unarmedRefused + 1
                A.say(actor, shell, "unarmed", 15000)
                return choice, facts
            end
            local crowdSettings = A.settings.crowd
            if type(crowdSettings) == "table" and crowdSettings.enabled and A.Crowd ~= nil then
                local crowd = A.Crowd.scan(actor, shell, now)
                if crowd.count >= (tonumber(crowdSettings.gateCount) or 3) then
                    A.metrics.crowdRefused = A.metrics.crowdRefused + 1
                    return choice, facts
                end
            end
            local Caution = a.Caution
            if Caution ~= nil and type(Caution.zombieMode) == "function" then
                local okMode, mode = pcall(Caution.zombieMode, actor)
                if okMode and mode == "avoid" then
                    A.metrics.reactiveRefused = A.metrics.reactiveRefused + 1
                    return choice, facts
                end
            end
            local reason = "alr_" .. tostring(why)
            local Gun = a.GunDiscipline
            if Gun ~= nil and type(Gun.engagement) == "function" then
                local okGun, verdict = pcall(Gun.engagement, actor, shell, threat, facts, "commit", reason, now)
                if okGun and verdict == "bypass" then
                    A.metrics.reactiveRefused = A.metrics.reactiveRefused + 1
                    if type(Gun.noteAvoid) == "function" then pcall(Gun.noteAvoid, actor, now) end
                    return choice, facts
                end
            end
            A.metrics.reactiveCommits = A.metrics.reactiveCommits + 1
            memory.engagementDecision, memory.engagementReason = "commit", reason
            memory.alrReactAtMs = now
            A.say(actor, shell, "spot", A.settings.lines.spotCooldownMs)
            if A.settings.debug then A.log("commit", tostring(actor.uid), why) end
            return "commit", facts
        end
    end, "DecisionLoop.engagement")
end

-- Retreat lease: the base mod passes 25000 (9000 after a recovery) for every
-- target kind; cap it for zombies.
function H.installLease(a)
    A.wrap(a.Survival, "beginDisengage", function(original)
        return function(actor, shell, threat, now, durationMs)
            local cap = tonumber(A.settings.lease.zombieMs)
            if A.settings.enabled and cap ~= nil and A.isZombie(threat)
                    and (tonumber(durationMs) or 0) > cap then
                A.metrics.leaseCaps = A.metrics.leaseCaps + 1
                durationMs = cap
            end
            return original(actor, shell, threat, now, durationMs)
        end
    end, "Survival.beginDisengage")
end

-- Perception.ignore(uid, target, holdMs): nil holdMs means 15000 in the base.
function H.installIgnore(a)
    A.wrap(a.Perception, "ignore", function(original)
        return function(actorUid, target, holdMs)
            local cap = tonumber(A.settings.ignore.zombieCapMs)
            if A.settings.enabled and cap ~= nil and A.isZombie(target) then
                local hold = tonumber(holdMs) or 15000
                if hold > cap then
                    A.metrics.ignoreCaps = A.metrics.ignoreCaps + 1
                    holdMs = cap
                end
            end
            return original(actorUid, target, holdMs)
        end
    end, "Perception.ignore")
end

-- Draw sequence durations (Combat.startDraw and Animations.drawPresetFor both
-- read them through this function).
function H.installDraw(a)
    A.wrap(a.Animations, "drawSequenceFor", function(original)
        return function(shell, item)
            local reachPreset, reachMs, takePreset, takeMs = original(shell, item)
            local scale = tonumber(A.settings.draw.scale) or 1
            if A.settings.enabled and scale > 0 and scale < 1 then
                A.metrics.draws = A.metrics.draws + 1
                if tonumber(reachMs) ~= nil then reachMs = math.floor(reachMs * scale) end
                if tonumber(takeMs) ~= nil then takeMs = math.floor(takeMs * scale) end
            end
            return reachPreset, reachMs, takePreset, takeMs
        end
    end, "Animations.drawSequenceFor")
end

-- ZombieFocus.radius() reads the sandbox option (default 8); lift it.
function H.installFocus(a)
    A.wrap(a.ZombieFocus, "radius", function(original)
        return function(...)
            local radius = original(...)
            local minimum = tonumber(A.settings.focus.minRadius)
            if A.settings.enabled and minimum ~= nil and (tonumber(radius) or 0) < minimum then
                return minimum
            end
            return radius
        end
    end, "ZombieFocus.radius")
end

function H.install(a)
    if H.installed then return true end
    if type(a) ~= "table" or a.DecisionLoop == nil or a.Perception == nil or a.Combat == nil then
        return false
    end
    H.installed = true
    H.installEngagement(a)
    H.installLease(a)
    H.installIgnore(a)
    H.installDraw(a)
    H.installFocus(a)
    return true
end

return H
