----------------------------------------------------------------
-- TELEPORT LOCATION MODULE
----------------------------------------------------------------
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local LP                = Players.LocalPlayer

local TeleportLocation = {}

local LOCATIONS = {
    ["Ancient Jungle"]       = CFrame.new(1467.848,   7.447  + 3,  -327.597),
    ["Ancient Ruin"]         = CFrame.new(6045.402,  -588.600 + 3, 4608.937),
    ["Coral Reefs"]          = CFrame.new(-2921.858,   3.25  + 3,  2083.297),
    ["Crater Island"]        = CFrame.new(1078.454,    5.072 + 3,  5099.396),
    ["Esoteric Depths"]      = CFrame.new(3224.075, -1302.854 + 3, 1404.934),
    ["Enchant 1"]            = CFrame.new(3234.833, -1302.855 + 3, 1398.39233),
    ["Enchant 2"]            = CFrame.new(1480.562,   127.624 + 3,  -587.132),
    ["Fisherman Island"]     = CFrame.new(92.806,      9.531 + 3,  2762.082),
    ["Kohana"]               = CFrame.new(-643.305,   16.035 + 3,   622.360),
    ["Kohana Volcano"]       = CFrame.new(-511.569,   17.535 + 3,   155.349),
    ["Volcanic Cavern"]      = CFrame.new(1098,        85.856 + 3, -10239),
    ["Lost Isle"]            = CFrame.new(-3701.151,   5.425 + 3, -1058.910),
    ["Lava Basin"]           = CFrame.new(875.891,     85.522 + 3,-10086.71),
    ["Sysiphus Statue"]      = CFrame.new(-3656.562, -134.531 + 3,  -964.316),
    ["Sacred Temple"]        = CFrame.new(1476.308,   -21.849 + 3,  -630.822),
    ["Treasure Room"]        = CFrame.new(-3601.568, -266.573 + 3, -1578.998),
    ["Tropical Grove"]       = CFrame.new(-2104.467,    6.268 + 3,  3718.254),
    ["Underground Cellar"]   = CFrame.new(2162.577,   -91.198 + 3,  -725.591),
    ["Weather Machine"]      = CFrame.new(-1513.924,    6.5   + 3,  1892.106),
    ["Pirate Cove"]          = CFrame.new(3338.228,     4.19  + 3,  3525.695),
    ["Crystal Depths"]       = CFrame.new(5750.214,   -904.81 + 3, 15393.308),
    ["Secret Passage"]       = CFrame.new(3432.08,    -299.34 + 3,  3358.65),
    ["Pirate Treasure Room"] = CFrame.new(3339.784,   -302.044 + 3, 3090.016),
    ["Sewers"]               = CFrame.new(-1442.80,  -1041.58 + 3,-10447.11),
    ["Underwater City"]      = CFrame.new(-3148.34,   -640.61 + 3,-10506.08),
    ["Copper Canyon"]        = CFrame.new(-4134.40,     8.25  + 3,    620.45),
}

local locationNames = {}
for name in pairs(LOCATIONS) do table.insert(locationNames, name) end
table.sort(locationNames)

local selectedLoc    = nil
local selectedBoatId = nil

----------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------

local function getNet(name)
    return _G.Net and _G.Net[name]
end

local function waitForCharReady(timeout)
    local elapsed = 0
    while elapsed < timeout do
        local char = LP.Character
        if char
            and char:FindFirstChild("HumanoidRootPart")
            and char:FindFirstChildOfClass("Humanoid")
            and char.Parent ~= nil
        then
            return char
        end
        task.wait(0.2)
        elapsed = elapsed + 0.2
    end
    return LP.Character
end

local function respawnCharacter()
    local char = LP.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0
    else
        char:BreakJoints()
    end
end

local function waitForMyBoat(timeout)
    local elapsed = 0
    while elapsed < timeout do
        for _, boat in ipairs(CollectionService:GetTagged("Boat")) do
            local owner = boat:GetAttribute("OwnerId")
            if owner and owner == LP.UserId then
                return boat
            end
        end
        task.wait(0.3)
        elapsed = elapsed + 0.3
    end
    return nil
end

local function fireBoatTeleport()
    local re = getNet("BoatTeleport")
    if re then
        pcall(function() re:FireServer() end)
    end
end

local function spawnBoat(boatId)
    local rf = getNet("SpawnBoat")
    if not rf then return false end
    local ok, result = pcall(function() return rf:InvokeServer(boatId) end)
    return ok and result
end

local function despawnMyBoat()
    local rf = getNet("DespawnBoat")
    if rf then pcall(function() rf:InvokeServer() end) end
end

local function getBoatBase(boat)
    return boat:FindFirstChild("Base")
end

local function getBoatSpeed(boatName)
    local ok, handlingData = pcall(function()
        return require(game:GetService("ReplicatedStorage").Shared.BoatsHandlingData)
    end)
    if ok and handlingData and handlingData[boatName] then
        return handlingData[boatName].Speed or 200
    end
    return 200
end

local function setCharacterTouchEnabled(enabled)
    local char = LP.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanTouch = enabled
        end
    end
end

