-- Run with runtime_KahluaAudit after runtime_mock_bootstrap.lua, Core.lua,
-- Batch.lua, Crafting.lua and SuQingFreshnessLunchbox_Lock.lua, in that order.
local C=SuQingFreshnessLunchbox
local B=C.Batch
local L=C.Lock
local assertions=0
local function check(condition,message)
    assertions=assertions+1
    assert(condition,message)
end

local function forward() return true,"original" end
local function emit(event,...)
    for _,callback in ipairs(event.callbacks) do callback(...) end
end

ArrayList={new=function() return Mock.list() end}
ISInventoryTransferAction={isValidStart=forward,isValid=forward,transferItem=forward}
ISEatFoodAction={isValidStart=forward,isValid=forward,complete=forward,eat=forward,
    getRequiredItem=function(action) return action.required end}
ISAddItemInRecipe={isValid=forward,complete=forward}
ISCraftAction={isValid=forward,complete=forward}
ISHandcraftAction={isValid=forward,start=forward,performRecipe=forward}
ISInventoryPane={refreshContainer=function(pane) pane.refreshes=(pane.refreshes or 0)+1 end}
ISInventoryPage={
    GetFloorContainer=function() return Mock.inventory() end,
    refreshBackpacks=function(page) page.railRefreshes=(page.railRefreshes or 0)+1 end,
    addContainerButton=function(page,container)
        local button={inventory=container}
        page.backpacks[#page.backpacks+1]=button
        return button
    end,
    selectContainer=function(page,button) page.inventoryPane.inventory=button.inventory end,
    setNewContainer=function(page,container) page.inventoryPane.inventory=container end,
    selectButtonForContainer=function(page,container) page.inventoryPane.inventory=container end,
}
local alternatePage,alternatePane={},{}
for key,method in pairs(ISInventoryPage) do alternatePage[key]=method end
for key,method in pairs(ISInventoryPane) do alternatePane[key]=method end
Events.OnTick.Remove=function(callback)
    for index,value in ipairs(Events.OnTick.callbacks) do
        if value==callback then table.remove(Events.OnTick.callbacks,index);return end
    end
end

local player=Mock.player(Mock.square(1))
local box=Mock.add(player.inventory,Mock.box())
local inner=box:getInventory()
local food=Mock.add(inner,Mock.food(3))
local other=Mock.food(3)
local floor=Mock.inventory()
local sourceList=ArrayList.new()
sourceList:add(player.inventory);sourceList:add(inner)
ISInventoryPaneContextMenu={getContainers=function() return sourceList end}
local page=setmetatable({
    onCharacter=true, player=0, inventory=inner, backpacks={}, buttonPool={},
    containerButtonPanel={removeChild=function(panel) panel.removed=true end},
}, {__index=ISInventoryPage})
page.inventoryPane=setmetatable({inventoryPage=page,inventory=inner,lastinventory=inner},{__index=ISInventoryPane})
function getPlayerInventory() return page end
function getPlayerLoot() return nil end

emit(Events.OnGameStart)
check(L.Ready(),"stock guard slots are available")
check(C.AcceptFood(inner,food),"open box accepts food")
check(ISInventoryPaneContextMenu.getContainers()==sourceList,"no copy without locked sources")
local allowed,detail=ISInventoryTransferAction.isValid({srcContainer=inner,destContainer=floor})
check(allowed and detail=="original","original transfer results retained")

box:getModData()[B.boxKey]={endsAt=112}
check(not C.AcceptFood(inner,food),"sealed box denies native insertion")
check(not ISInventoryTransferAction.isValidStart({srcContainer=inner,destContainer=floor}),"sealed source does not start")
check(not ISInventoryTransferAction.isValid({srcContainer=inner,destContainer=floor}),"sealed source rejected before queued transfer")
check(not ISInventoryTransferAction.isValid({srcContainer=floor,destContainer=inner}),"sealed destination rejected")
check(not ISInventoryTransferAction.transferItem({srcContainer=inner,destContainer=floor},food),"direct action transfer rejected")
check(ISInventoryTransferAction.isValid({item=box,srcContainer=player.inventory,destContainer=floor}),"whole box can move")
L.Refresh()
check(page.inventoryPane.inventory==player.inventory and page.inventoryPane.refreshes==1,"already open pane ejected")
local button=page:addContainerButton(inner)
check(button and #page.backpacks==0 and page.containerButtonPanel.removed,"hidden button still returned for native tint")
check(not page:selectContainer(button),"stale button denied")
check(not page:setNewContainer(inner),"direct container switch denied")
check(not page:selectButtonForContainer(inner),"forced selection denied")
page.inventoryPane.inventory=inner
page.inventoryPane:refreshContainer()
check(page.inventoryPane.inventory==player.inventory,"refresh repairs a stale pane")
local proxy=Mock.inventory()
proxy.type="proxInv"
page.inventoryPane.inventory=proxy
L.Refresh()
check(page.railRefreshes==1,"selected merged inventory is rebuilt at the seal boundary")

local filtered=ISInventoryPaneContextMenu.getContainers()
check(filtered:size()==1 and filtered:get(0)==player.inventory and sourceList:size()==2,"craft list filtered without mutating callers")
check(not ISEatFoodAction.isValidStart({item=other,required=food,getRequiredItem=ISEatFoodAction.getRequiredItem}),
    "sealed ingredient cannot be used by a different food action")
check(not ISEatFoodAction.complete({item=food}),"sealed item cannot be eaten")
check(not ISAddItemInRecipe.complete({usedItem=food}),"evolved recipe rejects sealed ingredient")
check(not ISCraftAction.complete({item=food,containers=sourceList}),"legacy craft rejects sealed item")
local selected=ArrayList.new();selected:add(food)
check(not ISHandcraftAction.performRecipe({items=selected}),"cached selected items blocked at handcraft commit")
check(not ISHandcraftAction.performRecipe({manualInputs={selected}}),"cached manual inputs blocked at handcraft commit")
local action={containers=sourceList}
check(ISHandcraftAction.start(action) and action.containers:size()==1,"handcraft start filters queued source list")

local wrapped=ISInventoryTransferAction.isValid
ISInventoryTransferAction.isValid=function(self,...) return wrapped(self,...) end
CleanUI_Vanilla_ISInventoryPage=alternatePage
CleanUI_Vanilla_ISInventoryPane=alternatePane
check(not L.Ready(),"changed chain prevents new seals before startup capture")
emit(Events.OnTick);emit(Events.OnTick)
check(L.Ready(),"startup forwarding wrapper is incorporated once")
check(not ISInventoryTransferAction.isValid({srcContainer=inner,destContainer=floor}),"lock survives startup forwarding")
local originalPage,originalPane=ISInventoryPage,ISInventoryPane
ISInventoryPage,ISInventoryPane=alternatePage,alternatePane
check(L.Ready(),"CleanUI stock-mode class switch preserves readiness")
check(not ISInventoryPage.selectContainer(page,button),"CleanUI stock mode cannot select the sealed source")
ISInventoryPage,ISInventoryPane=originalPage,originalPane

local beforeLateRefresh=ISInventoryPane.refreshContainer
local lateCalls=0
ISInventoryPane.refreshContainer=function(self,...)
    lateCalls=lateCalls+1
    return beforeLateRefresh(self,...)
end
check(not L.Ready(),"a wrapper installed after the two startup ticks reproduces the disabled menu")
check(L.Prepare(),"the first menu check binds the final inventory chain")
page.inventoryPane.inventory=inner
page.inventoryPane:refreshContainer()
check(page.inventoryPane.inventory==player.inventory and lateCalls==1,
    "late wrapper still runs once after the sealed pane is ejected")

box:getModData()[B.boxKey]=nil
check(C.AcceptFood(inner,food),"opening restores native insertion")
check(ISInventoryTransferAction.isValid({srcContainer=inner,destContainer=floor}),"opening restores transfer")
check(page:addContainerButton(inner) and #page.backpacks==1,"opening restores inventory button")
local prepared=ISInventoryPane.refreshContainer
ISInventoryPane.refreshContainer=function(self,...) return prepared(self,...) end
check(not L.Prepare(),"later drift still blocks sealing")
print("RUNTIME_BATCH_LOCK assertions="..assertions.." PASS")
