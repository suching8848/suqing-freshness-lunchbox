local C=SuQingFreshnessLunchbox;local N=Native
local check,near,test=N.check,N.near,N.test
local cold=SuQingRefrigeration;local CR=cold.Runtime
local index=__classmetatables[Food.class].__index
check(cold.version=="1.0.0-rc.2-perf.1","audited installed cooling logic version")
CR.Start();check(CR.ready);check(C.InstallCoolingBridge());check(C.AgeHookReady());check(index.updateAge==CR.ageWrapper)
local function coldBag(box)
    local bag=ProbeMakeBox("Base.Bag");ProbeWearable(bag)
    bag:getModData()[cold.key]={schema=1,on=true,paid=true,token="runtime-native-paid-snapshot",batteries={1,1,1,1,1,1}}
    bag:getInventory():AddItem(box);check(cold.Wearable(bag));check(cold.Valid(cold.Record(bag)))
    return bag
end
test("current cold carrier chain preserves freshness progress and native cooling",function()
    local b,f,t,s=N.setup(8);local bag=coldBag(b);check(CR.Cooling(f))
    f:updateAge(false);check(C.CoolingBridgeReady());check(not C.FoodRecord(f).externalEdit)
    local initial=C.FoodRecord(f).logicalAge;local start=N.now()
    for i=1,120 do
        local now=N.advance(0.1)
        f:updateAge(false);check(not C.FoodRecord(f).externalEdit,"known cold setAge must not invalidate lunchbox")
        C.ObserveTimeline(t,s,now,C.Config(),false);local result=C.SettleFood(f,b,now,t,false)
        check(result.elapsed>0,"cold carrier must not keep reanchoring")
        f:updateAge(false);check(not C.FoodRecord(f).externalEdit,"same-time cold setter is natural")
        local expected=math.max(0,initial-5*(now-start)/10)
        near(f:getAge(),expected,0.00002)
    end
    check(f:getHeat()<0.2001,"prior gradual native cooling preserved");check(CR.stats.errors==0)
    f:setAge(9);check(C.FoodRecord(f).externalEdit,"external setter outside cold scope still observed")
    C.SettleFood(f,b,N.now(),t,false);near(f:getAge(),9)
end)
test("unknown cooling version or changed hook chain is not trusted",function()
    local b,f,t,s=N.setup(5);local bag=coldBag(b);f:updateAge(false)
    cold.version="unrecognized";f:updateAge(false);check(C.FoodRecord(f).externalEdit);check(not C.CoolingBridgeReady())
    cold.version="1.0.0-rc.2-perf.1";C.SettleFood(f,b,N.now(),t,true)
    local previous=index.updateAge;index.updateAge=function(food,...) return previous(food,...) end
    f:updateAge(false);check(C.FoodRecord(f).externalEdit);check(not C.CoolingBridgeReady())
    index.updateAge=previous;check(C.CoolingBridgeReady())
end)
test("cooling scope always restores on delegated failure",function()
    local b,f=N.setup(5);local bag=coldBag(b);local bridge=C.coolingBridge
    local previous=bridge.prior;bridge.prior=function() error("native combination deliberate failure") end
    local ok=pcall(CR.Settle,f,N.now());bridge.prior=previous
    check(not ok);check(C.coolingWrites[f]==nil);f:setAge(7);check(C.FoodRecord(f).externalEdit)
end)
test("ordinary cold food retains original twenty percent aging",function()
    local b=ProbeMakeBox("Base.Bag");ProbeWearable(b)
    b:getModData()[cold.key]={schema=1,on=true,paid=true,token="ordinary-native-paid",batteries={1,1,1,1,1,1}}
    local f=ProbeMakeFood(1,5,10);b:getInventory():AddItem(f);f:updateAge(false)
    local start=f:getAge();N.advance(24);f:updateAge(false);near(f:getAge()-start,0.2,0.0002)
    check(C.FoodRecord(f)==nil);check(C.coolingWrites[f]==nil);check(CR.stats.errors==0)
end)
if SuQingFreshnessFridge then
test("current original fridge coexists; nested box has one freshness owner",function()
    local F=SuQingFreshnessFridge;check(F.version=="0.1.0-rc.2")
    local fridge,inventory=ProbeMakeFridge();check(F.IsFridge(fridge));check(F.Container(fridge)==inventory)
    local b,f,t,s=N.setup(5);inventory:AddItem(b)
    check(not F.IsDirectFood(f,fridge));check(C.IsDirectFood(f,b))
    local start=N.now();for i=1,10 do
        local now=N.advance(0.1);local old=F.SettleFood(f,fridge,now,{continuous=true,powered=true})
        check(not old.active);C.ObserveTimeline(t,s,now,C.Config(),false);C.SettleFood(f,b,now,t,false)
        near(f:getAge(),5-5*(now-start)/10,0.00002)
    end
    -- Actual transfer out of the box clears only the new owner's ledger. The
    -- existing fridge then restores at its original rate through the same setAge slot.
    C.ClearFood(f);b:getInventory():getItems():remove(f);inventory:AddItem(f)
    F.SettleFood(f,fridge,N.now(),{continuous=false,powered=true})
    local age=f:getAge();local now=N.advance(0.1);F.SettleFood(f,fridge,now,{continuous=true,powered=true})
    near(f:getAge(),age-5*0.1/10,0.00002);check(C.FoodRecord(f)==nil);check(F.FoodRecord(f)~=nil)
    -- Moving back never resurrects the old lunchbox timestamp or credits both.
    F.ClearFood(f);inventory:getItems():remove(f);b:getInventory():AddItem(f)
    C.SettleFood(f,b,N.now(),t,false);check(C.FoodRecord(f).time==N.now());check(F.FoodRecord(f)==nil)
end)
end
print("RUNTIME_NATIVE cases="..N.cases.." assertions="..N.assertions.." PASS")
