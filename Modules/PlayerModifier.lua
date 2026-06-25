-- ================================================================
-- PLAYER MODIFIER MODULE
-- ================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerConn(conn)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, conn)
    end
end

local function registerTask(thread)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, thread)
    end
end

-- ================================================================
-- MODULE STATE
-- ================================================================
local PlayerModifier = {
    WalkSpeedEnabled    = false,
    WalkSpeedValue      = 16,
    JumpPowerEnabled    = false,
    JumpPowerValue      = 50,
    InfiniteJumpEnabled = false,
    WalkOnWaterEnabled  = false,
    FreeCamEnabled      = false,
    NoClipEnabled       = false,

    _noClipConn       = nil,
    _waterConn        = nil,
    _infiniteJumpConn = nil,
    _freeCamThread    = nil,
}

-- ================================================================
-- HELPERS
-- ================================================================
local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function applyCharacterStats()
    local hum = getHumanoid()
    if not hum then return end
    if PlayerModifier.WalkSpeedEnabled then
        hum.WalkSpeed = PlayerModifier.WalkSpeedValue
    end
    if PlayerModifier.JumpPowerEnabled then
        if hum.UseJumpPower then
            hum.JumpPower  = PlayerModifier.JumpPowerValue
        else
            hum.JumpHeight = PlayerModifier.JumpPowerValue
        end
    end
end

-- ================================================================
-- CHARACTER ADDED
-- ================================================================
registerConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    applyCharacterStats()
    if PlayerModifier.NoClipEnabled       then PlayerModifier.SetNoClip(true)       end
    if PlayerModifier.WalkOnWaterEnabled  then PlayerModifier.SetWalkOnWater(true)  end
    if PlayerModifier.InfiniteJumpEnabled then PlayerModifier.SetInfiniteJump(true) end
end))

-- ================================================================
-- WALK SPEED
-- ================================================================
function PlayerModifier.SetWalkSpeed(value)
    local v = tonumber(value)
    if v and v >= 0 then
        PlayerModifier.WalkSpeedValue = v
        if PlayerModifier.WalkSpeedEnabled then
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = v end
        end
    end
end

function PlayerModifier.SetWalkSpeedEnabled(state)
    PlayerModifier.WalkSpeedEnabled = state
    local hum = getHumanoid()
    if not hum then return end
    hum.WalkSpeed = state and PlayerModifier.WalkSpeedValue or 16
end

-- ================================================================
-- JUMP POWER
-- ================================================================
function PlayerModifier.SetJumpPower(value)
    local v = tonumber(value)
    if v and v >= 0 then
        PlayerModifier.JumpPowerValue = v
        if PlayerModifier.JumpPowerEnabled then
            local hum = getHumanoid()
            if hum then
                if hum.UseJumpPower then hum.JumpPower  = v
                else                     hum.JumpHeight = v end
            end
        end
    end
end

function PlayerModifier.SetJumpPowerEnabled(state)
    PlayerModifier.JumpPowerEnabled = state
    local hum = getHumanoid()
    if not hum then return end
    if state then
        if hum.UseJumpPower then hum.JumpPower  = PlayerModifier.JumpPowerValue
        else                     hum.JumpHeight = PlayerModifier.JumpPowerValue end
    else
        if hum.UseJumpPower then hum.JumpPower  = 50
        else                     hum.JumpHeight = 7.2 end
    end
end

