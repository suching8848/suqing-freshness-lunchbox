-- Real EX/HavenFall/main Lua is loaded unchanged. Author baselines and loaded
-- script-manager state are fixtures; native mode uses actual native item/script
-- and CraftRecipe objects. No world or native HandcraftLogic is constructed.
Guard={native=type(ProbeMakeBox)=='function',events={},baseline={}}
function getText(key,...) return key end
function getTextOrNull(key,...) return key end
Events=setmetatable({}, {__index=function(t,key)
    local handlers={};Guard.events[key]=handlers
    local e={Add=function(fn)handlers[#handlers+1]=fn end};rawset(t,key,e);return e
end})
function emit(key,...)for _,fn in ipairs(Guard.events[key] or {})do fn(...)end end
if not ISBaseTimedAction then
    ISBaseTimedAction={derive=function(self,name)local t={};setmetatable(t,{__index=self});return t end,perform=function()end,stop=function()end}
end
function Guard.list(values)
    local l={values=values or {}}
    function l:size()return #self.values end
    function l:get(i)return self.values[i+1]end
    function l:add(item)self.values[#self.values+1]=item end
    function l:contains(item)for _,v in ipairs(self.values)do if v==item then return true end end return false end
    function l:clear()self.values={}end
    return l
end
ArrayList={new=function()return Guard.list()end}
Actions={addOrDropItem=function(character,item)character:getInventory():AddItem(item)end}
ISTimedActionQueue={add=function()end};ISInventoryTransferAction={new=function()return{}end}
javaTransferItems=function()return 'native-transfer-fixture'end
if not Guard.native then
    local previous=instanceof
    function instanceof(item,kind)return previous(item,kind) or kind=='InventoryItem' and item and (item.kind=='InventoryContainer' or item.kind=='DrainableComboItem') end
    ItemContainer={class='GuardItemContainer',floatingPointCorrection=function(n)return n end}
    __classmetatables={[ItemContainer.class]={__index={}}}
    local oldInventory=inventory
    function inventory()
        local inv=oldInventory()
        function inv:getContainingItem()return self.owner end
        function inv:getEffectiveCapacity(character)return __classmetatables[ItemContainer.class].__index.getEffectiveCapacity(self,character)end
        function inv:hasRoomFor(...)return __classmetatables[ItemContainer.class].__index.hasRoomFor(self,...)end
        return inv
    end
end
local index=__classmetatables[ItemContainer.class].__index
local oldEffective=index.getEffectiveCapacity or function(container)return container:getCapacity()end
index.hasRoomFor=index.hasRoomFor or function()return true end
for _,name in ipairs({'EsBackpack','SeanBackpack','SeanragBackpack','ZhiziBackpack','GugaBackpack'})do
    for n,suffix in ipairs({'','_T1','_T2','_T3'})do Guard.baseline['ESHF.'..name..suffix]=({60,80,100,120})[n] end
end
function ESHF_getEffectiveCapacity(prior)
    return function(container,character,...)
        local bag=container.getContainingItem and container:getContainingItem()
        local name=bag and bag:getType() or container.getType and container:getType()
        return Guard.baseline['ESHF.'..tostring(name)] or prior(container,character,...)
    end
end
index.getEffectiveCapacity=ESHF_getEffectiveCapacity(oldEffective)
Guard.scripts={};Guard.recipes={}
for id in pairs(Guard.baseline)do
    local script=Guard.native and IntegrationMakeScript(id) or {id=id}
    if not Guard.native then
        function script:getFullName()return self.id end
        function script:isItemType(kind)return kind==ItemType.CONTAINER end
        function script:getObsolete()return false end
        function script:isHidden()return false end
    end
    Guard.scripts[id]=script
end
for _,name in ipairs({'ExSuQingSuperUpgrade','ExSuQingRestore'})do
    local recipe
    if Guard.native then recipe=IntegrationMakeEXRecipe(name)
    else
        local input={ids=Guard.list({'Base.Existing'}),cache=Guard.list({'existing-script'})}
        function input:isKeep()return true end;function input:isItemCount()return true end
        function input:getItems()return self.ids end;function input:getPossibleInputItems()return self.cache end
        recipe={getInputs=function()return Guard.list({input})end}
    end
    Guard.recipes['ExSuQingBackpackSuperUpgrade.'..name]=recipe
end
function getScriptManager()return {getItem=function(self,id)return Guard.scripts[id]end,getCraftRecipe=function(self,id)return Guard.recipes[id]end}end
function Guard.actor()
    local a=actor()
    function a:hasTrait()return false end
    function a:getPlayerNum()return 0 end
    return a
end
function Guard.box(a,id)
    local box=Guard.native and ProbeMakeBox(id) or item(id,'InventoryContainer')
    if not Guard.native then
        box.inner.owner=box
        function box:getType()return string.match(self.fullType,'%.(.+)$')end
    end
    a:getInventory():AddItem(box);return box
end
function Guard.material(a,id)
    local m=Guard.native and IntegrationMakeMaterial(id) or item(id)
    if not Guard.native and id=='Base.Screwdriver' then m.screwdriver=true end
    a:getInventory():AddItem(m);return m
end
function Guard.recipe(full)return {getScriptObjectFullType=function()return full end,getName=function()return full end}end
ISInventoryPage={dirtyUI=function()end}
function getPlayerInventory()return nil end
function getPlayerLoot()return nil end
