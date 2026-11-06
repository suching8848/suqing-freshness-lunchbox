-- Method-only regression for the real Core.lua cooling bridge. No game/world/save.
local C=SuQingFreshnessLunchbox
local cases,assertions=0,0
local realPcall=pcall
local counters={}
local expectFastpath=EXPECT_FASTPATH~=false
local function check(value,label)
    assertions=assertions+1
    assert(value,label or "cooling bridge regression")
end
local function eq(a,b,label) check(a==b,(label or "equal")..": "..tostring(a).." / "..tostring(b)) end
local function capture(...) return {n=select("#",...),...} end
local function count(name) counters[name]=(counters[name] or 0)+1 end
local function resetCounters() counters={} end
local function value(name) return counters[name] or 0 end
local originalReady=C.CoolingBridgeReady
local originalBoxState=C.BoxState
C.CoolingBridgeReady=function(...) count("bridge_checks");return originalReady(...) end
C.BoxState=function(...) count("box_checks");return originalBoxState(...) end
pcall=function(...) count("protected_calls");return realPcall(...) end
function instanceof(item,kind) return type(item)=="table" and item.kind==kind end
local function test(name,fn)
    cases=cases+1
    fn()
    print("COOLING_BRIDGE_CASE "..name.." PASS")
end

local function setup(options)
    options=options or {}
    C.coolingBridge=nil;C.ageHook=nil
    C.coolingWrites=setmetatable({}, {__mode="k"})
    C.ownAgeWrites=setmetatable({}, {__mode="k"})
    local index={}
    index.setAge=function(food,age) food.age=age end
    Food={class="CoolingBridgeFood"}
    __classmetatables={[Food.class]={__index=index}}
    check(C.InstallAgeHook(),"install real setAge observation hook")
    local box={kind="InventoryContainer",fullType=C.FullType,id=31,md={}}
    local inventory={box=box,items={}}
    function inventory:getContainingItem() count("containing_lookups");return self.box end
    function inventory:getItems() return self end
    function inventory:contains(food) return self.items[food]==true end
    function box:getFullType() return self.fullType end
    function box:getInventory() count("inventory_lookups");return inventory end
    function box:getModData() return self.md end
    function box:getID() return self.id end
    box.md[C.boxKey]={schema=1,id="bridge-box",on=true,epoch=0,baseCapacity=4}
    local food={kind="Food",id=19,age=3,md={},container=inventory}
    function food:getModData() count("food_record_lookups");return self.md end
    function food:getContainer() count("container_lookups");return self.container end
    function food:getID() return self.id end
    function food:getFullType() return "Base.Apple" end
    function food:getAge() return self.age end
    function food:setAge(age) return index.setAge(self,age) end
    inventory.items[food]=true
    if options.record~=false then
        food.md[C.foodKey]={schema=1,active=options.active~=false,id="19",fullType="Base.Apple",
            boxId="bridge-box",boxItemId="31"}
    end
    local r={ready=options.ready~=false,hooksInstalled=true,busy={}}
    r.nativeAge=function() end
    r.ageWrapper=function() end
    r.Cooling=function() return true end
    r.SyncConfig=function() end
    r.Integral=function() return 0 end
    index.updateAge=r.ageWrapper
    local handler=function() return "delegated",nil,"tail",nil end
    r.Settle=function(item,time,...)
        count("delegated_calls")
        return handler(item,time,...)
    end
    SuQingRefrigeration={version="1.0.0-rc.2-perf.1",Runtime=r}
    check(C.InstallCoolingBridge(),"install real cooling bridge")
    resetCounters()
    return {food=food,box=box,inventory=inventory,index=index,r=r,
        record=food.md[C.foodKey],handler=function(fn) handler=fn end}
end

local function checkFourReturns(result,label)
    eq(result.n,4,label.." return count")
    eq(result[1],"delegated",label.." first")
    eq(result[2],nil,label.." middle nil")
    eq(result[3],"tail",label.." third")
    eq(result[4],nil,label.." trailing nil")
end
local function checkNoScope(s,label)
    s.handler(function(food,time,...)
        eq(food,s.food,label.." same food")
        eq(time,12,label.." same time")
        eq(select("#",...),3,label.." vararg count")
        local a,b,c=...
        eq(a,"arg",label.." first vararg");eq(b,nil,label.." middle nil arg");eq(c,7,label.." last arg")
        eq(C.coolingWrites[food],nil,label.." no created scope")
        return "delegated",nil,"tail",nil
    end)
    checkFourReturns(capture(s.r.Settle(s.food,12,"arg",nil,7)),label)
    eq(C.coolingWrites[s.food],nil,label.." no leaked scope")
