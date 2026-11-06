local U=SuQingContainerUpgrade
local A=SuQingFreshnessLunchbox.AttachedContainers
local checks,cases=0,0
local function check(v,label)checks=checks+1;assert(v,label)end
local function eq(a,b,label)checks=checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..'/'..tostring(b))end
local function case(name,fn)cases=cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why))end
case('new bridge does not replace the strict outer EX crafting guard',function()
    eq(ISHandcraftAction.performRecipe,CodexSuQingHavenFallEX.craftGuard)
    check(A.InstallUpgradeGuard());eq(ISHandcraftAction.performRecipe,CodexSuQingHavenFallEX.craftGuard)
end)
case('queued ordinary upgrade is rechecked before engine or payment',function()
    local a=Guard.actor();a.attached=Guard.list()
    function a:isAttachedItem(b)return self.attached:contains(b)end
    local box=Guard.box(a,SuQingFreshnessLunchbox.FullType)
    SuQingFreshnessLunchbox.EnsureBox(box)
    local data={kept=Guard.list({box}),all=Guard.list({box}),engine=0,paid=0}
    function data:getAllKeepInputItems()return self.kept end
    function data:getAllInputItems()return self.all end
    function data:processDestroyAndUsedItems()self.paid=self.paid+1 end
    local logic={getRecipeData=function()return data end,
        performCurrentRecipe=function()data.engine=data.engine+1;return true end}
    local action={character=a,logic=logic,craftRecipe=Guard.recipe('SuQingContainerUpgrade.SuQingUpgrade1')}
    check(U.CanComplete(data,a,1));a.attached:add(box)
    check(not ISHandcraftAction.performRecipe(action));eq(data.engine,0);eq(data.paid,0)
    eq(U.GetRecord(box),nil);eq(box:getInventory():getCapacity(),4);eq(box:getWeightReduction(),50)
end)
case('queued ordinary restoration is rechecked without losing its ledger',function()
    local a=Guard.actor();a.attached=Guard.list()
    function a:isAttachedItem(b)return self.attached:contains(b)end
    local box=Guard.box(a,SuQingFreshnessLunchbox.FullType)
    SuQingFreshnessLunchbox.EnsureBox(box)
    local data={kept=Guard.list({box}),all=Guard.list({box}),engine=0,paid=0}
    function data:getAllKeepInputItems()return self.kept end
    function data:getAllInputItems()return self.all end
    function data:processDestroyAndUsedItems()self.paid=self.paid+1 end
    check(U.Upgrade(data,a,1));local record=U.GetRecord(box);check(U.CanComplete(data,a,'restore'))
    a.attached:add(box)
    local logic={getRecipeData=function()return data end,
        performCurrentRecipe=function()data.engine=data.engine+1;return true end}
    local action={character=a,logic=logic,craftRecipe=Guard.recipe('SuQingContainerUpgrade.SuQingRestore')}
    check(not ISHandcraftAction.performRecipe(action));eq(data.engine,0);eq(data.paid,0)
    eq(U.GetRecord(box),record);eq(box:getInventory():getCapacity(),12);eq(box:getWeightReduction(),90)
end)
return 'ATTACHED_CONTAINERS_COMPLETION cases='..cases..' assertions='..checks..' failures=0; strict EX chain unchanged, queued attached target rejected before native consumption'
