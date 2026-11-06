local C,F=SuQingContainerUpgrade,SuQingFreshnessLunchbox
local id='SuQingFreshnessLunchbox.FreshnessLunchbox'
local cases,checks=0,0
local function check(value,label) checks=checks+1;assert(value,label) end
local function eq(a,b,label) checks=checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..' ~= '..tostring(b)) end
local function case(name,fn) cases=cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why)) end
local originalVersion=C.version
if originalVersion=='1.0.0' then
    case('existing personal version has no built-in lunchbox support',function()
        eq(C.supported[id],nil);eq(C.compatibility.profiles[id],nil)
        local a=actor();local b=item(id,'InventoryContainer');a.inventory:AddItem(b);F.EnsureBox(b)
        check(not C.IsSupported(b));local ok,why=C.CanUpgrade(b,a,1);check(not ok);eq(why,'unsupported')
        eq(C.GetRecord(b),nil);eq(b.inner.capacity,4);eq(F.BoxState(b).baseCapacity,4)
    end)
    case('personal ordinary targets remain functional with no lunchbox definition',function()
        eq(getScriptManager():getItem(id),nil)
        local a=actor();local b=item('Base.Bag_Schoolbag','InventoryContainer');a.inventory:AddItem(b)
        check(C.IsSupported(b));check(C.CanUpgrade(b,a,1))
        local data={getAllKeepInputItems=function()return list({b})end}
        check(C.Upgrade(data,a,1));check(C.Restore(data,a));eq(b.inner.capacity,4)
    end)
    return 'INTEGRATION_UPGRADE core='..originalVersion..' cases='..cases..' assertions='..checks..' failures=0; personal version intentionally unsupported; no adapter injection'
end
case('source directly supports exact independent box without adapter registration',function()
    eq(originalVersion,'1.0.3');check(C.supported[id]);eq(C.compatibility.profiles[id],'mod_container')
    eq(C.compatibility.positionPairs[id],nil);eq(SuQingFreshnessLunchboxUpgrade,nil)
    local count=0;for key in pairs(C.supported)do if key==id then count=count+1 end end;eq(count,1)
end)
case('source core loads and other containers upgrade with missing lunchbox definition',function()
    eq(getScriptManager():getItem(id),nil)
    local a=actor();local b=item('Base.Bag_Schoolbag','InventoryContainer');a.inventory:AddItem(b)
    check(C.IsSupported(b));check(C.CanUpgrade(b,a,1));local data={getAllKeepInputItems=function()return list({b})end}
    check(C.Upgrade(data,a,1));check(C.Restore(data,a));eq(b.inner.capacity,4);eq(C.GetRecord(b),nil)
end)
case('ordinary actual upgrade core preserves lunchbox identity across five tiers and paid restore',function()
    local character=actor();local box=item(F.FullType,'InventoryContainer');character.inventory:AddItem(box)
    F.EnsureBox(box);local state=F.BoxState(box);state.on=false
    local custom={keep=true};box.md.OtherMod=custom
    local data={getAllKeepInputItems=function()return list({box})end}
    local capacities={12,20,30,40,49};local reductions={90,93,95,97,99}
    for tier=1,5 do
        local ok,why=C.CanUpgrade(box,character,tier);check(ok,why)
        local upgraded,result=C.Upgrade(data,character,tier);check(upgraded);eq(result,box)
        eq(box.inner.capacity,capacities[tier]);eq(box.reduction,reductions[tier]);eq(box.weight,1)
        eq(F.BoxState(box),state);check(not state.on);eq(box.md.OtherMod,custom)
        check(not C.CanUpgrade(box,character,tier),'repeated paid tier refused')
        local snapshots={};local cost=C.tiers[tier]
        for _,spec in ipairs({{'Base.RippedSheets',cost.cloth},{'Base.LeatherStrips',cost.leather}})do
            for _=1,spec[2]do snapshots[#snapshots+1]={item=item(spec[1]),container=character.inventory,fullType=spec[1]}end
        end
        local thread=item('Base.Thread');thread.uses=(20-cost.thread)*.05;character.inventory:AddItem(thread)
        snapshots[#snapshots+1]={item=thread,container=character.inventory,fullType='Base.Thread',threadUnits=20}
        local paid,paymentReason=C.Refund.CommitPayment(box,snapshots,tier);check(paid,paymentReason)
    end
    local ledger=C.Refund.ReadLedger(C.GetRecord(box));eq(ledger.cloth,54);eq(ledger.leather,22);eq(ledger.threadUses,30)
    local plan,why=C.Refund.StageRefund(C.GetRecord(box),character);check(plan,why)
    eq(plan.cloth,27);eq(plan.leather,11);eq(plan.threadUses,15);check(C.Refund.InsertRefund(plan))
    local ok,returned=C.Restore(data,character);check(ok);eq(returned,box)
    eq(box.inner.capacity,4);eq(box.reduction,50);eq(box.weight,1)
    eq(F.BoxState(box),state);eq(box.md.OtherMod,custom);check(not C.CanRestore(box,character),'no repeat restore/refund eligibility')
    eq(C.GetRecord(box),nil)
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=30;F.EnsureBox(box)
    eq(box.inner.capacity,4,'later sandbox cannot undo baseline restoration')
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=4
end)
case('paid upgrade refuses nonempty boxes and either held hand',function()
    local a=actor();local box=item(F.FullType,'InventoryContainer');a.inventory:AddItem(box);F.EnsureBox(box)
    box.inner:AddItem(item('Base.Apple','Food'));check(not C.CanUpgrade(box,a,1),'nonempty')
    box.inner.items:clear();a.primary=box;check(not C.CanUpgrade(box,a,1),'primary')
    a.primary=nil;a.secondary=box;check(not C.CanUpgrade(box,a,1),'secondary')
    a.secondary=nil;check(C.CanUpgrade(box,a,1),'ready after removing from hand')
end)
return 'INTEGRATION_UPGRADE core='..originalVersion..' cases='..cases..' assertions='..checks..' failures=0; source built-in Core and Refund; deterministic actor and inventory shells'
