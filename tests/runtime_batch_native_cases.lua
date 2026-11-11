-- Run after runtime_native_bootstrap.lua, Core.lua and Batch.lua in the native item probe.
local C = SuQingFreshnessLunchbox
local B = C.Batch
local check, near, test = Native.check, Native.near, Native.test

test("sealed Food guards and the manifest survive actual native ModData serialization", function()
    SandboxVars.DaysForRottenFoodRemoval = 0
    SandboxVars.SuQingFreshnessLunchbox.BatchHours = 0.5
    ProbeRemoval:setValue(0)

    local box = ProbeMakeBox()
    local food = ProbeMakeFood(15, 5, 10, "Base.Compost")
    food:setIsCookable(true)
    box:getInventory():AddItem(food)
    check(C.EnsureBox(box))
    local taintedSeal, taintedReason = B.Start(box, Native.now())
    check(not taintedSeal and taintedReason == "unsafe_food", "tainted native food is refused")
    food:setTainted(false)
    local originalId = food:getID()
    local calories, hunger = food:getCalories(), food:getHungerChange()
    local poison, tainted, cooked = food:getPoisonPower(), food:isTainted(), food:isCooked()
    check(food:isRotten(), "test starts with actually rotten food")
    local start = Native.now()
    local ok, reason = B.Start(box, start)
    check(ok, "native seal failed: "..tostring(reason))
    local batch = B.Get(box)
    near(batch.endsAt - start, 0.5)
    near(food:getAge(), 15)
    check(food:getOffAgeMax() == B.nonperishable and not food:isCookable())
    check(food:getReplaceOnRotten() == "Base.Compost")
    ProbeNativeRot(food, box:getInventory())
    check(box:getInventory():getItems():contains(food), "native rot/deletion did not replace the sealed food")

    -- The native probe constructs a fresh item before loading its bytes. Give
    -- that item the ordinary script defaults so passing proves load applied
    -- the persisted sentinel and cookability, rather than inheriting them.
    local restoredFood = ProbeRoundTrip(food, 10, true)
    check(restoredFood:getID() == originalId, "native item ID survives round trip")
    check(restoredFood:getOffAgeMax() == B.nonperishable, "native save persisted the spoilage sentinel")
    check(not restoredFood:isCookable(), "native save persisted the cooking guard")
    check(restoredFood:getModData()[B.foodKey], "native save persisted the food receipt")

    -- InventoryItem's ModData codec is shared by Food and InventoryContainer.
    -- Serialize the box's data through a separate native carrier. Rebuild the
    -- box with the same item ID instead of testing a live Lua table alias.
    local carrier = ProbeMakeFood(1, 5, 10)
    carrier:getModData()[C.boxKey] = box:getModData()[C.boxKey]
    carrier:getModData()[B.boxKey] = batch
    local saved = ProbeRoundTrip(carrier):getModData()
    local rebuilt = ProbeMakeBox()
    rebuilt:setID(box:getID())
    rebuilt:getModData()[C.boxKey] = saved[C.boxKey]
    rebuilt:getModData()[B.boxKey] = saved[B.boxKey]
    rebuilt:getInventory():AddItem(restoredFood)
    check(B.Get(rebuilt) ~= batch and B.IsSealed(rebuilt), "serialized box manifest is durable")

    local late = Native.advance(8)
    check(late > batch.endsAt, "world clock advanced well past the deadline")
    ProbeNativeAge(restoredFood)
    ProbeNativeRot(restoredFood, rebuilt:getInventory())
    check(rebuilt:getInventory():getItems():contains(restoredFood), "late native rot cannot remove the sealed item")
    local completed, completionReason = B.Complete(rebuilt, late)
    check(completed, "native completion failed: "..tostring(completionReason))
    check(not B.IsSealed(rebuilt))
    near(restoredFood:getAge(), 0)
    near(restoredFood:getLastAged(), late)
    check(restoredFood:getOffAge() == 5 and restoredFood:getOffAgeMax() == 10)
    check(restoredFood:isCookable())
    check(restoredFood:getReplaceOnRotten() == "Base.Compost")
    near(restoredFood:getCalories(), calories)
    near(restoredFood:getHungerChange(), hunger)
    check(restoredFood:getPoisonPower() == poison, "poison value was preserved")
    check(restoredFood:isTainted() == tainted, "taint state was preserved")
    check(restoredFood:isCooked() == cooked)
    check(restoredFood:getModData()[B.foodKey] == nil)
    ProbeRemoval:setValue(-1)
end)

print("RUNTIME_BATCH_NATIVE cases="..Native.cases.." assertions="..Native.assertions.." PASS")
