require "SuQingFreshnessLunchbox/Batch"
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISAddItemInRecipe"
require "TimedActions/ISCraftAction"
require "Entity/TimedActions/ISHandcraftAction"

local C=SuQingFreshnessLunchbox
local B=C.Batch
C.Lock=C.Lock or {}
local L=C.Lock
if L.loaded then return L end
L.loaded=true

local function locked(container)
    return container and C.SP() and B.IsLockedContainer(container) or false
end

local function sealedFood(food)
    return food and C.SP() and B.IsSealedFood(food) or false
end

local function eject(page)
    local pane=page and page.inventoryPane
    if not pane then return false end
    if locked(page.forceSelectedContainer) then page.forceSelectedContainer=nil end
    local current=pane.inventory
    local currentLocked=locked(current)
    local lastLocked=locked(pane.lastinventory)
    local pageLocked=locked(page.inventory)
    if not currentLocked and not lastLocked and not pageLocked then
        return false
    end
    local fallback=not currentLocked and current or nil
    if not fallback and page.onCharacter then
        local player=getSpecificPlayer(page.player)
        fallback=player and player:getInventory()
    elseif not fallback then
        fallback=ISInventoryPage.GetFloorContainer(page.player)
    end
    if not fallback then return false end
    pane.inventory=fallback
    pane.lastinventory=fallback
    pane.selected={}
    page.inventory=fallback
    page.selectedButton=nil
    return true
end

local function refreshPage(page)
    local changed=eject(page)
    local pane=page and page.inventoryPane
    local container=pane and pane.inventory
    local kind=container and container.getType and container:getType()
    if (kind=="proxInv" or kind=="local") and page.refreshBackpacks then
        -- Rebuild the selected merged view from visible source tabs at the
        -- seal/release boundary, before its old rows can be used again.
        page:refreshBackpacks()
    elseif changed then
        pane:refreshContainer()
    end
end

function L.Refresh()
    ISInventoryPage.renderDirty=true
    for index=0,getNumActivePlayers()-1 do
        refreshPage(getPlayerInventory(index))
        refreshPage(getPlayerLoot(index))
    end
end

function L.FilterContainers(containers)
    if not containers or not C.SP() then return containers end
    for index=0,containers:size()-1 do
        if locked(containers:get(index)) then
            local filtered=ArrayList.new()
            for i=0,containers:size()-1 do
                local container=containers:get(i)
                if not locked(container) then filtered:add(container) end
            end
            return filtered
        end
    end
    return containers
end

local function containsSealedFood(items)
    if not items then return false end
    for i=0,items:size()-1 do
        if sealedFood(items:get(i)) then return true end
    end
    return false
end

local function craftLocked(action)
    if containsSealedFood(action.items) then return true end
    if action.manualInputs then
        for _,items in pairs(action.manualInputs) do
            if containsSealedFood(items) then return true end
        end
    end
    local data=action.logic and action.logic:getRecipeData()
    return data and containsSealedFood(data:getAllInputItems()) or false
end

