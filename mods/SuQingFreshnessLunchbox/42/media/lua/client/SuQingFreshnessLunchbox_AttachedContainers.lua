if isServer() then return end
require "SuQingFreshnessLunchbox/Core"

local C=SuQingFreshnessLunchbox
C.AttachedContainers=C.AttachedContainers or {}
local A=C.AttachedContainers
if A.loaded then return A end
A.loaded=true
A.warned={}

local function warnOnce(reason,value)
    if A.warned[reason] then return end
    A.warned[reason]=true
    print('[SuQingFreshnessLunchbox] '..getText('IGUI_SFL_AttachedGuardUnavailable',tostring(reason),tostring(value or '')))
end

-- Attachment metadata can be stale during a hotbar refresh. The native attached
-- collection and the actual main-inventory ownership must agree before exposing
-- the food container; a positive attached-slot number alone is not authority.
function A.IsAttachedBox(item,character)
    if not C.IsBox(item) or not character or not character.getInventory
       or not character.isAttachedItem then return false end
    local inventory=character:getInventory()
    return inventory~=nil and item:getContainer()==inventory
        and inventory:getItems():contains(item) and character:isAttachedItem(item) or false
end

function A.OnContainers(page,phase)
    if phase~='buttonsAdded' or not C.SP() or not page or not page.onCharacter
       or type(page.addContainerButton)~='function' or type(page.backpacks)~='table'
       or type(getSpecificPlayer)~='function' then return end
    local character=getSpecificPlayer(page.player)
    if not character or not character.getInventory then return end
    local inventory=character:getInventory()
    if not inventory then return end
    local seen={}
    for _,button in ipairs(page.backpacks) do seen[button.inventory]=true end
    local items=inventory:getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        if A.IsAttachedBox(item,character) then
            local inner=item:getInventory()
            if not seen[inner] then
                page:addContainerButton(inner,item:getTex(),item:getName(),item:getName())
                seen[inner]=true
            end
        end
    end
end

-- Ordinary 1.0.3 predates attached containers: isEquipped() excludes hotbar
-- attachments in B42.21. Guard only this exact lunchbox; all other targets and
-- all successful return values continue through the original ordinary API.
function A.InstallUpgradeGuard()
    if not C.SP() then return false,'multiplayer' end
    local ordinary=SuQingContainerUpgrade
    if type(ordinary)~='table' then A.upgradeStatus='absent';return false,'absent' end
    if ordinary.version~='1.0.3' then
        A.upgradeStatus='unsupported_version'
        warnOnce('unsupported_version',ordinary.version)
        return false,'unsupported_version'
    end
    if A.guardApi then
        if A.guardApi==ordinary and ordinary.CanUpgrade==A.guardCanUpgrade
           and ordinary.CanRestore==A.guardCanRestore then A.upgradeStatus='ready';return true end
        A.upgradeStatus='changed_chain'
        warnOnce('changed_chain')
        return false,'changed_chain'
    end
    if type(ordinary.CanUpgrade)~='function' or type(ordinary.CanRestore)~='function' then
        A.upgradeStatus='missing_api'
        warnOnce('missing_api')
        return false,'missing_api'
    end
    local canUpgrade,canRestore=ordinary.CanUpgrade,ordinary.CanRestore
    A.guardCanUpgrade=function(item,character,...)
        if A.IsAttachedBox(item,character) then return false,'equipped' end
        return canUpgrade(item,character,...)
    end
    A.guardCanRestore=function(item,character,...)
        if A.IsAttachedBox(item,character) then return false,'equipped' end
        return canRestore(item,character,...)
    end
    A.guardApi=ordinary
    A.nativeCanUpgrade=canUpgrade
    A.nativeCanRestore=canRestore
    ordinary.CanUpgrade=A.guardCanUpgrade
    ordinary.CanRestore=A.guardCanRestore
    A.upgradeStatus='ready'
    return true
end

function A.Install()
    if not C.SP() then return false end
    if not A.uiInstalled then
        if not Events or not Events.OnRefreshInventoryWindowContainers then
            warnOnce('missing_container_event')
            return false
        end
        Events.OnRefreshInventoryWindowContainers.Add(A.OnContainers)
        A.uiInstalled=true
    end
    A.InstallUpgradeGuard()
    return true
end

A.Install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(A.Install) end
return A
