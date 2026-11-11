require "SuQingFreshnessLunchbox/Core"

local C=SuQingFreshnessLunchbox
C.Batch=C.Batch or {}
local B=C.Batch
if B.loaded then return B end
B.loaded=true
B.boxKey="SuQingFreshnessLunchboxBatch"
B.foodKey="SuQingFreshnessLunchboxBatchFood"
-- Stock B42 Food.updateRotting, finishupdate and shouldUpdateInWorld recognize
-- this exact nonperishable value. Food.save/load preserve it and cookability.
B.nonperishable=1000000000
local serial=0
local busy=setmetatable({}, {__mode="k"})

function B.Hours()
    local settings=SandboxVars and SandboxVars.SuQingFreshnessLunchbox
    local hours=settings and settings.BatchHours
    return C.Finite(hours) and math.max(0.25,math.min(24,hours)) or 12
end

function B.Get(box)
    if box and box.getFullType and box:getFullType()==C.FullType and box.getModData
        and (not box.hasModData or box:hasModData()) then
        return box:getModData()[B.boxKey]
    end
end

function B.IsSealed(box)
    -- Unknown receipts are also locked until they can be safely recovered.
    return B.Get(box)~=nil
end

local function containingBox(container)
    return container and container.getContainingItem and container:getContainingItem()
end

function B.IsLockedContainer(container)
    return B.IsSealed(containingBox(container))
end

function B.IsSealedFood(food)
    if not C.IsFood(food) then return false end
    if (not food.hasModData or food:hasModData()) and food:getModData()[B.foodKey]~=nil then return true end
    return B.IsLockedContainer(food:getContainer())
end

local function nativeMethods(food)
    return food.getOffAgeMax and food.setOffAgeMax and food.isCookable and food.setIsCookable
        and food.getAge and food.setAge and food.getLastAged and food.setLastAged
end

local function validGuard(food,guard,id,fullType)
    return type(guard)=="table" and guard.schema==1 and guard.foodId==id and guard.fullType==fullType
        and type(guard.batchId)=="string" and type(guard.boxId)=="string" and type(guard.boxItemId)=="string"
        and C.Finite(guard.offAgeMax) and guard.offAgeMax>=0 and guard.offAgeMax<100000000
        and guard.offAgeMax==math.floor(guard.offAgeMax) and type(guard.cookable)=="boolean"
        and nativeMethods(food)
end

local function setGuard(food)
    food:setOffAgeMax(B.nonperishable)
    food:setIsCookable(false)
    if food:getOffAgeMax()~=B.nonperishable or food:isCookable() then
        error("sealed lunchbox native guard was not retained")
    end
end

local function canRestore(food,guard)
    local maxAge=food:getOffAgeMax()
    local cookable=food:isCookable()
    return (maxAge==B.nonperishable or maxAge==guard.offAgeMax)
        and (cookable==false or cookable==guard.cookable)
end

local function restoreNative(food,guard)
    if not canRestore(food,guard) then error("sealed lunchbox native state changed") end
    food:setOffAgeMax(guard.offAgeMax)
    food:setIsCookable(guard.cookable)
    if food:getOffAgeMax()~=guard.offAgeMax or food:isCookable()~=guard.cookable then
        error("sealed lunchbox native state could not be restored")
    end
end

local function resume(food)
    if C.onRestoreFood then C.onRestoreFood(food) end
end

local function retire(food)
    local cell=type(getCell)=="function" and getCell()
    if cell and cell.addToProcessItemsRemove then cell:addToProcessItemsRemove(food) end
end

local function writeAge(food,age)
    if C.WriteAge then C.WriteAge(food,age) else food:setAge(age) end
end

local function boxIdentity(box)
    local state=C.BoxState(box)
    return state and state.id,box.getID and tostring(box:getID()) or "unknown"
end

local function validBatch(box,batch)
    if type(batch)~="table" or batch.schema~=1 or type(batch.id)~="string"
        or type(batch.roster)~="table" or not C.Finite(batch.count) or batch.count<1
        or batch.count~=math.floor(batch.count) or not C.Finite(batch.startedAt)
        or not C.Finite(batch.endsAt) or batch.endsAt-batch.startedAt<0.25
        or batch.endsAt-batch.startedAt>24 then return false end
    local boxId,boxItemId=boxIdentity(box)
    return boxId~=nil and batch.boxId==boxId and batch.boxItemId==boxItemId
        and (batch.phase=="sealing" or batch.phase=="sealed"
            or batch.phase=="finishing" or batch.phase=="recovering")
