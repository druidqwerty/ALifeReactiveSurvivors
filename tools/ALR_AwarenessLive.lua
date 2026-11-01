-- TEST ONLY, inject in an isolated SP world. Observe natural owning-loop calls.
assert(not isClient() and not isServer(),"SP observer only")
local A,P=ALifeReactive,ProjectALife
local player=getSpecificPlayer(0)
assert(A and A.Awareness and P and P.Runtime.started,"world not ready")
assert(not ALRLive.awareness,"observer already installed")
local T={phase="prepare",at=getTimestampMs(),samples={},case="armed"}
ALRLive.awareness=T
local original=A.Awareness.interrupt
local function log(s) print("[ALR_AwareLive] "..s) T.samples[#T.samples+1]=s end
local function finish(ok,why)
    T.done=true
    log("RESULT "..(ok and "PASS " or "FAIL ")..why)
    A.Awareness.interrupt=original
    local w=getFileWriter("ALR_AwareLive_result.txt",true,false)
    for _,s in ipairs(T.samples) do w:writeln(s) end
    w:close()
end
A.Awareness.interrupt=function(actor,shell,state,now,helpers)
    local before={x=shell:getX(),y=shell:getY()}
    local result=original(actor,shell,state,now,helpers)
    if actor.uid==T.uid and result and T.phase=="react" then
        T.reaction=result.kind
        T.intent=result.intent
        T.action=result.action
        T.origin=before
        T.distance=ALifeCaravans.dist(shell:getX(),shell:getY(),T.zombie:getX(),T.zombie:getY())
        T.phase,T.at="moving",now
        log("NATURAL "..T.case.." state="..result.kind.." intent="..tostring(result.intent).." threatDistance="..T.distance)
    end
    return result
end
local function free(x,y)
    local sq=getCell():getGridSquare(x,y,0)
    return sq and sq:isFree(false) and sq:TreatAsSolidFloor() and not sq:getRoom()
end
local function arena()
    local px,py=math.floor(player:getX()),math.floor(player:getY())
    for dx=-18,18,6 do
        for dy=-18,18,6 do
            local x,y,clear=px+dx,py+dy,true
            for ax=-6,6 do
                for ay=-6,6 do if not free(x+ax,y+ay) then clear=false break end end
                if not clear then break end
            end
            if clear then return x+0.5,y+0.5 end
        end
    end
end
local function profile()
    local c=P.Catalog.current
    local fallback
    for _,entry in ipairs(c.npcOrder or {}) do
        local row=type(entry)=="table" and entry or c.npcs[entry]
        local faction=row and P.Catalog.faction(row.general.faction)
        if faction and not (faction.spawn and faction.spawn.visitorOnly) then
            fallback=fallback or row
            if string.find(string.lower(row.general.faction),"milit",1,true) then return row end
        end
    end
    return fallback
end
local function prepare(now)
    local x,y=arena()
    assert(x,"no clear loaded 13x13 arena")
    local entry=assert(profile(),"no NPC profile")
    local op="ALRAwareness"..T.case..now
    local actor,why=P.ActorRegistry.create({operationId=op,fingerprint=op,profileId=entry.id,
        factionId=entry.general.faction,worldPosition={x=x,y=y,z=0},activity="idle",intent="scan",
        memory={debugSpawn=true,spawnStance="friendly",hostileOverride=false,behaviorProfile="seek_destroy",
            moduleOverrides={}}})
    assert(actor,why)
    local request,err=P.SpawnService.request(actor.uid,op.."Spawn",op.."Spawn",5000)
    assert(request,err)
    T.uid,T.shell,T.phase,T.at=actor.uid,request.shell,"spawned",now
    log("SPAWN "..T.case.." uid="..T.uid.." profile="..entry.id)
end
local function armScene(now)
    local actor=P.ActorRegistry.read(T.uid)
    if not actor or actor.lifecycle~="active" then return end
    local shell=T.shell
    -- Keep A-Life's scaled health. Setting 2 on a healthy NPC is an injury,
    -- and Jeem can attribute it to the nearby player and start a radio response.
    -- A-Life selects from the inventory, not IsoZombie's hand slot. Strip
    -- weapons only from this newly-created fixture actor, then use its API.
    local inventory=shell:getInventory()
    local items=inventory:getItems()
    for i=items:size()-1,0,-1 do
        local item=items:get(i)
        if item:IsWeapon() then inventory:Remove(item) end
    end
    shell:setPrimaryHandItem(nil)
    shell:setSecondaryHandItem(nil)
    if T.case=="armed" then
        local bat=inventory:AddItem("Base.BaseballBat")
        assert(bat and P.Weapons.select(shell,bat,"melee"),"melee fixture loadout failed")
        P.Animations.refreshWeapon(shell,true)
        assert(P.Combat.weaponFor(shell)==bat,"fixture is not actually using the bat")
    else
        P.Weapons.select(shell,nil)
        P.Animations.refreshWeapon(shell,false)
        assert(P.Combat.isUnarmed(P.Combat.weaponFor(shell)),"fixture is not actually unarmed")
    end
    local initial=P.DecisionLoop.stopForTalk(actor,shell,P.DecisionLoop.states[T.uid],now)
    initial.intent="scan"
    P.DecisionLoop.states[T.uid]=initial
    local list=addZombiesInOutfit(math.floor(shell:getX()+5),math.floor(shell:getY()),0,1,nil,50)
    assert(list and list:size()>0,"real threat spawn failed")
    T.zombie=list:get(0)
    T.zombie:setTarget(shell)
    T.zombie:pathToCharacter(shell)
    shell:faceThisObject(T.zombie)
    T.phase,T.at="react",now
    log("SCENE "..T.case.." weapon="..tostring(P.Combat.weaponFor(shell)))
end
Events.OnTick.Add(function()
    if T.done then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<100 then return end
    T.tickAt=now
    local ok,err=pcall(function()
        if T.phase=="prepare" then prepare(now)
        elseif T.phase=="spawned" then
            armScene(now)
            assert(now-T.at<15000,"spawn readiness timeout")
        elseif T.phase=="react" then
            assert(now-T.at<12000,"natural early reaction missing; state="..tostring(P.DecisionLoop.states[T.uid] and P.DecisionLoop.states[T.uid].intent))
        elseif T.phase=="moving" then
            assert(T.distance>2.5,"response happened only at melee contact")
            local distance=ALifeCaravans.dist(T.shell:getX(),T.shell:getY(),T.origin.x,T.origin.y)
            if now-(T.sampleAt or 0)>500 then
                T.sampleAt=now
                local s=P.DecisionLoop.states[T.uid]
                log("MOVE "..T.case.." distance="..distance.." intent="..tostring(s and s.intent)
                    .." action="..tostring(s and s.action and s.action.status))
            end
            if distance>=1 then
                local current=P.DecisionLoop.states[T.uid]
                if T.case=="armed" then assert(T.reaction=="combat","armed NPC did not engage")
                else
                    local action=T.action
                    local completed=action and action.status=="complete" and action.result=="predicate_satisfied"
                        and action.finishedAtMs and now-action.finishedAtMs<=200 and action.target
                        and ALifeCaravans.dist(T.shell:getX(),T.shell:getY(),action.target.x,action.target.y)<=0.35
                    assert(T.intent=="alr_make_space" and ((current and current.intent==T.intent
                        and current.action==action and action.status=="running") or completed),
                        "movement was not the actual make-space action")
                end
                log("MOVE PASS "..T.case.." displacement="..distance.." elapsed="..(now-T.at))
                if not T.zombie:isDead() then T.zombie:Kill(nil) end
                T.zombie=nil
                if T.case=="unarmed" then return finish(true,"natural early engagement and unarmed safe movement before contact") end
                T.case,T.phase,T.at="unarmed","cooldown",now
            end
            assert(now-T.at<12000,"real movement timeout")
        elseif T.phase=="cooldown" and now-T.at>4000 then
            if T.shell and not T.shell:isDead() then T.shell:Kill(nil) end
            T.shell,T.uid=nil,nil
            T.phase="prepare"
        end
    end)
    if not ok then
        if T.zombie and not T.zombie:isDead() then T.zombie:Kill(nil) end
        finish(false,tostring(err))
    end
end)
log("START version="..A.VERSION)
