local loaded={}
function require(name)
    if loaded[name] then return loaded[name] end
    local root=MOD_ROOT.."/42/media/lua/"
    local chunk=assert(loadfile(root.."shared/"..name..".lua") or loadfile(root.."server/"..name..".lua"))
    loaded[name]=chunk() or true
    return loaded[name]
end
local now=100000
function getTimestampMs() return now end
function isServer() return false end
function isClient() return false end
function instanceof(o,c) return o and o.class==c end
function getText(k) return TRANSLATIONS[k] or k end
local function body(x,y,z)
    local b={x=x,y=y,z=z or 0,class="IsoZombie",data={}}
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getZ() return self.z end
    function b:isDead() return self.dead==true end
    function b:getModData() return self.data end
    function b:getVehicle() return self.vehicle end
    function b:getTarget() return self.target end
    return b
end
local shell,enemy=body(100,100),body(105,100)
local actor={uid="aware",lifecycle="active",generation=1,memory={}}
local choice,reason,allowed,bare,mode,leash,noncombat="bypass","continue_mission",true,false,"default",nil,false
local rows,combatCalls,moves,fear={},0,0,nil
ProjectALife={}
local P=ProjectALife
P.Perception={snapshotFor=function() return {bodies=rows} end,
    visible=function(_,b) return b.visible~=false end,closingSpeed=function(_,b) return b.closing or 0 end}
P.Combat={xyzOf=function(b) return b.x,b.y,b.z end,leashFor=function() return leash end,
    weaponFor=function() return {} end,isUnarmed=function() return bare end,
    canEngage=function() return allowed end}
P.DecisionLoop={panicHolds={},noncombat=function() return noncombat end,
    engagement=function(a) a.memory.engagementReason=reason return choice,{} end,
    startCombat=function() combatCalls=combatCalls+1 return {kind="combat"} end}
P.Caution={zombieMode=function() return mode end}
P.ModuleGunFear={interrupt=function() return fear end}
P.VehicleRules={riding=function() return shell.vehicle end}
require "ALifeReactive/01_ALR_Settings"
require "ALifeReactive/ALR_Hooks"
require "ALifeReactive/ALR_Hazards"
local A=ALifeReactive
A.Hooks.installEngagement(P)
A.Hazards.install(P)
A.Hazards.vehicle=function() return nil end
A.Hazards.crowd=function() return nil end
local target={x=97,y=100,z=0}
A.Retreat.choose=function() return target end
local moveOptions
local helpers={startMovement=function(_,_,point,intent,options)
    moves=moves+1
    moveOptions=options
    return {kind="movement",intent=intent,target=point}
end}
local passed,failed=0,0
local function check(name,ok)
    if ok then passed=passed+1 else failed=failed+1 print("FAIL awareness: "..name) end
end
local function reset()
    now=now+10000
    A.Awareness.nextAt={}
    A.settings.enabled,A.settings.react.enabled,A.settings.crowd.enabled=true,true,true
    choice,reason,allowed,bare,mode,leash,noncombat="bypass","continue_mission",true,false,"default",nil,false
    actor.memory,actor.lifecycle={},"active"
    shell.vehicle,shell.dead=nil,false
    enemy.x,enemy.y,enemy.z,enemy.dead,enemy.visible,enemy.closing=105,100,0,false,true,1
    enemy.data,enemy.target={},nil
    rows={{x=enemy.x,y=enemy.y,z=enemy.z,body=enemy}}
    combatCalls,moves,fear=0,0,nil
    target={x=97,y=100,z=0}
end
local function react(state)
    return P.ModuleGunFear.interrupt(actor,shell,state or {kind="idle",intent="scan"},now,helpers)
