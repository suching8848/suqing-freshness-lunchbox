-- Only collection exposition is native. Cell, square, vehicle, part and item
-- method shells are explicit deterministic fixtures, not real game objects.
function require() end
function isClient() return false end
function isServer() return false end
local events={}
Events=setmetatable({}, {__index=function(t,name)
    local list={};events[name]=list
    local event={Add=function(fn) list[#list+1]=fn end};rawset(t,name,event);return event
end})
SuQingFreshnessLunchbox={pending={},IsBox=function(item) return type(item)=="table" and item.box==true end,
    EnsureBox=function(item) return item end}
function instanceof(item,name) return type(item)=="table" and item.kind==name end
VehicleCollectionFixture={}
local F=VehicleCollectionFixture
function F.Reset()
    F.vehicles=VehicleCollectionMakeSet();F.grid={};F.partsScanned=0
    F.cell={getVehicles=function() return F.vehicles end,
        getGridSquare=function(self,x,y,z) return F.grid[x..":"..y..":"..z] end}
    SuQingFreshnessLunchbox.pending={}
end
function getCell() return F.cell end
function F.Square(x,loaded)
    local square={getX=function() return x end,getY=function() return 2 end,getZ=function() return 0 end}
    if loaded~=false then F.grid[x..":2:0"]=square end
    return square
end
function F.Inventory(containing)
    local inventory={items=VehicleCollectionMakeList(),containing=containing}
    function inventory:getItems() return self.items end
    function inventory:getContainingItem() return self.containing end
    function inventory:getVehiclePart() return self.part end
    return inventory
end
function F.Box(inventory)
    local box={box=true,kind="InventoryContainer",owner=inventory}
    function box:getContainer() return self.owner end
    function box:getWorldItem() return nil end
    function box:getInventory() return self.inner end
    box.inner=F.Inventory(box)
    if inventory then inventory.items:add(box) end
    return box
end
function F.Vehicle(x,loaded,partCount)
    local vehicle={square=F.Square(x,loaded),parts={}}
    function vehicle:getSquare() return self.square end
    function vehicle:getPartCount() return #self.parts end
    function vehicle:getPartByIndex(index) F.partsScanned=F.partsScanned+1;return self.parts[index+1] end
    for i=1,(partCount or 1) do
        local part={vehicle=vehicle,inventory=F.Inventory()}
        function part:getVehicle() return self.vehicle end
        function part:getItemContainer() return self.inventory end
        part.inventory.part=part;vehicle.parts[i]=part
    end
    return vehicle
end
F.Reset()
