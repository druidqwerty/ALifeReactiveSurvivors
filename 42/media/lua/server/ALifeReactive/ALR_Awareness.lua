-- Early decisions for idle NPCs, before the focus filter waits for contact.
-- Invoked only by A-Life's owning decision loop; no independent actor tick.
require "ALifeReactive/ALR_Retreat"
require "ALifeReactive/ALR_ActionHandoff"
local A = ALifeReactive
local W = { nextAt={}, window=-1, rays=0 }
A.Awareness = W

local function available(actor, shell, state, now)
    if not A.settings.enabled or not A.settings.react.enabled then return false end
    if not actor or not actor.uid or not state or (state.kind~="idle" and state.kind~="recovering") then return false end
    if actor.lifecycle and actor.lifecycle~="active" then return false end
    local m=actor.memory or {}
    if m.robbery or m.orderedTo or m.holdPost or (tonumber(m.talkHoldUntilMs) or 0)>now then return false end
    local intent=tostring(state.intent or "")
    if intent=="talk_hold" or intent=="robbery_pending" or intent=="standoff_pending"
        or intent=="idle_stand_up" or string.sub(intent,1,6)=="panic_" then return false end
    local p=ProjectALife
    if p.DecisionLoop.panicHolds and p.DecisionLoop.panicHolds[intent] then return false end
    if type(shell.isDead)=="function" and shell:isDead() then return false end
    if type(shell.getVehicle)=="function" and shell:getVehicle() then return false end
    if p.VehicleRules and p.VehicleRules.riding and p.VehicleRules.riding(shell) then return false end
    if p.Combat.leashFor and p.Combat.leashFor(actor) then return false end
    if p.Animations and p.Animations.blocksLocomotion and p.Animations.blocksLocomotion(shell) then return false end
    return true
end

function W.nearest(shell, now)
    local p=ProjectALife.Perception
    local x,y,z=A.xyz(shell)
    if not x or not p or not p.snapshotFor or not p.visible then return nil end
    if now<W.window or now-W.window>=250 then W.window,W.rays=now,0 end
    if W.rays>=32 then return nil end
    local radius=tonumber(A.settings.react.closingTiles) or 6
    local rows=A.Crowd.rowsNear(p,now,x,y,radius,65)
    local sorted={}
    for _,row in ipairs(rows) do
        local body=row.body
        if body and math.abs((row.z or z)-z)<0.4 and type(body.isDead)=="function" and not body:isDead() then
            local data=type(body.getModData)=="function" and body:getModData()
            if not (data and data.ProjectALifeOwned) then
                sorted[#sorted+1]={body=body,d2=(row.x-x)^2+(row.y-y)^2}
            end
        end
    end
    table.sort(sorted,function(a,b) return a.d2<b.d2 end)
    for i=1,math.min(12,#sorted) do
        if W.rays>=32 then return nil end
        W.rays=W.rays+1
        local row=sorted[i]
        if p.visible(shell,row.body)==true then
            local closing=p.closingSpeed and (tonumber(p.closingSpeed(shell,row.body)) or 0)>0
            local targeted=type(row.body.getTarget)=="function" and row.body:getTarget()==shell
            if closing or targeted or row.d2<=(tonumber(A.settings.react.nearTiles) or 2.5)^2 then
                return row.body
            end
        end
    end
    return nil
end

function W.interrupt(actor,shell,state,now,helpers)
    if not available(actor,shell,state,now) or now<(W.nextAt[actor.uid] or 0) then return nil end
    W.nextAt[actor.uid]=now+400
    local threat=W.nearest(shell,now)
    if not threat then return nil end
    local p=ProjectALife
    local choice=p.DecisionLoop.engagement(actor,shell,threat,"zombie",state,now)
    -- A-Life still owns weapons, endurance, gun discipline and target legality.
    local civilian=p.DecisionLoop.noncombat and p.DecisionLoop.noncombat(actor)
    if not civilian and state.kind~="recovering" and (choice=="commit" or choice=="defend")
        and p.DecisionLoop.startCombat and p.Combat.canEngage
        and p.Combat.canEngage(actor,threat,now,shell) then
        A.ActionHandoff.cancelOld(actor,state)
        local nextState=p.DecisionLoop.startCombat(actor,shell,threat,"zombie","alr_alert")
        if nextState then
            A.metrics.alerts=A.metrics.alerts+1
            W.nextAt[actor.uid]=now+1500
            return nextState
        end
    end
    -- Avoid/unarmed/tired is a reason to make space, not to freeze until bitten.
    if not A.settings.crowd.enabled or not helpers or not helpers.startMovement then return nil end
    local tx,ty=A.xyz(threat)
    local crowd=A.Crowd.scan(actor,shell,now)
    if crowd.count==0 then crowd={count=1,cx=tx,cy=ty,nearest=threat} end
    local target=A.Retreat.choose(actor,shell,crowd,nil,now,3)
    if not target then return nil end
    local nextState=helpers.startMovement(actor,shell,target,"alr_make_space",{
        activity="moving",pace="walk",timeoutMs=3500,tolerance=0.3,cautionSkip=true,threat=threat,threatKind="zombie"})
    if nextState then
        A.metrics.spaceMoves=A.metrics.spaceMoves+1
        W.nextAt[actor.uid]=now+math.max(2000,A.settings.crowd.cooldownMs or 6000)
        A.say(actor,shell,"make_space",15000)
    end
    return nextState
end

return W
