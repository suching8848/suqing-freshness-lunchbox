require "SuQingFreshnessLunchbox/Batch"
require "TimedActions/ISTransferAction"
local C=SuQingFreshnessLunchbox
local B=C.Batch
C.Runtime=C.Runtime or {}
local R=C.Runtime
if R.loaded then return R end
R.loaded=true
R.status="waiting"
R.boxes={}
R.seen={}
R.squares={}
R.errors=0

local function now() return getGameTime():getWorldAgeHours() end
local function listContains(list,item) return list and list.contains and list:contains(item) or false end
local function loadedSquare(square)
    local cell=type(getCell)=="function" and getCell() or nil
    return square~=nil and cell~=nil and cell:getGridSquare(square:getX(),square:getY(),square:getZ())==square
end

-- Trace an inventory item to an actually loaded owner without depending on
-- equip slots. Food and box objects retain their identity through normal moves.
function R.Location(item)
    local seen={}
    for _=1,32 do
        if not item or seen[item] then return nil,"unknown_owner" end
        seen[item]=true
        local world=item.getWorldItem and item:getWorldItem()
        if world then
            local square=world:getSquare()
            local items=square and square.getWorldObjects and square:getWorldObjects()
            if loadedSquare(square) and world:getItem()==item and listContains(items,world) then return "ground" end
            return nil,"unloaded"
        end
        local inventory=item.getContainer and item:getContainer()
        if not inventory or not listContains(inventory:getItems(),item) then return nil,"unknown_owner" end
        local containing=inventory.getContainingItem and inventory:getContainingItem()
        if containing then
            if not containing.getInventory or containing:getInventory()~=inventory then return nil,"unknown_owner" end
            item=containing
        else
            local part=inventory.getVehiclePart and inventory:getVehiclePart()
            if part then
                local vehicle=part:getVehicle()
                local square=vehicle and vehicle:getSquare()
                local cell=type(getCell)=="function" and getCell()
                local vehicles=cell and cell.getVehicles and cell:getVehicles()
                if loadedSquare(square) and listContains(vehicles,vehicle) then return "vehicle" end
                return nil,"unloaded"
            end
            local parent=inventory.getParent and inventory:getParent()
            if not parent then return nil,"unknown_owner" end
            local square=parent.getSquare and parent:getSquare()
                or parent.getCurrentSquare and parent:getCurrentSquare()
            if not loadedSquare(square) then return nil,"unloaded" end
            if type(instanceof)=="function" and instanceof(parent,"IsoGameCharacter") then return "character" end
            if listContains(square:getObjects(),parent) then return "furniture" end
            return nil,"unknown_owner"
        end
    end
    return nil,"ownership_depth"
end
function R.IsLoaded(box) return C.IsBox(box) and R.Location(box)~=nil or false end

local priorRestored=C.onRestoreFood
C.onRestoreFood=function(food)
    if priorRestored then priorRestored(food) end
    -- Emptying replaceOnRotten may let native finishupdate retire this food.
    -- Restore normal processing when the rule is reinstated, only while loaded.
    if R.Location(food) then
        local cell=type(getCell)=="function" and getCell()
        if cell and cell.addToProcessItems then cell:addToProcessItems(food) end
    end
end


local function refreshAccess()
    if not C.Lock or not C.Lock.Refresh then return end
    local ok,message=pcall(C.Lock.Refresh)
    if not ok then print("[SuQingFreshnessLunchbox] inventory refresh deferred: "..tostring(message)) end
end

function R.CanStartBatch(checkOnly)
    if not (R.ready and R.operational and R.transfer and ISTransferAction and ISTransferAction.transferItem==R.transfer.wrapper) then return false end
    local lock=C.Lock
    if not lock then return false end
    if not checkOnly and lock.Prepare then return lock.Prepare() end
    return lock.Ready and lock.Ready()
end

local function schedule(box,batch)
    if type(batch)~="table" or not C.Finite(batch.endsAt) then return false end
    if batch.phase=="sealing" or batch.phase=="recovering" then
        R.boxes[box]=now()
    else
        R.boxes[box]=batch.endsAt
    end
    return true
end

function R.Register(box)
    if not C.IsBox(box) then return false end
    if not R.ready then C.pending[box]=true;return true end
    if R.seen[box] then return true end
    if not C.EnsureBox(box) or not R.IsLoaded(box) then return false end
    R.seen[box]=true
    C.pending[box]=nil
    if B.IsSealed(box) then
        schedule(box,B.Get(box))
    else
        -- The previous version could save a per-food replacement receipt.
        -- Recover that data on discovery, once per loaded box, never per tick.
        local items=C.GetInventory(box):getItems()
        for i=0,items:size()-1 do B.RecoverFood(items:get(i)) end
    end
    return true
