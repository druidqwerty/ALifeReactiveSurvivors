-- TEST ONLY: isolated two-client server after Caravans joint test PASS.
assert(isServer(),"dedicated server only")
local P=ProjectALife
local T={phase="wait",samples={},results={}}
ALRAwareMPServer=T
local function log(s) T.samples[#T.samples+1]=s print("[ALR_AwareMPServer] "..s) end
local function finish(ok,why)
    T.done=true
    log("RESULT "..(ok and "PASS " or "FAIL ")..why)
    local w=getFileWriter("ALR_AwareMP_result.txt",true,false)
    w:writeln((ok and "PASS " or "FAIL ")..why)
    for _,s in ipairs(T.samples) do w:writeln(s) end
    w:close()
end
local function arena(player)
    local px,py=math.floor(player:getX()),math.floor(player:getY())
    for dx=-18,18,6 do for dy=-18,18,6 do
        local x,y,clear=px+dx,py+dy,true
        for ax=-6,6 do for ay=-6,6 do
            local sq=getCell():getGridSquare(x+ax,y+ay,0)
            if not sq or not sq:isFree(false) or not sq:TreatAsSolidFloor() or sq:getRoom() then clear=false break end
        end if not clear then break end end
        if clear then return x+0.5,y+0.5 end
    end end
end
Events.OnClientCommand.Add(function(module,command,player,args)
    if module~="ALRAwareMP" or T.done or args.uid~=T.uid then return end
    local ok,why=pcall(function()
        if command=="ready" and T.phase=="clients" then
            T.owner=player:getUsername()
            local actor=P.ActorRegistry.read(T.uid)
            assert(actor and actor.lifecycle=="active","actor unavailable")
            local list=addZombiesInOutfit(math.floor(args.x+5),math.floor(args.y),0,1,nil,50)
            assert(list and list:size()>0,"zombie spawn failed")
            T.z=list:get(0)
            T.x,T.y=args.x,args.y
            T.phase,T.at="spawn_threat",getTimestampMs()
        elseif command=="reaction" and player:getUsername()==T.owner then
            for _,peer in pairs(ALRLive.peers) do
                sendServerCommand(peer,"ALRAwareMP","reaction",{uid=T.uid,x=args.x,y=args.y})
            end
        elseif command=="result" then
            assert(args.ok,args.why)
            T.results[player:getUsername()]=args
            log(player:getUsername().." PASS "..args.why)
        end
    end)
    if not ok then finish(false,tostring(why)) end
end)
Events.OnTick.Add(function()
    if T.done then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<250 then return end
    T.tickAt=now
    local ok,why=pcall(function()
        if T.phase=="wait" then
            if not ((ALCJointServer and ALCJointServer.ok) or ALRLive.awarenessReady) then return end
            local player=ALRLive.peers.admin
            local x,y=arena(player)
            assert(x,"no loaded clear arena")
            local catalog=P.Catalog.current
            local profile
            for _,entry in ipairs(catalog.npcOrder or {}) do
                local row=type(entry)=="table" and entry or catalog.npcs[entry]
                if row and string.find(string.lower(row.general.faction),"milit",1,true) then profile=row break end
            end
            assert(profile,"militia fixture profile absent")
            local op="ALRMP"..now
            local actor,err
            if ALRLive.awarenessExistingUid then
                actor=P.ActorRegistry.read(ALRLive.awarenessExistingUid)
                assert(actor and actor.lifecycle=="active","existing fixture actor unavailable")
            else
            actor,err=P.ActorRegistry.create({operationId=op,fingerprint=op,profileId=profile.id,
                factionId=profile.general.faction,worldPosition={x=x,y=y,z=0},activity="idle",intent="scan",
                memory={debugSpawn=true,spawnStance="friendly",hostileOverride=false,behaviorProfile="seek_destroy",moduleOverrides={}}})
            assert(actor,err)
            local request,reason=P.SpawnService.request(actor.uid,op.."Spawn",op.."Spawn",10000)
            assert(request,reason)
            end
            T.uid,T.phase,T.at=actor.uid,"clients",now
            for _,peer in pairs(ALRLive.peers) do sendServerCommand(peer,"ALRAwareMP","watch",{uid=T.uid}) end
            log("SPAWN "..T.uid)
        elseif T.phase=="spawn_threat" then
            local id=T.z:getOnlineID()
            if not id or id<0 then return end
            T.zid=id
            for _,peer in pairs(ALRLive.peers) do
                sendServerCommand(peer,"ALRAwareMP","threat",{uid=T.uid,zid=id,x=T.x,y=T.y})
            end
            T.phase,T.at="watch",now
            log("OWNING CLIENT "..T.owner.." real zombie="..id)
        elseif T.phase=="watch" then
            if T.results.admin and T.results.observer then
                assert(T.results[T.owner].owner==true,"no owning-loop proof")
                finish(true,"natural owner-client make-space before contact, actual action movement and other-client replication")
            end
        end
        if T.at then assert(now-T.at<60000,"timeout "..T.phase) end
    end)
    if not ok then finish(false,tostring(why)) end
end)
log("installed")
