-- TEST ONLY: owner uses normal A-Life thinking, spectator verifies replication.
assert(isClient(),"real MP client only")
local A,P=ALifeReactive,ProjectALife
local T={phase="wait",samples={}}
ALRAwareMPClient=T
local original=A.Awareness.interrupt
local function log(s) T.samples[#T.samples+1]=s print("[ALR_AwareMPClient] "..s) end
local function finish(ok,why)
    T.done=true
    A.Awareness.interrupt=original
    log("RESULT "..(ok and "PASS " or "FAIL ")..why)
    sendClientCommand(getSpecificPlayer(0),"ALRAwareMP","result",{uid=T.uid,ok=ok,why=why,owner=T.owner==true})
    local w=getFileWriter("ALR_AwareMPClient_result.txt",true,false)
    w:writeln((ok and "PASS " or "FAIL ")..why)
    for _,s in ipairs(T.samples) do w:writeln(s) end
    w:close()
end
Events.OnServerCommand.Add(function(module,command,args)
    if module~="ALRAwareMP" or T.done then return end
    if command=="watch" then T.uid,T.phase,T.at=args.uid,"adopt",getTimestampMs()
    elseif command=="threat" then
        T.zid,T.x,T.y,T.phase,T.at=args.zid,args.x,args.y,"threat",getTimestampMs()
    elseif command=="reaction" and not T.owner then
        T.x,T.y,T.phase,T.at=args.x,args.y,"spectator",getTimestampMs()
    end
end)
local function body()
    local list=getCell():getZombieList()
    for i=0,list:size()-1 do
        local b=list:get(i)
        if not b:isDead() and b:getModData().ProjectALifeUID==T.uid then return b end
    end
end
A.Awareness.interrupt=function(actor,shell,state,now,helpers)
    local result=original(actor,shell,state,now,helpers)
    if T.owner and actor.uid==T.uid and result and T.phase=="react" then
        T.distance=ALifeCaravans.dist(shell:getX(),shell:getY(),T.z:getX(),T.z:getY())
        T.x,T.y=shell:getX(),shell:getY()
        T.action=result.action
        T.phase,T.at="moving",now
        sendClientCommand(getSpecificPlayer(0),"ALRAwareMP","reaction",{uid=T.uid,x=T.x,y=T.y})
        log("NATURAL intent="..tostring(result.intent).." distance="..T.distance.." action="..tostring(result.action and result.action.status))
    end
    return result
end
Events.OnTick.Add(function()
    if T.done or T.phase=="wait" then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<100 then return end
    T.tickAt=now
    local ok,why=pcall(function()
        assert(now-T.at<45000,"phase timeout "..T.phase)
        local shell=body()
        if not shell then return end
        if T.phase=="adopt" then
            local actor=P.ActorRegistry.read(T.uid)
            if not actor or actor.lifecycle~="active" or not P.Executor.authorityFor(shell) then return end
            T.owner=true
            local inv=shell:getInventory(); local items=inv:getItems()
            for i=items:size()-1,0,-1 do local item=items:get(i); if item:IsWeapon() then inv:Remove(item) end end
            shell:setPrimaryHandItem(nil); shell:setSecondaryHandItem(nil)
            P.Weapons.select(shell,nil); P.Animations.refreshWeapon(shell,false)
            assert(P.Combat.isUnarmed(P.Combat.weaponFor(shell)),"unarmed fixture failed")
            local s=P.DecisionLoop.stopForTalk(actor,shell,P.DecisionLoop.states[T.uid],now)
            s.intent="scan"; P.DecisionLoop.states[T.uid]=s
            sendClientCommand(getSpecificPlayer(0),"ALRAwareMP","ready",{uid=T.uid,x=shell:getX(),y=shell:getY()})
            T.phase,T.at="armed",now
        elseif T.phase=="threat" then
            if not T.owner then T.phase="wait_reaction"; return end
            local list=getCell():getZombieList()
            for i=0,list:size()-1 do if list:get(i):getOnlineID()==T.zid then T.z=list:get(i) break end end
            if not T.z then return end
            T.z:setTarget(shell); T.z:pathToCharacter(shell); shell:faceThisObject(T.z)
            local seen=false
            for _,row in ipairs(A.Crowd.rowsNear(P.Perception,now,shell:getX(),shell:getY(),6,65)) do
                if row.body==T.z then seen=true break end
            end
            if not seen or P.Perception.visible(shell,T.z)~=true then return end
            -- Network spawn takes time; establish the fixture's initial idle
            -- state once when the actual threat has reached this client.
            local actor=P.ActorRegistry.read(T.uid)
            local state=P.DecisionLoop.stopForTalk(actor,shell,P.DecisionLoop.states[T.uid],now)
            state.intent="scan"; P.DecisionLoop.states[T.uid]=state
            T.z:setTarget(shell); T.z:pathToCharacter(shell); shell:faceThisObject(T.z)
            T.phase,T.at="react",now
        elseif T.phase=="moving" then
            assert(P.Executor.authorityFor(shell),"owner changed during focused test")
            assert(T.distance>2.5,"reaction only at contact")
            local s=P.DecisionLoop.states[T.uid]
            local distance=ALifeCaravans.dist(T.x,T.y,shell:getX(),shell:getY())
            if now-(T.sampleAt or 0)>=200 then
                T.sampleAt=now
                log("MOVE distance="..distance.." intent="..tostring(s and s.intent).." status="..tostring(s and s.action and s.action.status)
                    .." originalAction="..tostring(T.action and T.action.status))
            end
            if distance>=1 then
                local action=T.action
                local completed=action and action.status=="complete" and action.result=="predicate_satisfied"
                    and action.finishedAtMs and now-action.finishedAtMs<=200 and action.target
                    and ALifeCaravans.dist(shell:getX(),shell:getY(),action.target.x,action.target.y)<=0.35
                assert((s and s.intent=="alr_make_space" and s.action==action and action.status=="running") or completed,
                    "not actual make-space movement: intent="..tostring(s and s.intent).." status="..tostring(s and s.action and s.action.status)
                    .." original="..tostring(T.action and T.action.status))
                finish(true,"owner natural reaction at "..T.distance.." tiles; actual make-space movement="..distance.." action="..action.status)
            end
        elseif T.phase=="spectator" then
            local distance=ALifeCaravans.dist(T.x,T.y,shell:getX(),shell:getY())
            if distance>=0.8 then finish(true,"spectator saw original actor move "..distance.." tiles") end
        end
    end)
    if not ok then finish(false,tostring(why)) end
end)
log("installed")
