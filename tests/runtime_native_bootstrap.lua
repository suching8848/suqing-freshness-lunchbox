-- Keep only actual native inventory/time/exposed-method objects; fake event bus.
function require() end
function isClient() return false end
function isServer() return false end
function isGamePaused() return false end
function getTimestampMs() return 1106000000 end
function getNumActivePlayers() return 0 end
function getSpecificPlayer() return nil end
function getCell() return nil end
print=ProbePrint
Events={}
for _,key in ipairs({"OnGameStart","OnTick","OnTickEvenPaused","LoadGridsquare","OnSave","OnMainMenuEnter","OnContainerUpdate"}) do
    Events[key]={Add=function() end}
end
ISTransferAction={transferItem=function(self,character,item) return item end}
local globals={}
ModData={getOrCreate=function(key) if not globals[key] then globals[key]={} end return globals[key] end}
SandboxVars={DaysForRottenFoodRemoval=-1,FoodRotSpeed=3,
    SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true},
    SuQingRefrigeration={Enabled=true,RotSpeedPercent=20}}
Native={cases=0,assertions=0}
function Native.check(ok,message) Native.assertions=Native.assertions+1;if not ok then error(message or "native check failed") end end
function Native.near(a,b,t,message) Native.check(math.abs(a-b)<(t or 0.00001),(message or "native mismatch")..": "..tostring(a).." vs "..tostring(b)) end
function Native.test(name,fn) Native.cases=Native.cases+1;fn();print("NATIVE_CASE "..name.." PASS") end
function Native.now() return getGameTime():getWorldAgeHours() end
function Native.advance(hours) ProbeTime:setTimeOfDay(ProbeTime:getTimeOfDay()+hours);return Native.now() end
function Native.setup(age,fresh,rotten,replacement)
    local C=SuQingFreshnessLunchbox
    SandboxVars.DaysForRottenFoodRemoval=-1;SandboxVars.SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}
    local box=ProbeMakeBox();local food=ProbeMakeFood(age or 3,fresh or 5,rotten or 10,replacement)
    box:getInventory():AddItem(food);C.EnsureBox(box)
    local t={};local session=C.OpenTimeline(t,Native.now(),C.Config(),false)
    C.SettleFood(food,box,Native.now(),t,false)
    return box,food,t,session
end
function Native.settle(box,food,t,session,hours)
    local now=Native.advance(hours)
    local C=SuQingFreshnessLunchbox
    Native.check(C.ObserveTimeline(t,session,now,C.Config(),false))
    return C.SettleFood(food,box,now,t,false)
end
