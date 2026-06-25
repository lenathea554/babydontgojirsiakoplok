----------------------------------------------------------------
-- LEGIT INSTANT MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerTask(thread)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, thread)
    end
end

-- ================================================================
-- DEPENDENCIES
-- ================================================================
local FishingController = require(ReplicatedStorage.Controllers.FishingController)

local RF_CancelFishingInputs = _G.Net.CancelFishingInputs
local RE_CatchFishCompleted  = _G.Net.CatchFishCompleted

local LocalPlayer   = Players.LocalPlayer
local CurrentCamera = workspace.CurrentCamera

local PI = math.pi

-- ================================================================
-- CAST MODE POWER CALCULATION
-- ================================================================
local function getPowerAtTime(chargeTime, elapsed)
    local speed = Random.new(chargeTime):NextInteger(4, 10)
    local angle = PI / 2 + elapsed * speed
    return (1 - math.sin(angle)) / 2
end

local function waitForTargetPower(chargeTime, targetPower)
    local deadline = chargeTime + 2.0
    while workspace:GetServerTimeNow() < deadline do
        local elapsed = workspace:GetServerTimeNow() - chargeTime
        local power   = getPowerAtTime(chargeTime, elapsed)
        if power >= targetPower then
            return
        end
        task.wait(0.001)
    end
end

-- ================================================================
-- STATE
-- ================================================================
local LegitInstant = {}

local CAST_MODE_LIST = { "Stable", "Fast", "Perfect", "Random" }

local state = {
    enabled   = false,
    castMode  = "Stable",
    castDelay = 0.3,
}

local loopTask = nil

-- ================================================================
-- CORE LOOP
-- ================================================================
local function legitLoop()
    while state.enabled do
        if _G._NEXTHUB_TREASURE_ACTIVE then
            task.wait(0.5)
            continue
        end

        if LocalPlayer:GetAttribute("InCutscene") then
            task.wait(0.5)
            continue
        end

        if LocalPlayer:GetAttribute("IsTrading") or LocalPlayer:GetAttribute("SellAll") then
            task.wait(0.1)
            continue
        end

        if FishingController:OnCooldown() then
            task.wait(0.2)
            continue
        end

        if FishingController:GetCurrentGUID() then
            FishingController:RequestFishingMinigameClick()
            task.defer(function()
                pcall(function() RE_CatchFishCompleted:FireServer() end)
            end)
            local t = os.clock()
            while FishingController:GetCurrentGUID() and os.clock() - t < 5 do
                task.wait(0.05)
            end
            task.wait(state.castDelay)
            continue
        end

        local mousePos = Vector2.new(
            CurrentCamera.ViewportSize.X / 2,
            CurrentCamera.ViewportSize.Y / 2
        )

        if state.castMode == "Stable" then
            FishingController:RequestChargeFishingRod(mousePos, true)
            task.wait(0.8)

        else
            local chargeTime = nil

            task.spawn(function()
                chargeTime = workspace:GetServerTimeNow()
                FishingController:RequestChargeFishingRod(mousePos, false)
            end)

            local t0 = os.clock()
            while not chargeTime and os.clock() - t0 < 1 do
                task.wait(0.01)
            end

            local t1 = os.clock()
            while not FishingController:GetFishingInput() and os.clock() - t1 < 2 do
                task.wait(0.01)
            end

            local v17 = FishingController:GetFishingInput()
            if not v17 then
                task.wait(0.5)
                continue
            end

            if state.castMode == "Perfect" then
                waitForTargetPower(chargeTime, 0.99)
            elseif state.castMode == "Random" then
                task.wait(math.random(10, 150) / 100)
            else -- Fast
                task.wait(0.05)
            end

            local currentV17 = FishingController:GetFishingInput()
            if currentV17 then
                pcall(currentV17, nil, false)
            end

            task.wait(0.5)
        end

        local t2 = os.clock()
        while not FishingController:GetCurrentGUID() and os.clock() - t2 < 4 do
            task.wait(0.05)
        end
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function LegitInstant.SetCastMode(mode)
    if type(mode) == "string" and table.find(CAST_MODE_LIST, mode) then
        state.castMode = mode
    end
end

function LegitInstant.GetCastModes()
    return CAST_MODE_LIST
end

function LegitInstant.SetCastDelay(n)
    local num = tonumber(n)
    if num and num >= 0 then
        state.castDelay = num
    end
end

function LegitInstant.IsActive()
    return state.enabled
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function LegitInstant.Start()
    if state.enabled then return end
    state.enabled = true

    loopTask = task.spawn(legitLoop)
    registerTask(loopTask)
end

function LegitInstant.Stop()
    if not state.enabled then return end
    state.enabled = false

    if loopTask then
        pcall(task.cancel, loopTask)
        loopTask = nil
    end

    if RF_CancelFishingInputs then
        task.spawn(function()
            pcall(function() RF_CancelFishingInputs:InvokeServer() end)
        end)
    end
end

return LegitInstant