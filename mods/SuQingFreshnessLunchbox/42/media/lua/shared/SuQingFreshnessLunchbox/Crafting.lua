require "SuQingFreshnessLunchbox/Core"
local C=SuQingFreshnessLunchbox
C.Crafting=C.Crafting or {}
local F=C.Crafting
if F.loaded then return F end
F.loaded=true
F.recipeModes={
    ['SuQingFreshnessLunchbox.MakeFreshnessLunchboxFromLunchbox']='lunchbox',
    ['SuQingFreshnessLunchbox.MakeFreshnessLunchboxFromMetal']='metal',
}
F.sourceTypes={['Base.Lunchbox']=true,['Base.Lunchbox2']=true}
F.watchTypes={
    ['Base.WristWatch_Left_DigitalBlack']=true,['Base.WristWatch_Right_DigitalBlack']=true,
    ['Base.WristWatch_Left_DigitalRed']=true,['Base.WristWatch_Right_DigitalRed']=true,
    ['Base.WristWatch_Left_DigitalDress']=true,['Base.WristWatch_Right_DigitalDress']=true,
}
F.classicTypes={
    ['Base.WristWatch_Left_ClassicBlack']=true,['Base.WristWatch_Right_ClassicBlack']=true,
    ['Base.WristWatch_Left_ClassicBrown']=true,['Base.WristWatch_Right_ClassicBrown']=true,
    ['Base.WristWatch_Left_ClassicGold']=true,['Base.WristWatch_Right_ClassicGold']=true,
    ['Base.WristWatch_Left_ClassicMilitary']=true,['Base.WristWatch_Right_ClassicMilitary']=true,
}
function F.RecipeMode(recipe)
    if not recipe then return nil end
    local name=recipe.getScriptObjectFullType and recipe:getScriptObjectFullType() or recipe:getName()
    return F.recipeModes[name]
end

-- Called by native inventory acceptance. The category shown in the UI is not
-- used, so food from other mods may retain their own display categorization.
function C.AcceptFood(container,item)
    return item~=nil and type(instanceof)=="function" and instanceof(item,"Food")
end

function F.SourceAllowed(item,character)
    if not item or not item.getFullType or not F.sourceTypes[item:getFullType()]
       or not instanceof(item,"InventoryContainer") or not character then return false,"source" end
    local inner=item:getInventory()
    if not inner or inner:getItems():size()~=0 then return false,"not_empty" end
    if item:isFavorite() then return false,"favorite" end
    if item:isEquipped() or character:isEquipped(item)
       or character:getPrimaryHandItem()==item or character:getSecondaryHandItem()==item then
        return false,"equipped"
    end
    local md=item:getModData()
    if md.SuQingContainerUpgrade~=nil or md.SuQingContainerUpgradeAuto~=nil or md.ExSuQingBackpackSuperUpgrade~=nil
       or md.SuQingRefrigeration~=nil then return false,"modified_source" end
    if not item:getContainer() or not item:getContainer():getItems():contains(item) then
        return false,"missing_input"
    end
    return true
end

-- Native OnTest selects individual inputs. Payment and item destruction remain
-- entirely under native craft logic; no custom charge or refund path is added.
function F.TestItem(item,character)
    if not C.SP() or not item then return false end
    if F.sourceTypes[item:getFullType()] then return F.SourceAllowed(item,character) end
    return true
end

function F.Preflight(data,character,mode)
    if not C.SP() or not data or not data.getAllInputItems then return false,"recipe_data" end
    mode=mode or (data.getRecipe and F.RecipeMode(data:getRecipe()))
    if mode~='lunchbox' and mode~='metal' then return false,'recipe_data' end
    local list=data:getAllInputItems()
    local counts={source=0,digital=0,classic=0,pocket=0,wire=0,metal=0,tool=0}
    local seen={}
    for i=0,list:size()-1 do
        local item=list:get(i)
        if not item or not item:getContainer() or not item:getContainer():getItems():contains(item) then
            return false,'missing_input'
        end
        if seen[item] then return false,"duplicate_input" end
        seen[item]=true
        local id=item:getFullType()
        if F.sourceTypes[id] then
            local ok,why=F.SourceAllowed(item,character)
            if not ok then return false,why end
            counts.source=counts.source+1
        elseif F.watchTypes[id] or F.classicTypes[id] or id=='Base.Pocketwatch'
           or id=='Base.ElectricWire' or id=='Base.SmallSheetMetal' then
            if item:isFavorite() then return false,"favorite_material" end
            if item:isEquipped() or character:isEquipped(item)
               or character:getPrimaryHandItem()==item or character:getSecondaryHandItem()==item then
                return false,"equipped_material"
            end
            local kind=F.watchTypes[id] and 'digital' or (F.classicTypes[id] and 'classic' or
                (id=='Base.Pocketwatch' and 'pocket' or (id=='Base.ElectricWire' and 'wire' or 'metal')))
            counts[kind]=counts[kind]+1
        else
            -- The only kept row is selected by the native screwdriver tag.
            if not item.hasTag or not ItemTag or not ItemTag.SCREWDRIVER
               or not item:hasTag(ItemTag.SCREWDRIVER) then return false,"unexpected_input" end
            counts.tool=counts.tool+1
        end
    end
    if counts.source~=(mode=='lunchbox' and 1 or 0) or counts.metal~=(mode=='metal' and 2 or 0)
       or counts.digital~=1 or counts.classic~=1 or counts.pocket~=1 or counts.wire~=2
       or counts.tool~=1 then return false,"input_count" end
    return true
end

function F.OnCreate(data,character)
    local created=data and data.getAllCreatedItems and data:getAllCreatedItems()
    if not created then return end
    for i=0,created:size()-1 do
        local item=created:get(i)
        if C.IsBox(item) then
            local state=C.EnsureBox(item)
            if not state then error('SuQingFreshnessLunchbox: new output initialization failed') end
            if C.Runtime and C.Runtime.Register then C.Runtime.Register(item) end
        end
    end
end
return F
