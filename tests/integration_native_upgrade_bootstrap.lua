-- Uses actual exposed native objects and instanceof; no user save is loaded.
function require() end
function isClient() return false end
function isServer() return false end
function getTimestampMs() return 1106000000 end
print=ProbePrint
SandboxVars={DaysForRottenFoodRemoval=-1,SuQingFreshnessLunchbox={Enabled=true,BaseCapacity=4,RestoreHours=10,AllowRotten=true}}
function list(values)
    local t={values=values or {}}
    function t:size() return #self.values end
    function t:get(i) return self.values[i+1] end
    return t
end
instanceItem=IntegrationMakeMaterial
function actor()
    local a={inventory=IntegrationMakeInventory()}
    function a:getInventory() return self.inventory end
    function a:isEquipped(item) return self.primary==item or self.secondary==item end
    function a:getPrimaryHandItem() return self.primary end
    function a:getSecondaryHandItem() return self.secondary end
    function a:getPerkLevel() return 10 end
    return a
end
