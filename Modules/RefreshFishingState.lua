----------------------------------------------------------------
-- REFRESH FISHING STATE MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LP = Players.LocalPlayer
local RefreshFishingState = {}

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local RF_CancelFishingInputs = _G.Net.CancelFishingInputs
local RF_CatchFishCompleted = _G.Net.CatchFishCompleted

----------------------------------------------------------------
-- CORE RESET LOGIC
----------------------------------------------------------------
local function safeCall(fn)
    pcall(fn)
end

function RefreshFishingState.Refresh()
    if RF_CancelFishingInputs then
        safeCall(function()
            RF_CancelFishingInputs:InvokeServer()
        end)
    end

    if RF_CatchFishCompleted then
        safeCall(function()
            RF_CatchFishCompleted:InvokeServer()
        end)
    end

    task.delay(0.3, function()
        if RF_CancelFishingInputs then
            safeCall(function()
                RF_CancelFishingInputs:InvokeServer()
            end)
        end
    end)
end

return RefreshFishingState