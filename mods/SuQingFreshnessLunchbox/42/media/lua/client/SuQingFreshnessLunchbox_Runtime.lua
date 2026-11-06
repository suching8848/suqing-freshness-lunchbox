require "SuQingFreshnessLunchbox/Core"
require "TimedActions/ISTransferAction"
local C=SuQingFreshnessLunchbox
C.Runtime=C.Runtime or {}
local R=C.Runtime
if R.loaded then return R end
R.loaded=true
R.status="waiting"
R.operational=false
R.boxes=setmetatable({}, {__mode="k"})
R.foods=setmetatable({}, {__mode="k"})
R.squares=setmetatable({}, {__mode="k"})
R.stats={settled=0,active=0,anchors=0,errors=0}

local function now() return getGameTime():getWorldAgeHours() end
local function paused() return type(isGamePaused)=="function" and isGamePaused() or false end
local function timelineConfig()
    local config=C.Config()
    if not R.operational then config.enabled=false end
    return config
end
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

function R.RestoreAll()
    for food in pairs(R.foods) do C.RestoreFood(food) end
end
function R.Forget(box,uncertain)
    for food,owner in pairs(R.foods) do
        if owner==box then
            C.RestoreFood(food)
            local record=C.FoodRecord(food)
            if uncertain and record then record.ownershipUncertain=true end
            R.foods[food]=nil
        end
    end
    R.boxes[box]=nil
    -- Keep valid per-food timestamps: a later same-box load can prove coverage.
end
function R.SettleBox(box,time,forceAnchor)
    local location,reason=R.Location(box)
    if not location then R.Forget(box,reason~="unloaded");return false end
    if not C.EnsureBox(box) then R.Forget(box);return false end
    local list=C.GetInventory(box):getItems()
    for i=0,list:size()-1 do
        local food=list:get(i)
        if C.IsFood(food) then
            local result=C.SettleFood(food,box,time,R.timeline,forceAnchor)
            R.foods[food]=box
            R.stats.settled=R.stats.settled+1
            if result.active then R.stats.active=R.stats.active+1 end
            if result.elapsed==0 then R.stats.anchors=R.stats.anchors+1 end
        end
    end
    return true
end
function R.Register(box)
    if not C.IsBox(box) or not C.EnsureBox(box) then return false end
    if not R.ready then C.pending[box]=true;return true end
    if not R.IsLoaded(box) then return false end
    local existed=R.boxes[box]
    R.boxes[box]=true;C.pending[box]=nil
    if not existed then R.SettleBox(box,now(),not R.operational or not C.AgeHookReady()) end
    return true
end
function R.ScanInventory(inventory,seen,depth)
    if not inventory then return end
    seen=seen or {};depth=depth or 0
    if seen[inventory] or depth>32 then return end
    seen[inventory]=true
    local containing=inventory.getContainingItem and inventory:getContainingItem()
    if C.IsBox(containing) then R.Register(containing) end
    local list=inventory:getItems()
    for i=0,list:size()-1 do
        local item=list:get(i)
        if C.IsBox(item) then R.Register(item) end
        if type(instanceof)=="function" and instanceof(item,"InventoryContainer") then
            R.ScanInventory(item:getInventory(),seen,depth+1)
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
            if C.IsBox(item) then R.Register(item) end
            if item and type(instanceof)=="function" and instanceof(item,"InventoryContainer") then
                R.ScanInventory(item:getInventory())
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
    for i=0,vehicles:size()-1 do
        local vehicle=vehicles:get(i)
        if loadedSquare(vehicle:getSquare()) then
            for n=0,vehicle:getPartCount()-1 do
                local part=vehicle:getPartByIndex(n)
                if part and part.getItemContainer then R.ScanInventory(part:getItemContainer()) end
            end
        end
    end
end
function R.DiscoverProcessItems()
    local cell=type(getCell)=="function" and getCell()
    local items=cell and cell.getProcessItems and cell:getProcessItems()
    local size=items and items:size() or 0
    if size==0 then R.cursor=nil;return end
    for _=1,math.min(size,64) do
        R.cursor=((R.cursor or -1)+1)%size
        local food=items:get(R.cursor)
        local inventory=food and food.getContainer and food:getContainer()
        local box=inventory and inventory.getContainingItem and inventory:getContainingItem()
        if C.IsBox(box) then R.Register(box) end
    end
