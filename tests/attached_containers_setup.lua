AttachedTest={cases=0,checks=0,players={},nativeCalls={upgrade=0,restore=0}}
local T=AttachedTest
function T.check(v,label) T.checks=T.checks+1;assert(v,label) end
function T.eq(a,b,label) T.checks=T.checks+1;assert(a==b,(label or 'equal')..': '..tostring(a)..' ~= '..tostring(b)) end
function T.case(name,fn) T.cases=T.cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why)) end
function T.actor()
    local a=actor();a.attached=list()
    function a:isAttachedItem(value)return self.attached:contains(value)end
    return a
end
function T.box(a,id)
    local b=item(id or SuQingFreshnessLunchbox.FullType,'InventoryContainer')
    function b:getTex()return self.texture or 'box-texture'end
    function b:getName()return self.label or 'freshness lunchbox'end
    function b:getAttachedSlot()return self.attachedSlot or -1 end
    a.inventory:AddItem(b)
    return b
end
function T.page(a,index)
    index=index or 0;T.players[index]=a
    local p={player=index,onCharacter=true,backpacks={},additions=0}
    function p:addContainerButton(inner,texture,name,tip)
        self.additions=self.additions+1
        local button={inventory=inner,texture=texture,name=name,tooltip=tip}
        self.backpacks[#self.backpacks+1]=button
        return button
    end
    return p
end
getSpecificPlayer=function(i)return T.players[i]end
T.results={state={},target={},extra={}}
SuQingContainerUpgrade={version='1.0.3'}
function SuQingContainerUpgrade.CanUpgrade(value,character,tier)
    T.nativeCalls.upgrade=T.nativeCalls.upgrade+1
    return true,nil,T.results.state,T.results.target,nil,T.results.extra
end
function SuQingContainerUpgrade.CanRestore(value,character)
    T.nativeCalls.restore=T.nativeCalls.restore+1
    return true,nil,T.results.state,nil,T.results.extra
end
return 'ATTACHED_CONTAINERS setup ready'
