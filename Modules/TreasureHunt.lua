----------------------------------------------------------------
-- AUTO TREASURE HUNT MODULE
----------------------------------------------------------------
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

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
-- REMOTES
-- ================================================================
local RE_TreasureChestClaimed = _G.Net.TreasureChestClaimed

-- ================================================================
-- CONSTANTS
-- ================================================================
local WRECKAGE_NAME   = "Sunken Wreckage"
local TREASURE_NAME   = "Treasure"
local SHINE_NAME      = "Shine"

local SCAN_INTERVAL   = 5
local FISHING_GRACE   = 1.5
local PROMPT_WAIT     = 1
local CLAIM_WAIT      = 5
local PROMPT_RETRY    = 3

local TELEPORT_OFFSET = Vector3.new(0, 3, 0)
local TELEPORT_HOLD_FRAMES = 4

local BODY_PARTS = {
    "HumanoidRootPart", "Head",
    "UpperTorso",       "LowerTorso",
    "LeftUpperArm",     "LeftLowerArm",   "LeftHand",
    "RightUpperArm",    "RightLowerArm",  "RightHand",
    "LeftUpperLeg",     "LeftLowerLeg",   "LeftFoot",
    "RightUpperLeg",    "RightLowerLeg",  "RightFoot",
}

-- ================================================================
-- STATE
-- ================================================================
local AutoTreasureHunt = {
    Enabled    = false,
    _thread    = nil,
    _claimConn = nil,
}

local state = {
    claimCount  = 0,
    claimedFlag = false,
}

-- ================================================================
-- NETWORK OWNERSHIP
-- ================================================================
local function claimNetworkOwnership(hrp)
    if not hrp or hrp.Anchored then return end
    pcall(function()
        hrp:SetNetworkOwner(Players.LocalPlayer)
    end)
end

local function setCFrameHeld(hrp, cf)
    if not hrp then return end
    claimNetworkOwnership(hrp)
    hrp.CFrame = cf

    local heldFrames = 0
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent then
            if conn then conn:Disconnect() end
            return
        end

        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        heldFrames += 1
        if heldFrames >= TELEPORT_HOLD_FRAMES then
            conn:Disconnect()
        end
    end)
    registerConn(conn)
end

-- ================================================================
-- COLLISION
-- ================================================================
local function setCollision(canCollide)
    local lp   = Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return end
    for _, name in ipairs(BODY_PARTS) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            part.CanCollide = canCollide
        end
    end
end

-- ================================================================
-- HUMANOID STATE
-- ================================================================
local function suppressSwimState(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Swimming,    false) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,     false) end)
end

local function restoreStates(character)
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Swimming,    true) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,     true) end)
end

-- ================================================================
-- FIND TREASURE
-- ================================================================
local function findTreasure()
    local wreckage = Workspace:FindFirstChild(WRECKAGE_NAME)
    if not wreckage then return nil, nil end
    local treasure = wreckage:FindFirstChild(TREASURE_NAME)
    if not treasure then return nil, nil end
    if treasure:GetAttribute("Opened") ~= nil then return nil, nil end
    local shine = treasure:FindFirstChild(SHINE_NAME)
    return treasure, shine
end

local function findPrompt(treasure)
    if not treasure then return nil end
    for _, child in ipairs(treasure:GetChildren()) do
        local pp = child:FindFirstChildOfClass("ProximityPrompt")
        if pp then return pp end
    end
    return treasure:FindFirstChildOfClass("ProximityPrompt", true)
end

-- ================================================================
-- POSITION SAVE / RESTORE
-- ================================================================
local function savePosition()
    local lp   = Players.LocalPlayer
    local char = lp and lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.CFrame or nil
end

local function restorePosition(cframe)
    if not cframe then return end
    local lp   = Players.LocalPlayer
    local char = lp and lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    setCFrameHeld(hrp, cframe)
end