end

function R.ScanInventory(inventory,seen,depth)
    if not inventory then return end
    seen=seen or {};depth=depth or 0
    if seen[inventory] or depth>32 then return end
    seen[inventory]=true
    local containing=inventory.getContainingItem and inventory:getContainingItem()
    if C.IsBox(containing) then R.Register(containing);return end
    local list=inventory:getItems()
    for i=0,list:size()-1 do
        local item=list:get(i)
        if C.IsBox(item) then R.Register(item)
        elseif type(instanceof)=="function" and instanceof(item,"InventoryContainer") then
            R.ScanInventory(item:getInventory(),seen,depth+1)
        elseif C.IsFood(item) and (not item.hasModData or item:hasModData()) then
            B.RecoverFood(item)
        end
    end
end

function R.ScanSquare(square)
    if not square then return end
    if not R.ready then R.squares[square]=true;return end
    if not loadedSquare(square) then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        local count=object.getContainerCount and object:getContainerCount() or 0
        if count>0 and object.getContainerByIndex then
            for n=0,count-1 do R.ScanInventory(object:getContainerByIndex(n)) end
        elseif object.getContainer then R.ScanInventory(object:getContainer()) end
    end
    local world=square.getWorldObjects and square:getWorldObjects()
    if world then
        for i=0,world:size()-1 do
            local item=world:get(i):getItem()
            if C.IsBox(item) then R.Register(item)
            elseif item and type(instanceof)=="function" and instanceof(item,"InventoryContainer") then
                R.ScanInventory(item:getInventory())
            elseif C.IsFood(item) and (not item.hasModData or item:hasModData()) then
                B.RecoverFood(item)
            end
        end
    end
end
function R.ScanPlayers()
    local count=type(getNumActivePlayers)=="function" and getNumActivePlayers() or 1
    for i=0,count-1 do
        local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(i)
            or (i==0 and type(getPlayer)=="function" and getPlayer())
        if player and player.getInventory then R.ScanInventory(player:getInventory()) end
    end
end
function R.ScanVehicles()
    local cell=type(getCell)=="function" and getCell()
    local vehicles=cell and cell.getVehicles and cell:getVehicles()
    if not vehicles then return end
    -- B42.21 returns HashSet<BaseVehicle>; Set has no indexed get(int).
    local iterator=vehicles:iterator()
    while iterator:hasNext() do
        local vehicle=iterator:next()
        if loadedSquare(vehicle:getSquare()) then
            for n=0,vehicle:getPartCount()-1 do
                local part=vehicle:getPartByIndex(n)
                if part and part.getItemContainer then R.ScanInventory(part:getItemContainer()) end
            end
        end
    end
end

function R.StartBatch(box)
    if not R.CanStartBatch() then return false,"lock_unavailable" end
    if not R.Register(box) or not R.IsLoaded(box) then return false,"invalid_box" end
    local ok,reason=B.Start(box,now())
    if schedule(box,B.Get(box)) then refreshAccess() end
    return ok,reason
end

local function completeDue()
    if not R.operational then return end
    local time
    for box,deadline in pairs(R.boxes) do
        time=time or now()
        if time>=deadline then
            if not R.IsLoaded(box) then
                R.boxes[box]=nil
                R.seen[box]=nil
            else
                local ok,reason=B.Complete(box,time)
                if ok or not B.IsSealed(box) then
                    R.boxes[box]=nil
                    refreshAccess()
                else
                    -- A failed boundary is retryable. Avoid a full inventory
                    -- retry every frame while the game clock is stationary.
                    R.boxes[box]=time+0.05
                    if R.lastBatchError~=reason then
                        R.lastBatchError=reason
                        print("[SuQingFreshnessLunchbox] batch completion deferred: "..tostring(reason))
                    end
                end
            end
        end
    end
end

function R.Tick()
    if not R.ready then return end
    completeDue()
    R.ticks=R.ticks+1
    for box in pairs(C.pending) do R.Register(box) end
    if R.ticks%120==0 then
        for box in pairs(R.seen) do
            if not R.IsLoaded(box) then R.seen[box]=nil;R.boxes[box]=nil end
        end
        R.ScanPlayers();R.ScanVehicles()
        R.discoveryRequested=false
    elseif R.discoveryRequested and R.ticks%30==0 then
        R.discoveryRequested=false
        R.ScanPlayers()
    end
end