end
function R.Observe()
    local ok,reason=C.ObserveTimeline(R.timeline,R.session,now(),timelineConfig(),paused())
    if not ok then error("lunchbox timeline: "..tostring(reason)) end
end
function R.Tick()
    if not R.ready then return end
    -- ISA queues its forwarding layer on the first normal OnTick. Our normal
    -- tick listener captures that completed startup chain. Before that listener
    -- runs there is no transfer hook to validate, including paused startup.
    if R.transfer and not R.InstallTransferHook() then error("lunchbox transfer chain changed") end
    R.Observe()
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for box in pairs(C.pending) do R.Register(box) end
    R.ticks=(R.ticks or 0)+1
    if R.ticks==1 or R.ticks%30==0 then R.ScanPlayers();R.ScanVehicles() end
    R.DiscoverProcessItems()
    for food,box in pairs(R.foods) do
        if not C.IsDirectFood(food,box) then C.ClearFood(food);R.foods[food]=nil end
    end
    local time=now()
    for box in pairs(R.boxes) do R.SettleBox(box,time,not R.operational) end
end
function R.Toggle(box)
    if not R.ready or not R.operational or not R.IsLoaded(box) then return false end
    R.Observe();R.Register(box);R.SettleBox(box,now(),false)
    local state=C.BoxState(box)
    if not state then return false end
    state.on=not state.on;state.epoch=state.epoch+1
    R.SettleBox(box,now(),true)
    return true
end

local function ownerOf(food)
    local inventory=C.IsFood(food) and food:getContainer()
    local box=inventory and inventory.getContainingItem and inventory:getContainingItem()
    return C.IsDirectFood(food,box) and box or nil
end
local function pack(...) return {n=select("#",...),...} end
function R.InstallTransferHook()
    if R.transfer then return ISTransferAction and ISTransferAction.transferItem==R.transfer.wrapper end
    if not ISTransferAction or type(ISTransferAction.transferItem)~="function" then return false end
    local prior=ISTransferAction.transferItem
    local wrapper=function(self,character,item,source,destination,...)
        if not R.ready then return prior(self,character,item,source,destination,...) end
        R.Observe()
        if C.IsBox(item) then R.Register(item);R.SettleBox(item,now(),false) end
        if C.IsFood(item) then
            local box=ownerOf(item)
            if box then C.SettleFood(item,box,now(),R.timeline,false) end
            C.RestoreFood(item)
        end
        local result=pack(pcall(prior,self,character,item,source,destination,...))
        local finalOK,finalError=pcall(function()
            if C.IsBox(item) then R.Register(item);R.SettleBox(item,now(),false) end
            if C.IsFood(item) then
                local box=ownerOf(item)
                if box then R.Register(box);C.SettleFood(item,box,now(),R.timeline,true);R.foods[item]=box
                else C.ClearFood(item);R.foods[item]=nil end
            end
            local output=result[1] and result[2] or nil
            if output~=nil and output~=item then
                if C.IsBox(output) then R.Register(output) end
                if C.IsFood(output) then
                    local box=ownerOf(output)
                    if box then R.Register(box);C.SettleFood(output,box,now(),R.timeline,true);R.foods[output]=box end
                end
            end
        end)
        if not result[1] then error(result[2]) end
        if not finalOK then error(finalError) end
        return unpack(result,2,result.n)
    end
    R.transfer={prior=prior,wrapper=wrapper}
    ISTransferAction.transferItem=wrapper
    return true
