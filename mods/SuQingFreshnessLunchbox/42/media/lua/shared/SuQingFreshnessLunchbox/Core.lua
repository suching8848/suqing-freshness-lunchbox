-- Independent portable lunchbox. Only this module's two ModData keys are owned.
SuQingFreshnessLunchbox=SuQingFreshnessLunchbox or {}
local C=SuQingFreshnessLunchbox
if C.coreLoaded then return C end
C.coreLoaded=true
C.version="0.2.0-rc.4"
C.FullType="SuQingFreshnessLunchbox.FreshnessLunchbox"
C.boxKey="SuQingFreshnessLunchbox"
C.foodKey="SuQingFreshnessLunchboxFood"
C.timelineKey="SuQingFreshnessLunchboxTimeline"
C.historyLimit=128
C.ownAgeWrites=setmetatable({}, {__mode="k"})
C.coolingWrites=setmetatable({}, {__mode="k"})
C.pending=setmetatable({}, {__mode="k"})
local observed=setmetatable({}, {__mode="v"})

function C.Finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function number(value,default,low,high)
    if not C.Finite(value) then value=default end
    return math.max(low,math.min(high,value))
end
function C.Config()
    local s=SandboxVars and SandboxVars.SuQingFreshnessLunchbox or {}
    return {enabled=s.Enabled~=false,baseCapacity=math.floor(number(s.BaseCapacity,4,1,30)),
        restoreHours=number(s.RestoreHours,10,0.25,1000),allowRotten=s.AllowRotten~=false}
end
function C.SP()
    return not(type(isClient)=="function" and isClient())
        and not(type(isServer)=="function" and isServer())
end
function C.IsBox(item)
    return item and type(instanceof)=="function" and instanceof(item,"InventoryContainer")
        and item:getFullType()==C.FullType and item:getInventory()~=nil or false
end
function C.GetInventory(item) return C.IsBox(item) and item:getInventory() or nil end
function C.BoxState(item)
    if not C.IsBox(item) then return nil end
    local s=item:getModData()[C.boxKey]
    if type(s)~="table" or s.schema~=1 or type(s.id)~="string" or s.id==""
        or type(s.on)~="boolean" or not C.Finite(s.epoch) or s.epoch<0 or s.epoch~=math.floor(s.epoch)
        or not C.Finite(s.baseCapacity) or s.baseCapacity<1 or s.baseCapacity>30
        or s.baseCapacity~=math.floor(s.baseCapacity) then return nil end
    return s
end
function C.EnsureBox(item)
    if not C.IsBox(item) then return nil,"not_box" end
    local md=item:getModData()
    if md[C.boxKey]~=nil then return C.BoxState(item),"existing" end
    -- Missing initialization is not permission to overwrite a paid upgrade.
    if md.SuQingContainerUpgrade or md.SuQingContainerUpgradeAuto or md.ExSuQingBackpackSuperUpgrade then
        return nil,"initialization_missing_with_upgrade"
    end
    local capacity=C.Config().baseCapacity
    local inventory=item:getInventory()
    local old=inventory:getCapacity()
    local ok,message=pcall(function()
        item:setCapacity(capacity)
        if inventory:getCapacity()~=capacity then error("initial capacity was not retained") end
    end)
    if not ok then
        local restored,restoreError=pcall(function() item:setCapacity(old) end)
        if not restored then error("lunchbox capacity rollback failed: "..tostring(restoreError)) end
        error(message)
    end
    C.serial=(C.serial or 0)+1
    local stamp=type(getTimestampMs)=="function" and getTimestampMs() or 0
    local id=item.getID and tostring(item:getID()) or "unknown"
    local state={schema=1,id="SFL:"..tostring(stamp)..":"..id..":"..C.serial,
        on=true,epoch=0,baseCapacity=capacity}
    md[C.boxKey]=state
    C.pending[item]=true
    return state,"created"
end
function C.IsFood(food)
    return food and type(instanceof)=="function" and instanceof(food,"Food") or false
end
function C.IsDirectFood(food,box,listedIndex)
    local inventory=C.GetInventory(box)
    if not C.IsFood(food) or not inventory or food:getContainer()~=inventory then return false end
    local items=inventory:getItems()
    -- A hint comes from a real list enumeration, and is never an ownership cache.
    if listedIndex~=nil and listedIndex>=0 and listedIndex<items:size() and items:get(listedIndex)==food then
        return true
    end
    return items:contains(food)
