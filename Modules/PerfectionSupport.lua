----------------------------------------------------------------
-- PERFECTION SUPPORT MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PerfectionSupport = {}

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local RF_UpdateAutoFishingState = _G.Net.UpdateAutoFishingState

----------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------
local state = {
    enabled = false,
}
local oldRequest = nil

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function PerfectionSupport.Enable()
    if state.enabled then return end
    state.enabled = true

    if RF_UpdateAutoFishingState then
        task.spawn(function()
            pcall(function() RF_UpdateAutoFishingState:InvokeServer(true) end)
        end)
    end

    pcall(function()
        local FishingController = require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("FishingController"))
        if FishingController and not oldRequest then
            oldRequest = FishingController.RequestChargeFishingRod
            FishingController.RequestChargeFishingRod = function()
                return nil 
            end
        end
    end)
end

function PerfectionSupport.Disable()
    if not state.enabled then return end
    state.enabled = false

    if RF_UpdateAutoFishingState then
        task.spawn(function()
            pcall(function() RF_UpdateAutoFishingState:InvokeServer(false) end)
        end)
    end

    if oldRequest then
        pcall(function()
            local FishingController = require(ReplicatedStorage.Controllers.FishingController)
            FishingController.RequestChargeFishingRod = oldRequest
            oldRequest = nil
        end)
    end
end

function PerfectionSupport.IsActive()
    return state.enabled
end

return PerfectionSupport