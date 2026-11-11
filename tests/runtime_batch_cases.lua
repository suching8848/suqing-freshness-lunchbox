-- Load after runtime_mock_bootstrap.lua, Core.lua, Batch.lua, Crafting.lua and Runtime.lua.
local C = SuQingFreshnessLunchbox
local B = C.Batch
local R = C.Runtime
local cases, assertions, failures = 0, 0, 0

C.Lock = {Ready=function() return true end, Refresh=function() end}

local function check(value, message)
    assertions = assertions + 1
    if not value then error(message or "check failed", 0) end
end

local function equal(actual, expected, message)
    check(actual == expected, (message or "not equal")..": "..tostring(actual).." ~= "..tostring(expected))
end

local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001,
        (message or "not near")..": "..tostring(actual).." ~= "..tostring(expected))
end

local function emit(event, ...)
    for _, callback in ipairs(Events[event].callbacks) do callback(...) end
end

local function observe(time)
    Mock.clock = time
    emit("OnTickEvenPaused")
    if not Mock.paused then emit("OnTick") end
end

local function enterWorld()
    emit("OnGameStart")
    emit("OnTick")
    emit("OnTick")
    check(R.ready, "runtime ready")
end

local function addFood(container, age, cookable, replacement)
    local food = Mock.add(container, Mock.food(age, 5, 10, replacement))
    food.cookable = cookable == true
    food.portion, food.poison, food.tainted = 0.4, 7, false
    food.setOffAgeMax = function(self, value) self.rotten = value end
    food.isCookable = function(self) return self.cookable end
    food.setIsCookable = function(self, value) self.cookable = value end
    food.isTainted = function(self) return self.tainted end
    Mock.process:add(food)
    return food
end

local function boxWithFoods(count)
    local player = Mock.player(Mock.square(1))
    local box = Mock.add(player.inventory, Mock.box())
    local foods = {}
    for i = 1, count do
        foods[i] = addFood(box.inventory, 5 + i % 13, i % 2 == 1, "Base.Compost")
    end
    return box, foods, player
end

local function seal(box)
    local ok, reason = R.StartBatch(box)
    check(ok, "seal failed: "..tostring(reason))
    check(B.IsSealed(box), "box remains locked while processing")
    local batch = B.Get(box)
    check(batch and batch.phase == "sealed", "durable sealed record")
    return batch
end