end
function C.Identity(food)
    return food.getID and tostring(food:getID()) or "unknown",food:getFullType()
end
function C.FoodRecord(food)
    if not C.IsFood(food) then return nil end
    local r=food:getModData()[C.foodKey]
    return type(r)=="table" and r.schema==1 and r or nil
end
function C.Eligible(food,config)
    if not C.IsFood(food) then return nil,"not_food" end
    if food.isBurnt and food:isBurnt() then return nil,"burnt" end
    if food.isFertilized and food:isFertilized() then return nil,"fertilized" end
    local fresh,rotten,age=food:getOffAge(),food:getOffAgeMax(),food:getAge()
    if not C.Finite(fresh) or fresh<=0 or fresh>=100000000 or not C.Finite(rotten)
        or rotten<fresh or rotten>=100000000 or not C.Finite(age) or age<0 then return nil,"unsupported_age" end
    if config and not config.allowRotten and age>=rotten then return nil,"rotten_disabled" end
    return fresh,rotten
end
function C.RemovalPolicy()
    local n=SandboxVars and SandboxVars.DaysForRottenFoodRemoval
    return C.Finite(n) and n or nil
end
local function policyReason(food,fresh,rotten)
    if not fresh then return rotten end
    local removal=C.RemovalPolicy()
    if food:getAge()>=rotten and (not removal or removal>=0) then return "native_removal_policy" end
    return nil
end
function C.PolicyReason(food,config)
    local fresh,rotten=C.Eligible(food,config or C.Config())
    return policyReason(food,fresh,rotten)
end
local function signature(food,fresh,rotten)
    return food:getFullType()..":"..tostring(fresh)..":"..tostring(rotten)..":"
        ..tostring(food.isCooked and food:isCooked() or false)
end

-- Preserve the complete preceding setter chain. Only already-owned food records
-- receive an external-edit marker. Native Java updateAge does not call this Lua slot.
function C.InstallAgeHook()
    if C.ageHook then return C.AgeHookReady(),"existing" end
    local meta=__classmetatables and Food and Food.class and __classmetatables[Food.class]
    local index=meta and meta.__index
    if type(index)~="table" or type(index.setAge)~="function" then return false,"age_setter_unavailable" end
    local prior=index.setAge
    local wrapper=function(food,value,...)
        local record=C.FoodRecord(food)
        if record and not C.ownAgeWrites[food] then
            local id,fullType=C.Identity(food)
            if record.id==id and record.fullType==fullType and not C.IsKnownCoolingWrite(food,value,record) then
                record.externalEdit=true
            end
        end
        return prior(food,value,...)
    end
    C.ageHook={index=index,prior=prior,wrapper=wrapper}
    index.setAge=wrapper
    return true
end
function C.AgeHookReady()
    return C.ageHook~=nil and C.ageHook.index.setAge==C.ageHook.wrapper or false
end
function C.WriteAge(food,age)
    local previous=C.ownAgeWrites[food]
    C.ownAgeWrites[food]=true
    local ok,message=pcall(function() food:setAge(age) end)
    C.ownAgeWrites[food]=previous
    if not ok then error(message) end
end

-- The audited optional refrigeration mod uses Lua setAge even when applying
-- ordinary forward aging. Its exact supported version and captured hook slots
-- delimit this narrow scope; unrelated setters still mark an external edit.
local function supportedCoolingVersion(version)
    return version=="1.0.0-rc.2-perf.1" or version=="1.0.0-rc.2-perf.2"
        or version=="1.0.0-rc.2-perf.3" or version=="1.0.0-rc.2-perf.4"
        or version=="1.0.0-rc.2-perf.5" or version=="1.0.0-rc.2-perf.6"
        or version=="1.0.0-rc.2-perf.7" or version=="1.0.0-rc.2-perf.8"