local function pack(...) return {n=select("#",...),...} end
function R.InstallTransferHook(captureStartup)
    if not ISTransferAction or type(ISTransferAction.transferItem)~="function" then return false end
    if R.transfer and ISTransferAction.transferItem==R.transfer.wrapper then return true end
    if R.transfer and not captureStartup then return false end
    local prior=ISTransferAction.transferItem
    local wrapper
    wrapper=function(self,character,item,source,destination,...)
        -- A startup re-wrap can still hold the previous closure as a delegate.
        if not R.transfer or R.transfer.wrapper~=wrapper then
            return prior(self,character,item,source,destination,...)
        end
        if C.SP() and (B.IsLockedContainer(source) or B.IsLockedContainer(destination)) then
            return item
        end
        if R.ready and C.IsFood(item) then B.RecoverFood(item) end
        if C.SP() and B.IsSealedFood(item) then return item end
        if not R.ready then return prior(self,character,item,source,destination,...) end
        local result=pack(pcall(prior,self,character,item,source,destination,...))
        if C.IsBox(item) then R.Register(item) end
        local output=result[1] and result[2] or nil
        if output~=nil and output~=item and C.IsBox(output) then R.Register(output) end
        if not result[1] then error(result[2]) end
        return unpack(result,2,result.n)
    end
    R.transfer={prior=prior,wrapper=wrapper}
    ISTransferAction.transferItem=wrapper
    return true
end

function R.Start(origin)
    if R.ready then return false end
    if not C.SP() then R.status="unsupported";return false end
    R.ready=true;R.ticks=0;R.failed=false
    R.operational=false;R.transferStartupPasses=0
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for box in pairs(C.pending) do R.Register(box) end
    R.ScanPlayers();R.ScanVehicles()
    R.status="waiting_transfer"
    print("[SuQingFreshnessLunchbox] "..C.version.." single-player ready via "..tostring(origin or "explicit start").."; sealed batch restoration")
    return true
end

function R.HasLoadedPlayerWorld()
    if not C.SP() or not getCell or not getCell() then return false end
    if MainScreen and MainScreen.instance and MainScreen.instance.inGame==false then return false end
    local count=type(getNumActivePlayers)=="function" and getNumActivePlayers() or 1
    for i=0,count-1 do
        local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(i)
            or (i==0 and type(getPlayer)=="function" and getPlayer())
        local square=player and player.getCurrentSquare and player:getCurrentSquare()
            or player and player.getSquare and player:getSquare()
        if loadedSquare(square) then return true end
    end
    return false
end

function R.NormalTick()
    if not R.ready and not R.failed and not R.fallbackTried and R.HasLoadedPlayerWorld() then
        R.fallbackTried=true
        R.Start("loaded-world fallback")
    end
    if not R.ready then return end
    if not R.operational then
        -- Capture the chain after ISA has installed its first-tick forwarding.
        R.transferStartupPasses=(R.transferStartupPasses or 0)+1
        if R.transferStartupPasses<2 then return end
    end
    if not R.InstallTransferHook(not R.operational) then error("lunchbox transfer chain changed") end
    R.operational=true
    R.status="ready"
end

function R.Save()
    if R.ready then completeDue() end
end

function R.Stop()
    R.ready=false;R.operational=false;R.status="stopped";R.failed=false
    R.fallbackTried=false;R.transferStartupPasses=0;R.ticks=0
    R.boxes={};R.seen={};R.squares={}
    R.discoveryRequested=false;R.lastBatchError=nil
end

local function guarded(callback,eventName)
    return function(...)
        local ok,message=pcall(callback,...)
        if not ok then
            R.ready=false;R.operational=false;R.status="error";R.failed=true
            R.errors=R.errors+1
            print("[SuQingFreshnessLunchbox] batch scheduler stopped after "..eventName..": "..tostring(message))
        end
    end
end

Events.OnGameStart.Add(guarded(function() R.fallbackTried=false;R.Start("OnGameStart") end,"OnGameStart"))
Events.OnTickEvenPaused.Add(guarded(R.Tick,"OnTickEvenPaused"))
Events.OnTick.Add(guarded(R.NormalTick,"OnTick"))
Events.LoadGridsquare.Add(guarded(R.ScanSquare,"LoadGridsquare"))
Events.OnSave.Add(guarded(R.Save,"OnSave"))
Events.OnMainMenuEnter.Add(guarded(R.Stop,"OnMainMenuEnter"))
if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(function() R.discoveryRequested=true end) end
if Events.OnRefreshInventoryWindowContainers then
    Events.OnRefreshInventoryWindowContainers.Add(guarded(function(page,phase)
        if R.ready and phase=="end" and page and page.inventory then R.ScanInventory(page.inventory) end
    end,"OnRefreshInventoryWindowContainers"))
end
if Events.OnObjectAdded then
    Events.OnObjectAdded.Add(guarded(function(object)
        local square=object and object.getSquare and object:getSquare()
        if square then R.ScanSquare(square) end
    end,"OnObjectAdded"))
end
return R
