----------------------------------------------------------------
-- TELEPORT PLAYER MODULE
----------------------------------------------------------------
local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local TeleportPlayer = {}

local selectedPlayer = nil

function TeleportPlayer.GetAllPlayers()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then table.insert(list, plr.Name) end
    end
    table.sort(list)
    return list
end

function TeleportPlayer.SetTarget(name) selectedPlayer = name end

function TeleportPlayer.TeleportTo(name)
    name = name or selectedPlayer
    local target = Players:FindFirstChild(name)
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
        local myChar = LP.Character
        if myChar then
            local targetHRP = target.Character.HumanoidRootPart
            myChar:PivotTo(targetHRP.CFrame * CFrame.new(0, 5, 2))
        end
    end
end

return TeleportPlayer