end
function C.CoolingBridgeReady()
    local b=C.coolingBridge
    if not b then return false end
    local cold=SuQingRefrigeration
    local r=cold and cold.Runtime
    return cold==b.core and supportedCoolingVersion(cold.version) and r==b.runtime
        and r.Settle==b.wrapper and r.ready==true and r.hooksInstalled==true
        and b.index.updateAge==r.ageWrapper and r.ageWrapper==b.ageWrapper
        and r.nativeAge==b.nativeAge and C.AgeHookReady() or false
end
function C.IsKnownCoolingWrite(food,value,record)
    local scope=C.coolingWrites[food]
    return scope~=nil and scope.record==record and C.CoolingBridgeReady()
        and C.coolingBridge.runtime.busy[food]==true
        and C.Finite(value) and value>=scope.entryAge and value<=food:getAge()
        and C.IsDirectFood(food,scope.box) or false
end
local function pack(...) return {n=select("#",...),...} end
function C.InstallCoolingBridge()
    if C.coolingBridge then return C.CoolingBridgeReady(),"existing" end
    local cold=SuQingRefrigeration
    local r=cold and cold.Runtime
    if not cold or not r then return false,"absent" end
    if not supportedCoolingVersion(cold.version) or type(r.Settle)~="function" or type(r.Cooling)~="function"
        or type(r.SyncConfig)~="function" or type(r.Integral)~="function" or type(r.busy)~="table" then
        return false,"unsupported_cooling_version"
    end
    local meta=__classmetatables and Food and Food.class and __classmetatables[Food.class]
    local index=meta and meta.__index
    if type(index)~="table" then return false,"missing_age_index" end
    local b={core=cold,runtime=r,index=index,prior=r.Settle}
    local wrapper=function(food,time,...)
        if not C.IsFood(food) then return b.prior(food,time,...) end
        -- Start may install the existing age hook after this bridge. Capture
        -- those slots only once, then fail closed if any participating chain moves.
        if not b.ageWrapper and r.ready and r.hooksInstalled and index.updateAge==r.ageWrapper then
            b.ageWrapper=r.ageWrapper;b.nativeAge=r.nativeAge
        end
        local record=C.FoodRecord(food)
        -- Ordinary cold-bag food has no lunchbox record and needs no write
        -- scope. Delegate without container checks or a protected result table;
        -- any enclosing scope is left untouched, including on errors.
        if not record or not record.active or r.busy[food] then
            return b.prior(food,time,...)
        end
        local inventory=food:getContainer()
        local box=inventory and inventory.getContainingItem and inventory:getContainingItem()
        local state=C.BoxState(box)
        if not state or not C.CoolingBridgeReady() or not C.IsDirectFood(food,box)
            or record.boxId~=state.id or record.boxItemId~=tostring(box:getID()) then
            return b.prior(food,time,...)
        end
        local previous=C.coolingWrites[food]
        C.coolingWrites[food]={record=record,box=box,entryAge=food:getAge()}
        local result=pack(pcall(b.prior,food,time,...))
        C.coolingWrites[food]=previous
        if not result[1] then error(result[2]) end
        return unpack(result,2,result.n)
    end
    b.wrapper=wrapper;C.coolingBridge=b;r.Settle=wrapper
    return true,"installed"
end

function C.RestoreFood(food)
    local r=C.FoodRecord(food)
    local s=r and r.shield
    if type(s)~="table" then return false,"no_shield" end
    r.shield=nil
    local id,fullType=C.Identity(food)
    if s.id~=id or s.fullType~=fullType then return false,"identity_changed" end
    if s.mode~="replacement" or type(s.original)~="string" or s.original=="" then return false,"invalid_shield" end
    if not food.getReplaceOnRotten or not food.setReplaceOnRotten then return false,"missing_replacement_api" end
    if food:getReplaceOnRotten()~="" then return false,"external_replacement_edit" end
    food:setReplaceOnRotten(s.original)
    if C.onRestoreFood then C.onRestoreFood(food) end
    return true,"restored"
end
function C.ClearFood(food)
    local record=C.FoodRecord(food)
    if not record then return end
    local md=food:getModData()
    C.RestoreFood(food)
    -- Restoring the native rule can call back into the transfer chain.
    if md[C.foodKey]==record then md[C.foodKey]=nil end