-- ================================================================
-- TELEPORT
-- ================================================================
local function teleportToChest(shine)
    local lp   = Players.LocalPlayer
    local char = lp and lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    setCFrameHeld(hrp, CFrame.new(shine.CFrame.Position + TELEPORT_OFFSET))
    return true
end

-- ================================================================
-- FIRE PROXIMITY PROMPT
-- ================================================================
local function triggerPrompt(prompt)
    if not prompt then return false end
    local ok = pcall(fireproximityprompt, prompt)
    return ok
end

-- ================================================================
-- CLAIM WATCHER
-- ================================================================
local function startClaimWatcher()
    if AutoTreasureHunt._claimConn then return end
    AutoTreasureHunt._claimConn = RE_TreasureChestClaimed.OnClientEvent:Connect(function()
        if not AutoTreasureHunt.Enabled then return end
        state.claimCount  = state.claimCount + 1
        state.claimedFlag = true
    end)
    registerConn(AutoTreasureHunt._claimConn)
end

local function stopClaimWatcher()
    if AutoTreasureHunt._claimConn then
        pcall(function() AutoTreasureHunt._claimConn:Disconnect() end)
        AutoTreasureHunt._claimConn = nil
    end
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function stopLoop()
    if AutoTreasureHunt._thread then
        pcall(task.cancel, AutoTreasureHunt._thread)
        AutoTreasureHunt._thread = nil
    end
end

local function runLoop()
    stopLoop()

    AutoTreasureHunt._thread = task.spawn(function()
        local lp = Players.LocalPlayer
        if not lp then return end

        while AutoTreasureHunt.Enabled do

            if not lp.Character then
                task.wait(2)
                continue
            end

            local treasure, shine = findTreasure()

            if not treasure or not shine then
                task.wait(SCAN_INTERVAL)
                continue
            end

            local char = lp.Character
            if not char then task.wait(1) continue end

            local savedCFrame = savePosition()

            _G._NEXTHUB_TREASURE_ACTIVE = true
            task.wait(FISHING_GRACE)

            if not shine.Parent
                or treasure:GetAttribute("Opened") ~= nil
            then
                _G._NEXTHUB_TREASURE_ACTIVE = false
                task.wait(1)
                continue
            end

            suppressSwimState(char)
            setCollision(false)

            teleportToChest(shine)

            task.wait(PROMPT_WAIT)

            state.claimedFlag = false
            local prompted = false

            for attempt = 1, PROMPT_RETRY do
                local prompt = findPrompt(treasure)
                if prompt then
                    triggerPrompt(prompt)
                    prompted = true
                    break
                end
                task.wait(0.5)
            end

            if not prompted then
                task.wait(1)
            end

            local waited = 0
            while not state.claimedFlag and waited < CLAIM_WAIT do
                task.wait(0.25)
                waited = waited + 0.25
            end

            local charNow = lp.Character
            if charNow then
                restoreStates(charNow)
                setCollision(true)
            end

            restorePosition(savedCFrame)

            _G._NEXTHUB_TREASURE_ACTIVE = false

            task.wait(SCAN_INTERVAL)
        end
    end)

    registerTask(AutoTreasureHunt._thread)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoTreasureHunt.GetClaimCount()
    return state.claimCount
end

function AutoTreasureHunt.ResetCount()
    state.claimCount = 0
end

function AutoTreasureHunt.IsActive()
    return AutoTreasureHunt.Enabled
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function AutoTreasureHunt.Start()
    if AutoTreasureHunt.Enabled then return end
    AutoTreasureHunt.Enabled = true
    _G._NEXTHUB_TREASURE_ACTIVE = false

    startClaimWatcher()
    runLoop()
end

function AutoTreasureHunt.Stop()
    if not AutoTreasureHunt.Enabled then return end
    AutoTreasureHunt.Enabled    = false
    _G._NEXTHUB_TREASURE_ACTIVE = false

    stopLoop()
    stopClaimWatcher()

    local lp = Players.LocalPlayer
    if lp and lp.Character then
        setCollision(true)
        restoreStates(lp.Character)
    end
end

return AutoTreasureHunt