local function cloneData(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = cloneData(v) end
    return copy
end

local function case(name, fn)
    cases = cases + 1
    Mock.reset()
    local ok, reason = pcall(fn)
    if ok then
        print("BATCH_CASE "..name.." PASS")
    else
        failures = failures + 1
        print("BATCH_CASE "..name.." FAIL: "..tostring(reason))
    end
end

case("manual seal freezes the 12-hour roster and gives one reset at the deadline", function()
    local box, foods = boxWithFoods(2)
    local first, second = foods[1], foods[2]
    first.cooked = true
    enterWorld()
    observe(101)
    check(not B.IsSealed(box), "an idle lunchbox does not start automatically")
    near(first.age, 6)

    local batch = seal(box)
    equal(batch.count, 2)
    equal(batch.startedAt, 101)
    equal(batch.endsAt, 113)
    equal(first.rotten, B.nonperishable)
    equal(first.cookable, false)
    equal(first.replacement, "Base.Compost")
    near(first.age, 6, "sealing itself does not refresh food")
    local repeated = R.StartBatch(box)
    check(not repeated, "running batch cannot be restarted")
    equal(B.Get(box), batch, "seal does not replace the active roster")
    SandboxVars.SuQingFreshnessLunchbox.BatchHours = 0.5

    observe(112.999)
    equal(B.Get(box), batch)
    near(first.age, 6)
    observe(113)
    check(not B.IsSealed(box), "deadline completion unlocks the box")
    near(first.age, 0)
    near(second.age, 0)
    equal(first.rotten, 10)
    equal(second.rotten, 10)
    equal(first.cookable, true)
    equal(second.cookable, false)
    equal(first.replacement, "Base.Compost")
    equal(first.lastAged, 113)
    equal(first.portion, 0.4)
    equal(first.poison, 7)
    equal(first.tainted, false)
    equal(first.cooked, true)

    Mock.clock = 114
    first:updateAge(false)
    local naturalAge = first.age
    check(naturalAge > 0, "ordinary aging resumes")
    observe(114)
    near(first.age, naturalAge, "later observations never reset a finished batch")
end)

case("duration clamps to a quarter hour and 24 hours without opening early", function()
    local short, shortFoods = boxWithFoods(1)
    local long = Mock.add(getPlayer():getInventory(), Mock.box())
    local longFood = addFood(long.inventory, 8)
    enterWorld()
    local config = SandboxVars.SuQingFreshnessLunchbox
    config.BatchHours = 0.1
    equal(seal(short).endsAt, 100.25)
    config.BatchHours = 100
    equal(seal(long).endsAt, 124)
    observe(100.249)
    check(B.IsSealed(short) and B.IsSealed(long))
    observe(100.25)
    check(not B.IsSealed(short) and B.IsSealed(long))
    near(shortFoods[1].age, 0)
    near(longFood.age, 8)
    observe(124)
    check(not B.IsSealed(long))
    near(longFood.age, 0)
end)

case("tainted food prevents sealing without mutating a different food", function()
    local box, foods = boxWithFoods(2)
    foods[2].tainted = true
    enterWorld()
    local ok, reason = R.StartBatch(box)
    check(not ok)
    equal(reason, "unsafe_food")
    check(not B.IsSealed(box))
    equal(foods[1].rotten, 10)
    equal(foods[1].cookable, true)
    near(foods[1].age, 6)
end)

case("saved batch survives a new object and completes once on late re-entry", function()
    local box, foods = boxWithFoods(1)
    local food = foods[1]
    enterWorld()
    local batch = seal(box)
    local roster = batch.roster
    observe(107)
    emit("OnSave")
    equal(B.Get(box).roster, roster, "save does not recapture the roster")
    local boxId, foodId = box.id, food.id
    local boxData, foodData = cloneData(box.md), cloneData(food.md)
    local savedAge, savedCookable, savedRotten = food.age, food.cookable, food.rotten

    Mock.reset()
    Mock.clock = 120
    local loaded, loadedFoods = boxWithFoods(1)
    local loadedFood = loadedFoods[1]
    loaded.id, loaded.md = boxId, boxData
    loadedFood.id, loadedFood.md = foodId, foodData
    loadedFood.age, loadedFood.cookable, loadedFood.rotten = savedAge, savedCookable, savedRotten
    enterWorld()
    observe(120)
    check(not B.IsSealed(loaded))
    near(loadedFood.age, 0)
    equal(loadedFood.lastAged, 120, "late observation is the refresh instant")
    equal(loadedFood.rotten, 10)
    equal(loadedFood.cookable, true)
end)

case("unloaded boxes wait for an actual loaded observation before completing", function()
    local box, foods = boxWithFoods(1)
    local food = foods[1]
    enterWorld()
    local square = Mock.square(2)
    Mock.ground(box, square)
    emit("LoadGridsquare", square)
    seal(box)
    Mock.grid[square.x] = nil
    observe(112)
    check(B.IsSealed(box), "unloaded box remains sealed")
    near(food.age, 6)
    Mock.grid[square.x] = square
    emit("LoadGridsquare", square)
    observe(114)
    check(not B.IsSealed(box))
    near(food.age, 0)
    equal(food.lastAged, 114)
end)

case("old on state and paid capacity migrate without an automatic refresh", function()
    local box, foods = boxWithFoods(1)
    local food = foods[1]
    box.md[C.boxKey] = {schema=1,id="SFL:legacy",on=true,epoch=2,baseCapacity=4}
    local paid = {level=5,token="paid upgrade"}
    box.md.SuQingContainerUpgrade = paid
    box:setCapacity(49)
    box.weightReduction = 87
    food.md[C.foodKey] = {schema=1,logicalAge=1,age=food.age,active=true,time=80}
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity = 12
    enterWorld()
    observe(125)
    check(not B.IsSealed(box))
    near(food.age, 6)
    equal(box:getCapacity(), 49)
    equal(box:getInventory():getCapacity(), 49)
    equal(box:getWeightReduction(), 87)
    equal(box.md.SuQingContainerUpgrade, paid)
    seal(box)
    equal(box:getCapacity(), 49, "sealing does not change paid capacity")
end)

case("sealed input and output are rejected but moving the whole box is allowed", function()
    local box, foods, player = boxWithFoods(1)
    local food = foods[1]
    local other = addFood(player.inventory, 8)
    enterWorld()
    check(C.AcceptFood(box.inventory, other))
    seal(box)
    check(not C.AcceptFood(box.inventory, other))
    check(B.IsLockedContainer(box.inventory) and B.IsSealedFood(food))
    ISTransferAction.transferItem({}, player, food, box.inventory, player.inventory)
    equal(food.container, box.inventory, "queued removal is blocked at the final transfer")
    ISTransferAction.transferItem({}, player, other, player.inventory, box.inventory)
    equal(other.container, player.inventory, "queued insertion is blocked at the final transfer")

    local cabinet = Mock.furniture(player.square)
    local moved, second, missing, fourth = ISTransferAction.transferItem({}, player, box,
        player.inventory, cabinet.inventory)
    equal(moved, box)
    equal(second, "second")
    equal(missing, nil)
    equal(fourth, 4)
    equal(box.container, cabinet.inventory)
    check(B.IsSealed(box))
    observe(112)
    check(C.AcceptFood(box.inventory, other))
    ISTransferAction.transferItem({}, player, food, box.inventory, player.inventory)
    equal(food.container, player.inventory)
    near(food.age, 0)
end)

case("partial completion retains the lock and can retry without further credit", function()
    local box, foods = boxWithFoods(2)
    enterWorld()
    local batch = seal(box)
    local attempts, fail = 0, true
    for _, food in ipairs(foods) do
        local original = food.setAge
        food.setAge = function(self, age)
            if age == 0 then
                attempts = attempts + 1
                if fail and attempts == 2 then error("planned second write failure") end
            end
            return original(self, age)
        end
    end
    Mock.clock = 112
    local ok, reason = B.Complete(box, Mock.clock)
    check(not ok, "a partial write reports failure")
    equal(reason, "finish_failed")
    check(B.IsSealed(box), "failed completion keeps the box locked")
    equal(B.Get(box).id, batch.id)
    fail = false
    check(B.Complete(box, Mock.clock), "failed batch can resume")
    check(not B.IsSealed(box))
    near(foods[1].age, 0)
    near(foods[2].age, 0)
    equal(foods[1].rotten, 10)
    equal(foods[2].rotten, 10)
    local finishedAttempts = attempts
    B.Complete(box, Mock.clock)
    observe(113)
    equal(attempts, finishedAttempts, "completion cannot reapply")
end)

case("foreign replacement with a reused native ID cannot claim a sealed member's place", function()
    local box, foods, player = boxWithFoods(2)
    local removed, remaining = foods[1], foods[2]
    enterWorld()
    seal(box)
    local removedAge, remainingAge = removed.age, remaining.age
    Mock.add(player.inventory, removed)
    check(B.RecoverFood(removed), "moved member can recover its original native fields")
    near(removed.age, removedAge)
    equal(removed.rotten, 10)
    equal(removed.cookable, true)
    local intruder = addFood(box.inventory, 9)
    intruder.id = removed.id

    Mock.clock = 112
    local ok, reason = B.Complete(box, Mock.clock)
    check(not ok)
    equal(reason, "manifest_changed")
    check(not B.IsSealed(box), "validated recovery unlocks the changed batch")
    near(intruder.age, 9, "replacement food receives no refresh")
    near(remaining.age, remainingAge, "an invalid roster grants no refresh")
    equal(remaining.rotten, 10)
    equal(remaining.cookable, false)
end)

local function measureWaitingTick(count, sealed)
    Mock.reset()
    local box, foods = boxWithFoods(count)
    enterWorld()
    local batch = sealed and seal(box) or nil
    local inventoryReads, processReads, foodCalls = 0, 0, 0
    local items = box.inventory.getItems
    box.inventory.getItems = function(self)
        inventoryReads = inventoryReads + 1
        return items(self)
    end
    local getProcessItems = Mock.cell.getProcessItems
    Mock.cell.getProcessItems = function(self)
        processReads = processReads + 1
        return getProcessItems(self)
    end
    for _, food in ipairs(foods) do
        for _, method in ipairs({"getAge","setAge","getContainer","getModData","getID","getFullType",
            "getOffAge","getOffAgeMax","setOffAgeMax","setLastAged","getLastAged","updateAge",
            "isCookable","setIsCookable","isTainted"}) do
            local original = food[method]
            food[method] = function(self, ...)
                foodCalls = foodCalls + 1
                return original(self, ...)
            end
        end
    end
    for i = 1, 240 do observe(100 + i / 1000) end
    Mock.cell.getProcessItems = getProcessItems
    print("LUNCHBOX_BATCH_WAIT foods="..count.." sealed="..tostring(sealed)
        .." inventoryReads="..inventoryReads.." processReads="..processReads.." foodCalls="..foodCalls)
    check(R.ready)
    equal(inventoryReads, 0, "periodic discovery must not enumerate the lunchbox")
    equal(processReads, 0, "no process-item discovery from ticks")
    equal(foodCalls, 0, "waiting ticks do not read or write individual foods")
    if batch then
        equal(B.Get(box), batch)
        equal(batch.count, count)
    end
end

case("waiting work has no per-food reads or writes even across periodic discovery", function()
    measureWaitingTick(32, false)
    measureWaitingTick(32, true)
    measureWaitingTick(64, true)
    measureWaitingTick(128, true)
end)

case("same-session reentry captures a startup transfer wrapper exactly once", function()
    local box, foods, player=boxWithFoods(1)
    enterWorld()
    local batch=seal(box)
    emit("OnMainMenuEnter")
    local previous=ISTransferAction.transferItem
    local calls=0
    ISTransferAction.transferItem=function(...)
        calls=calls+1
        return previous(...)
    end
    enterWorld()
    check(R.CanStartBatch(),"startup can capture the rewrapped chain")
    ISTransferAction.transferItem({},player,foods[1],box.inventory,player.inventory)
    equal(calls,0,"outer wrapper blocks sealed food before delegation")
    observe(batch.endsAt)
    check(not B.IsSealed(box))
    ISTransferAction.transferItem({},player,foods[1],box.inventory,player.inventory)
    equal(calls,1,"unsealed transfer follows the startup chain once")
    equal(foods[1]:getContainer(),player.inventory)
end)

print("RUNTIME_BATCH cases="..cases.." assertions="..assertions.." failures="..failures)
if failures > 0 then error("batch regression failures: "..failures) end
