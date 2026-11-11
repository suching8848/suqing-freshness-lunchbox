local C=SuQingFreshnessLunchbox;local R=C.Runtime
local cases,assertions=0,0
local function check(ok,message) assertions=assertions+1;if not ok then error(message or "check failed") end end
local function near(a,b,t,message) check(math.abs(a-b)<(t or 0.00001),(message or "number mismatch")..": "..tostring(a).." vs "..tostring(b)) end
local function test(name,fn) cases=cases+1;fn();print("MOCK_CASE "..name.." PASS") end
local function tick(h) Mock.clock=Mock.clock+h;R.Tick() end
test("initial capacity is persistent across configuration and paid upgrade restore",function()
    Mock.reset();SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=6
    local b=Mock.box();local s=C.EnsureBox(b);check(s.baseCapacity==6);check(b.inventory.capacity==6)
    b:setCapacity(20);b.weightReduction=93;b.md.SuQingContainerUpgrade={level=2}
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=12;C.EnsureBox(b);check(b.inventory.capacity==20);check(b.weightReduction==93)
    b:setCapacity(6);b.md.SuQingContainerUpgrade=nil;C.EnsureBox(b);check(b.inventory.capacity==6);check(C.BoxState(b)==s)
    local bad=Mock.box();bad.md.SuQingContainerUpgrade={level=1};check(C.EnsureBox(bad)==nil);check(bad.inventory.capacity==4)
end)
test("startup before transfer readiness preserves ordinary aging without credit",function()
    Mock.reset();local s=Mock.square(1);local p=Mock.player(s);local b=Mock.add(p.inventory,Mock.box());local f=Mock.add(b.inventory,Mock.food(5))
    R.Start();check(not R.operational);R.Tick();Mock.clock=101;R.Tick();near(f:getAge(),5+1/24)
    R.NormalTick();check(not R.operational);Mock.clock=102;R.Tick();R.NormalTick();check(R.operational)
    near(f:getAge(),5+2/24);check(R.timeline.segments[1].enabled==false);tick(1);near(f:getAge(),5+2/24-0.5)
end)
test("fresh-life rate and double precision",function()
    local b,f=Mock.setup(10000000,99999999,99999999)
    SandboxVars.SuQingFreshnessLunchbox.RestoreHours=1000;R.Tick()
    local initial=f:getAge();for i=1,3600 do tick(1/3600000) end
    check(f:getAge()<initial,"float32 stalled");near(C.FoodRecord(f).logicalAge,initial-99.999999,0.0001)
    check(not C.FoodRecord(f).externalEdit);check(C.ownAgeWrites[f]==nil)
end)
test("72 identical foods are independently anchored and settled",function()
    local b,f=Mock.setup(3);local foods={f}
    for i=2,72 do foods[i]=Mock.add(b.inventory,Mock.food(3)) end
    R.Tick();tick(1)
    for i=1,72 do near(foods[i]:getAge(),2.5);check(C.FoodRecord(foods[i]).id==tostring(foods[i]:getID())) end
end)
test("different foods retain native fresh-life rates",function()
    local b,f=Mock.setup(3,2,4);local g=Mock.add(b.inventory,Mock.food(3,4,7));R.Tick();tick(0.25)
    near(f:getAge(),2.95);near(g:getAge(),2.9)
end)
test("nested containers process direct foods exactly once",function()
    local b,f=Mock.setup(3);local inner=Mock.add(b.inventory,Mock.box());local g=Mock.add(inner.inventory,Mock.food(3))
    local ordinary=Mock.add(b.inventory,Mock.box("Base.Bag"));local h=Mock.add(ordinary.inventory,Mock.food(3))
    R.ScanPlayers();tick(1);near(f:getAge(),2.5);near(g:getAge(),2.5);near(h:getAge(),3);check(C.FoodRecord(h)==nil)
end)
test("new food cannot receive old elapsed time",function()
    local b,f=Mock.setup(3);tick(2);local g=Mock.add(b.inventory,Mock.food(3));R.Tick()
    near(f:getAge(),2);near(g:getAge(),3);tick(1);near(f:getAge(),1.5);near(g:getAge(),2.5)
end)
test("food transfer resets ownership; whole box transfer preserves progress",function()
    local b,f,s,p=Mock.setup(3);tick(1)
    local other=Mock.add(p.inventory,Mock.box());R.Register(other)
    local a,x,y,z=ISTransferAction.transferItem({},p,f,b.inventory,other.inventory)
    check(a==f and x=="second" and y==nil and z==4,"transfer returns preserved")
    tick(1);near(f:getAge(),2);check(C.FoodRecord(f).boxId==C.BoxState(other).id)
    local cabinet=Mock.furniture(s);ISTransferAction.transferItem({},p,other,p.inventory,cabinet.inventory)
    tick(1);near(f:getAge(),1.5);check(R.Location(other)=="furniture")
    ISTransferAction.transferItem({},p,f,other.inventory,p.inventory);check(C.FoodRecord(f)==nil)
end)
test("hand carry backpack ground furniture vehicle discovery",function()
    local b,f,s,p=Mock.setup(5);check(R.Location(b)=="character")
    local bag=Mock.add(p.inventory,Mock.box("Base.Bag"));ISTransferAction.transferItem({},p,b,p.inventory,bag.inventory)
    tick(1);near(f:getAge(),4.5);check(R.Location(b)=="character")
    Mock.ground(b,s);R.ScanSquare(s);tick(1);near(f:getAge(),4);check(R.Location(b)=="ground")
    local cabinet=Mock.furniture(s);Mock.add(cabinet.inventory,b);R.ScanSquare(s);tick(1);near(f:getAge(),3.5)
    local v,part=Mock.vehicle(s);Mock.add(part.inventory,b);R.ScanVehicles();tick(1);near(f:getAge(),3);check(R.Location(b)=="vehicle")
end)
test("unloaded same box catches proven active time after native aging",function()
    local b,f,s=Mock.setup(5);tick(1);Mock.grid[s.x]=nil;R.Tick();check(R.boxes[b]==nil)
    tick(5);f:updateAge(false);check(f:getAge()>4.5);check(not C.FoodRecord(f).externalEdit)
    Mock.grid[s.x]=s;R.ScanSquare(s);R.ScanPlayers();near(f:getAge(),2);check(C.FoodRecord(f).time==Mock.clock)
end)
test("external Lua Age edits survive unload reload",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick();tick(5)
    f:setAge(9);check(C.FoodRecord(f).externalEdit);f:setLastAged(Mock.clock)
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),9);tick(1);near(f:getAge(),8.5)
end)
test("uncertain whole-box ownership cannot earn elapsed credit",function()
    local b,f,s,p=Mock.setup(5);p.inventory.items:remove(b);b.container=nil;R.Tick()
    check(C.FoodRecord(f).ownershipUncertain);tick(5);Mock.add(p.inventory,b);R.ScanPlayers()
    near(f:getAge(),5+5/24);check(not C.FoodRecord(f).ownershipUncertain);tick(1);near(f:getAge(),5+5/24-0.5)
end)
test("hook chain changes disable native reconciliation",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick();tick(5);f:updateAge()
    local previous=Mock.foodIndex.setAge;Mock.foodIndex.setAge=function(food,age) return previous(food,age) end
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),5+5/24,0.00001)
    Mock.foodIndex.setAge=previous;check(C.AgeHookReady())
