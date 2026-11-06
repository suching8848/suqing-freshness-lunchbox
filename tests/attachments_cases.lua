-- Actual bridge and vanilla definition chunks are compiled by the game Kahlua
-- compiler. These shells model only the definition tables, locations and events.
local assertions,cases=0,0
local logs,callbacks,group,anchors
local expected={
    BedrollBottom="Bedroll Bottom",
    BedrollBottomBig="Bedroll Bottom Big",
    BedrollBottomALICE="Bedroll Bottom ALICE",
}
local anchorNames={
    ["Bedroll Bottom"]="bedroll_bottom",
    ["Bedroll Bottom Big"]="bedroll_bottom_big",
    ["Bedroll Bottom ALICE"]="bedroll_bottom_alice",
}
local function eq(actual,wanted,label)
    assertions=assertions+1
    assert(actual==wanted,(label or "value")..": "..tostring(actual).." ~= "..tostring(wanted))
end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function definition(slotType)
    for _,v in pairs(ISHotbarAttachDefinition) do if type(v)=="table" and v.type==slotType then return v end end
end
local function reset(withDefinitions)
    SuQingFreshnessLunchbox={}
    ISHotbarAttachDefinition=nil
    logs,callbacks,anchors={},{},{}
    print=function(text) logs[#logs+1]=text end
    require=function() return true end
    getTextOrNull=function(key,detail) return key..":"..detail end
    group={}
    for location,anchor in pairs(anchorNames) do
        local entry={anchor=anchor};function entry:getAttachmentName() return self.anchor end
        anchors[location]=entry
    end
    function group:getLocation(name) return anchors[name] end
    AttachedLocations={getGroup=function(name) eq(name,"Human","group");return group end}
    Events={}
    for _,name in ipairs({"OnGameBoot","OnGameStart"}) do
        callbacks[name]={}
        local list=callbacks[name]
        Events[name]={Add=function(fn) list[#list+1]=fn end}
    end
    if withDefinitions then VanillaAttachmentDefinitionsChunk() end
end
local function emit(name) for _,fn in ipairs(callbacks[name]) do fn() end end
local function load() AttachmentBridgeChunk();return SuQingFreshnessLunchbox.Attachments end
local function checkMappings(number)
    local n=0
    for slotType,location in pairs(expected) do
        local def=definition(slotType)
        if def and def.attachments and def.attachments.SuQingFreshnessLunchbox==location then n=n+1 end
    end
    eq(n,number,"exact lunchbox mappings")
end
local function run(fn) cases=cases+1;fn() end

run(function() -- Missing tables are a safe cold-start state; lifecycle retries recover.
    reset(false);AttachedLocations=nil
    local a=load();eq(a.status,"unavailable");eq(a.availableTypes,0)
    eq(ISHotbarAttachDefinition,nil);eq(#callbacks.OnGameBoot,1);eq(#callbacks.OnGameStart,1)
    VanillaAttachmentDefinitionsChunk()
    AttachedLocations={getGroup=function() return group end}
    local before=count(ISHotbarAttachDefinition)
    emit("OnGameBoot");eq(a.status,"ready");checkMappings(3)
    eq(count(ISHotbarAttachDefinition),before,"no new slots")
end)

run(function() -- The real vanilla definitions retain all original table identities.
    reset(true)
    local before=count(ISHotbarAttachDefinition)
    local originals={}
    for _,v in pairs(ISHotbarAttachDefinition) do
        if type(v)=="table" and expected[v.type] then
            originals[v.type]={definition=v,attachments=v.attachments,bedroll=v.attachments.Bedroll,size=count(v.attachments)}
        end
    end
    local replacement=ISHotbarAttachDefinition.replacements
    local a=load();eq(a.availableTypes,3);eq(a.skippedTypes,0);checkMappings(3)
    eq(count(ISHotbarAttachDefinition),before);eq(ISHotbarAttachDefinition.replacements,replacement)
    for slotType,old in pairs(originals) do
        local v=definition(slotType)
        eq(v,old.definition);eq(v.attachments,old.attachments)
        eq(v.attachments.Bedroll,old.bedroll);eq(count(v.attachments),old.size+1)
    end
    eq(definition("SmallBeltLeft").attachments.SuQingFreshnessLunchbox,nil)
    eq(definition("Back").attachments.SuQingFreshnessLunchbox,nil)
end)

run(function() -- Repeated lifecycle events do not multiply registrations or logs.
    reset(true);local a=load();local before=#logs
    for i=1,4 do emit("OnGameBoot");emit("OnGameStart");a.Install() end
    eq(#callbacks.OnGameBoot,1);eq(#callbacks.OnGameStart,1);eq(#logs,before);checkMappings(3)
    eq(Events.OnTick,nil);eq(Events.OnPlayerUpdate,nil)
end)

run(function() -- Hot file reload uses stable callbacks and the same bridge state.
    reset(true);local a=load();local handler=a.onLifecycle
    load();load();eq(SuQingFreshnessLunchbox.Attachments,a);eq(a.onLifecycle,handler)
    eq(#callbacks.OnGameBoot,1);eq(#callbacks.OnGameStart,1);checkMappings(3)
end)

run(function() -- A missing optional slot does not create it or block the other two.
    reset(true)
    for i,v in pairs(ISHotbarAttachDefinition) do if type(v)=="table" and v.type=="BedrollBottomBig" then ISHotbarAttachDefinition[i]=nil end end
    local before=count(ISHotbarAttachDefinition);local a=load()
    eq(a.status,"partial");eq(a.availableTypes,2);eq(count(ISHotbarAttachDefinition),before)
    eq(definition("BedrollBottomBig"),nil);checkMappings(2)
end)

run(function() -- Duplicate provider definitions are ambiguous and both remain untouched.
    reset(true)
    local duplicate={type="BedrollBottom",animset="back",attachments={Bedroll="Bedroll Bottom"}}
    table.insert(ISHotbarAttachDefinition,duplicate)
    local a=load();eq(a.availableTypes,2)
    eq(duplicate.attachments.SuQingFreshnessLunchbox,nil)
    eq(definition("BedrollBottom").attachments.SuQingFreshnessLunchbox,nil)
end)

run(function() -- A conflicting lunchbox mapping is never overwritten.
    reset(true);local d=definition("BedrollBottom")
    d.attachments.SuQingFreshnessLunchbox="Another Location"
    local a=load();eq(a.availableTypes,2);eq(d.attachments.SuQingFreshnessLunchbox,"Another Location")
    eq(d.attachments.Bedroll,"Bedroll Bottom")
end)

run(function() -- A changed original tent mapping is treated as an upstream conflict.
    reset(true);local d=definition("BedrollBottomBig");d.attachments.Bedroll="Different Tent Location"
    local a=load();eq(a.availableTypes,2);eq(d.attachments.SuQingFreshnessLunchbox,nil)
    eq(d.attachments.Bedroll,"Different Tent Location")
end)

run(function()
    reset(true);local d=definition("BedrollBottomALICE");d.attachments=nil
    local a=load();eq(a.availableTypes,2);eq(d.attachments,nil)
end)

run(function()
    reset(true);local d=definition("BedrollBottom");d.animset="holster right"
    local a=load();eq(a.availableTypes,2);eq(d.attachments.SuQingFreshnessLunchbox,nil)
end)

run(function()
    reset(true);anchors["Bedroll Bottom Big"]=nil
    local a=load();eq(a.availableTypes,2);eq(definition("BedrollBottomBig").attachments.SuQingFreshnessLunchbox,nil)
end)

run(function()
    reset(true);anchors["Bedroll Bottom ALICE"].anchor="different_anchor"
    local a=load();eq(a.availableTypes,2);eq(definition("BedrollBottomALICE").attachments.SuQingFreshnessLunchbox,nil)
end)

run(function()
    reset(true);AttachedLocations=nil;local before=count(ISHotbarAttachDefinition)
    local a=load();eq(a.availableTypes,0);checkMappings(0);eq(count(ISHotbarAttachDefinition),before)
end)

run(function()
    reset(true);AttachedLocations.getGroup=function() return nil end
    local a=load();eq(a.availableTypes,0);checkMappings(0)
end)

run(function()
    reset(true);ISHotbarAttachDefinition="unavailable"
    local a=load();eq(a.availableTypes,0);eq(ISHotbarAttachDefinition,"unavailable")
end)

run(function() -- Equivalent pre-existing mappings are safe and idempotent.
    reset(true)
    for slotType,location in pairs(expected) do definition(slotType).attachments.SuQingFreshnessLunchbox=location end
    local a=load();eq(a.availableTypes,3);checkMappings(3)
end)

run(function() -- Other item types/metadata remain identical, even on target slots.
    reset(true);local d=definition("BedrollBottom")
    d.attachments.AnotherMod="Another Place";d.otherMetadata={owner="another mod"}
    local metadata=d.otherMetadata;local before=count(d.attachments)
    load();eq(d.attachments.AnotherMod,"Another Place");eq(d.otherMetadata,metadata)
    eq(count(d.attachments),before+1)
end)

run(function() -- No lifecycle API is required when the vanilla definitions already exist.
    reset(true);Events=nil;local a=load();eq(a.availableTypes,3);checkMappings(3)
end)

run(function() -- Missing translations produce a diagnostic containing both languages.
    reset(false);getTextOrNull=nil;load()
    eq(string.find(logs[1],"返鲜餐盒",1,true)~=nil,true)
    eq(string.find(logs[1],"Freshness lunchbox",1,true)~=nil,true)
end)

run(function() -- Late upstream changes withdraw only our unchanged addition.
    reset(true);local a=load();local d=definition("BedrollBottom")
    d.attachments.Bedroll="Late Provider Location"
    emit("OnGameStart")
    eq(a.availableTypes,2);eq(d.attachments.SuQingFreshnessLunchbox,nil)
    eq(d.attachments.Bedroll,"Late Provider Location")
    d.attachments.Bedroll="Bedroll Bottom";a.Install();checkMappings(3)
end)

run(function() -- A later owner's conflicting value is retained, even on our old table.
    reset(true);local a=load();local d=definition("BedrollBottomBig")
    d.attachments.SuQingFreshnessLunchbox="Late Owner Location"
    a.Install();eq(a.availableTypes,2)
    eq(d.attachments.SuQingFreshnessLunchbox,"Late Owner Location")
    eq(a.ownedMappings[d.attachments],nil)
end)

run(function() -- Replaced definitions do not leave our entries on retired tables.
    reset(true);local a=load();local old=definition("BedrollBottom").attachments
    ISHotbarAttachDefinition=nil;VanillaAttachmentDefinitionsChunk();a.Install();checkMappings(3)
    eq(old.SuQingFreshnessLunchbox,nil);eq(count(a.ownedMappings),3)
end)

run(function() -- Missing late prerequisites withdraw owned entries; recovery reinstalls them.
    reset(true);local a=load();AttachedLocations=nil;a.Install()
    eq(a.availableTypes,0);checkMappings(0);eq(count(a.ownedMappings),0)
    AttachedLocations={getGroup=function() return group end};a.Install();checkMappings(3)
end)

run(function() -- Unexpected API exceptions remain visible; the bridge never swallows them.
    reset(true);group.getLocation=function() error("injected upstream exception") end
    local ok,err=pcall(AttachmentBridgeChunk)
    eq(ok,false);eq(string.find(tostring(err),"injected upstream exception",1,true)~=nil,true)
end)

return "ATTACHMENTS_KAHLUA cases="..cases.." assertions="..assertions.." failures=0"