end
function R.Start(origin)
    if R.ready then return false end
    if not C.SP() then R.status="unsupported";return false end
    R.status="starting";R.failed=false;R.lastError=nil
    R.operational=R.transfer~=nil and ISTransferAction and ISTransferAction.transferItem==R.transfer.wrapper or false
    if not ModData or type(ModData.getOrCreate)~="function" then error("lunchbox world ModData unavailable") end
    R.timeline=ModData.getOrCreate(C.timelineKey)
    local session,reason=C.OpenTimeline(R.timeline,now(),timelineConfig(),paused())
    if not session then error("lunchbox timeline unavailable: "..tostring(reason)) end
    C.InstallAgeHook() -- If unavailable, native-age reconciliation fails closed.
    C.InstallCoolingBridge()
    if not ISTransferAction or type(ISTransferAction.transferItem)~="function" then
        error("lunchbox transfer chain unavailable")
    end
    R.session=session;R.ready=true;R.ticks=0
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for box in pairs(C.pending) do R.Register(box) end
    R.ScanPlayers();R.ScanVehicles();R.DiscoverProcessItems()
    R.status=R.operational and "ready" or "waiting_transfer"
    print("[SuQingFreshnessLunchbox] "..C.version.." single-player ready via "..tostring(origin or "explicit start").."; coverage-verified game-time restoration")
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
    -- One fallback attempt is allowed only for a verifiably loaded SP world.
    -- A detected error stays stopped until the next explicit game-start event.
    if not R.ready and not R.failed and not R.fallbackTried and R.HasLoadedPlayerWorld() then
        R.fallbackTried=true;R.Start("loaded-world fallback")
    end
    if not R.ready then return end
    if not R.transfer then
        -- A one-shot OnTick queue can be registered before or after us. Let one
        -- entire normal dispatch finish before capturing its final continuation.
        R.transferStartupPasses=(R.transferStartupPasses or 0)+1
        if R.transferStartupPasses<2 then return end
    end
    local starting=not R.operational
    if not R.InstallTransferHook() then error("lunchbox transfer chain changed") end
    R.operational=true
    if starting then
        R.Observe()
        for box in pairs(R.boxes) do R.SettleBox(box,now(),true) end
    end
    R.status="ready"
end
function R.Save()
    if not R.ready then return end
    R.Observe()
    for box in pairs(R.boxes) do R.SettleBox(box,now(),not R.operational) end
    -- Age is always real. Replacement guards may remain in memory through save:
    -- the native Food save does not serialize replaceOnRotten; the owned receipt
    -- is safe to recover when the newly loaded native item has its original rule.
end
function R.Stop()
    R.RestoreAll();R.ready=false;R.session=nil;R.timeline=nil;R.cursor=nil;R.ticks=0
    R.status="stopped";R.operational=false;R.failed=false;R.lastError=nil;R.fallbackTried=false;R.transferStartupPasses=0
    R.boxes=setmetatable({}, {__mode="k"});R.foods=setmetatable({}, {__mode="k"})
    R.squares=setmetatable({}, {__mode="k"})
end
local function guarded(callback,eventName)
    return function(...)
        local ok,message=pcall(callback,...)
        if not ok then
            local restored,restoreError=pcall(R.RestoreAll)
            R.ready=false;R.operational=false;R.status="error";R.failed=true;R.lastError=tostring(message);R.stats.errors=R.stats.errors+1
            print("[SuQingFreshnessLunchbox] disabled after "..tostring(eventName or "callback").." error: "..tostring(message)
                ..(restored and "" or "; restore failed: "..tostring(restoreError)))
        end
    end
end
Events.OnGameStart.Add(guarded(function() R.fallbackTried=false;R.Start("OnGameStart") end,"OnGameStart"))
Events.OnTickEvenPaused.Add(guarded(R.Tick,"OnTickEvenPaused"))
Events.OnTick.Add(guarded(R.NormalTick,"OnTick"))
Events.LoadGridsquare.Add(guarded(R.ScanSquare))
Events.OnSave.Add(guarded(R.Save))
Events.OnMainMenuEnter.Add(guarded(R.Stop))
if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(guarded(function() if R.ready then R.ScanPlayers();R.DiscoverProcessItems() end end)) end
if Events.OnRefreshInventoryWindowContainers then Events.OnRefreshInventoryWindowContainers.Add(guarded(function(page,phase)
    if R.ready and phase=="end" and page and page.inventory then R.ScanInventory(page.inventory) end
end)) end
if Events.OnObjectAdded then Events.OnObjectAdded.Add(guarded(function(object)
    local square=object and object.getSquare and object:getSquare()
    if square then R.ScanSquare(square) end
end)) end
return R