end)
test("manual off and resumed operation never erase ordinary aging",function()
    local b,f=Mock.setup(5);tick(1);check(R.Toggle(b));check(not C.BoxState(b).on)
    tick(24);near(f:getAge(),5.5);check(R.Toggle(b));near(f:getAge(),5.5);tick(1);near(f:getAge(),5)
end)
test("global disabled time does not earn unloaded catchup",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick()
    SandboxVars.SuQingFreshnessLunchbox.Enabled=false;R.Tick();tick(24)
    SandboxVars.SuQingFreshnessLunchbox.Enabled=true;R.Tick();tick(1)
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),5+25/24,0.00001);tick(1);near(f:getAge(),5+25/24-0.5,0.00001)
end)
test("save restart with equal game time keeps accumulated precision",function()
    local b,f=Mock.setup(5);tick(0.25);local logical=C.FoodRecord(f).logicalAge
    R.Save();R.Stop();R.Start();near(C.FoodRecord(f).logicalAge,logical,0.0000001);tick(0.25);near(f:getAge(),4.75)
end)
test("mod absent gameplay gap is not backdated",function()
    local b,f=Mock.setup(5);tick(1);R.Save();R.Stop();Mock.clock=Mock.clock+24;R.Start()
    near(f:getAge(),5.5);tick(1);near(f:getAge(),5)
end)
test("session starts do not credit real world offline duration",function()
    local b,f=Mock.setup(5);R.Save();R.Stop();R.Start();near(f:getAge(),5);check(C.FoodRecord(f).time==100)
end)
test("rate changes integrate only observed complete intervals",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick();tick(2)
    SandboxVars.SuQingFreshnessLunchbox.RestoreHours=5;R.Tick();tick(2)
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),2)
end)
test("unknown config-change interval is conservative",function()
    local b,f=Mock.setup(5);Mock.clock=102;SandboxVars.SuQingFreshnessLunchbox.RestoreHours=5;R.Tick()
    near(f:getAge(),5+2/24);tick(1);near(f:getAge(),5+2/24-1)
end)
test("pause consumes no restoration time",function()
    local b,f=Mock.setup(5);Mock.paused=true;R.Tick();R.Tick();near(f:getAge(),5)
    Mock.paused=false;R.Tick();tick(1);near(f:getAge(),4.5)
end)
test("history is bounded; expired history cannot award old progress",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick()
    for i=1,150 do SandboxVars.SuQingFreshnessLunchbox.RestoreHours=5+i%2;tick(1) end
    check(#R.timeline.segments<=C.historyLimit);check(R.timeline.truncated)
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),5+150/24,0.00001)
end)
test("replacement guard retains true rotten Age through save and restores on exit",function()
    local b,f=Mock.setup(15,5,10,"Base.Compost");check(f:getReplaceOnRotten()=="");check(f:isRotten());near(f:getAge(),15)
    R.Save();check(f:getReplaceOnRotten()=="");check(f:isRotten());R.Toggle(b);check(f:getReplaceOnRotten()=="Base.Compost");check(f:isRotten())
end)
test("replacement restore respects external Age and replacement edits",function()
    local b,f=Mock.setup(15,5,10,"Base.Compost");f:setAge(20);check(C.RestoreFood(f));near(f:getAge(),20);check(f.replacement=="Base.Compost")
    R.Tick();f:setReplaceOnRotten("Other.Rule");check(not C.RestoreFood(f));check(f.replacement=="Other.Rule")
end)
test("enabled or unknown native removal refuses rotten restoration without fake Age",function()
    local b,f=Mock.setup(15,5,10,"Base.Compost");SandboxVars.DaysForRottenFoodRemoval=0;R.Tick()
    check(not C.FoodRecord(f).active);check(f.replacement=="Base.Compost");near(f:getAge(),15);check(f:isRotten())
    SandboxVars.DaysForRottenFoodRemoval=nil;R.Tick();check(not C.FoodRecord(f).active);near(f:getAge(),15)
end)
test("burnt fertilized infinite unknown schema and ordinary food are preserved",function()
    local b,f=Mock.setup(3);f.burnt=true;tick(1);near(f:getAge(),3+1/24);check(not C.FoodRecord(f).active)
    f.burnt=false;f.fertilized=true;tick(1);check(not C.FoodRecord(f).active)
    local g=Mock.add(b.inventory,Mock.food(3,100000000,100000000));R.Tick();check(not C.FoodRecord(g).active)
    local h=Mock.add(b.inventory,Mock.food(3));h.md[C.foodKey]={schema=99,custom=true};R.Tick();check(h.md[C.foodKey].custom)
    local ordinary=Mock.food(3);ordinary:setAge(4);check(ordinary.md[C.foodKey]==nil)
end)
test("cooking threshold edits reanchor without history",function()
    local b,f,s=Mock.setup(5);Mock.grid[s.x]=nil;R.Tick();tick(2);f.cooked=true;f.fresh=8;f.rotten=12
    Mock.grid[s.x]=s;R.ScanPlayers();near(f:getAge(),5+2/24);tick(1);near(f:getAge(),5+2/24-0.8)
end)
test("failed transfer restores valid guard and propagates error",function()
    local b,f,s,p=Mock.setup(15,5,10,"Base.Compost")
    local ok=pcall(function() ISTransferAction.transferItem({fail=true},p,f,b.inventory,p.inventory) end)
    check(not ok);check(f.container==b.inventory);check(f.replacement=="");check(C.FoodRecord(f).shield~=nil)
end)
test("setter exceptions cannot leak internal scope",function()
    local b,f=Mock.setup(3);f.failWrite=true
    local ok=pcall(function() C.WriteAge(f,2) end);check(not ok);check(C.ownAgeWrites[f]==nil)
    f.failWrite=false;f:setAge(4);check(C.FoodRecord(f).externalEdit)
end)
test("clock rollback resets generation and anchors",function()
    local b,f=Mock.setup(3);R.Save();R.Stop();Mock.clock=90;R.Start();check(R.timeline.generation==2);near(f:getAge(),3)
end)
test("loaded-world fallback is single attempt and errors remain stopped",function()
    local b,f=Mock.setup(3);R.Stop();MainScreen={instance={inGame=false}};R.NormalTick();check(not R.ready)
    MainScreen.instance.inGame=true;R.NormalTick();check(R.ready);check(R.operational);check(R.fallbackTried)
    R.Stop();local prior=ModData.getOrCreate;local calls=0
    ModData.getOrCreate=function()calls=calls+1;error('deliberate fallback failure')end
    for _,callback in ipairs(Events.OnTick.callbacks)do callback()end
    check(R.failed);check(R.status=='error');check(not R.operational);local errors=R.stats.errors
    for i=1,3 do for _,callback in ipairs(Events.OnTick.callbacks)do callback()end end
    check(calls==1);check(R.stats.errors==errors);ModData.getOrCreate=prior;R.Stop();MainScreen=nil
end)