end

test("ordinary cold food delegates without owner or bridge lookups",function()
    local s=setup({record=false})
    checkNoScope(s,"ordinary")
    if expectFastpath then
        eq(value("container_lookups"),0,"ordinary zero container lookups")
        eq(value("containing_lookups"),0,"ordinary zero containing-item lookups")
        eq(value("box_checks"),0,"ordinary zero box checks")
        eq(value("bridge_checks"),0,"ordinary zero bridge checks")
        eq(value("protected_calls"),0,"ordinary zero protected delegate calls")
    end
    eq(C.coolingBridge.ageWrapper,s.r.ageWrapper,"ordinary path retains lazy hook capture")
    eq(C.coolingBridge.nativeAge,s.r.nativeAge,"ordinary path captures native hook")
end)
test("inactive lunchbox record delegates directly",function()
    local s=setup({active=false});checkNoScope(s,"inactive")
    if expectFastpath then
        eq(value("container_lookups"),0,"inactive zero container lookups")
        eq(value("bridge_checks"),0,"inactive zero bridge checks")
        eq(value("protected_calls"),0,"inactive zero protected delegate calls")
    end
end)
test("busy nested call keeps an existing scope",function()
    local s=setup();local previous={marker="existing"}
    C.coolingWrites[s.food]=previous;s.r.busy[s.food]=true
    s.handler(function(food) eq(C.coolingWrites[food],previous,"busy nested inherits existing scope");return 5,nil end)
    local result=capture(s.r.Settle(s.food,12))
    eq(result.n,2,"busy return count");eq(result[1],5,"busy first return");eq(result[2],nil,"busy nil return")
    eq(C.coolingWrites[s.food],previous,"busy scope unchanged")
    if expectFastpath then
        eq(value("container_lookups"),0,"busy zero owner queries")
        eq(value("bridge_checks"),0,"busy zero bridge checks")
        eq(value("protected_calls"),0,"busy zero new protected calls")
    end
end)
test("active trusted owner installs a valid scope and restores it",function()
    local s=setup()
    s.handler(function(food)
        local scope=C.coolingWrites[food]
        check(scope~=nil,"active scope exists");eq(scope.record,s.record,"active same record")
        eq(scope.box,s.box,"active same box");eq(scope.entryAge,3,"active entry age")
        s.r.busy[food]=true
        check(C.IsKnownCoolingWrite(food,3,s.record),"active scope passes original known-writer checks")
        food:setAge(3);check(not s.record.externalEdit,"known cooling setter preserves lunchbox trust")
        s.r.busy[food]=nil
        return "delegated",nil,"tail",nil
    end)
    checkFourReturns(capture(s.r.Settle(s.food,12)),"active")
    eq(C.coolingWrites[s.food],nil,"active scope restored to absent")
    eq(value("protected_calls"),1,"active delegate remains protected")
end)
test("invalid chain delegates without creating a scope",function()
    local changes={
        function(s) SuQingRefrigeration.version="unknown" end,
        function(s) s.index.updateAge=function() end end,
        function(s) s.index.setAge=function() end end,
        function(s) s.r.nativeAge=function() end end,
        function(s) s.r.ready=false end,
    }
    for n,change in ipairs(changes) do
        local s=setup();s.r.Settle(s.food,0) -- capture the original supported hook slots
        change(s);resetCounters();checkNoScope(s,"bad chain "..n)
        if expectFastpath then eq(value("protected_calls"),0,"bad chain direct delegate") end
    end
end)
test("wrong owner or missing inventory membership creates no scope",function()
    local changes={
        function(s) s.record.boxId="other" end,
        function(s) s.record.boxItemId="other" end,
        function(s) s.inventory.items[s.food]=nil end,
        function(s) s.box.fullType="Base.Bag" end,
        function(s) s.food.container=nil end,
    }
    for n,change in ipairs(changes) do
        local s=setup();change(s);checkNoScope(s,"wrong owner "..n)
        if expectFastpath then eq(value("protected_calls"),0,"wrong owner direct delegate") end
    end
end)
test("direct-path errors preserve the preexisting scope",function()
    local s=setup({record=false});local previous={marker="outer"};C.coolingWrites[s.food]=previous
    s.handler(function(food)
        eq(C.coolingWrites[food],previous,"direct failure sees previous scope")
        error("deliberate direct cooling failure")
    end)
    local result=capture(realPcall(s.r.Settle,s.food,12))
    eq(result[1],false,"direct error propagates")
    check(string.find(tostring(result[2]),"deliberate direct cooling failure",1,true)~=nil,"direct error message preserved")
    eq(C.coolingWrites[s.food],previous,"direct error preserves scope")
    if expectFastpath then eq(value("protected_calls"),0,"direct failure avoids new pcall") end
end)
test("protected-path errors restore absent and existing scopes",function()
    for n=1,2 do
        local s=setup();local previous=n==2 and {marker="outer"} or nil
        C.coolingWrites[s.food]=previous
        s.handler(function(food)
            check(C.coolingWrites[food]~=previous,"failure sees temporary active scope")
            error("deliberate scoped cooling failure")
        end)
        local result=capture(realPcall(s.r.Settle,s.food,12))
        eq(result[1],false,"scoped error propagates")
        check(string.find(tostring(result[2]),"deliberate scoped cooling failure",1,true)~=nil,"scoped error message preserved")
        eq(C.coolingWrites[s.food],previous,"scoped error restores previous scope")
    end
end)
test("same-food nested active scopes restore in stack order",function()
    local s=setup();local previous={marker="outer"};C.coolingWrites[s.food]=previous
    local depth=0;local firstScope
    s.handler(function(food,time)
        local scope=C.coolingWrites[food]
        if depth==0 then
            check(scope~=previous,"first nested scope replaces prior")
            firstScope=scope;depth=1
            local inner=capture(s.r.Settle(food,time))
            eq(inner.n,3,"nested returns count");eq(inner[1],nil,"nested leading nil")
            eq(inner[2],false,"nested false");eq(inner[3],nil,"nested trailing nil")
            eq(C.coolingWrites[food],firstScope,"nested return restores first scope")
            depth=0;return "outer",nil
        end
        check(scope~=firstScope and scope~=previous,"inner uses distinct temporary scope")
        eq(scope.record,s.record,"inner keeps target record")
        return nil,false,nil
    end)
    local result=capture(s.r.Settle(s.food,12))
    eq(result.n,2,"outer return count");eq(result[1],"outer","outer value");eq(result[2],nil,"outer trailing nil")
    eq(C.coolingWrites[s.food],previous,"outer completion restores preexisting scope")
end)
test("ordinary first call before runtime start still captures hooks later",function()
    local s=setup({record=false,ready=false})
    s.r.Settle(s.food,12);eq(C.coolingBridge.ageWrapper,nil,"unready call does not capture")
    s.r.ready=true;s.r.Settle(s.food,12)
    eq(C.coolingBridge.ageWrapper,s.r.ageWrapper,"ordinary call after start captures")
    eq(C.coolingBridge.nativeAge,s.r.nativeAge,"ordinary call captures native implementation")
    check(originalReady(),"lazy chain becomes trusted")
end)
test("non-food calls retain raw delegation and return arity",function()
    local s=setup();local item={kind="InventoryItem"}
    s.handler(function(food,time,...) eq(food,item,"same non-food");return nil,"item",nil end)
    local result=capture(s.r.Settle(item,12))
    eq(result.n,3,"non-food arity");eq(result[1],nil,"non-food leading nil")
    eq(result[2],"item","non-food value");eq(result[3],nil,"non-food trailing nil")
    eq(value("container_lookups"),0,"non-food zero container lookups")
end)
test("ordinary existing scope survives a successful delegation",function()
    local s=setup({record=false});local previous={marker="outer"};C.coolingWrites[s.food]=previous
    s.handler(function(food) eq(C.coolingWrites[food],previous,"direct success inherits scope");return true end)
    eq(s.r.Settle(s.food,12),true,"direct success return")
    eq(C.coolingWrites[s.food],previous,"direct success retains scope")
end)

-- Deterministic bridge overhead counts; no elapsed-time/FPS claims are made.
local s=setup({record=false})
for n=1,1000 do s.r.Settle(s.food,12) end
eq(value("delegated_calls"),1000,"all ordinary calls reach predecessor exactly once")
if expectFastpath then
    eq(value("container_lookups"),0,"1000 calls zero owner queries")
    eq(value("bridge_checks"),0,"1000 calls zero bridge checks")
    eq(value("protected_calls"),0,"1000 calls zero protected delegations")
end
print("COOLING_BRIDGE_METRICS calls="..value("delegated_calls")
    .." food_record_lookups="..value("food_record_lookups")
    .." container_lookups="..value("container_lookups")
    .." containing_lookups="..value("containing_lookups")
    .." box_checks="..value("box_checks")
    .." bridge_checks="..value("bridge_checks")
    .." protected_calls="..value("protected_calls"))
print("COOLING_BRIDGE_FASTPATH cases="..cases.." assertions="..assertions.." PASS")
pcall=realPcall
return "COOLING_BRIDGE_FASTPATH PASS"
