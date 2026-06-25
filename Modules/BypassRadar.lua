----------------------------------------------------------------
-- BYPASS RADAR MODULE
----------------------------------------------------------------
local BypassRadar = {}
local RF_UpdateRadar = _G.Net.UpdateFishingRadar
local enabled = false

function BypassRadar.Start()
    if enabled or not RF_UpdateRadar then return end
    enabled = true
    pcall(function()
        RF_UpdateRadar:InvokeServer(true)
    end)
end

function BypassRadar.Stop()
    if not enabled or not RF_UpdateRadar then return end
    enabled = false
    pcall(function()
        RF_UpdateRadar:InvokeServer(false)
    end)
end

function BypassRadar.IsActive()
    return enabled
end

return BypassRadar