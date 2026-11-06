local T=AttachedTest
local A=SuQingFreshnessLunchbox.AttachedContainers
local U=SuQingContainerUpgrade
local check,eq,case=T.check,T.eq,T.case
local function attached()
    local a=T.actor();local b=T.box(a);a.attached:add(b);return a,b
end
case('native attachments are distinct from equipped clothing/hands',function()
    local a,b=attached();check(a:isAttachedItem(b));check(not a:isEquipped(b));check(A.IsAttachedBox(b,a))
end)
case('actual attached food container gains one native button before layout',function()
    local a,b=attached();local page=T.page(a)
    emit('OnRefreshInventoryWindowContainers',page,'begin');eq(page.additions,0)
    emit('OnRefreshInventoryWindowContainers',page,'buttonsAdded');eq(page.additions,1)
    eq(page.backpacks[1].inventory,b.inner);eq(page.backpacks[1].texture,'box-texture')
    eq(page.backpacks[1].name,'freshness lunchbox')
    emit('OnRefreshInventoryWindowContainers',page,'buttonsAdded');eq(page.additions,1)
    emit('OnRefreshInventoryWindowContainers',page,'end');eq(page.additions,1)
end)
case('already exposed containers are not duplicated',function()
    local a,b=attached();local page=T.page(a);page.backpacks={{inventory=b.inner}}
    A.OnContainers(page,'buttonsAdded');eq(page.additions,0);eq(#page.backpacks,1)
end)
case('detaching removes the button on normal native rebuild',function()
    local a,b=attached();local page=T.page(a);A.OnContainers(page,'buttonsAdded');eq(page.additions,1)
    a.attached:remove(b);page.backpacks={};A.OnContainers(page,'buttonsAdded');eq(#page.backpacks,0)
end)
case('stale slot metadata cannot expose an unattached container',function()
    local a=T.actor();local b=T.box(a);b.attachedSlot=3;local page=T.page(a)
    check(not A.IsAttachedBox(b,a));A.OnContainers(page,'buttonsAdded');eq(page.additions,0)
end)
case('a forged attached collection without owned inventory is rejected',function()
    local a,b=attached();local page=T.page(a);a.inventory.items:remove(b)
    check(not A.IsAttachedBox(b,a));A.OnContainers(page,'buttonsAdded');eq(page.additions,0)
end)
case('nested and foreign-owned boxes are not exposed',function()
    local a,b=attached();local parent=T.box(a,'Base.Bag_Schoolbag')
    a.inventory:Remove(b);parent.inner:AddItem(b);local page=T.page(a)
    A.OnContainers(page,'buttonsAdded');eq(page.additions,0)
    parent.inner:Remove(b);local other=T.actor();other.inventory:AddItem(b)
    A.OnContainers(page,'buttonsAdded');eq(page.additions,0)
end)
case('only exact lunchboxes are added, with per-player ownership',function()
    local a,b=attached();local bag=T.box(a,'Base.Bag_Schoolbag');a.attached:add(bag)
    local other,second=attached();local p=T.page(a,0);local q=T.page(other,1)
    A.OnContainers(p,'buttonsAdded');A.OnContainers(q,'buttonsAdded')
    eq(#p.backpacks,1);eq(p.backpacks[1].inventory,b.inner)
    eq(#q.backpacks,1);eq(q.backpacks[1].inventory,second.inner)
end)
case('loot pages and inactive phases are untouched',function()
    local a,b=attached();local page=T.page(a);page.onCharacter=false
    A.OnContainers(page,'buttonsAdded');eq(page.additions,0)
    page.onCharacter=true;A.OnContainers(page,'beforeFloor');eq(page.additions,0)
end)
case('multiplayer adds no container button or guard installation',function()
    local old=isClient;isClient=function()return true end
    local a,b=attached();local p=T.page(a);A.OnContainers(p,'buttonsAdded');eq(p.additions,0)
    local ok,why=A.InstallUpgradeGuard();eq(ok,false);eq(why,'multiplayer');isClient=old
end)
case('attached upgrade and restore are rejected before ordinary APIs',function()
    local a,b=attached();local uc,rc=T.nativeCalls.upgrade,T.nativeCalls.restore
    local ok,why=U.CanUpgrade(b,a,1);eq(ok,false);eq(why,'equipped')
    ok,why=U.CanRestore(b,a);eq(ok,false);eq(why,'equipped')
    eq(T.nativeCalls.upgrade,uc);eq(T.nativeCalls.restore,rc)
end)
case('detached lunchboxes and other targets preserve all ordinary returns',function()
    local a,b=attached();a.attached:remove(b)
    local ok,why,state,target,nothing,extra=U.CanUpgrade(b,a,1)
    eq(ok,true);eq(why,nil);eq(state,T.results.state);eq(target,T.results.target)
    eq(nothing,nil);eq(extra,T.results.extra)
    local bag=T.box(a,'Base.Bag_Schoolbag');a.attached:add(bag)
    ok,why,state,nothing,extra=U.CanRestore(bag,a)
    eq(ok,true);eq(why,nil);eq(state,T.results.state);eq(nothing,nil);eq(extra,T.results.extra)
end)
case('install and game-start are idempotent',function()
    local up,restore=U.CanUpgrade,U.CanRestore
    check(A.Install());emit('OnGameStart');check(A.InstallUpgradeGuard())
    eq(U.CanUpgrade,up);eq(U.CanRestore,restore)
    local a,b=attached();local page=T.page(a);emit('OnRefreshInventoryWindowContainers',page,'buttonsAdded')
    eq(page.additions,1)
end)
case('optional ordinary absence and unsupported versions are untouched',function()
    local original=SuQingContainerUpgrade;SuQingContainerUpgrade=nil
    local ok,why=A.InstallUpgradeGuard();eq(ok,false);eq(why,'absent')
    local sentinel=function()return 'other'end
    SuQingContainerUpgrade={version='9.0',CanUpgrade=sentinel,CanRestore=sentinel}
    ok,why=A.InstallUpgradeGuard();eq(ok,false);eq(why,'unsupported_version')
    eq(SuQingContainerUpgrade.CanUpgrade,sentinel);SuQingContainerUpgrade=original
end)
case('changed wrapper chains are reported without overwriting them',function()
    local original=U.CanUpgrade;local foreign=function()return original()end
    U.CanUpgrade=foreign;local ok,why=A.InstallUpgradeGuard()
    eq(ok,false);eq(why,'changed_chain');eq(U.CanUpgrade,foreign);U.CanUpgrade=original
end)
return 'ATTACHED_CONTAINERS cases='..T.cases..' assertions='..T.checks..' failures=0'
