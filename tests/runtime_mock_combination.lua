-- Executes current installed refrigeration/fridge Lua and the new runtime
-- together; only the native room/power ownership objects are modeled.
local C=SuQingFreshnessLunchbox;local R=C.Runtime
local F=SuQingFreshnessFridge;local FR=F.Runtime
local cold=SuQingRefrigeration;local CR=cold.Runtime
local cases,assertions=0,0
local function check(ok,label) assertions=assertions+1;if not ok then error(label or "combination check failed") end end
local function near(a,b) check(math.abs(a-b)<0.00002,"combination age "..a.."/"..b) end
local function test(name,fn) cases=cases+1;fn();print("COMBINATION_CASE "..name.." PASS") end
F.Capacity={Install=function() return true end,IsReady=function() return true end}
SandboxVars.SuQingRefrigeration={Enabled=true,RotSpeedPercent=20}
SandboxVars.SuQingFreshnessFridge={Enabled=true,Capacity=200,RestoreHours=10,AllowRotten=true}
Mock.reset();local square=Mock.square(1);local player=Mock.player(square)
local fridge=Mock.furniture(square);fridge.md={};fridge.inventory.type="fridge"
function fridge:getSprite() return {getName=function() return "suqing_freshness_fridge_01_0" end} end
function fridge:getModData() return self.md end
function fridge.inventory:isPowered() return true end
local box=Mock.add(player.inventory,Mock.box());local food=Mock.add(box.inventory,Mock.food(5))
test("startup captures supported existing transfer wrappers after listeners",function()
    check(R.Start());CR.Start();FR.Start();check(CR.ready and FR.ready)
    local prior=ISTransferAction.transferItem;check(prior==FR.transferWrapper)
    R.NormalTick();R.NormalTick();R.Tick();check(R.ready);check(R.transfer.prior==prior);check(ISTransferAction.transferItem==R.transfer.wrapper)
end)
test("single food transfers hand off one owner through all three runtimes",function()
    Mock.clock=100.1;R.Tick();near(food:getAge(),4.95)
    ISTransferAction.transferItem({},player,food,box.inventory,fridge.inventory)
    check(C.FoodRecord(food)==nil);check(F.FoodRecord(food)~=nil)
    -- The existing fridge deliberately anchors its first observed world pass.
    FR.PreTick();FR.PostTick()
    Mock.clock=100.2;FR.PreTick();FR.PostTick();near(food:getAge(),4.9)
    ISTransferAction.transferItem({},player,food,fridge.inventory,box.inventory)
    check(F.FoodRecord(food)==nil);check(C.FoodRecord(food)~=nil)
    Mock.clock=100.3;R.Tick();near(food:getAge(),4.85)
end)
test("whole lunchbox in the old fridge is not processed a second time",function()
    ISTransferAction.transferItem({},player,box,player.inventory,fridge.inventory)
    Mock.clock=100.4;R.Tick();FR.PreTick();FR.PostTick();near(food:getAge(),4.8)
    check(F.FoodRecord(food)==nil);check(C.FoodRecord(food)~=nil);check(C.FoodRecord(food).boxId==C.BoxState(box).id)
end)
test("main menu save reload preserves the established transfer chain",function()
    R.Save();R.Stop();FR.Stop();CR.ready=false
    R.ScanSquare(square) -- loaded-square event queues discovery before OnGameStart
    check(R.Start());CR.Start();FR.Start();R.Tick();check(R.ready and CR.ready and FR.ready)
    near(food:getAge(),4.8);Mock.clock=100.5;R.Tick();near(food:getAge(),4.75)
    check(R.stats.errors==0);check(CR.stats.errors==0);check(FR.stats.errors==0)
end)
print("RUNTIME_COMBINATION_MOCK cases="..cases.." assertions="..assertions.." PASS")
