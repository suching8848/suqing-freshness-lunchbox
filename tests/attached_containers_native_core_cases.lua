local T=AttachedTest
local A=SuQingFreshnessLunchbox.AttachedContainers
local U=SuQingContainerUpgrade
local check,eq,case=T.check,T.eq,T.case
case('actual ordinary API permits detached box then blocks attachment',function()
    local a=T.actor();local b=T.box(a);SuQingFreshnessLunchbox.EnsureBox(b)
    check(U.CanUpgrade(b,a,1));a.attached:add(b)
    local ok,why=U.CanUpgrade(b,a,1);eq(ok,false);eq(why,'equipped')
    ok,why=U.ProbeChange(b,a,1);eq(ok,false);eq(why,'equipped')
    local data={getAllKeepInputItems=function()return list({b})end}
    ok,why=U.CanComplete(data,a,1);eq(ok,false);eq(why,'equipped')
    eq(U.Test1(b,a),false)
    ok,why=U.Upgrade(data,a,1);eq(ok,false);eq(why,'equipped')
    eq(b.inner.capacity,4);eq(b.reduction,50);eq(U.GetRecord(b),nil)
    a.attached:remove(b);check(U.Upgrade(data,a,1));eq(b.inner.capacity,12)
    local record=U.GetRecord(b);a.attached:add(b)
    ok,why=U.CanRestore(b,a);eq(ok,false);eq(why,'equipped')
    ok,why=U.ProbeChange(b,a,'restore');eq(ok,false);eq(why,'equipped')
    ok,why=U.Restore(data,a);eq(ok,false);eq(why,'equipped')
    ok,why=U.CanComplete(data,a,'restore');eq(ok,false);eq(why,'equipped')
    eq(U.TestRestore(b,a),false)
    eq(U.GetRecord(b),record);eq(b.inner.capacity,12);eq(b.reduction,90)
    a.attached:remove(b);check(U.Restore(data,a));eq(b.inner.capacity,4);eq(b.reduction,50)
end)
case('other containers retain actual ordinary behavior',function()
    local a=T.actor();local b=T.box(a,'Base.Bag_Schoolbag')
    local data={getAllKeepInputItems=function()return list({b})end}
    check(U.Upgrade(data,a,1));eq(b.inner.capacity,12);check(U.Restore(data,a));eq(b.inner.capacity,4)
end)
return 'ATTACHED_CONTAINERS_ORDINARY cases='..T.cases..' assertions='..T.checks..' failures=0'
