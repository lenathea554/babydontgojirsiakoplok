----------------------------------------------------------------
-- SAVE POSITION MODULE
----------------------------------------------------------------
local Players = game:GetService("Players")

local LP = Players.LocalPlayer
local SavePosition = {}

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local TWEEN_SPEED = 50

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local savedCFrame = nil
local isTeleporting = false

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function getHRP()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function SavePosition.Save()
    local hrp = getHRP()
    if hrp then
        savedCFrame = hrp.CFrame
        return true
    end
    return false
end

function SavePosition.Teleport()
    if not savedCFrame or isTeleporting then
        return false
    end

    local hrp = getHRP()
    if not hrp then return false end

    hrp.CFrame = savedCFrame
    return true
end

function SavePosition.Reset()
    savedCFrame = nil
    isTeleporting = false
end

function SavePosition.HasSaved()
    return savedCFrame ~= nil
end

function SavePosition.IsTeleporting()
    return isTeleporting
end

return SavePosition