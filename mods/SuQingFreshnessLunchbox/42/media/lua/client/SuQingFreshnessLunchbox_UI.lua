require "SuQingFreshnessLunchbox/Batch"
require "SuQingFreshnessLunchbox_Lock"
local C=SuQingFreshnessLunchbox
local B=C.Batch
local function remaining(batch)
    if type(batch)~="table" or not C.Finite(batch.endsAt) then return nil end
    return math.max(0,math.ceil((batch.endsAt-getGameTime():getWorldAgeHours())*60))
end

local function addBox(context,item,seen,playerIndex)
    if not C.IsBox(item) or seen[item] then return end
    seen[item]=true
    local sealed=B.IsSealed(item)
    local runtime=C.Runtime
    local available=runtime and runtime.CanStartBatch and runtime.CanStartBatch()
    local enabled=C.Config().enabled
    local minutes=sealed and remaining(B.Get(item))
    local label=getText('IGUI_SFL_SealBatch')
    if sealed then
        label=not minutes and getText('IGUI_SFL_BatchSealed')
            or minutes==0 and getText('IGUI_SFL_BatchReady')
            or getText('IGUI_SFL_BatchRemaining',tostring(minutes))
    end
    local option=context:addOption(label,item,function(box)
        if not runtime or not runtime.StartBatch then return end
        local ok,reason=runtime.StartBatch(box)
        if ok then return end
        local player=getSpecificPlayer(playerIndex)
        local reasonText=getTextOrNull('IGUI_SFL_BatchReason_'..tostring(reason))
        if player then
            player:Say(reasonText or getText('IGUI_SFL_BatchRejected'))
        end
    end)
    option.notAvailable=sealed or not available or not enabled
    if not ISToolTip then return end
    local status
    if sealed then status=getText('IGUI_SFL_BatchLocked')
    elseif not enabled then status=getText('IGUI_SFL_GlobalOff')
    elseif runtime and (runtime.failed or runtime.status=='error') then status=getText('IGUI_SFL_Error')
    elseif runtime and runtime.operational and not available then
        status=getText('IGUI_SFL_BatchReason_lock_unavailable')
    elseif not available then status=getText('IGUI_SFL_Starting')
    else status=getText('IGUI_SFL_BatchInfo',tostring(B.Hours())) end
    local tip=ISToolTip:new();tip:initialise();tip:setVisible(false)
    tip.description=status..' <LINE> '..
        getText('IGUI_SFL_Capacity',tostring(item:getInventory():getCapacity()))
    option.toolTip=tip
end
local function inventoryMenu(playerIndex,context,items)
    if not C.SP() then return end
    local seen={}
    for _,entry in ipairs(items) do
        if type(entry)=='table' and entry.items then
            for _,item in ipairs(entry.items) do addBox(context,item,seen,playerIndex) end
        else addBox(context,entry,seen,playerIndex) end
    end
end
local function worldMenu(playerIndex,context,objects,test)
    if not C.SP() then return end
    if test then
        for _,object in ipairs(objects) do
            if object.getItem and C.IsBox(object:getItem()) then return true end
        end
        return
    end
    local seen={}
    for _,object in ipairs(objects) do
        if object.getItem then addBox(context,object:getItem(),seen,playerIndex) end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu)
Events.OnFillWorldObjectContextMenu.Add(worldMenu)
