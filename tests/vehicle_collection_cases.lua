local F=VehicleCollectionFixture
local R=SuQingFreshnessLunchbox.Runtime
local cases,assertions=0,0
local function eq(actual,expected,label)
    assertions=assertions+1
    assert(actual==expected,(label or "value")..": "..tostring(actual).." ~= "..tostring(expected))
end
local function run(fn) cases=cases+1;F.Reset();fn() end
local function pending(box) return SuQingFreshnessLunchbox.pending[box]==true end

run(function() -- Exact exposed native interface: Set has no indexed get.
    eq(F.vehicles.get,nil,"HashSet.get missing")
    eq(F.vehicles:size(),0);eq(F.vehicles.iterator~=nil,true);eq(F.vehicles.contains~=nil,true)
    local iterator=F.vehicles:iterator();eq(iterator:hasNext(),false)
end)

run(function() -- rc.6 fails only when a vehicle exists, so an empty-cell mock missed it.
    R.ScanVehicles();eq(F.partsScanned,0)
    local vehicle=F.Vehicle(1,true);local box=F.Box(vehicle.parts[1].inventory)
    F.vehicles:add(vehicle)
    local ok,message=pcall(R.ScanVehicles)
    if VehicleCollectionExpectLegacyFailure then
        eq(ok,false,"rc6 indexed Set access must reproduce")
        eq(message~=nil,true,"rc6 failure is retained")
        VehicleCollectionPrint("VEHICLE_COLLECTION_EXPECTED_RC6_ERROR "..tostring(message))
        eq(pending(box),false)
    else
        eq(ok,true,"fixed native Set scan")
        eq(F.partsScanned,1);eq(pending(box),true)
    end
end)

run(function() -- Membership path uses real Set.contains and real List.contains.
    local vehicle=F.Vehicle(1,true);local box=F.Box(vehicle.parts[1].inventory)
    F.vehicles:add(vehicle);eq(R.Location(box),"vehicle")
    F.vehicles:remove(vehicle)
    local location,why=R.Location(box);eq(location,nil);eq(why,"unloaded")
end)

if VehicleCollectionExpectLegacyFailure then
    return "VEHICLE_COLLECTION_LEGACY_REPRO cases="..cases.." assertions="..assertions.." failures=0"
end

run(function() -- Unordered multi-vehicle Set scans each loaded part exactly once.
    local boxes={}
    for x=1,4 do
        local vehicle=F.Vehicle(x,true,2);F.vehicles:add(vehicle);F.vehicles:add(vehicle)
        for _,part in ipairs(vehicle.parts) do boxes[#boxes+1]=F.Box(part.inventory) end
    end
    eq(F.vehicles:size(),4);R.ScanVehicles();eq(F.partsScanned,8)
    for _,box in ipairs(boxes) do eq(pending(box),true) end
end)

run(function() -- Present but unloaded vehicles are not traversed or considered loaded.
    local vehicle=F.Vehicle(8,false);local box=F.Box(vehicle.parts[1].inventory)
    F.vehicles:add(vehicle);R.ScanVehicles();eq(F.partsScanned,0);eq(pending(box),false)
    local location,why=R.Location(box);eq(location,nil);eq(why,"unloaded")
end)

run(function() -- A vehicle without a square is also skipped.
    local vehicle=F.Vehicle(9,true);local box=F.Box(vehicle.parts[1].inventory);vehicle.square=nil
    F.vehicles:add(vehicle);R.ScanVehicles();eq(F.partsScanned,0);eq(pending(box),false)
end)

run(function() -- Nested lunchbox retains exact vehicle membership ownership.
    local vehicle=F.Vehicle(10,true);local outer=F.Box(vehicle.parts[1].inventory);local inner=F.Box(outer.inner)
    F.vehicles:add(vehicle);R.ScanVehicles();eq(pending(outer),true);eq(pending(inner),true)
    eq(R.Location(inner),"vehicle")
    F.vehicles:clear();eq(R.Location(inner),nil)
end)

run(function() -- Stale item membership in a part inventory does not count as loaded.
    local vehicle=F.Vehicle(11,true);local box=F.Box(vehicle.parts[1].inventory)
    F.vehicles:add(vehicle);vehicle.parts[1].inventory.items:remove(box)
    local location,why=R.Location(box);eq(location,nil);eq(why,"unknown_owner")
end)

run(function() -- Optional absence is safe and does not manufacture a collection.
    F.cell=nil;R.ScanVehicles();eq(F.partsScanned,0)
    F.cell={};R.ScanVehicles();eq(F.partsScanned,0)
    F.cell={getVehicles=function() return nil end};R.ScanVehicles();eq(F.partsScanned,0)
end)

run(function() -- Missing per-part inventory is permitted by the real scan contract.
    local vehicle=F.Vehicle(12,true,2);vehicle.parts[1].inventory=nil;vehicle.parts[2].getItemContainer=nil
    F.vehicles:add(vehicle);R.ScanVehicles();eq(F.partsScanned,2)
end)

return "VEHICLE_COLLECTION_FIXED cases="..cases.." assertions="..assertions.." failures=0"