end
reset()
check("armed idle NPC engages a visible closing zombie before contact",react().kind=="combat" and combatCalls==1)
reset(); bare=true
check("unarmed NPC makes space rather than rushing in",react().intent=="alr_make_space" and combatCalls==0)
check("short safe steps leave at least one tile of real movement before arrival",1.5-(moveOptions.tolerance or 0.8)>=1)
reset(); mode="avoid"
check("zombie-avoid order retains avoidance with movement",react().kind=="movement" and combatCalls==0)
reset(); choice,reason="watch","avoid_commitment"
check("wounded tired wait decision becomes a safe sidestep",react().kind=="movement" and combatCalls==0)
reset()
check("recovering NPC can reposition but never starts early combat",react({kind="recovering",intent="recover_endurance"}).kind=="movement" and combatCalls==0)
reset(); target=nil; choice="watch"
check("blocked escape does not invent an unsafe destination",react()==nil and moves==0)
reset(); allowed=false; target=nil
check("unreachable target cannot bypass A-Life combat legality",react()==nil and combatCalls==0)
reset(); noncombat=true
check("civilian noncombatant makes space instead of attacking",react().kind=="movement" and combatCalls==0)
reset(); enemy.visible=false
check("hidden zombie behind a wall cannot trigger early response",react()==nil)
reset(); enemy.z=1; rows[1].z=1
check("zombie upstairs cannot trigger response",react()==nil)
reset(); enemy.dead=true
check("corpse cannot trigger early response",react()==nil and A.Crowd.scan(actor,shell,now).count==0)
reset(); enemy.data.ProjectALifeOwned=true
check("NPC shell excluded from both awareness and crowd count",react()==nil and A.Crowd.scan(actor,shell,now).count==0)
reset(); enemy.closing=0
check("distant uninterested zombie does not derail activity",react()==nil)
reset(); enemy.closing=0; enemy.target=shell
check("targeting zombie can prompt movement even between walking animations",react()~=nil)
reset(); actor.memory.talkHoldUntilMs=now+5000
check("active conversation preserved",react()==nil)
reset(); actor.memory.orderedTo={x=120,y=120}
check("explicit travel order preserved",react()==nil)
reset(); actor.memory.holdPost=true
check("hold-post order preserved",react()==nil)
reset(); leash={x=100,y=100,radius=5}
check("guard leash is not overridden",react()==nil)
reset(); shell.vehicle={}
check("seated NPC never dismounts for awareness",react()==nil)
reset(); actor.lifecycle="dead"
check("dead registry actor cannot think",react()==nil)
reset(); shell.dead=true
check("dead shell cannot think",react()==nil)
reset()
check("working movement leg not overwritten",react({kind="movement",intent="patrol"})==nil)
reset()
check("panic hold preserved",react({kind="idle",intent="panic_stare"})==nil)
reset(); fear={kind="retreat",intent="gun_fear"}
check("gunman fear takes priority over zombie awareness",react()==fear and combatCalls==0)
reset(); A.settings.react.enabled=false
check("world reactive switch disables early awareness live",react()==nil)
reset(); A.settings.crowd.enabled=false; bare=true
check("world crowd switch disables new sidesteps live",react()==nil)
reset(); choice="watch"
react(); now=now+500
check("sidestep cooldown prevents repeated path replacement",react()==nil and moves==1)
reset(); A.Awareness.window=now; A.Awareness.rays=32
check("shared visibility budget bounds work across all NPCs",react()==nil)
check("no unexpected runtime errors",A.metrics.errors==0)

-- Model the real caller order: interrupt creates a ledger action, then the
-- owning loop cancels the actor. Without the handoff this kills our new leg.
local ledger={entries={},activeByActor={}}
local cancelled=0
function ledger.cancelActor(uid,generation)
    local key=uid..":"..generation
    local action=ledger.entries[ledger.activeByActor[key]]
    if not action then return 0 end
    action.status="cancelled"; ledger.activeByActor[key]=nil
    cancelled=cancelled+1
    return 1
end
P.ActionLedger=ledger
check("exact actor-ledger handoff installs",A.ActionHandoff.install(P))
local function action(id)
    local row={uid=actor.uid,generation=1,operationId=id,status="running"}
    ledger.entries[id]=row; ledger.activeByActor[actor.uid..":1"]=id
    return row
end
reset(); bare=true
local old=action("old")
local realHelpers={startMovement=function(_,_,_,intent)
    assert(old.status=="cancelled","old action must be cancelled before begin")
    return {kind="movement",intent=intent,action=action("new")}
end}
local nextState=P.ModuleGunFear.interrupt(actor,shell,{kind="idle"},now,realHelpers)
ledger.cancelActor(actor.uid,1,"gun_fear")
check("new make-space action survives owning-loop cancellation",nextState.action.status=="running" and old.status=="cancelled")
ledger.cancelActor(actor.uid,1,"gun_fear")
check("protection is consumed once, not perpetual immunity",nextState.action.status=="cancelled")
local row=action("death")
A.ActionHandoff.protect(actor,{action=row},now)
ledger.cancelActor(actor.uid,1,"actor_dead")
check("death cancellation never blocked",row.status=="cancelled")
row=action("expired")
A.ActionHandoff.protect(actor,{action=row},now)
now=now+101; ledger.cancelActor(actor.uid,1,"gun_fear")
check("unused handoff expires immediately",row.status=="cancelled")
row=action("original")
A.ActionHandoff.protect(actor,{action=row},now)
local replacement=action("replacement")
ledger.cancelActor(actor.uid,1,"gun_fear")
check("replacement action cannot inherit protection",replacement.status=="cancelled")
row=action("other_generation")
A.ActionHandoff.protect(actor,{action=row},now)
ledger.cancelActor(actor.uid,2,"gun_fear")
check("another generation consumes no false cancellation skip",A.ActionHandoff.pending==nil and row.status=="running")
reset(); fear={kind="retreat",action=row}
check("upstream fear is not protected by our handoff",react()==fear and A.ActionHandoff.pending==nil)

require "ALifeReactive/ALR_Boot"
A.Sandbox.refresh=function() return false end
A.Tuning.hookConfigure=function() end
A.Tuning.apply=function() error("injected startup failure") end
check("transient bootstrap failure remains retryable",not A.Boot.install() and not A.Boot.installed)
local errors=A.metrics.errors
check("bootstrap backoff prevents per-frame error spam",not A.Boot.install() and A.metrics.errors==errors)
now=now+1100
A.Tuning.apply=function() end
check("bootstrap succeeds after dependency recovers",A.Boot.install() and A.Boot.installed)
print("RESULT awareness passed="..passed.." failed="..failed)
return failed