-- ================================================================
-- INFINITE JUMP
-- ================================================================
function PlayerModifier.SetInfiniteJump(state)
    PlayerModifier.InfiniteJumpEnabled = state

    if PlayerModifier._infiniteJumpConn then
        pcall(function() PlayerModifier._infiniteJumpConn:Disconnect() end)
        PlayerModifier._infiniteJumpConn = nil
    end

    if not state then return end

    local conn = UserInputService.JumpRequest:Connect(function()
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
    PlayerModifier._infiniteJumpConn = conn
    registerConn(conn)
end

-- ================================================================
-- WALK ON WATER
-- ================================================================
local VOXEL_RES          = 4
local WATER_FLOAT_OFFSET = 3
local WATER_CHECK_RATE   = 0.1

local function snapToGrid(v, res)
    return math.floor(v / res) * res
end

local function isInWater(pos)
    local sx = snapToGrid(pos.X, VOXEL_RES)
    local sy = snapToGrid(pos.Y, VOXEL_RES)
    local sz = snapToGrid(pos.Z, VOXEL_RES)

    local minPt = Vector3.new(sx,            sy - VOXEL_RES, sz)
    local maxPt = Vector3.new(sx + VOXEL_RES, sy,            sz + VOXEL_RES)

    local ok, occupancy = pcall(function()
        return Workspace.Terrain:ReadVoxels(Region3.new(minPt, maxPt), VOXEL_RES)
    end)
    if not ok then return false end

    for _, plane in ipairs(occupancy) do
        for _, row in ipairs(plane) do
            for _, v in ipairs(row) do
                if v > 0 then return true end
            end
        end
    end
    return false
end

function PlayerModifier.SetWalkOnWater(state)
    PlayerModifier.WalkOnWaterEnabled = state

    if PlayerModifier._waterConn then
        pcall(function() PlayerModifier._waterConn:Disconnect() end)
        PlayerModifier._waterConn = nil
    end

    if not state then
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bv = hrp:FindFirstChild("_WaterBodyVel")
            if bv then bv:Destroy() end
        end
        return
    end

    local lastCheck = 0

    local conn = RunService.Heartbeat:Connect(function(dt)
        if not PlayerModifier.WalkOnWaterEnabled then return end

        local now = os.clock()
        if now - lastCheck < WATER_CHECK_RATE then return end
        lastCheck = now

        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local footPos = hrp.Position - Vector3.new(0, 2.5, 0)

        if isInWater(footPos) or isInWater(hrp.Position) then
            local bv = hrp:FindFirstChild("_WaterBodyVel")
            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.Name     = "_WaterBodyVel"
                bv.MaxForce = Vector3.new(0, math.huge, 0)
                bv.Velocity = Vector3.zero
                bv.Parent   = hrp
            end

            local hum      = char:FindFirstChildOfClass("Humanoid")
            local onGround = hum and hum.FloorMaterial ~= Enum.Material.Air

            if onGround then
                bv.Velocity = Vector3.zero
            else
                bv.Velocity = Vector3.new(0, WATER_FLOAT_OFFSET, 0)
            end

            local waterSurfaceY = snapToGrid(hrp.Position.Y, VOXEL_RES)
            if hrp.Position.Y < waterSurfaceY + WATER_FLOAT_OFFSET then
                hrp.CFrame = hrp.CFrame + Vector3.new(0, WATER_FLOAT_OFFSET * dt, 0)
            end
        else
            local bv = hrp:FindFirstChild("_WaterBodyVel")
            if bv then bv:Destroy() end
        end
    end)

    PlayerModifier._waterConn = conn
    registerConn(conn)
end

-- ================================================================
-- UNLIMITED FREE CAM
-- ================================================================
function PlayerModifier.SetFreeCam(state)
    PlayerModifier.FreeCamEnabled = state

    if PlayerModifier._freeCamThread then
        pcall(task.cancel, PlayerModifier._freeCamThread)
        PlayerModifier._freeCamThread = nil
    end

    if not state then
        LocalPlayer.CameraMaxZoomDistance = 99
        LocalPlayer.CameraMinZoomDistance = 0.5
        return
    end

    LocalPlayer.CameraMaxZoomDistance = 3000
    LocalPlayer.CameraMinZoomDistance = 0

    PlayerModifier._freeCamThread = task.spawn(function()
        while PlayerModifier.FreeCamEnabled do
            task.wait(5)
            pcall(function()
                LocalPlayer.CameraMaxZoomDistance = 3000
                LocalPlayer.CameraMinZoomDistance = 0
            end)
        end
    end)
    registerTask(PlayerModifier._freeCamThread)
end

-- ================================================================
-- NO-CLIP
-- ================================================================
function PlayerModifier.SetNoClip(state)
    PlayerModifier.NoClipEnabled = state

    if PlayerModifier._noClipConn then
        pcall(function() PlayerModifier._noClipConn:Disconnect() end)
        PlayerModifier._noClipConn = nil
    end

    if not state then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
        return
    end

    local conn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = false
            end
        end
    end)

    PlayerModifier._noClipConn = conn
    registerConn(conn)
end

return PlayerModifier