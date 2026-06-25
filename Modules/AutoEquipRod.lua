----------------------------------------------------------------
-- AUTO EQUIP ROD MODULE
----------------------------------------------------------------
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local AutoEquipRod = {}

local LP = Players.LocalPlayer

-- ================================================================
-- STATE
-- ================================================================
local enabled         = false
local heartbeatConn   = nil
local charConn        = nil
local lastCheck       = 0
local CHECK_INTERVAL  = 1.0

-- ================================================================
-- REMOTE
-- ================================================================
local RE_EquipToolFromHotbar = _G.Net.EquipToolFromHotbar

-- ================================================================
-- HELPERS
-- ================================================================
local function isHoldingRod()
    local char = LP.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return false end
    local name = tool.Name:lower()
    return name:find("rod") or name:find("fishing") or name:find("pole")
end

local function equipRod()
    if not RE_EquipToolFromHotbar then return end
    pcall(function()
        RE_EquipToolFromHotbar:FireServer(1)
    end)
end

-- ================================================================
-- CORE LOOP
-- ================================================================
local function onHeartbeat()
    if not enabled then return end
    local now = tick()
    if now - lastCheck < CHECK_INTERVAL then return end
    lastCheck = now
    if not isHoldingRod() then
        equipRod()
    end
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function AutoEquipRod.Start()
    if enabled then return end
    enabled   = true
    lastCheck = 0

    heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, heartbeatConn)
    end
end

function AutoEquipRod.Stop()
    if not enabled then return end
    enabled = false

    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
end

-- ================================================================
-- RESPAWN HANDLING
-- ================================================================
charConn = LP.CharacterAdded:Connect(function()
    if enabled then
        task.wait(1.5)
        equipRod()
    end
end)

if _G._NEXTHUB and _G._NEXTHUB.conns then
    table.insert(_G._NEXTHUB.conns, charConn)
end

return AutoEquipRod