end
function C.ProtectFood(food,box,listedIndex)
    if not C.IsDirectFood(food,box,listedIndex) then return false end
    local r=C.FoodRecord(food)
    local state=C.BoxState(box)
    if not r or not r.active or not state or not state.on then return false end
    local fresh,rotten=C.Eligible(food,C.Config())
    if not fresh or food:getAge()<rotten then return false end
    local removal=C.RemovalPolicy()
    if not removal or removal>=0 then return false end
    if r.shield then return r.shield.mode=="replacement" end
    local replacement=food.getReplaceOnRotten and food:getReplaceOnRotten() or nil
    if type(replacement)~="string" or replacement=="" or not food.setReplaceOnRotten then return false end
    local id,fullType=C.Identity(food)
    r.shield={mode="replacement",id=id,fullType=fullType,original=replacement}
    food:setReplaceOnRotten("")
    return true
end

local function segmentConfig(config,paused)
    local removal=C.RemovalPolicy()
    return {enabled=config.enabled and not paused,restoreHours=config.restoreHours,
        allowRotten=config.allowRotten,removal=removal or "unknown"}
end
local function sameConfig(a,b)
    return a.enabled==b.enabled and a.restoreHours==b.restoreHours
        and a.allowRotten==b.allowRotten and a.removal==b.removal
end
local function validSegment(s)
    return type(s)=="table" and C.Finite(s.from) and C.Finite(s.to) and s.to>=s.from
        and type(s.enabled)=="boolean" and type(s.allowRotten)=="boolean"
        and C.Finite(s.restoreHours) and s.restoreHours>=0.25 and s.restoreHours<=1000
        and (s.removal=="unknown" or C.Finite(s.removal))
end
function C.ValidTimeline(t)
    if type(t)~="table" or t.schema~=1 or type(t.segments)~="table"
        or not C.Finite(t.generation) or t.generation<1 then return false end
    local endTime
    for _,s in ipairs(t.segments) do
        if not validSegment(s) or (endTime and s.from<endTime) then return false end
        endTime=s.to
    end
    return true
