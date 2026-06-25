----------------------------------------------------------------
-- EVENT TELEPORT MODULE
----------------------------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local TeleportEvent = {}

local EVENTS = {
    ["Shark Hunt"] = {Vector3.new(1.65, -1.35, 2095.72), Vector3.new(1369.94, -1.35, 930.125), Vector3.new(-1585.5, -1.35, 1242.87), Vector3.new(-1896.8, -1.35, 2634.37)},
    ["Worm Hunt"] = {Vector3.new(2190.85, -1.4, 97.57), Vector3.new(-2450.6, -1.4, 139.73), Vector3.new(-267.47, -1.4, 5188.53)},
    ["Megalodon Hunt"] = {Vector3.new(-1076.3, -1.4, 1676.19), Vector3.new(-1191.8, -1.4, 3597.30), Vector3.new(412.7, -1.4, 4134.39)},
    ["Ghost Shark Hunt"] = {Vector3.new(489.558, -1.35, 25.406), Vector3.new(-1358.2, -1.35, 4100.55), Vector3.new(627.859, -1.35, 3798.08)},
}

local SEARCH_RADIUS, HEIGHT_OFFSET, PLATFORM_BREAK = 30, 15, 20
local selectedEvent = nil
local platform, platformPos, platformLoop = nil, nil, nil
local locationCache = {}

local function cleanupPlatform()
    if platformLoop then platformLoop:Disconnect() platformLoop = nil end
    if platform then pcall(function() platform:Destroy() end) platform = nil end
    platformPos = nil
end

local function createPlatform(pos)
    cleanupPlatform()
    platformPos = pos
    platform = Instance.new("Part")
    platform.Size, platform.Anchored, platform.CanCollide, platform.Transparency = Vector3.new(15, 1, 15), true, true, 1
    platform.CFrame = CFrame.new(pos - Vector3.new(0, 4, 0))
    platform.Parent = Workspace
    
    if _G._NEXTHUB then table.insert(_G._NEXTHUB.instances, platform) end

    platformLoop = RunService.Heartbeat:Connect(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or (hrp.Position - platformPos).Magnitude > PLATFORM_BREAK then
            cleanupPlatform()
        end
    end)
end

function TeleportEvent.TeleportOnce(name)
    name = name or selectedEvent
    if not EVENTS[name] then return end
    
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local coords = EVENTS[name]
    local target = coords[math.random(1, #coords)]
    local finalPos = target + Vector3.new(0, HEIGHT_OFFSET, 0)

    char:PivotTo(CFrame.new(finalPos))
    createPlatform(finalPos)
end

function TeleportEvent.GetAllEvents()
    local t = {}
    for k in pairs(EVENTS) do table.insert(t, k) end
    table.sort(t)
    return t
end

function TeleportEvent.SetEvent(name) selectedEvent = name end

return TeleportEvent