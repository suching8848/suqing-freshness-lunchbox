local C,F=SuQingFreshnessLunchbox,SuQingFreshnessLunchbox.Crafting
local X,B=ExSuQingBackpackSuperUpgrade,CodexSuQingHavenFallEX
local cases,checks=0,0
local function check(ok,label)checks=checks+1;assert(ok,label)end
local function eq(a,b,label)checks=checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..'/'..tostring(b))end
local function case(name,fn)cases=cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why))end
emit('OnGameStart')
local actor=Guard.actor();local bag=Guard.box(actor,'ESHF.EsBackpack')
if GuardExpectBroken then
    check(B.enabled);check(ISHandcraftAction.performRecipe~=B.craftGuard)
    local ok,why=X.CanUpgrade(bag,actor);check(not ok);eq(why,'havenfall_native_conversion_guard_not_ready')
    return 'EX_GUARD_RC2_REPRO native='..tostring(Guard.native)..' assertions='..checks..' failures=0; original late OnGameStart wrapper invalidates exact HavenFall guard identity'
end
case('strict existing HavenFall guard remains outermost with ordinary guard chain',function()
    check(B.enabled);check(X.Capacity.IsReady());eq(ISHandcraftAction.performRecipe,B.craftGuard)
    check(F.installed);check(SuQingContainerUpgrade.craftGuardInstalled);check(SuQingContainerUpgrade.Variant.installed)
    local ok,why=X.CanUpgrade(bag,actor);check(ok,why)
    local prior=ISHandcraftAction.performRecipe
    ISHandcraftAction.performRecipe=function(...)return prior(...)end
    local allowed,reason=X.CanUpgrade(bag,actor);check(not allowed);eq(reason,'havenfall_native_conversion_guard_not_ready')
    ISHandcraftAction.performRecipe=prior;check(X.CanUpgrade(bag,actor))
end)
case('existing EX action path still upgrades once and restores through native completion',function()
    local data={kept=Guard.list({bag}),all=Guard.list({bag}),engine=0,paid=0}
    function data:getAllKeepInputItems()return self.kept end;function data:getAllInputItems()return self.all end
    function data:processDestroyAndUsedItems()self.paid=self.paid+1 end
    local logic={getRecipeData=function()return data end,performCurrentRecipe=function()data.engine=data.engine+1;return true end}
    local action={character=actor,logic=logic,craftRecipe=Guard.recipe('ExSuQingBackpackSuperUpgrade.ExSuQingSuperUpgrade')}
    check(ISHandcraftAction.performRecipe(action));eq(data.engine,1);eq(data.paid,1);check(X.GetRecord(bag));eq(bag:getInventory():getEffectiveCapacity(nil),120)
    check(not ISHandcraftAction.performRecipe(action));eq(data.engine,1)
    local restore={character=actor,logic=logic,craftRecipe=Guard.recipe('ExSuQingBackpackSuperUpgrade.ExSuQingRestore')}
    check(ISHandcraftAction.performRecipe(restore));eq(X.GetRecord(bag),nil);eq(data.engine,2);eq(data.paid,2)
end)
case('HavenFall native conversions block every EX record and otherwise delegate once',function()
    local data={all=Guard.list({bag}),created=Guard.list(),consumed=Guard.list(),engine=0,paid=0}
    function data:getAllInputItems()return self.all end;function data:getAllCreatedItems()return self.created end
    function data:getAllConsumedItems()return self.consumed end
    function data:luaCallOnCreate()end;function data:processDestroyAndUsedItems()self.paid=self.paid+1 end
    local logic={getRecipeData=function()return data end,performCurrentRecipe=function()data.engine=data.engine+1;return true end,getCreatedOutputItems=function()end}
    local action={character=actor,logic=logic,craftRecipe=Guard.recipe('ESHFUpgrade.NativeUpgrade')}
    local paid=X.NewRecord(bag);paid.paidCloth=40;paid.paidLeather=20;paid.paidThreadUses=20;paid.paidPremiumUses=4
    check(X.IsValidRecord(paid,bag));bag:getModData()[X.modDataKey]=paid
    ISHandcraftAction.performRecipe(action);eq(data.engine,0);eq(data.paid,0)
    bag:getModData()[X.modDataKey]={corrupt=true};ISHandcraftAction.performRecipe(action);eq(data.engine,0);eq(data.paid,0)
    bag:getModData()[X.modDataKey]=nil;ISHandcraftAction.performRecipe(action);eq(data.engine,1);eq(data.paid,1)
    action.craftRecipe=Guard.recipe('Other.Unrelated');ISHandcraftAction.performRecipe(action);eq(data.engine,2);eq(data.paid,2)
end)
case('lunchbox two routes still run the unchanged preflight and original completion once',function()
    for _,mode in ipairs({'Lunchbox','Metal'})do
        local a=Guard.actor();local inputs={};local tool
        local function add(id,box)local m=box and Guard.box(a,id) or Guard.material(a,id);inputs[#inputs+1]=m;return m end
        if mode=='Lunchbox' then add('Base.Lunchbox',true) else add('Base.SmallSheetMetal');add('Base.SmallSheetMetal') end
        add('Base.WristWatch_Left_DigitalBlack');add('Base.Pocketwatch');add('Base.WristWatch_Right_ClassicGold')
        add('Base.ElectricWire');add('Base.ElectricWire');tool=add('Base.Screwdriver')
        local data={all=Guard.list(inputs),created=Guard.list(),consumed=Guard.list(),engine=0,paid=0}
        function data:getAllInputItems()return self.all end;function data:getAllCreatedItems()return self.created end
        function data:getAllConsumedItems()return self.consumed end;function data:luaCallOnCreate(character)F.OnCreate(self,character)end
        function data:processDestroyAndUsedItems(character)self.paid=self.paid+1;for _,m in ipairs(inputs)do if m~=tool then character:getInventory():Remove(m);self.consumed:add(m)end end end
        local logic={getRecipeData=function()return data end,performCurrentRecipe=function()data.engine=data.engine+1;return true end,getCreatedOutputItems=function()end}
        local action={character=a,logic=logic,craftRecipe=Guard.recipe('SuQingFreshnessLunchbox.MakeFreshnessLunchboxFrom'..mode)}
        check(F.Preflight(data,a,mode=='Metal' and 'metal' or 'lunchbox'))
        a:getInventory():Remove(inputs[2]);check(not ISHandcraftAction.performRecipe(action));eq(data.engine,0);eq(data.paid,0)
        a:getInventory():AddItem(inputs[2]);ISHandcraftAction.performRecipe(action);eq(data.engine,1);eq(data.paid,1)
        check(a:getInventory():getItems():contains(tool))
    end
end)
case('repeated game starts keep exact outer guard and register no duplicate scripts',function()
    local top=ISHandcraftAction.performRecipe
    local counts={};for name,recipe in pairs(Guard.recipes)do counts[name]=recipe:getInputs():get(0):getItems():size()end
    for i=1,3 do emit('OnGameStart');eq(ISHandcraftAction.performRecipe,top);eq(top,B.craftGuard);check(B.Install()) end
    for name,recipe in pairs(Guard.recipes)do eq(recipe:getInputs():get(0):getItems():size(),counts[name])end
    check(X.CanUpgrade(bag,actor))
end)
return 'EX_GUARD_CHAIN native='..tostring(Guard.native)..' cases='..cases..' assertions='..checks..' failures=0; original EX, HavenFall bridge, ordinary crafting+variant and vanilla completion delegated unchanged'