end
local function appendSegment(t,session,time,config,paused)
    local s=segmentConfig(config,paused)
    s.from=time;s.to=time;s.session=session
    t.segments[#t.segments+1]=s
    while #t.segments>C.historyLimit do table.remove(t.segments,1);t.truncated=true end
    t.current=#t.segments;t.session=session;t.lastTime=time
    t.floor=t.segments[1].from
    return s
end
function C.OpenTimeline(t,time,config,paused)
    observed[1]=nil
    if not C.Finite(time) then return nil,"invalid_clock" end
    local empty=true
    for _ in pairs(t) do empty=false;break end
    if t.schema==nil and empty then t.schema=1;t.generation=1;t.segments={};t.serial=0 end
    if not C.ValidTimeline(t) then return nil,"invalid_timeline" end
    local last=t.segments[#t.segments]
    if last and time<last.to then
        t.generation=t.generation+1;t.segments={};t.truncated=true
    end
    t.serial=(C.Finite(t.serial) and t.serial or 0)+1
    local session="session:"..tostring(t.serial)..":"..tostring(type(getTimestampMs)=="function" and getTimestampMs() or 0)
    appendSegment(t,session,time,config or C.Config(),paused)
    return session
end
function C.ObserveTimeline(t,session,time,config,paused,wantContext)
    observed[1]=nil
    if not C.ValidTimeline(t) or t.session~=session or not C.Finite(time) then return false,"invalid_timeline" end
    if time<t.lastTime then return false,"clock_reversed" end
    local current=t.segments[t.current]
    local cfg=segmentConfig(config or C.Config(),paused)
    if not current or current.session~=session then return false,"invalid_session" end
    if sameConfig(current,cfg) then
        current.to=time;t.lastTime=time
    else
        -- The exact change time was not observed; leave the previous poll gap
        -- uncovered instead of backdating a setting to the whole elapsed interval.
        current=appendSegment(t,session,time,config or C.Config(),paused)
    end
    if wantContext then
        cfg.timeline=t;cfg.segments=t.segments;cfg.segment=current;cfg.index=t.current
        cfg.generation=t.generation;cfg.session=session;cfg.time=time;cfg.from=current.from;cfg.floor=t.floor
        observed[1]=cfg
        return true,cfg
    end
    return true
end
local function observedSegment(t,time,observation)
    if not observation or observation~=observed[1] or observation.invalidated
        or observation.timeline~=t or observation.time~=time or t.schema~=1
        or t.generation~=observation.generation or t.session~=observation.session or t.lastTime~=time
        or t.floor~=observation.floor or t.segments~=observation.segments or t.current~=observation.index
        or t.current~=#t.segments then return nil end
    local current=t.segments[t.current]
    if current~=observation.segment or current.from~=observation.from or current.to~=time
        or current.session~=observation.session or not sameConfig(current,observation) then return nil end
    return current
end
local function segmentAmount(s,duration,fresh,rotten,age)
    if not s.enabled then return nil,"inactive_history" end
    if age>=rotten and not s.allowRotten then return nil,"rotten_disabled_history" end
    if age>=rotten and (s.removal=="unknown" or s.removal>=0) then return nil,"native_removal_policy" end
    return fresh*duration/s.restoreHours
end
local function coverage(t,startTime,endTime,fresh,rotten,age,current)
    if not C.Finite(startTime) or not C.Finite(endTime) or endTime<startTime then
        return nil,"invalid_history"
    end
    if startTime<(t.floor or startTime) then return nil,"truncated_history" end
    if endTime==startTime then return 0,0 end
    if current and startTime>=current.from and endTime<=current.to then
        local elapsed=endTime-startTime
        local amount,reason=segmentAmount(current,elapsed,fresh,rotten,age)
        if not amount then return nil,reason end
        return amount,elapsed
    end
    local cursor,amount,elapsed=startTime,0,0
    for _,s in ipairs(t.segments) do
        if s.to>cursor and s.from<endTime then
            if s.from>cursor then return nil,"uncovered_history" end
            local finish=math.min(s.to,endTime)
            local duration=finish-cursor
            local credit,reason=segmentAmount(s,duration,fresh,rotten,math.max(0,age-amount))
            if not credit then return nil,reason end
            amount=amount+credit;elapsed=elapsed+duration;cursor=finish
            if cursor==endTime then return amount,elapsed end
        end
    end
    return nil,"uncovered_history"
end
function C.Coverage(t,startTime,endTime,fresh,rotten,age)
    if not C.ValidTimeline(t) then return nil,"invalid_history" end
    return coverage(t,startTime,endTime,fresh,rotten,age)
end

local function lastAged(food)
    local n=food.getLastAged and food:getLastAged() or nil
    return C.Finite(n) and n or nil
end
local function settlementInterrupted(food,box,md,old,listedIndex)
    if md[C.foodKey]~=old then return true end
    if C.IsDirectFood(food,box,listedIndex) then return false end
    C.ClearFood(food)
    return true
end
local function ownershipChanged()
    return {active=false,reason="ownership_changed",elapsed=0}
end
local function needsReplacementGuard(food,age,rotten)
    if age<rotten then return false end
    local replacement=food.getReplaceOnRotten and food:getReplaceOnRotten()
    return type(replacement)=="string" and replacement~=""
end
function C.SettleFood(food,box,time,timeline,forceAnchor,observation,listedIndex)
    if not C.coolingBridge then C.InstallCoolingBridge() end
    if not C.IsDirectFood(food,box,listedIndex) then
        local record=C.FoodRecord(food)
        local previousBox=listedIndex~=nil and C.BoxState(box)
        if listedIndex==nil or (record and previousBox and record.boxId==previousBox.id) then C.ClearFood(food) end
        return {active=false,reason="outside_box",elapsed=0}
    end
    local md=food:getModData()
    local old=md[C.foodKey]
    local restored=C.RestoreFood(food)
    if restored and settlementInterrupted(food,box,md,old,listedIndex) then return ownershipChanged() end
    local state=C.EnsureBox(box)
    if not state or not C.Finite(time) then return {active=false,reason="invalid_box",elapsed=0} end
    local config=C.Config()
    local fresh,rotten=C.Eligible(food,config)
    local reason=policyReason(food,fresh,rotten)
    local active=state.on and config.enabled and fresh~=nil and reason==nil
    if old~=nil and (type(old)~="table" or old.schema~=1) then return {active=false,reason="unknown_schema",elapsed=0} end
    local id,fullType=C.Identity(food)
    local sig=fresh and signature(food,fresh,rotten) or "unsupported"
    local boxItemId=box.getID and tostring(box:getID()) or "unknown"
    local actual,aged=food:getAge(),lastAged(food)
    local current=observedSegment(timeline,time,observation)
    local trusted=not forceAnchor and active and type(old)=="table" and old.active==true
        and old.id==id and old.fullType==fullType and old.boxId==state.id and old.boxItemId==boxItemId and old.epoch==state.epoch
        and old.signature==sig and not old.externalEdit and not old.ownershipUncertain
        and C.Finite(old.logicalAge) and old.logicalAge>=0
        and C.Finite(old.age) and C.Finite(old.time) and old.time<=time
        and (current or C.ValidTimeline(timeline)) and old.timelineGeneration==timeline.generation
    local nativeAgeChange=false
    if trusted and actual~=old.age then
        -- All normal Lua setAge writers are observed. A native forward aging
        -- step advances lastAged, unlike an external age edit on the Lua path.
        nativeAgeChange=C.AgeHookReady() and actual>old.age and aged~=nil
            and C.Finite(old.lastAged) and aged>old.lastAged and aged<=time+0.001
        if not nativeAgeChange then trusted=false;reason="external_age_edit" end
    end
    local amount,elapsed
    if trusted then amount,elapsed=coverage(timeline,old.time,time,fresh,rotten,old.logicalAge,current) end
    local logicalAge
    if amount~=nil then
        logicalAge=math.max(0,old.logicalAge-amount)
        -- Only skip a verified no-op. Rounded native age can differ from the
        -- double-precision logical value, and a shield must still be managed.
        if current and elapsed==0 and not restored and old.shield==nil and not nativeAgeChange
            and logicalAge==actual and aged~=nil and aged==old.lastAged and C.AgeHookReady()
            and not needsReplacementGuard(food,actual,rotten) then
            return {active=true,elapsed=0,reason="restoring",nativeAgeReconciled=false}
        end
        C.WriteAge(food,logicalAge)
        if settlementInterrupted(food,box,md,old,listedIndex) then return ownershipChanged() end
    else
        if trusted then reason=elapsed end
        -- Never erase ordinary aging from unknown, disabled or mod-absent gaps.
        food:updateAge(false)
        if settlementInterrupted(food,box,md,old,listedIndex) then return ownershipChanged() end
        state=C.EnsureBox(box)
        if not state then return {active=false,reason="invalid_box",elapsed=0} end
        config=C.Config()
        actual=food:getAge()
        fresh,rotten=C.Eligible(food,config);sig=fresh and signature(food,fresh,rotten) or "unsupported"
        local currentReason=policyReason(food,fresh,rotten)
        reason=reason or currentReason
        active=state.on and config.enabled and fresh~=nil and currentReason==nil
        logicalAge=actual;elapsed=0
    end
    if active then food:setLastAged(time) end
    local age=food:getAge()
    md[C.foodKey]={schema=1,id=id,fullType=fullType,boxId=state.id,boxItemId=boxItemId,epoch=state.epoch,
        time=time,age=age,logicalAge=logicalAge,lastAged=lastAged(food),active=active,
        signature=sig,timelineGeneration=timeline and timeline.generation or 0}
    if active then
        -- Read the live threshold after writing Age. Fresh food cannot need a
        -- replacement guard; uncertain and rotten food keep the full check.
        local maxAge=listedIndex~=nil and food:getOffAgeMax()
        if not C.Finite(maxAge) or not C.Finite(age) or age>=maxAge then C.ProtectFood(food,box,listedIndex) end
    end
    return {active=active,elapsed=type(elapsed)=="number" and elapsed or 0,
        reason=active and (amount~=nil and "restoring" or (reason or "anchored"))
            or (not state.on and "box_off" or not config.enabled and "disabled" or reason or "unsupported_age"),
        nativeAgeReconciled=nativeAgeChange}
end

function C.GetStatus(item)
    local state=C.BoxState(item)
    local config=C.Config()
    return {valid=state~=nil,on=state and state.on or false,enabled=config.enabled,
        active=state~=nil and state.on and config.enabled,restoreHours=config.restoreHours,
        removalSafe=C.RemovalPolicy()~=nil and C.RemovalPolicy()<0}
end
return C
