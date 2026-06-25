----------------------------------------------------------------
-- AUTO EVENT HUNT
----------------------------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer or Players.PlayerAdded:Wait()

local AutoHuntEvent = {}

----------------------------------------------------------------
-- EVENTS DATA
----------------------------------------------------------------
local HUNT_EVENTS = {
    ["Shark Hunt"] = {
        Vector3.new(1.65, -1.35, 2095.72),
        Vector3.new(1369.94, -1.35, 930.125),
        Vector3.new(-1585.5, -1.35, 1242.87),
        Vector3.new(-1896.8, -1.35, 2634.37),
    },
    ["Worm Hunt"] = {
        Vector3.new(2190.85, -1.4, 97.57),
        Vector3.new(-2450.6, -1.4, 139.73),
        Vector3.new(-267.47, -1.4, 5188.53),
    },
    ["Megalodon Hunt"] = {
        Vector3.new(-1076.3, -1.4, 1676.19),
        Vector3.new(-1191.8, -1.4, 3597.30),
        Vector3.new(412.7, -1.4, 4134.39),
    },
    ["Ghost Shark Hunt"] = {
        Vector3.new(489.558, -1.35, 25.406),
        Vector3.new(-1358.2, -1.35, 4100.55),
        Vector3.new(627.859, -1.35, 3798.08),
    },
}

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local SEARCH_RADIUS = 30
local HEIGHT_OFFSET = 15
local SCAN_DELAY = 1.5
local EVENT_TIMEOUT = 6
local PLATFORM_BREAK_DIST = 25
local TWEEN_SPEED = 50

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local enabled = false
local selectedEvent = nil

local loopTask = nil
local platform = nil
local platformConn = nil
local lockedPos = nil
local startCFrame = nil
local lastSeenTime = 0
local isTweening = false

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function getHRP()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function safeTween(targetPos)
    local hrp = getHRP()
    if not hrp or isTweening then return end
    
    isTweening = true
    local distance = (hrp.Position - targetPos).Magnitude
    local duration = distance / TWEEN_SPEED
    
    local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, info, {CFrame = CFrame.new(targetPos)})
    
    tween:Play()
    tween.Completed:Wait()
    isTweening = false
end

local function isLocationValid(coord)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character }
    
    local parts = Workspace:GetPartBoundsInRadius(coord, SEARCH_RADIUS, params)
    
    for _, part in ipairs(parts) do
        if part.CanCollide and part.Transparency < 1 and part.Size.Magnitude > 3 then
            return true
        end
    end
    return false
end

local function findActiveEventLocation(eventName)
    local coords = HUNT_EVENTS[eventName]
    if not coords then return nil end

    for _, coord in ipairs(coords) do
        if isLocationValid(coord) then
            return coord + Vector3.new(0, HEIGHT_OFFSET, 0)
        end
    end
    return nil
end

local function cleanupPlatform()
    if platformConn then
        platformConn:Disconnect()
        platformConn = nil
    end
    if platform then
        if platform.Parent then platform:Destroy() end
        platform = nil
    end
end

local function ensurePlatform(pos)
    if platform or isTweening then return end

    platform = Instance.new("Part")
    platform.Size = Vector3.new(15, 1, 15)
    platform.Anchored = true
    platform.CanCollide = true
    platform.Transparency = 1
    platform.CFrame = CFrame.new(pos - Vector3.new(0, 3, 0)) 
    platform.Parent = Workspace

    if _G._NEXTHUB and _G._NEXTHUB.instances then
        table.insert(_G._NEXTHUB.instances, platform)
    end

    platformConn = RunService.Heartbeat:Connect(function()
        local hrp = getHRP()
        if not hrp or not platform then
            cleanupPlatform()
            return
        end

        if (hrp.Position - platform.Position).Magnitude > PLATFORM_BREAK_DIST then
            cleanupPlatform()
            lockedPos = nil
        end
    end)
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function AutoHuntEvent.GetEvents()
    local t = {}
    for k in pairs(HUNT_EVENTS) do
        table.insert(t, k)
    end
    table.sort(t)
    return t
end

function AutoHuntEvent.SetEvent(ev)
    if HUNT_EVENTS[ev] then
        selectedEvent = ev
    end
end

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------
function AutoHuntEvent.Start()
    if enabled or not selectedEvent then return end
    
    local hrp = getHRP()
    if not hrp then return end
    
    enabled = true
    startCFrame = hrp.CFrame
    lockedPos = nil
    lastSeenTime = 0
    cleanupPlatform()

    loopTask = task.spawn(function()
        while enabled do
            local hrp = getHRP()
            
            if hrp then
                local currentEventPos = findActiveEventLocation(selectedEvent)

                if currentEventPos then
                    lastSeenTime = tick()
                    
                    if not lockedPos then
                        lockedPos = currentEventPos
                        safeTween(lockedPos)
                    end

                    if lockedPos and not isTweening then
                        ensurePlatform(lockedPos)
                    end
                else
                    if lockedPos then
                        if tick() - lastSeenTime >= EVENT_TIMEOUT then
                            lockedPos = nil
                            cleanupPlatform()
                            
                            if startCFrame then
                                safeTween(startCFrame.Position)
                            end
                        end
                    end
                end
            else
                task.wait(1)
            end

            task.wait(SCAN_DELAY)
        end
    end)

    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, loopTask)
    end
end

function AutoHuntEvent.Stop()
    if not enabled then return end
    enabled = false

    lockedPos = nil
    lastSeenTime = 0
    cleanupPlatform()

    local hrp = getHRP()
    if hrp and startCFrame then
        task.spawn(function()
            safeTween(startCFrame.Position)
        end)
    end
end

return AutoHuntEvent