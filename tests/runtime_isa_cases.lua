local P=ISAProbe;local C=SuQingFreshnessLunchbox;local R=C.Runtime
local check,eq,case=P.check,P.eq,P.case
if not P.native then Mock.paused=true end
P.emit('OnGameStart');check(R.ready,'GameStart registers food protection immediately')
P.emit('OnTickEvenPaused')
if ISAExpectBroken then
    check(R.transfer~=nil,'rc3 installs before ISA normal tick')
    P.emit('OnTick');P.emit('OnTickEvenPaused')
    check(not R.ready,'rc3 stops after legitimate ISA forwarding wrapper')
    eq(R.stats.errors,1)
    return 'ISA_RC3_REPRO native='..tostring(P.native)..' assertions='..P.checks..' PASS'
end
case('paused startup waits for complete normal-tick dispatch without credit',function()
    check(not R.operational);eq(R.status,'waiting_transfer');eq(R.transfer,nil);eq(R.stats.errors,0)
    for i=1,3 do P.emit('OnTickEvenPaused')end
    eq(R.transfer,nil);eq(R.stats.errors,0)
    local segment=R.timeline.segments[#R.timeline.segments];eq(segment.enabled,false,'startup history cannot award restoration')
    for i=1,6 do P.emit('OnTick');P.emit('OnTickEvenPaused')end
    check(R.ready);check(R.operational);eq(R.status,'ready');eq(R.stats.errors,0)
    eq(ISTransferAction.transferItem,R.transfer.wrapper);eq(ISAUnderTest.Patches,nil,'real ISA once-only queue completed')
end)
case('actual ISA forwarding layer and battery notification remain inside chain',function()
    local battery=P.native and ProbeMakeFood(1,5,10) or Mock.food(1)
    if not P.native then
        function battery:getCondition()return 50 end
        function battery:getCurrentUsesFloat()return 0.5 end
    end
    battery:getModData().ISA_maxCapacity=100
    local object={powerBank=true,getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end}
    local source={getParent=function()return object end};local destination={getParent=function()return nil end}
    ISAUnderTest.WorldUtil={objectIsType=function(obj,kind)return obj and obj.powerBank and kind=='PowerBank'end}
    local before=P.baseTransfers;eq(ISTransferAction.transferItem({}, {},battery,source,destination),battery)
    eq(P.baseTransfers,before+1);eq(#P.commands,1);eq(P.commands[1].name,'moveBattery');eq(P.commands[1].args[2],'take')
end)
case('strict unknown outer layer still stops and never retries after error',function()
    local previous=ISTransferAction.transferItem
    ISTransferAction.transferItem=function(...)return previous(...)end
    P.emit('OnTickEvenPaused');eq(R.ready,false);eq(R.operational,false);eq(R.status,'error');check(R.failed);eq(R.stats.errors,1)
    for i=1,4 do P.emit('OnTick');P.emit('OnTickEvenPaused')end
    eq(R.ready,false);eq(R.stats.errors,1,'failed runtime must not loop or clear diagnostics')
    ISTransferAction.transferItem=previous
end)
case('menu and next game start reuse one existing wrapper without double transfer',function()
    MainScreen.instance.inGame=false;P.emit('OnMainMenuEnter');eq(R.ready,false);eq(R.status,'stopped')
    P.emit('OnTick');eq(R.ready,false,'main menu is not a loaded-world fallback')
    local wrapper=ISTransferAction.transferItem
    MainScreen.instance.inGame=true;P.emit('OnGameStart');P.emit('OnTick');P.emit('OnTickEvenPaused')
    check(R.ready);check(R.operational);eq(ISTransferAction.transferItem,wrapper);eq(R.transfer.wrapper,wrapper)
    local item=P.native and ProbeMakeFood(1,5,10) or Mock.food(1);local before=P.baseTransfers
    eq(ISTransferAction.transferItem({}, {},item,nil,nil),item);eq(P.baseTransfers,before+1)
end)
return 'ISA_LIFECYCLE native='..tostring(P.native)..' cases='..P.cases..' assertions='..P.checks..' PASS'
