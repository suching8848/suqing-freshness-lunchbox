-- Deterministic inventory/actor shells only. No save or world is opened.
require=function() return true end
local callbacks={}
Events=setmetatable({}, {__index=function(t,k)
    callbacks[k]={};local e={Add=function(fn) table.insert(callbacks[k],fn) end};rawset(t,k,e);return e
end})
function emit(name,...) for _,fn in ipairs(callbacks[name] or {}) do fn(...) end end
function isClient() return false end
function isServer() return false end
function instanceof(item,kind) return type(item)=='table' and item.kind==kind end
function getTimestampMs() return 1793920000000 end
function getText(key,...) return key end
function getTextOrNull(key,...) return key end
SandboxVars={SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}}
ItemTag={SCREWDRIVER={name='screwdriver'}}
ItemType={CONTAINER={name='container'}}
Perks={Tailoring={name='Tailoring'}}
function list(values)
    local t={values=values or {}}
    function t:size()return #self.values end
    function t:get(i)return self.values[i+1]end
    function t:add(v)
        if self.failAdd then self.failAdd=false;error('injected add failure') end
        table.insert(self.values,v)
    end
    function t:contains(v)for _,x in ipairs(self.values)do if x==v then return true end end return false end
    function t:clear()self.values={}end
    function t:remove(v)for i,x in ipairs(self.values)do if x==v then table.remove(self.values,i);return true end end return false end
    return t
end
local serial=0
function inventory()
    local t={items=list(),capacity=4}
    function t:getItems()return self.items end
    function t:getCapacity()return self.capacity end
    function t:setCapacity(v)self.capacity=v end
    function t:AddItem(item)self.items:add(item);item.container=self;return item end
    function t:Remove(item)self.items:remove(item);if item.container==self then item.container=nil end end
    return t
end
function item(id,kind)
    serial=serial+1
    local t={id=serial,fullType=id,kind=kind or 'InventoryItem',md={},favorite=false,equipped=false,
        weight=1,reduction=50,uses=1,condition=8,inner=kind=='InventoryContainer' and inventory() or nil}
    function t:getID()return self.id end
    function t:getFullType()return self.fullType end
    function t:getModData()return self.md end
    function t:getContainer()return self.container end
    function t:getInventory()return self.inner end
    function t:getActualWeight()return self.weight end
    function t:getWeightReduction()return self.reduction end
    function t:setWeightReduction(v)self.reduction=v end
    function t:setCapacity(v)self.inner.capacity=math.min(v,math.floor(50-self.weight))end
    function t:isFavorite()return self.favorite end
    function t:isEquipped()return self.equipped end
    function t:getWorldItem()return nil end
    function t:hasTag(tag)return self.screwdriver and tag==ItemTag.SCREWDRIVER end
    function t:getCurrentUsesFloat()return self.uses end
    function t:setCurrentUsesFloat(v)self.uses=v end
    function t:getUseDelta()return .05 end
    function t:getCurrentUses()return math.floor(self.uses/.05+.00001)end
    function t:setDrawDirty(v)self.dirty=v end
    return t
end
function instanceItem(id)return item(id)end
function actor()
    local t={inventory=inventory()}
    function t:getInventory()return self.inventory end
    function t:isEquipped(v)return v.equipped or self.primary==v or self.secondary==v end
    function t:getPrimaryHandItem()return self.primary end
    function t:getSecondaryHandItem()return self.secondary end
    function t:getPerkLevel()return 10 end
    return t
end
ISBaseTimedAction={derive=function(self,name)local t={};setmetatable(t,{__index=self});return t end,
    perform=function()end,stop=function(self)self.stopped=true end}
Actions={addOrDropItem=function(character,value)character:getInventory():AddItem(value)end}
ArrayList={new=function()return list()end}
ISToolTip={new=function()return{initialise=function()end,setVisible=function()end}end}
Mock={}
function Mock.context()
    local t={options={}}
    function t:addOption(label,target,fn)local o={label=label,target=target,callback=fn};self.options[#self.options+1]=o;return o end
    return t
end
return 'INTEGRATION bootstrap ready'