end

local function collect(box,batch,expectGuard)
    local inventory=C.GetInventory(box)
    local list=inventory:getItems()
    local entries,seen={},{}
    local matches=list:size()==batch.count
    for i=0,list:size()-1 do
        local food=list:get(i)
        local isDirect=C.IsFood(food) and food:getContainer()==inventory
        local id,fullType
        if isDirect then id,fullType=C.Identity(food) end
        local md=isDirect and food:getModData()
        local guard=md and md[B.foodKey]
        if md and guard~=nil then
            if not validGuard(food,guard,id,fullType) or not canRestore(food,guard) then return nil end
            entries[#entries+1]={food=food,md=md,guard=guard}
            if expectGuard and (food:getOffAgeMax()~=B.nonperishable or food:isCookable()) then matches=false end
        elseif isDirect and batch.roster[id]==fullType and food.getOffAgeMax
            and food:getOffAgeMax()==B.nonperishable then
            -- A known guarded item lost the only copy of its original state.
            return nil
        end
        if not isDirect or seen[id] or batch.roster[id]~=fullType or not guard
            or guard.batchId~=batch.id or guard.boxId~=batch.boxId or guard.boxItemId~=batch.boxItemId then
            matches=false
        end
        if id then seen[id]=true end
    end
    for id in pairs(batch.roster) do
        if not seen[id] then matches=false;break end
    end
    return entries,matches
end

local function release(box,batch,entries)
    if B.Get(box)~=batch then return false end
    for _,entry in ipairs(entries) do
        if entry.md[B.foodKey]~=entry.guard then return false end
    end
    for _,entry in ipairs(entries) do entry.md[B.foodKey]=nil end
    box:getModData()[B.boxKey]=nil
    return true
end

local function reassert(entries)
    local rolledBack=true
    for _,entry in ipairs(entries) do
        local reverted=pcall(function()
            if entry.md[B.foodKey]~=entry.guard or not canRestore(entry.food,entry.guard) then
                error("sealed lunchbox food receipt changed")
            end
            setGuard(entry.food)
            if entry.age~=nil then writeAge(entry.food,entry.age) end
            if entry.lastAged~=nil then entry.food:setLastAged(entry.lastAged) end
            retire(entry.food)
        end)
        rolledBack=rolledBack and reverted
    end
    return rolledBack
end

local function recoverBatch(box,batch,entries)
    batch.phase="recovering"
    for _,entry in ipairs(entries) do
        local ok=pcall(function()
            restoreNative(entry.food,entry.guard)
            resume(entry.food)
        end)
        if not ok then reassert(entries);return false,"recovery_required" end
    end
    if not release(box,batch,entries) then reassert(entries);return false,"recovery_required" end
    return false,"manifest_changed"
end

local function start(box,time)
    if B.IsSealed(box) then return false,"already_sealed" end
    if not C.Finite(time) or time<0 then return false,"invalid_time" end
    local cfg=C.Config()
    if not cfg.enabled then return false,"disabled" end
    if not C.EnsureBox(box) then return false,"invalid_box" end
    local inventory=C.GetInventory(box)
    local list=inventory:getItems()
    local count=list:size()
    if count==0 then return false,"empty" end
    local boxId,boxItemId=boxIdentity(box)
    if not boxId or boxItemId=="unknown" then return false,"invalid_box" end
    serial=serial+1
    local stamp=type(getTimestampMs)=="function" and getTimestampMs() or 0
    local batchId=boxId..":"..boxItemId..":"..tostring(stamp)..":"..tostring(serial)
    local foods={}
    for i=0,count-1 do foods[i+1]=list:get(i) end
    local entries,roster={},{}
    for _,food in ipairs(foods) do
        -- Native heat can purify taint even when a food is not cookable.
        if not C.IsFood(food) or food:getContainer()~=inventory or not nativeMethods(food)
            or (food.isTainted and food:isTainted()) then return false,"unsafe_food" end
        local md=food:getModData()
        if md[B.foodKey]~=nil then return false,"guard_present" end
        C.RestoreFood(food)
        local fresh,rotten=C.Eligible(food,cfg)
        local id,fullType=C.Identity(food)
        local cookable=food:isCookable()
        if not fresh or not C.Finite(rotten) or rotten~=math.floor(rotten)
            or id=="unknown" or type(fullType)~="string" or roster[id] or type(cookable)~="boolean" then
            return false,"unsafe_food"
        end
        roster[id]=fullType
        entries[#entries+1]={food=food,md=md,guard={schema=1,foodId=id,fullType=fullType,
            batchId=batchId,boxId=boxId,boxItemId=boxItemId,offAgeMax=rotten,cookable=cookable}}
    end
    local batch={schema=1,id=batchId,phase="sealing",boxId=boxId,boxItemId=boxItemId,
        startedAt=time,endsAt=time+B.Hours(),count=count,roster=roster}
    if not validBatch(box,batch) then return false,"invalid_time" end
    box:getModData()[B.boxKey]=batch
    local ok=pcall(function()
        for _,entry in ipairs(entries) do
            entry.md[B.foodKey]=entry.guard
            setGuard(entry.food)
            retire(entry.food)
        end
        local _,matches=collect(box,batch,true)
        if not matches then error("sealed lunchbox changed during seal") end
        for _,entry in ipairs(entries) do C.ClearFood(entry.food) end
        batch.phase="sealed"
    end)
    if ok then return true,"sealed" end
    local current=collect(box,batch)
    if not current then return false,"recovery_required" end
    local _,reason=recoverBatch(box,batch,current)
    return false,reason=="manifest_changed" and "seal_failed" or reason
