require "SuQingFreshnessLunchbox/Crafting"
require "Entity/TimedActions/ISHandcraftAction"
local C=SuQingFreshnessLunchbox
local F=C.Crafting
function F.Install()
    if F.installed or not C.SP() or not ISHandcraftAction or not ISHandcraftAction.performRecipe then return false end
    F.nativePerform=ISHandcraftAction.performRecipe
    F.wrapper=function(action,...)
        local recipe=action.craftRecipe
        local mode=F.RecipeMode(recipe)
        if mode then
            -- Revalidate immediately before native completion. Recipe inputs may
            -- have changed while the action was queued. Do not rerun canPerform:
            -- native craftStarted has already reserved this action's ingredients.
            local data=action.logic and action.logic:getRecipeData()
            local ok,why=F.Preflight(data,action.character,mode)
            if not ok then
                print('[SuQingFreshnessLunchbox] '..getText('IGUI_SFL_CraftRejected',getText('IGUI_SFL_CraftReason_'..tostring(why))))
                return false
            end
        end
        return F.nativePerform(action,...)
    end
    ISHandcraftAction.performRecipe=F.wrapper
    F.installed=true
    return true
end
F.Install()
Events.OnGameStart.Add(F.Install)
return F
