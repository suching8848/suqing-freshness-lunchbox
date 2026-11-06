-- Native engine globals and native LuaEventManager remain intact here.
-- No world cell/player/save is constructed by this method-level event probe.
print=ProbePrint
function require()end
ISTransferAction={transferItem=function()end}
SandboxVars={DaysForRottenFoodRemoval=-1,SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}}
print('NATIVE_EVENT_BINDINGS',type(ModData),type(ModData and ModData.getOrCreate),type(triggerEvent),type(isClient),type(isServer),isClient(),isServer())
