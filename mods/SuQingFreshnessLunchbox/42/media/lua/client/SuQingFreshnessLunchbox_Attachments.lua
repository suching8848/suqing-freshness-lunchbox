-- Optional integration with existing backpack-bottom slots only. Native hotbar
-- actions retain sole ownership of attachment, detachment and occupied slots.
require "SuQingFreshnessLunchbox/Core"
local C=SuQingFreshnessLunchbox
C.Attachments=C.Attachments or {}
local A=C.Attachments
A.attachmentType="SuQingFreshnessLunchbox"
A.reported=A.reported or {}
A.registeredEvents=A.registeredEvents or {}
A.ownedMappings=A.ownedMappings or {}

local slots={
    {type="BedrollBottom",location="Bedroll Bottom",anchor="bedroll_bottom"},
    {type="BedrollBottomBig",location="Bedroll Bottom Big",anchor="bedroll_bottom_big"},
    {type="BedrollBottomALICE",location="Bedroll Bottom ALICE",anchor="bedroll_bottom_alice"},
}

local function report(key,detail)
    local identity=key..":"..detail
    if A.reported[identity] then return end
    A.reported[identity]=true
    local text=type(getTextOrNull)=="function" and getTextOrNull(key,detail)
    if not text then
        if key=="IGUI_SFL_AttachmentReady" then
            text="返鲜餐盒已接入现有背包底部挂点 / Freshness lunchbox backpack-bottom attachment types: "..detail
        else
            text="返鲜餐盒挂点适配已跳过，保留原有挂点 / Freshness lunchbox attachment integration skipped; existing slots unchanged: "..detail
        end
    end
    print("[SuQingFreshnessLunchbox] "..text)
end

local function inspect(definitions,group,spec)
    local selected,count=nil,0
    for _,definition in pairs(definitions) do
        if type(definition)=="table" and definition.type==spec.type then
            selected,count=definition,count+1
        end
    end
    if count==0 then return nil,"slot_missing" end
    if count~=1 then return nil,"duplicate_slot_type" end
    if selected.animset~="back" or type(selected.attachments)~="table" then
        return nil,"slot_structure_changed"
    end
    if selected.attachments.Bedroll~=spec.location then return nil,"bedroll_mapping_changed" end
    local current=selected.attachments[A.attachmentType]
    if current~=nil and current~=spec.location then return nil,"lunchbox_mapping_conflict" end
    local location=group:getLocation(spec.location)
    if not location or not location.getAttachmentName then return nil,"attached_location_missing" end
    if location:getAttachmentName()~=spec.anchor then return nil,"model_anchor_changed" end
    return selected
end

function A.Install()
    local definitions=ISHotbarAttachDefinition
    local group,unavailable
    if type(definitions)~="table" then unavailable="hotbar_definitions_unavailable"
    elseif not AttachedLocations or not AttachedLocations.getGroup then unavailable="attached_locations_unavailable"
    else
        group=AttachedLocations.getGroup("Human")
        if not group or not group.getLocation then unavailable="human_locations_unavailable" end
    end
    local installed,reasons,valid=0,{},{}
    for _,spec in ipairs(slots) do
        local definition,reason
        if unavailable then reason=unavailable else definition,reason=inspect(definitions,group,spec) end
        if definition then
            valid[definition.attachments]=spec.location
            installed=installed+1
        else
            local detail=spec.type.." / "..reason
            reasons[#reasons+1]=detail
            report("IGUI_SFL_AttachmentSkipped",detail)
        end
    end
    -- A later provider may replace a previously valid definition. Withdraw only
    -- entries this bridge added and whose value nobody else has changed.
    -- Validate every slot before committing so unexpected API errors stay visible
    -- without partially applying the current installation pass.
    for mapping,location in pairs(A.ownedMappings) do
        if valid[mapping]~=location then
            if mapping[A.attachmentType]==location then mapping[A.attachmentType]=nil end
            A.ownedMappings[mapping]=nil
        end
    end
    for mapping,location in pairs(valid) do
        if mapping[A.attachmentType]==nil then
            mapping[A.attachmentType]=location
            A.ownedMappings[mapping]=location
        end
    end
    A.availableTypes=installed
    A.skippedTypes=#slots-installed
    A.lastReasons=reasons
    A.ready=installed>0
    A.status=installed==#slots and "ready" or (installed>0 and "partial" or "unavailable")
    if installed>0 then report("IGUI_SFL_AttachmentReady",tostring(installed)) end
    return A.ready,installed
end

-- Do not force-reload the vanilla definition file: it also owns replacements
-- supplied by other mods. Immediate installation and lifecycle retries cover
-- cold initialization; stable callbacks make repeated file loads idempotent.
A.onLifecycle=A.onLifecycle or function() return C.Attachments.Install() end
for _,name in ipairs({"OnGameBoot","OnGameStart"}) do
    local event=Events and Events[name]
    if event and type(event.Add)=="function" and A.registeredEvents[name]~=event then
        event.Add(A.onLifecycle)
        A.registeredEvents[name]=event
    end
end
A.Install()
return A
