-- Behavioral scenarios for safe local retreat; no running game assumed.
local ROOT = MOD_ROOT .. "/42/media/lua/"
local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    local file = assert(loadfile(ROOT .. "shared/" .. name .. ".lua") or loadfile(ROOT .. "server/" .. name .. ".lua"))
    loaded[name] = file() or true
    return loaded[name]
end
local passed, failed = 0, 0
local function check(name, result)
    if result then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name) end
end
local CLOCK = 100000
function getTimestampMs() return CLOCK end
local world, zombies, moves, retreats, baseCalls
local origin = {x=100.5, y=100.5, z=0}
local function square(x, y)
    if world.unloaded and world.unloaded(x,y) then return nil end
    return {getBuilding=function() return world.building and world.building(x,y) or nil end,
        TreatAsSolidFloor=function() return not (world.hole and world.hole(x,y)) end,
        hazard=world.hazard and world.hazard(x,y) or nil}
end
function getCell() return {getGridSquare=function(_,x,y,z) return square(x,y) end} end
local shell = {getX=function() return origin.x end, getY=function() return origin.y end,
    getZ=function() return origin.z end}
local actor = {uid="retreat-test", generation=1, memory={}}
local P = {
    FireManeuver={route=function(_,from,to) return not world.blocked or not world.blocked(from,to) end},
    Caution={squareHazard=function(sq) return sq.hazard end},
    Perception={snapshotFor=function() return {bodies=zombies, actors={}} end,
        closingSpeed=function() return 1 end, visible=function(_,body) return body.seen ~= false end},
    Relations={}, Combat={leashFor=function() return nil end},
    DecisionLoop={panicHolds={}},
    ModuleGunFear={interrupt=function() baseCalls=baseCalls+1; return "base-decision" end},
}
ProjectALife=P
require "ALifeReactive/01_ALR_Settings"
require "ALifeReactive/ALR_Hazards"
local A=ALifeReactive
A.settings.vehicle.enabled=false
A.settings.crowd.safeRetreat=true
A.Hazards.install(P)
local helpers={startMovement=function(_,_,target,intent)
    if world.refuseMove then return nil end
    moves[#moves+1]=target
    return {kind="movement",intent=intent}
end, startRetreat=function() retreats=retreats+1; return {} end}
local function zombie(x,y,seen,dead,z)
    return {x=x,y=y,z=z or 0,body={seen=seen,isDead=function() return dead==true end}}
end
local function reset()
    CLOCK=CLOCK+1000
    world,zombies,moves,retreats,baseCalls={},{},{},0,0
    A.Hazards.nextCrowdMs,A.Hazards.legs={},{}
    actor.memory={}
    zombies={zombie(104,100),zombie(105,101),zombie(105,99)}
end
local function choose(ally)
    return A.Retreat.choose(actor,shell,A.Crowd.scan(actor,shell,CLOCK),ally,CLOCK)
end
local function interrupt(state)
    return P.ModuleGunFear.interrupt(actor,shell,state or {kind="idle"},CLOCK,helpers)
end

reset()
local target=choose()
check("open field escapes east-side threat to west",target and target.x<origin.x-2)
check("target remains on same floor",target and target.z==origin.z)
check("distance is bounded",target and (target.x-origin.x)^2+(target.y-origin.y)^2<=64.01)

reset()
zombies[#zombies+1]=zombie(94,100)
zombies[#zombies+1]=zombie(94,102)
zombies[#zombies+1]=zombie(93,99)
target=choose()
check("second crowd outside trigger radius changes escape direction",target and math.abs(target.y-origin.y)>2)

reset(); world.blocked=function(_,to) return to.x<origin.x-1 end
target=choose()
check("obstructed west route chooses another exit",target and target.x>=origin.x-1)

reset(); world.hazard=function(x,y) if x<100 then return "fire" end end
target=choose()
check("fire on escape corridor is avoided",target and target.x>=100)

reset(); world.hazard=function(x,y) if x<100 then return "campfire" end end
target=choose()
check("lit campfire on escape corridor is avoided",target and target.x>=100)

reset(); world.hazard=function(x,y) if x<100 then return "water" end end
target=choose()
check("water is avoided",target and target.x>=100)

reset(); world.unloaded=function(x,y) return x<100 end
target=choose()
check("unloaded squares are not presumed safe",target and target.x>=100)

reset(); world.hole=function(x,y) return x<100 end
target=choose()
check("missing floor is avoided",target and target.x>=100)

reset(); local otherBuilding={}
world.building=function(x,y) if x<100 then return otherBuilding end end
target=choose()
check("no unvalidated building-entry retarget",target and target.x>=100)

reset(); world.blocked=function() return true end
local result=interrupt()
check("no safe path preserves original hook",result=="base-decision" and baseCalls==1)
check("no safe path cannot invoke geometric fallback",#moves==0 and retreats==0)

reset(); world.refuseMove=true
result=interrupt()
check("movement refusal cannot invoke geometric fallback",result=="base-decision" and retreats==0)

reset(); result=interrupt()
check("default safe planner reaches real movement integration",type(result)=="table" and #moves==1)
check("subsequent own movement not interrupted",interrupt(result)=="base-decision")

reset(); actor.memory.holdPost=true
check("guard order unchanged",interrupt()=="base-decision" and #moves==0)
reset(); actor.memory.orderedTo={x=1}
check("explicit order unchanged",interrupt()=="base-decision" and #moves==0)
reset(); check("combat policy unchanged",interrupt({kind="combat"})=="base-decision" and #moves==0)

reset(); local saved=P.FireManeuver.route; P.FireManeuver.route=nil
check("missing dependency fails closed",choose()==nil)
P.FireManeuver.route=saved
reset(); saved=P.FireManeuver.route; P.FireManeuver.route=function() error("changed API") end
check("changed API cannot crash planner",choose()==nil)
P.FireManeuver.route=saved

reset(); local initial=choose()
zombies[#zombies+1]=zombie(93,100,false)
A.Retreat.windowMs=-1
target=choose()
check("unseen distant zombie is not omniscient knowledge",target and initial and target.x==initial.x and target.y==initial.y)
zombies[#zombies].body.seen=true
A.Retreat.windowMs=-1
target=choose()
check("visible distant threat influences destination",target and (target.x~=initial.x or target.y~=initial.y))

reset(); local rows={zombie(101.3,100.5)}
local pressure,nearest=A.RetreatSafety.pressure(origin,rows)
check("can escape already-touching zombie outward",A.RetreatSafety.rank(origin,{x=96.5,y=100.5},rows,pressure,nearest)~=nil)
check("cannot run through already-touching zombie",A.RetreatSafety.rank(origin,{x=104.5,y=100.5},rows,pressure,nearest)==nil)

reset(); for i=1,129 do zombies[i]=zombie(104,100) end
check("dense scene does not use truncated threat picture",choose()==nil)
reset(); choose(); choose(); choose(); choose()
local _,reason=choose()
check("global search budget bounded across actors",reason=="budget")
reset(); for i=1,17 do zombies[#zombies+1]=zombie(107+i*0.01,100,false) end
check("visibility budget exhaustion never uses partial threat picture",choose()==nil)
reset(); world.hazard=function(x,y) if x==101 and y==100 then return "campfire" end end
check("diagonal cannot skip a hazardous side tile",not A.RetreatSafety.route(shell,
    {x=100.9,y=100.85,z=0},{x=104.9,y=104.85,z=0}))
reset(); world.hole=function(x,y) return x==101 and y==100 end
check("diagonal cannot skip a side floor hole",not A.RetreatSafety.route(shell,
    {x=100.9,y=100.85,z=0},{x=104.9,y=104.85,z=0}))
check("no logged runtime errors",A.metrics.errors==0)
print("RESULT retreat passed="..passed.." failed="..failed)
return failed