local function measureLoadedBox(count)
    Mock.reset()
    local player = Mock.player(Mock.square(1))
    local box = Mock.add(player.inventory, Mock.box())
    R.Start()
    R.NormalTick()
    R.NormalTick()
    for i = 1, C.historyLimit do
        Mock.clock = Mock.clock + 0.125
        R.Observe()
        SandboxVars.SuQingFreshnessLunchbox.RestoreHours = 10 + i % 2
        R.Observe()
    end
    check(#R.timeline.segments == 128 and R.timeline.truncated, "expected a full save history")

    local foods = {}
    for i = 1, count do
        local food = Mock.add(box.inventory, Mock.food(3))
        Mock.process:add(food)
        foods[i] = food
    end
    R.Tick()

    local validationCalls, segmentVisits, memberComparisons = 0, 0, 0
    local list = box.inventory.items
    local contains = list.contains
    list.contains = function(self, item)
        for _, member in ipairs(self.items) do
            memberComparisons = memberComparisons + 1
            if member == item then return true end
        end
        return false
    end
    local validate = C.ValidTimeline
    C.ValidTimeline = function(timeline)
        validationCalls = validationCalls + 1
        return validate(timeline)
    end
    local segments = R.timeline.segments
    local iter = ipairs
    ipairs = function(values)
        local nextValue, state, index = iter(values)
        if values ~= segments then return nextValue, state, index end
        return function(sequence, key)
            local nextKey, value = nextValue(sequence, key)
            if nextKey ~= nil then segmentVisits = segmentVisits + 1 end
            return nextKey, value
        end, state, index
    end

    local ok, message = pcall(tick, 0.25)
    ipairs = iter
    C.ValidTimeline = validate
    list.contains = contains
    if not ok then error(message) end

    for _, food in ipairs(foods) do
        near(food:getAge(), 2.875)
        check(C.FoodRecord(food).time == Mock.clock, "every tracked food was settled")
    end
    print("LUNCHBOX_TICK_OPS foods="..count.." validations="..validationCalls
        .." segmentVisits="..segmentVisits.." memberComparisons="..memberComparisons)
    return {validations=validationCalls, segments=segmentVisits, comparisons=memberComparisons}
end

test("steady loaded-box work scales with history plus item count",function()
    local low = measureLoadedBox(32)
    local high = measureLoadedBox(64)
    for _, sample in ipairs({low, high}) do
        check(sample.validations <= 2, "whole history must be validated at most twice per tick")
        check(sample.segments <= 2 * C.historyLimit, "each food must avoid rescanning the history prefix")
    end
    check(low.comparisons <= 64 and high.comparisons <= 128, "each food must avoid a linear list lookup")
end)

test("unchanged clock skips writes without missing an external age edit or a new food",function()
    local box, food = Mock.setup(3)
    tick(0.25)
    local ageWrites, lastAgedWrites = 0, 0
    local setAge, setLastAged = food.setAge, food.setLastAged
    food.setAge = function(self, age)
        ageWrites = ageWrites + 1
        return setAge(self, age)
    end
    food.setLastAged = function(self, time)
        lastAgedWrites = lastAgedWrites + 1
        return setLastAged(self, time)
    end
    local record = C.FoodRecord(food)
    R.Tick()
    check(ageWrites == 0 and lastAgedWrites == 0, "no setters at the same clock")
    check(C.FoodRecord(food) == record, "no replacement receipt at the same clock")
    near(food:getAge(), 2.875)

    Mock.paused = true
    R.Tick()
    ageWrites, lastAgedWrites = 0, 0
    record = C.FoodRecord(food)
    R.Tick()
    check(ageWrites == 0 and lastAgedWrites == 0, "steady pause does not write")
    check(C.FoodRecord(food) == record, "steady pause retains the receipt")
    near(food:getAge(), 2.875)

    food:setAge(7)
    local added = Mock.add(box.inventory, Mock.food(3))
    R.Tick()
    near(food:getAge(), 7)
    near(C.FoodRecord(food).logicalAge, 7)
    check(C.FoodRecord(added).time == Mock.clock, "new food anchored while the clock was stopped")
    Mock.paused = false
    R.Tick()
    tick(0.25)
    near(food:getAge(), 6.875)
    near(added:getAge(), 2.875)
end)

test("reentrant native container update never applies old box age to moved food",function()
    local box, first, _, player = Mock.setup(3)
    local moved = Mock.add(box.inventory, Mock.food(3))
    local remains = Mock.add(box.inventory, Mock.food(3))
    local list = box.inventory.items
    local get = list.get
    list.get = function(self, index)
        if index < 0 or index >= self:size() then error("container index out of bounds") end
        return get(self, index)
    end
    R.Tick()
    local movedStamp = moved:getLastAged()
    local updateAge = first.updateAge
    local callbacks = 0
    first.updateAge = function(self, ...)
        updateAge(self, ...)
        Mock.add(player.inventory, self)
        Mock.add(player.inventory, moved)
        for _, callback in ipairs(Events.OnContainerUpdate.callbacks) do
            callback(self)
            callbacks = callbacks + 1
        end
    end
    first:setAge(4)
    tick(0.25)
    first.updateAge = updateAge
    check(callbacks > 0, "native update synchronously notified Lua")
    check(first:getContainer() == player.inventory, "settling food moved during the native call")
    check(moved:getContainer() == player.inventory, "food moved during settlement")
    near(first:getAge(), 4 + 0.25 / 24)
    check(C.FoodRecord(first) == nil, "settling food did not receive an old-box receipt")
    near(moved:getAge(), 3)
    check(moved:getLastAged() == movedStamp, "old box did not stamp moved food")
    near(remains:getAge(), 2.875)
    check(C.FoodRecord(remains).boxId == C.BoxState(box).id, "shifted food kept its ownership")
    R.Tick()
    check(C.FoodRecord(moved) == nil, "stale ownership removed on next tick")

    ISTransferAction.transferItem({}, player, moved, player.inventory, box.inventory)
    local transferredAge = moved:getAge()
    check(C.FoodRecord(moved).time == Mock.clock, "returning food reanchored")
    tick(0.25)
    near(moved:getAge(), transferredAge - 0.125)
end)

print("RUNTIME_MOCK cases="..cases.." assertions="..assertions.." PASS")
