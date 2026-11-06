-- Isolated method-level model; no user data, files, game client or world.
Mock={clock=100,paused=false,id=1000,data={},grid={},players={},process=nil,vehicles=nil}
function require() end
function isClient() return false end
function isServer() return false end
function isGamePaused() return Mock.paused end
function getTimestampMs() return 1106000000 end
function getGameTime() return {getWorldAgeHours=function() return Mock.clock end} end
function instanceof(item,kind) return type(item)=="table" and (item.kind==kind or kind=="IsoGameCharacter" and item.kind=="Player") end
local function list()
    return {items={},size=function(self) return #self.items end,get=function(self,n) return self.items[n+1] end,
        contains=function(self,item) for _,v in ipairs(self.items) do if v==item then return true end end return false end,
        add=function(self,item) self.items[#self.items+1]=item end,
        remove=function(self,item) for n,v in ipairs(self.items) do if v==item then table.remove(self.items,n);return true end end return false end}
end
Mock.list=list
-- IsoCell.getVehicles is a Set in B42.21: deliberately expose no get(index).
local function vehicleSet()
    local result=list()
    result.get=nil
    result.iterator=function(self)
        local i=0
        return {hasNext=function() return i<#self.items end,
            next=function() i=i+1;return self.items[i] end}
    end
    local add=result.add
    result.add=function(self,item) if not self:contains(item) then add(self,item) end end
    return result
end
function Mock.inventory(containing,parent)
    return {items=list(),capacity=4,containing=containing,parent=parent,
        getItems=function(self) return self.items end,getContainingItem=function(self) return self.containing end,
        getParent=function(self) return self.parent end,getVehiclePart=function(self) return self.part end,
        getCapacity=function(self) return self.capacity end,setCapacity=function(self,n) self.capacity=n end,
        getType=function(self) return self.type or "container" end,
        getSourceGrid=function(self) return self.parent and self.parent.square end}
end
function Mock.square(x)
    local s={x=x,y=1,z=0,objects=list(),world=list()}
    function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return self.z end
    function s:getObjects() return self.objects end;function s:getWorldObjects() return self.world end
    Mock.grid[x]=s;return s
end
local ItemIndex={}
function ItemIndex:getFullType() return self.fullType end
function ItemIndex:getID() return self.id end
function ItemIndex:getModData() return self.md end
function ItemIndex:getContainer() return self.container end
function ItemIndex:getWorldItem() return self.world end
local BoxIndex=setmetatable({}, {__index=ItemIndex})
function BoxIndex:getInventory() return self.inventory end
function BoxIndex:setCapacity(n) self.inventory.capacity=n;self.capacity=n end
function BoxIndex:getCapacity() return self.capacity end
function BoxIndex:getWeightReduction() return self.weightReduction end
function BoxIndex:setWeightReduction(n) self.weightReduction=n end
function BoxIndex:canBeEquipped() return self.wearSlot end
local FoodIndex=setmetatable({}, {__index=ItemIndex})
function FoodIndex:getAge() return self.age end
function FoodIndex:setAge(n) self.age=nativeFloat32(n);if self.failWrite then error("mock setter error") end end
function FoodIndex:getLastAged() return self.lastAged end
function FoodIndex:setLastAged(n) self.lastAged=nativeFloat32(n) end
function FoodIndex:getOffAge() return self.fresh end
function FoodIndex:getOffAgeMax() return self.rotten end
function FoodIndex:isRotten() return self.age>=self.rotten end
function FoodIndex:isCooked() return self.cooked or false end
function FoodIndex:isBurnt() return self.burnt or false end
function FoodIndex:isFertilized() return self.fertilized or false end
function FoodIndex:getHeat() return self.heat or 1 end
function FoodIndex:setHeat(n) self.heat=n end
function FoodIndex:getReplaceOnRotten() return self.replacement end
function FoodIndex:setReplaceOnRotten(n) self.replacement=n end
function FoodIndex:updateAge()
    self.nativeCalls=(self.nativeCalls or 0)+1
    if self.lastAged<Mock.clock then
        self.age=nativeFloat32(self.age+(Mock.clock-self.lastAged)/24)
        self.lastAged=nativeFloat32(Mock.clock)
    end
end
Mock.foodIndex=FoodIndex
Food={class="FoodClass"};__classmetatables={[Food.class]={__index=FoodIndex}}
function Mock.box(fullType)
    Mock.id=Mock.id+1
    local b=setmetatable({kind="InventoryContainer",fullType=fullType or "SuQingFreshnessLunchbox.FreshnessLunchbox",
        id=Mock.id,md={},capacity=4,weightReduction=50,weight=1}, {__index=BoxIndex})
    b.inventory=Mock.inventory(b);return b
end
function Mock.food(age,fresh,rotten,replacement)
    Mock.id=Mock.id+1
    return setmetatable({kind="Food",fullType="Base.Apple",id=Mock.id,md={},age=nativeFloat32(age or 1),
        lastAged=nativeFloat32(Mock.clock),fresh=fresh or 5,rotten=rotten or 10,replacement=replacement}, {__index=FoodIndex})
end
function Mock.add(inventory,item)
    if item.container then item.container.items:remove(item) end
    if item.world then item.world.square.world:remove(item.world);item.world=nil end
    item.container=inventory;inventory.items:add(item);return item
end
function Mock.ground(item,square)
    if item.container then item.container.items:remove(item);item.container=nil end
    local w={item=item,square=square,getSquare=function(self) return self.square end,getItem=function(self) return self.item end}
    item.world=w;square.world:add(w);return w
end
function Mock.player(square)
    local p={kind="Player",square=square,getSquare=function(self) return self.square end}
    p.inventory=Mock.inventory(nil,p);function p:getInventory() return self.inventory end
    Mock.players[#Mock.players+1]=p;return p
end
function Mock.furniture(square)
    local p={square=square,getSquare=function(self) return self.square end}
    p.inventory=Mock.inventory(nil,p)
    function p:getContainerCount() return 1 end;function p:getContainerByIndex() return self.inventory end
    square.objects:add(p);return p
end
function Mock.vehicle(square)
    local v={square=square,parts={},getSquare=function(self) return self.square end,
        getPartCount=function(self) return #self.parts end,getPartByIndex=function(self,i) return self.parts[i+1] end}
    local p={vehicle=v,getVehicle=function(self) return self.vehicle end,getItemContainer=function(self) return self.inventory end}
    p.inventory=Mock.inventory();p.inventory.part=p;v.parts={p};Mock.vehicles:add(v);return v,p
end
Mock.process=list();Mock.vehicles=vehicleSet()
Mock.cell={getGridSquare=function(self,x,y,z) return Mock.grid[x] end,
    getProcessItems=function() return Mock.process end,getVehicles=function() return Mock.vehicles end,
    addToProcessItems=function(self,item) if not Mock.process:contains(item) then Mock.process:add(item) end end}
function getCell() return Mock.cell end
function getNumActivePlayers() return #Mock.players end
function getSpecificPlayer(i) return Mock.players[i+1] end
function getPlayer() return Mock.players[1] end
ModData={getOrCreate=function(key) if not Mock.data[key] then Mock.data[key]={} end return Mock.data[key] end}
Events={}
for _,key in ipairs({"OnGameStart","OnTick","OnTickEvenPaused","LoadGridsquare","OnSave","OnMainMenuEnter",
    "OnContainerUpdate","OnRefreshInventoryWindowContainers","OnObjectAdded","OnPlayerUpdate"}) do
    local e={callbacks={}};e.Add=function(fn) e.callbacks[#e.callbacks+1]=fn end;Events[key]=e
end
ISTransferAction={transferItem=function(self,character,item,source,destination)
    if self and self.fail then error("mock transfer error") end
    Mock.add(destination,item);return item,"second",nil,4
end}
SandboxVars={DaysForRottenFoodRemoval=-1,SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}}
function Mock.reset()
    if SuQingFreshnessLunchbox and SuQingFreshnessLunchbox.Runtime then SuQingFreshnessLunchbox.Runtime.Stop() end
    Mock.clock=100;Mock.paused=false;Mock.data={};Mock.grid={};Mock.players={};Mock.process=list();Mock.vehicles=vehicleSet()
    SandboxVars.DaysForRottenFoodRemoval=-1
    SandboxVars.SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}
    if SuQingFreshnessLunchbox then SuQingFreshnessLunchbox.pending=setmetatable({}, {__mode="k"}) end
end
function Mock.setup(age,fresh,rotten,replacement)
    Mock.reset();local s=Mock.square(1);local p=Mock.player(s);local b=Mock.add(p.inventory,Mock.box())
    local f=Mock.add(b.inventory,Mock.food(age,fresh,rotten,replacement))
    SuQingFreshnessLunchbox.Runtime.Start();SuQingFreshnessLunchbox.Runtime.NormalTick();SuQingFreshnessLunchbox.Runtime.NormalTick();return b,f,s,p
end