local hooks={}
local function addHook(owner,key,make)
    if not owner or type(owner[key])~="function" then return false end
    for _,hook in ipairs(hooks) do
        if hook.owner==owner and hook.key==key then return true end
    end
    local hook={owner=owner,key=key,make=make}
    hooks[#hooks+1]=hook
    return true
end

local function bind(hook,prior)
    local guarded=hook.make(prior)
    local function wrapper(...)
        -- An outer mod may still delegate to our previous wrapper.
        if hook.wrapper~=wrapper then return prior(...) end
        return guarded(...)
    end
    hook.wrapper=wrapper
    hook.forwarder=nil
    hook.owner[hook.key]=wrapper
end

local function denyWhen(predicate)
    return function(prior)
        return function(self,...)
            if predicate(self,...) then return false end
            return prior(self,...)
        end
    end
end

local function transferLocked(action)
    return locked(action.srcContainer) or locked(action.destContainer)
end

local function eatLocked(action)
    return sealedFood(action.item)
end

local function recipeAdditionLocked(action)
    return sealedFood(action.usedItem) or sealedFood(action.baseItem)
end

local function filterCraftContainers(prior)
    return function(self,...)
        self.containers=L.FilterContainers(self.containers)
        return prior(self,...)
    end
end

local function legacyCraft(prior)
    return filterCraftContainers(denyWhen(function(action) return sealedFood(action.item) end)(prior))
end

local pageClasses,paneClasses={},{}
local function addInventoryHooks(pageClass,paneClass)
    if not pageClass or not paneClass or type(pageClass.addContainerButton)~="function"
        or type(pageClass.selectContainer)~="function" or type(pageClass.setNewContainer)~="function"
        or type(pageClass.selectButtonForContainer)~="function" or type(paneClass.refreshContainer)~="function" then
        return false
    end
    addHook(pageClass,"addContainerButton",function(prior)
        return function(self,container,...)
            local button=prior(self,container,...)
            if button and locked(container) and self.backpacks[#self.backpacks]==button then
                -- Vanilla callers immediately tint the returned button. Return
                -- the real button, but keep it out of the visible/craft list.
                self.containerButtonPanel:removeChild(button)
                self.backpacks[#self.backpacks]=nil
                self.buttonPool[#self.buttonPool+1]=button
            end
            return button
        end
    end)
    addHook(pageClass,"selectContainer",denyWhen(function(_,button)
        return button and locked(button.inventory)
    end))
    addHook(pageClass,"setNewContainer",denyWhen(function(_,container)
        return locked(container)
    end))
    addHook(pageClass,"selectButtonForContainer",denyWhen(function(_,container)
        return locked(container)
    end))
    addHook(paneClass,"refreshContainer",function(prior)
        return function(self,...)
            if locked(self.inventory) then
                eject(self.inventoryPage)
                if locked(self.inventory) then return end
            end
            return prior(self,...)
        end
    end)
    pageClasses[pageClass]=true
    paneClasses[paneClass]=true
    return true
end

local function addCleanUIHooks()
    -- CleanUI 42.22 can switch the active class tables without reloading Lua.
    -- Protect both its enhanced and namespaced stock-mode windows.
    addInventoryHooks(CleanUI_Clean_ISInventoryPage,CleanUI_Clean_ISInventoryPane)
    addInventoryHooks(CleanUI_Vanilla_ISInventoryPage,CleanUI_Vanilla_ISInventoryPane)
end

local function install()
    if #hooks>0 or not C.SP() then return end
    local ok=addInventoryHooks(ISInventoryPage,ISInventoryPane)
    addCleanUIHooks()
    ok=addHook(ISInventoryPaneContextMenu,"getContainers",function(prior)
        return function(...)
            return L.FilterContainers(prior(...))
        end
    end) and ok
    ok=addHook(ISInventoryTransferAction,"isValidStart",denyWhen(transferLocked)) and ok
    ok=addHook(ISInventoryTransferAction,"isValid",denyWhen(transferLocked)) and ok
    ok=addHook(ISInventoryTransferAction,"transferItem",denyWhen(transferLocked)) and ok
    ok=addHook(ISEatFoodAction,"isValidStart",denyWhen(function(action)
        return eatLocked(action) or sealedFood(action:getRequiredItem())
    end)) and ok
    ok=addHook(ISEatFoodAction,"isValid",denyWhen(eatLocked)) and ok
    ok=addHook(ISEatFoodAction,"complete",denyWhen(eatLocked)) and ok
    ok=addHook(ISEatFoodAction,"eat",denyWhen(eatLocked)) and ok
    ok=addHook(ISAddItemInRecipe,"isValid",denyWhen(recipeAdditionLocked)) and ok
    ok=addHook(ISAddItemInRecipe,"complete",denyWhen(recipeAdditionLocked)) and ok
    ok=addHook(ISCraftAction,"isValid",legacyCraft) and ok
    ok=addHook(ISCraftAction,"complete",legacyCraft) and ok
    ok=addHook(ISHandcraftAction,"isValid",denyWhen(craftLocked)) and ok
    ok=addHook(ISHandcraftAction,"start",filterCraftContainers) and ok
    ok=addHook(ISHandcraftAction,"performRecipe",denyWhen(craftLocked)) and ok
    if not ok then hooks={};pageClasses={};paneClasses={};return end
    for _,hook in ipairs(hooks) do bind(hook,hook.owner[hook.key]) end
end

local function isBound(hook)
    local current=hook.owner[hook.key]
    return current==hook.wrapper or (hook.forwarder~=nil and current==hook.forwarder)
end

-- Loot Tracker 1.8.5 periodically rewraps these two slots if its closure
-- is no longer outermost. Leave its reviewed forwarders above our guards.
local lootTrackerLines={selectContainer=627,setNewContainer=661}
local function sourcePath(path)
    return type(path)=="string" and string.lower((string.gsub(path,"\\","/"))) or nil
end

local function fromLootTracker(fn,path,line)
    if type(fn)~="function" then return false end
    local ok,source,firstLine=pcall(function()
        return getFilenameOfClosure(fn),getFirstLineOfClosure(fn)
    end)
    return ok and sourcePath(source)==path and firstLine==line
end

local function syncLootTracker()
    local check=LootTracker and LootTracker.Clicks and LootTracker.Clicks.checkClass
    if not check or type(getModInfoByID)~="function" then return end
    local info=getModInfoByID("LootTrackerB42")
    if not info or not info.getModVersion or not info.getVersionDir or info:getModVersion()~="1.8.5" then return end
    local dir=sourcePath(info:getVersionDir())
    if not dir then return end
    local path=dir.."/media/lua/client/loottracker/lt_clicks.lua"
    if not fromLootTracker(check,path,594) then return end

    local guards,changed={},false
    for _,hook in ipairs(hooks) do
        local line=lootTrackerLines[hook.key]
        if line then
            local current=hook.owner[hook.key]
            if not isBound(hook) and fromLootTracker(current,path,line) then
                bind(hook,current)
                changed=true
            end
            if hook.owner[hook.key]==hook.wrapper then guards[#guards+1]=hook end
        end
    end
    if not changed or not pcall(check) then return end
    -- The reviewed synchronous check captured these exact guards. Merely
    -- seeing a closure from the same source is not enough to trust it.
    for _,hook in ipairs(guards) do
        local outer=hook.owner[hook.key]
        if fromLootTracker(outer,path,lootTrackerLines[hook.key]) then hook.forwarder=outer end
    end
end

function L.Ready()
    if #hooks==0 then return false,"required inventory or action methods missing" end
    if not pageClasses[ISInventoryPage] or not paneClasses[ISInventoryPane] then
        return false,"active inventory UI classes not bound"
    end
    for _,hook in ipairs(hooks) do
        local current=hook.owner[hook.key]
        if not isBound(hook) then
            local name=tostring(hook.owner.Type or "inventory context").."."..hook.key
            if type(current)=="function" and type(getFilenameOfClosure)=="function" then
                local ok,source=pcall(getFilenameOfClosure,current)
                if ok and source then name=name.." from "..source end
            end
            return false,name
        end
    end
    return true
end

local function bindStartupChain()
    install()
    if #hooks==0 then return end
    addInventoryHooks(ISInventoryPage,ISInventoryPane)
    addCleanUIHooks()
    for _,hook in ipairs(hooks) do
        local current=hook.owner[hook.key]
        if not isBound(hook) and type(current)=="function" then
            bind(hook,current)
        end
    end
end

local passes=0
local function captureStartupChain()
    passes=passes+1
    if passes<2 then return end
    Events.OnTick.Remove(captureStartupChain)
    bindStartupChain()
end

local menuChecked,lastFailure
function L.Prepare()
    if not L.Ready() then syncLootTracker() end
    -- A live inventory class or forwarding hook can be installed after the
    -- startup tick window. Finalize once, before this world's first seal.
    if not menuChecked then
        menuChecked=true
        bindStartupChain()
    end
    local ready,reason=L.Ready()
    if ready then
        lastFailure=nil
    elseif lastFailure~=reason then
        lastFailure=reason
        print("[SuQingFreshnessLunchbox] batch lock unavailable: "..reason)
    end
    return ready
end

Events.OnGameStart.Add(function()
    menuChecked=false;lastFailure=nil
    install()
    if Events.OnTick.Remove then
        passes=0
        Events.OnTick.Remove(captureStartupChain)
        Events.OnTick.Add(captureStartupChain)
    end
end)
Events.OnRefreshInventoryWindowContainers.Add(function(page,phase)
    if phase=="begin" or phase=="buttonsAdded" then eject(page) end
end)

return L
