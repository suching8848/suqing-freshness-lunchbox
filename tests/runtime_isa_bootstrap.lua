ISAProbe={native=type(NativeEmit)=='function',checks=0,cases=0,baseTransfers=0,commands={}}
if not ISAProbe.native then
    local events={}
    Events=setmetatable({}, {__index=function(t,key)
        local e={callbacks={}}
        e.Add=function(fn)e.callbacks[#e.callbacks+1]=fn end
        e.Remove=function(fn)for i,v in ipairs(e.callbacks)do if v==fn then table.remove(e.callbacks,i);return end end end
        events[key]=e;rawset(t,key,e);return e
    end})
    function ISAProbe.emit(key)
        local copied={};for _,fn in ipairs(Events[key].callbacks)do copied[#copied+1]=fn end
        for _,fn in ipairs(copied)do fn()end
    end
    Mock.reset();local square=Mock.square(1);Mock.player(square)
else
    ISAProbe.emit=NativeEmit
end
ISBaseObject={derive=function(self,name)local c={};c.__index=c;setmetatable(c,{__index=self});return c end}
MainScreen={instance={inGame=true}}
ISPlugGenerator={perform=function()end};ISActivateGenerator={perform=function()end}
ISTransferAction={transferItem=function(self,character,item,source,destination)
    ISAProbe.baseTransfers=ISAProbe.baseTransfers+1;return item
end}
ISAProbe.PBSystem={instance={sendCommand=function(self,character,name,args)ISAProbe.commands[#ISAProbe.commands+1]={name=name,args=args}end}}
function require(name)
    if name=='ImmersiveSolarArrays/Utilities' then return ISAUnderTest end
    if name=='ImmersiveSolarArrays/PowerBank/PowerBankSystem_Client' then return ISAProbe.PBSystem end
end
function ISAProbe.check(ok,label)ISAProbe.checks=ISAProbe.checks+1;assert(ok,label)end
function ISAProbe.eq(a,b,label)ISAProbe.check(a==b,(label or 'equal')..': '..tostring(a)..'/'..tostring(b))end
function ISAProbe.case(name,fn)ISAProbe.cases=ISAProbe.cases+1;local ok,why=pcall(fn);assert(ok,name..': '..tostring(why))end
