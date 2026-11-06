local C,F=SuQingContainerUpgrade,SuQingFreshnessLunchbox
local cases,checks=0,0
local function check(ok,label) checks=checks+1;assert(ok,label) end
local function eq(a,b,label) checks=checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..'/'..tostring(b)) end
local function case(name,fn) cases=cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why)) end
case('native inventory containers work without optional lunchbox script provider',function()
    eq(C.version,'1.0.3');eq(getScriptManager():getItem(F.FullType),nil)
    local a=actor();local bag=ProbeMakeBox('Base.Bag_Schoolbag');a.inventory:AddItem(bag)
    check(instanceof(bag,'InventoryContainer'));check(C.IsSupported(bag));check(C.CanUpgrade(bag,a,1))
    local data={getAllKeepInputItems=function()return list({bag})end}
    check(C.Upgrade(data,a,1));eq(bag:getInventory():getCapacity(),12);eq(bag:getWeightReduction(),90)
    check(C.Restore(data,a));eq(bag:getInventory():getCapacity(),4);eq(bag:getWeightReduction(),50)
end)
case('five native lunchbox tiers retain identity and record actual native materials',function()
    local a=actor();local box=ProbeMakeBox();a.inventory:AddItem(box);check(F.EnsureBox(box))
    local state=F.BoxState(box);state.on=false;state.epoch=2;local other={keep='native-extra'};box:getModData().OtherMod=other
    local data={getAllKeepInputItems=function()return list({box})end}
    local capacities={12,20,30,40,49};local reductions={90,93,95,97,99}
    for tier=1,5 do
        check(C.CanUpgrade(box,a,tier));check(C.ProbeChange(box,a,tier));eq(box:getInventory():getCapacity(),tier==1 and 4 or capacities[tier-1])
        local ok,result=C.Upgrade(data,a,tier);check(ok);eq(result,box)
        eq(box:getInventory():getCapacity(),capacities[tier]);eq(box:getWeightReduction(),reductions[tier]);eq(box:getActualWeight(),1)
        eq(F.BoxState(box),state);eq(box:getModData().OtherMod,other);check(not C.CanUpgrade(box,a,tier))
        local snapshots={};local cost=C.tiers[tier]
        for _,spec in ipairs({{'Base.RippedSheets',cost.cloth},{'Base.LeatherStrips',cost.leather}})do
            for i=1,spec[2]do
                local material=IntegrationMakeMaterial(spec[1]);check(instanceof(material,'InventoryItem'))
                a.inventory:AddItem(material);a.inventory:Remove(material)
                check(not a.inventory:getItems():contains(material));eq(material:getContainer(),nil)
                snapshots[#snapshots+1]={item=material,container=a.inventory,fullType=spec[1]}
            end
        end
        local thread=IntegrationMakeMaterial('Base.Thread');check(instanceof(thread,'DrainableComboItem'));a.inventory:AddItem(thread)
        eq(thread:getCurrentUses(),20);thread:setCurrentUses(20-cost.thread);eq(thread:getCurrentUses(),20-cost.thread)
        snapshots[#snapshots+1]={item=thread,container=a.inventory,fullType='Base.Thread',threadUnits=20}
        check(C.Refund.CommitPayment(box,snapshots,tier))
    end
    local ledger=C.Refund.ReadLedger(C.GetRecord(box));eq(ledger.cloth,54);eq(ledger.leather,22);eq(ledger.threadUses,30)
    local plan,why=C.Refund.StageRefund(C.GetRecord(box),a);check(plan,why)
    eq(plan.cloth,27);eq(plan.leather,11);eq(plan.threadUses,15);eq(#plan.entries,39)
    check(C.Refund.InsertRefund(plan))
    for _,entry in ipairs(plan.entries)do
        check(instanceof(entry.item,'InventoryItem'));check(a.inventory:getItems():contains(entry.item));eq(entry.item:getContainer(),a.inventory)
        if entry.uses then eq(entry.item:getCurrentUses(),entry.uses) end
    end
    check(C.ProbeChange(box,a,'restore'));local ok,result=C.Restore(data,a);check(ok);eq(result,box)
    eq(box:getInventory():getCapacity(),4);eq(box:getWeightReduction(),50);eq(box:getActualWeight(),1)
    eq(C.GetRecord(box),nil);eq(F.BoxState(box),state);eq(state.on,false);eq(state.epoch,2);eq(box:getModData().OtherMod,other)
    check(not C.CanRestore(box,a));check(not C.Restore(data,a))
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=30;F.EnsureBox(box);eq(box:getInventory():getCapacity(),4)
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=4
end)
case('native nonempty and hand held guards remain enforced',function()
    local a=actor();local box=ProbeMakeBox();a.inventory:AddItem(box);F.EnsureBox(box)
    local food=ProbeMakeFood(1,5,10);box:getInventory():AddItem(food)
    check(not C.CanUpgrade(box,a,1));box:getInventory():Remove(food)
    a.primary=box;check(not C.CanUpgrade(box,a,1));a.primary=nil;a.secondary=box;check(not C.CanUpgrade(box,a,1))
    a.secondary=nil;check(C.CanUpgrade(box,a,1))
end)
return 'INTEGRATION_NATIVE_UPGRADE core='..C.version..' cases='..cases..' assertions='..checks..' failures=0; actual InventoryContainer, ItemContainer, InventoryItem, DrainableComboItem and ordinary Core/Refund; actor and kept-input shells only'
