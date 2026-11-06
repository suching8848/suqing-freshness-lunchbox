require "SuQingFreshnessLunchbox/Core"
local C=SuQingFreshnessLunchbox
local function addBox(context,item,seen)
    if not C.IsBox(item) or seen[item] then return end
    seen[item]=true
    local state=C.EnsureBox(item)
    if not state then return end
    local key=state.on and 'IGUI_SFL_TurnOff' or 'IGUI_SFL_TurnOn'
    local option=context:addOption(getText(key),item,function(box)
        if C.Runtime and C.Runtime.Toggle then C.Runtime.Toggle(box) end
    end)
    local available=C.Runtime and C.Runtime.ready and C.Runtime.operational==true
    if not available then option.notAvailable=true end
    if ISToolTip then
        local cfg=C.Config()
        local status
        if not C.Runtime or type(C.Runtime.Toggle)~='function' then status='IGUI_SFL_Unavailable'
        elseif C.Runtime.failed or C.Runtime.status=='error' then status='IGUI_SFL_Error'
        elseif not available then status=C.Runtime.status=='stopped' and 'IGUI_SFL_Stopped' or 'IGUI_SFL_Starting'
        else status=not cfg.enabled and 'IGUI_SFL_GlobalOff' or (state.on and 'IGUI_SFL_On' or 'IGUI_SFL_Off') end
        local tip=ISToolTip:new();tip:initialise();tip:setVisible(false)
        tip.description=getText(status)..' <LINE> '..
            getText('IGUI_SFL_Rate',tostring(cfg.restoreHours))..' <LINE> '..
            getText('IGUI_SFL_Capacity',tostring(item:getInventory():getCapacity()))..' <LINE> '..
            getText('IGUI_SFL_TimeScope')
        local runtimeStatus=C.GetStatus(item)
        if cfg.allowRotten and not runtimeStatus.removalSafe then
            tip.description=tip.description..' <LINE> '..getText('IGUI_SFL_RottenRemovalLimit')
        end
        option.toolTip=tip
    end
end
local function inventoryMenu(playerIndex,context,items)
    if not C.SP() then return end
    local seen={}
    for _,entry in ipairs(items) do
        if type(entry)=='table' and entry.items then
            for _,item in ipairs(entry.items) do addBox(context,item,seen) end
        else addBox(context,entry,seen) end
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
    for _,object in ipairs(objects) do if object.getItem then addBox(context,object:getItem(),seen) end end
end
Events.OnFillInventoryObjectContextMenu.Add(inventoryMenu)
Events.OnFillWorldObjectContextMenu.Add(worldMenu)
