-- No adapter and no injected support. The generated source registry is the
-- sole authority. External lunchbox item definitions can be absent.
Integration={}
function Integration.setupManager()
    local manager={missing=true}
    function manager:getItem() return nil end
    function manager:FindItem() return nil end
    function manager:getCraftRecipe() return nil end
    Integration.manager=manager
    getScriptManager=function() return Integration.manager end
    return manager
end
Integration.setupManager()
