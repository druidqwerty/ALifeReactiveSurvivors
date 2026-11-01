-- A-Life 1.4.6 cancels the actor ledger AFTER ModuleGunFear.interrupt returns.
-- Retire the previous action before creating ours, then protect only that
-- exact fresh action from the immediate redundant "gun_fear" cancellation.
-- Death, orders, ownership loss, later cancellations and upstream fear remain intact.
require "ALifeReactive/00_ALR_Core"
local A=ALifeReactive
local G={}
A.ActionHandoff=G

function G.cancelOld(actor,state)
    local p=ProjectALife
    if state and state.kind=="scavenging" and state.plan and p.Scavenging and p.Scavenging.cancel then
        p.Scavenging.cancel(state.plan,"alr_interrupt")
    end
    if p.ActionLedger and p.ActionLedger.cancelActor then
        p.ActionLedger.cancelActor(actor.uid,actor.generation,"alr_interrupt")
    end
end

function G.helpers(actor,state,helpers)
    if not helpers or not helpers.startMovement then return helpers end
    local copy={}
    for k,v in pairs(helpers) do copy[k]=v end
    copy.startMovement=function(a,shell,target,intent,options)
        G.cancelOld(actor,state)
        return helpers.startMovement(a,shell,target,intent,options)
    end
    return copy
end

function G.protect(actor,result,now)
    local action=result and result.action
    if G.ledger and action and action.status=="running" and action.uid==actor.uid
        and action.generation==actor.generation and action.operationId then
        G.pending={uid=actor.uid,generation=actor.generation,action=action,untilMs=now+100}
    end
    return result
end

function G.install(p)
    local ledger=p.ActionLedger
    if not ledger or not ledger.cancelActor or not ledger.activeByActor or not ledger.entries then return false end
    if G.ledger==ledger then return true end
    A.wrap(ledger,"cancelActor",function(original)
        return function(uid,generation,reason)
            local pending=G.pending
            G.pending=nil
            if pending and reason=="gun_fear" and pending.uid==uid and pending.generation==generation
                and A.now()<=pending.untilMs and pending.action.status=="running" then
                local id=ledger.activeByActor[uid..":"..tostring(generation)]
                if id and ledger.entries[id]==pending.action then return 0 end
            end
            return original(uid,generation,reason)
        end
    end,"ActionLedger.cancelActor.handoff")
    G.ledger=ledger
    return true
end
return G