local function simulateReverse(boat, boatName)
    local base = getBoatBase(boat)
    if not base then
        return
    end
    local lv = base:FindFirstChildWhichIsA("LinearVelocity")
    if not lv then
        return
    end

    local maxSpeed        = getBoatSpeed(boatName)
    local reverseSpeed    = maxSpeed * 0.25
    local reverseDuration = 50 / reverseSpeed

    local elapsed = 0
    local conn

    lv.VectorVelocity = Vector3.new(reverseSpeed, 0, 0)

    conn = RunService.Heartbeat:Connect(function(dt)
        elapsed = elapsed + dt
        if not base or not base.Parent or not lv or not lv.Parent then
            conn:Disconnect()
            return
        end
        lv.VectorVelocity = lv.VectorVelocity:Lerp(
            Vector3.new(reverseSpeed, 0, 0), dt * 3)
        if elapsed >= reverseDuration then
            conn:Disconnect()
            lv.VectorVelocity = Vector3.new(0, 0, 0)
        end
    end)

    task.wait(reverseDuration + 0.8)
    if lv and lv.Parent then
        lv.VectorVelocity = Vector3.new(0, 0, 0)
    end
end

local function relocateAndLock(boat, targetCF)
    local base = getBoatBase(boat)
    if not base then
        pcall(function() boat:PivotTo(targetCF) end)
        return { Disconnect = function() end }
    end

    pcall(function() base.Anchored = false end)
    pcall(function()
        base.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        base.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)
    pcall(function() base.CFrame = targetCF end)
    pcall(function() base.Anchored = true end)
    pcall(function()
        base.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        base.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    local holdConn = RunService.Heartbeat:Connect(function()
        if not base or not base.Parent then return end
        pcall(function() base.CFrame = targetCF end)
        base.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        base.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    local inlineElapsed = 0
    local inlineDone    = false
    local inlineConn

    inlineConn = RunService.Heartbeat:Connect(function(dt)
        inlineElapsed = inlineElapsed + dt
        if not base or not base.Parent then
            inlineConn:Disconnect()
            return
        end

        pcall(function() base.CFrame = targetCF end)
        base.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        base.AssemblyAngularVelocity = Vector3.new(0,0,0)
        if inlineElapsed >= 2.5 and not inlineDone then
            inlineDone = true
            inlineConn:Disconnect()
        end
    end)

    local pollElapsed = 0
    while not inlineDone and pollElapsed < 4.0 do
        task.wait(0.1)
        pollElapsed = pollElapsed + 0.1
    end
    if inlineConn then pcall(function() inlineConn:Disconnect() end) end

    return holdConn
end

local function jumpCharacter()
    local char = LP.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")

    if hum then
        hum.Sit = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if hrp then
        for _, obj in ipairs(hrp:GetChildren()) do
            if obj.Name == "SeatWeld" and (obj:IsA("Weld") or obj:IsA("Motor6D")) then
                pcall(function() obj:Destroy() end)
            end
        end
    end

    task.wait(0.1)

    char = LP.Character
    hum  = char and char:FindFirstChildOfClass("Humanoid")
    hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hum and hrp then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new(
                hrp.AssemblyLinearVelocity.X,
                math.max(hrp.AssemblyLinearVelocity.Y, hum.JumpPower or 50),
                hrp.AssemblyLinearVelocity.Z
            )
        end)
    end
end

local function tweenCharToTarget(targetCF)
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")

    if not hrp then
        return
    end

    if hum then
        hum.Sit = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    for _, obj in ipairs(hrp:GetChildren()) do
        if obj.Name == "SeatWeld" and (obj:IsA("Weld") or obj:IsA("Motor6D")) then
            pcall(function() obj:Destroy() end)
        end
    end

    pcall(function() hrp.Anchored = true end)
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    local tween = TweenService:Create(hrp,
        TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { CFrame = targetCF }
    )

    tween:Play()
    tween.Completed:Wait()

    pcall(function() hrp.Anchored = false end)
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end)

    char = LP.Character
    hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

----------------------------------------------------------------
-- PIPELINE
----------------------------------------------------------------
function TeleportLocation.Teleport(name, boatId)
    name   = name   or selectedLoc
    boatId = boatId or selectedBoatId

    local targetCF = LOCATIONS[name]
    if not targetCF or not boatId then
        return
    end

    respawnCharacter()
    local char = waitForCharReady(14)
    if not char then
        return
    end

    task.wait(3.0)

    local spawned = spawnBoat(boatId)
    if not spawned then
        return
    end

    task.wait(5.0)
    local boat = waitForMyBoat(10)
    if not boat then
        return
    end
    local boatName = boat.Name
    task.wait(1.0)

    fireBoatTeleport()
    task.wait(7.0)
    char = LP.Character
    if not char then
        return
    end
    local hum4 = char:FindFirstChildOfClass("Humanoid")
    task.wait(0.5)

    simulateReverse(boat, boatName)
    task.wait(1.0)

    setCharacterTouchEnabled(false)
    task.wait(0.1)

    local holdConn = relocateAndLock(boat, targetCF)
    task.wait(0.5)

    jumpCharacter()
    task.wait(2.0)

    setCharacterTouchEnabled(true)

    fireBoatTeleport()
    task.wait(4.0)

    jumpCharacter()
    task.wait(1.5)

    tweenCharToTarget(targetCF)

    if holdConn then
        pcall(function() holdConn:Disconnect() end)
    end
    task.wait(0.5)
    despawnMyBoat()
end

function TeleportLocation.GetAllLocations() return locationNames end
function TeleportLocation.SetLocation(name)  selectedLoc    = name end
function TeleportLocation.SetBoatId(id)      selectedBoatId = id   end

return TeleportLocation