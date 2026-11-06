local C,F=SuQingFreshnessLunchbox,SuQingFreshnessLunchbox.Crafting
local checks,cases=0,0
local function check(v,label)checks=checks+1;assert(v,label)end
local function eq(a,b,label)checks=checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..' ~= '..tostring(b))end
local function case(name,fn)cases=cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why))end
C.Runtime={ready=true,operational=true,Register=function()return true end,Toggle=function(box)local s=C.BoxState(box);s.on=not s.on;return true end}
local function prepare(mode,digital,classic)
    mode=mode or 'lunchbox'
    local a=actor();local materials={};local source
    local function add(id,kind)local v=item(id,kind);a.inventory:AddItem(v);materials[#materials+1]=v;return v end
    if mode=='lunchbox' then source=add('Base.Lunchbox','InventoryContainer')
    else add('Base.SmallSheetMetal');add('Base.SmallSheetMetal') end
    add(digital or 'Base.WristWatch_Left_DigitalBlack')
    add('Base.Pocketwatch');add(classic or 'Base.WristWatch_Right_ClassicGold')
    add('Base.ElectricWire');add('Base.ElectricWire')
    local tool=add('Base.Screwdriver');tool.screwdriver=true;tool.favorite=true
    local recipe={getScriptObjectFullType=function()return 'SuQingFreshnessLunchbox.MakeFreshnessLunchboxFrom'..(mode=='metal' and 'Metal' or 'Lunchbox')end}
    local data={inputs=list(materials),created=list(),consumed=list(),paid=0,performed=0}
    function data:getRecipe()return recipe end
    function data:getAllInputItems()return self.inputs end
    function data:getAllCreatedItems()return self.created end
    function data:getAllConsumedItems()return self.consumed end
    function data:luaCallOnCreate(character)F.OnCreate(self,character)end
    function data:processDestroyAndUsedItems(character)
        self.paid=self.paid+1
        for _,v in ipairs(materials)do if v~=tool then a.inventory:Remove(v);self.consumed:add(v)end end
    end
    local logic={getRecipeData=function()return data end,performCurrentRecipe=function()
        data.performed=data.performed+1
        if data.nativeFailure then return false end
        local out=item(C.FullType,'InventoryContainer');out.condition=source and source.condition or 10
        data.created:add(out);return true
    end,getCreatedOutputItems=function(_,outputs)for _,v in ipairs(data.created.values)do outputs:add(v)end end}
    local action=setmetatable({character=a,logic=logic,craftRecipe=recipe},{__index=ISHandcraftAction})
    return a,source,materials,tool,data,action
end
emit('OnGameStart')
case('native food filter uses class identity',function()
    check(C.AcceptFood(nil,item('Other.CookingCategorizedFood','Food')),'food accepted')
    check(not C.AcceptFood(nil,item('Base.ElectricWire')),'wire rejected')
    check(not C.AcceptFood(nil,item(C.FullType,'InventoryContainer')),'box nesting rejected')
end)
for _,mode in ipairs({'lunchbox','metal'})do
case(mode..' route completes the actual vanilla Lua payment flow once',function()
    local a,source,materials,tool,data,action=prepare(mode)
    check(F.Preflight(data,a),'valid preflight')
    ISHandcraftAction.performRecipe(action)
    eq(data.performed,1);eq(data.paid,1);eq(data.created:size(),1)
    eq(data.consumed:size(),mode=='metal' and 7 or 6);check(a.inventory:getItems():contains(tool),'kept favorite screwdriver')
    local out=data.created:get(0)
    eq(out:getInventory():getCapacity(),4);eq(out:getActualWeight(),1);eq(out:getWeightReduction(),50)
    check(C.BoxState(out)~=nil,'native OnCreate initialized box')
    if source then eq(out.condition,source.condition);check(not a.inventory:getItems():contains(source))
    else eq(out:getModData()['Base.SmallSheetMetal'],2,'two actual metal sheets recorded') end
    eq(out:getModData()['Base.Pocketwatch'],1)
    eq(out:getModData()['Base.WristWatch_Left_DigitalBlack'],1)
    eq(out:getModData()['Base.WristWatch_Right_ClassicGold'],1)
    eq(out:getModData()['Base.ElectricWire'],2)
    eq(out:getModData()['Base.Battery'],nil);eq(out:getModData()['Base.ElectronicsScrap'],nil)
end)
case(mode..' route cancellation and native failure never charge',function()
    local a,source,_,_,data,action=prepare(mode)
    action:stop();check(action.stopped,'vanilla cancel stopped');eq(data.paid,0);eq(data.performed,0)
    data.nativeFailure=true;ISHandcraftAction.performRecipe(action)
    eq(data.paid,0);eq(data.created:size(),0)
end)
case(mode..' route missing and duplicate objects cannot pay',function()
    local a,_,materials,tool,data,action=prepare(mode)
    a.inventory:Remove(materials[2]);check(not F.Preflight(data,a),'removed material')
    check(not action:performRecipe(),'no payment after material removal');eq(data.paid,0)
    a.inventory:AddItem(materials[2]);data.inputs.values[3]=materials[2]
    check(not F.Preflight(data,a),'one physical watch cannot satisfy two groups');eq(data.paid,0)
end)
case(mode..' route favorite, equipped and insufficient materials refuse charge',function()
    local a,_,materials,_,data,action=prepare(mode)
    materials[2].favorite=true;check(not F.Preflight(data,a),'favorite material');materials[2].favorite=false
    a.primary=materials[2];check(not F.Preflight(data,a),'held material');a.primary=nil
    table.remove(data.inputs.values,#materials-1)
    check(not action:performRecipe(),'one wire is insufficient');eq(data.paid,0);eq(data.created:size(),0)
end)
end
case('digital six and classic eight watch families are disjoint and accepted',function()
    local d,c=0,0
    for id in pairs(F.watchTypes)do
        d=d+1;check(not F.classicTypes[id],'groups disjoint')
        local a,_,_,_,data=prepare('metal',id);check(F.Preflight(data,a),id)
    end
    for id in pairs(F.classicTypes)do
        c=c+1;check(not F.watchTypes[id],'groups disjoint')
        local a,_,_,_,data=prepare('lunchbox',nil,id);check(F.Preflight(data,a),id)
    end
    eq(d,6);eq(c,8)
end)
case('lunchbox source restrictions do not leak into the metal recipe',function()
    local a,source,_,_,data,action=prepare()
    source.inner:AddItem(item('Base.Apple','Food'))
    check(not F.SourceAllowed(source,a),'nonempty');check(not action:performRecipe());eq(data.paid,0)
    source.inner.items:clear();a.primary=source;check(not F.TestItem(source,a),'primary');check(not F.Preflight(data,a))
    a.primary=nil;a.secondary=source;check(not F.Preflight(data,a),'secondary')
    a.secondary=nil;source.favorite=true;check(not F.Preflight(data,a),'favorite');source.favorite=false
    for _,key in ipairs({'SuQingContainerUpgrade','SuQingContainerUpgradeAuto','ExSuQingBackpackSuperUpgrade','SuQingRefrigeration'})do
        source.md[key]={schema=1};check(not F.Preflight(data,a),key);source.md[key]=nil
    end
    check(F.Preflight(data,a),'clean source')
    source.fullType='Base.Lunchbox2';check(F.Preflight(data,a),'other vanilla lunchbox')
    local ma,_,_,_,md=prepare('metal');check(F.Preflight(md,ma),'metal route has no input box')
    check(not F.Preflight(md,ma,'lunchbox'),'metal inputs do not satisfy source route')
    check(not F.Preflight(data,a,'metal'),'source inputs do not satisfy metal route')
end)
case('unrelated recipes retain native completion',function()
    local _,_,_,_,data,action=prepare('metal')
    action.craftRecipe={getScriptObjectFullType=function()return 'Other.OtherRecipe'end}
    data.inputs.values={};action:performRecipe();eq(data.performed,1);eq(data.paid,1)
end)
case('initial capacity stays fixed through settings and paid upgrades',function()
    local box=item(C.FullType,'InventoryContainer');C.EnsureBox(box)
    local state=C.BoxState(box);SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=30
    C.EnsureBox(box);eq(box.inner.capacity,4);eq(C.BoxState(box),state)
    box.md.SuQingContainerUpgrade={level=5};box:setCapacity(49);box:setWeightReduction(99)
    C.EnsureBox(box);eq(box.inner.capacity,49);eq(box.reduction,99)
    box.md.SuQingContainerUpgrade=nil;box:setCapacity(4);box:setWeightReduction(50)
    C.EnsureBox(box);eq(box.inner.capacity,4);eq(box.reduction,50)
    local newer=item(C.FullType,'InventoryContainer');C.EnsureBox(newer);eq(newer.inner.capacity,30)
    SandboxVars.SuQingFreshnessLunchbox.BaseCapacity=4
end)
case('inventory stack and ground menus deduplicate and toggle',function()
    local box=item(C.FullType,'InventoryContainer');C.EnsureBox(box)
    local ctx=Mock.context();emit('OnFillInventoryObjectContextMenu',0,ctx,{box,{items={box}}})
    eq(#ctx.options,1);check(ctx.options[1].toolTip~=nil,'native tooltip')
    ctx.options[1].callback(box);check(not C.BoxState(box).on,'per-box toggle')
    local ground={getItem=function()return box end};local world=Mock.context()
    emit('OnFillWorldObjectContextMenu',0,world,{ground},false);eq(#world.options,1)
    local preview=Mock.context();emit('OnFillWorldObjectContextMenu',0,preview,{ground},true);eq(#preview.options,0)
end)
case('menu explains unavailable runtime and rotten-food-removal limitation',function()
    local box=item(C.FullType,'InventoryContainer');C.EnsureBox(box)
    C.Runtime.ready=false
    local ctx=Mock.context();emit('OnFillInventoryObjectContextMenu',0,ctx,{box})
    check(ctx.options[1].notAvailable,'initialization disables toggle')
    check(string.find(ctx.options[1].toolTip.description,'IGUI_SFL_Starting',1,true)~=nil,'starting status')
    C.Runtime.ready=true
    for _,policy in ipairs({0,3,'unknown'})do
        SandboxVars.DaysForRottenFoodRemoval=policy
        local menu=Mock.context();emit('OnFillInventoryObjectContextMenu',0,menu,{box})
        check(string.find(menu.options[1].toolTip.description,'IGUI_SFL_RottenRemovalLimit',1,true)~=nil,'conservative policy warning '..tostring(policy))
    end
    SandboxVars.DaysForRottenFoodRemoval=-1
    local menu=Mock.context();emit('OnFillInventoryObjectContextMenu',0,menu,{box})
    check(string.find(menu.options[1].toolTip.description,'IGUI_SFL_RottenRemovalLimit',1,true)==nil,'no warning on supported policy')
end)
case('menus distinguish transfer preparation, stopped, missing and failed freshness',function()
    local box=item(C.FullType,'InventoryContainer');C.EnsureBox(box)
    local runtime=C.Runtime
    runtime.ready=true;runtime.operational=false;runtime.status='waiting_transfer'
    local preparing=Mock.context();emit('OnFillInventoryObjectContextMenu',0,preparing,{box})
    check(preparing.options[1].notAvailable);check(string.find(preparing.options[1].toolTip.description,'IGUI_SFL_Starting',1,true)~=nil)
    runtime.ready=false;runtime.failed=true;runtime.status='error'
    local failed=Mock.context();emit('OnFillInventoryObjectContextMenu',0,failed,{box})
    check(failed.options[1].notAvailable);check(string.find(failed.options[1].toolTip.description,'IGUI_SFL_Error',1,true)~=nil)
    check(string.find(failed.options[1].toolTip.description,'IGUI_SFL_Starting',1,true)==nil)
    runtime.failed=false;runtime.status='stopped'
    local stopped=Mock.context();emit('OnFillInventoryObjectContextMenu',0,stopped,{box})
    check(string.find(stopped.options[1].toolTip.description,'IGUI_SFL_Stopped',1,true)~=nil)
    C.Runtime=nil;local missing=Mock.context();emit('OnFillInventoryObjectContextMenu',0,missing,{box})
    check(missing.options[1].notAvailable);check(string.find(missing.options[1].toolTip.description,'IGUI_SFL_Unavailable',1,true)~=nil)
    C.Runtime=runtime;runtime.ready=true;runtime.operational=true;runtime.status='ready'
end)
return 'INTEGRATION_CRAFT_UI cases='..cases..' assertions='..checks..' failures=0; actual vanilla Lua completion path, deterministic native-logic shells'
