----------------------------------------------------------------
-- HIDE OTHER PLAYERS MODULE
----------------------------------------------------------------
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerConn(conn)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, conn)
    end
end

-- ================================================================
-- STATE
-- ================================================================
local HideOtherPlayers = {}

local enabled    = false
local conns      = {}
local localPlayer = Players.LocalPlayer

-- ================================================================
-- INTERNAL
-- ================================================================
local function setCharacterVisibility(character, hidden)
    if not character then return end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("Decal") then
            if hidden then
                if part:FindFirstChild("__origTransp") == nil then
                    local tag = Instance.new("NumberValue")
                    tag.Name  = "__origTransp"
                    tag.Value = part.Transparency
                    tag.Parent = part
                end
                part.Transparency = 1
            else
                local tag = part:FindFirstChild("__origTransp")
                part.Transparency = tag and tag.Value or 0
                if tag then tag:Destroy() end
            end
        end
    end
end

local function hookPlayer(player)
    if player == localPlayer then return end
    if conns[player] then return end

    local char = player.Character
        or Workspace:FindFirstChild(player.Name)
    if char then
        setCharacterVisibility(char, true)
    end

    local conn = player.CharacterAdded:Connect(function(newChar)
        if not enabled then return end
        task.defer(function()
            setCharacterVisibility(newChar, true)
        end)
    end)

    conns[player] = conn
    registerConn(conn)
end

local function unhookPlayer(player)
    if player == localPlayer then return end

    local char = player.Character
        or Workspace:FindFirstChild(player.Name)
    if char then
        setCharacterVisibility(char, false)
    end

    local conn = conns[player]
    if conn then
        pcall(function() conn:Disconnect() end)
        conns[player] = nil
    end
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function HideOtherPlayers.Start()
    if enabled then return end
    enabled = true

    for _, player in ipairs(Players:GetPlayers()) do
        hookPlayer(player)
    end

    local joinConn = Players.PlayerAdded:Connect(function(player)
        if not enabled then return end
        hookPlayer(player)
    end)
    conns["__PlayerAdded"] = joinConn
    registerConn(joinConn)

    local leaveConn = Players.PlayerRemoving:Connect(function(player)
        conns[player] = nil
    end)
    conns["__PlayerRemoving"] = leaveConn
    registerConn(leaveConn)
end

function HideOtherPlayers.Stop()
    if not enabled then return end
    enabled = false

    for _, player in ipairs(Players:GetPlayers()) do
        unhookPlayer(player)
    end

    for key, conn in pairs(conns) do
        pcall(function() conn:Disconnect() end)
        conns[key] = nil
    end
end

return HideOtherPlayers