end

local function complete(box,time)
    local batch=B.Get(box)
    if batch==nil then return false,"not_sealed" end
    if not validBatch(box,batch) then return false,"invalid_batch" end
    if not C.Finite(time) or time<batch.startedAt then return false,"invalid_time" end
    local recovering=batch.phase=="sealing" or batch.phase=="recovering"
    if not recovering and time<batch.endsAt then return false,"not_due" end
    local entries,matches=collect(box,batch,batch.phase=="sealed")
    if not entries then return false,"recovery_required" end
    if recovering or not matches then return recoverBatch(box,batch,entries) end
    batch.phase="finishing"
    local ok=pcall(function()
        for _,entry in ipairs(entries) do
            local food=entry.food
            entry.age,entry.lastAged=food:getAge(),food:getLastAged()
            writeAge(food,0)
            food:setLastAged(time)
            if food:getAge()~=0 or food:getLastAged()~=time then
                error("sealed lunchbox food age could not be committed")
            end
            restoreNative(food,entry.guard)
            resume(food)
        end
        local _,unchanged=collect(box,batch)
        if not unchanged or not release(box,batch,entries) then error("sealed lunchbox changed during finish") end
    end)
    if ok then return true,"complete" end
    return false,reassert(entries) and "finish_failed" or "recovery_required"
end

local function runBatch(operation,box,time)
    if not C.SP() then return false,"unsupported" end
    if not C.IsBox(box) then return false,"invalid_box" end
    if busy[box] then return false,"busy" end
    busy[box]=true
    local ok,result,reason=pcall(operation,box,time)
    busy[box]=nil
    if not ok then return false,B.IsSealed(box) and "recovery_required" or "seal_failed" end
    return result,reason
end

function B.Start(box,time)
    return runBatch(start,box,time)
end

function B.Complete(box,time)
    return runBatch(complete,box,time)
end

function B.RecoverFood(food)
    if not C.SP() then return false,"unsupported" end
    if not C.IsFood(food) then return false,"unsafe_food" end
    if food.hasModData and not food:hasModData() then return false,"not_guarded" end
    local md=food:getModData()
    local guard=md[B.foodKey]
    local legacy=guard==nil and C.FoodRecord(food)
    if guard==nil and not legacy then return false,"not_guarded" end
    if B.IsLockedContainer(food:getContainer()) then return false,"still_sealed" end
    local runtime=C.Runtime
    if not runtime or not runtime.Location or not runtime.Location(food) then return false,"unknown_owner" end
    if guard==nil then C.ClearFood(food);return true,"legacy_recovered" end
    local id,fullType=C.Identity(food)
    if not validGuard(food,guard,id,fullType) or not canRestore(food,guard) then return false,"recovery_required" end
    local ok=pcall(function()
        restoreNative(food,guard)
        resume(food)
    end)
    if not ok or md[B.foodKey]~=guard or B.IsLockedContainer(food:getContainer()) or not runtime.Location(food) then
        reassert({{food=food,md=md,guard=guard}})
        return false,"recovery_required"
    end
    md[B.foodKey]=nil
    return true,"recovered"
end

return B
