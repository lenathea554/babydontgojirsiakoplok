----------------------------------------------------------------
-- SUPER INSTANT MODULE (+ Instant Bobber/Bait)
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local SuperInstant = {}

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local RE_CatchFishCompleted            = _G.Net.CatchFishCompleted
local RF_ChargeFishingRod              = _G.Net.ChargeFishingRod
local RF_RequestFishingMinigameStarted = _G.Net.RequestFishingMinigameStarted
local RF_CancelFishingInputs           = _G.Net.CancelFishingInputs
local RE_BaitCastVisual                = _G.Net.BaitCastVisual

local PI = math.pi

local function getPowerAtTime(chargeTime, elapsed)
    local speed = Random.new(chargeTime):NextInteger(4, 10)
    local angle = PI / 2 + elapsed * speed
    return (1 - math.sin(angle)) / 2
end

local function waitForPower(chargeTime, threshold)
    local deadline = chargeTime + 2.0
    while workspace:GetServerTimeNow() < deadline do
        local elapsed = workspace:GetServerTimeNow() - chargeTime
        local power   = getPowerAtTime(chargeTime, elapsed)
        if power >= threshold then
            return elapsed, power
        end
        task.wait(0.001)
    end
    local elapsed = workspace:GetServerTimeNow() - chargeTime
    return elapsed, getPowerAtTime(chargeTime, elapsed)
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local CAST_MODE_LIST = { "Perfect", "Fast", "Random" }

local state = {
    enabled       = false,
    instantBobber = true,
    antiStuck     = false,
    castMode      = "Fast",
    completeDelay = 3,
    castDelay     = 0.1,
    stuckTimeout  = 4,
    lastActivity  = 0,
    notifDelay    = 1.6,
    notifDuration = 4.7,
}

local loopTask    = nil
local stuckTask   = nil
local notifHooked = false

----------------------------------------------------------------
-- INSTANT BAIT CAST
----------------------------------------------------------------
local baitSnapConn   = nil
local baitHookDone   = false

local activeSnapTask = nil

local SNAP_MAX_ATTEMPTS = 12
local SNAP_INTERVAL     = 0.1

local function snapBaitModel(model, castPosition)
    if activeSnapTask then
        pcall(task.cancel, activeSnapTask)
        activeSnapTask = nil
    end

    if not model or not model.Parent then return end

    activeSnapTask = task.spawn(function()
        for _ = 1, SNAP_MAX_ATTEMPTS do
            if not model or not model.Parent then
                break
            end

            local ok = pcall(function()
                model:PivotTo(CFrame.new(castPosition))
            end)

            if ok then
                break
            end

            task.wait(SNAP_INTERVAL)
        end
        activeSnapTask = nil
    end)

    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, activeSnapTask)
    end
end

local function startBaitHook()
    if baitHookDone then return end
    if not RE_BaitCastVisual then return end

    baitSnapConn = RE_BaitCastVisual.OnClientEvent:Connect(function(p1, p2)
        if not state.enabled then return end
        if not state.instantBobber then return end
        if type(p2) ~= "table" then return end

        local castPos = p2.CastPosition
        if not castPos then return end

        local modelName = tostring(p1.UserId)
        local CosmeticFolder = workspace:FindFirstChild("CosmeticFolder")
        if not CosmeticFolder then return end

        local function trySnap()
            local model = CosmeticFolder:FindFirstChild(modelName)
            if model then
                snapBaitModel(model, castPos)
                return
            end

            local snapped = false
            local watchConn
            watchConn = CosmeticFolder.ChildAdded:Connect(function(child)
                if child.Name ~= modelName or snapped then return end
                snapped = true
                watchConn:Disconnect()
                task.defer(function()
                    snapBaitModel(child, castPos)
                end)
            end)

            task.delay(3, function()
                if not snapped then
                    pcall(function() watchConn:Disconnect() end)
                end
            end)
        end

        task.defer(trySnap)
    end)

    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, baitSnapConn)
    end

    baitHookDone = true
end

local function stopBaitHook()
    if baitSnapConn then
        pcall(function() baitSnapConn:Disconnect() end)
        baitSnapConn = nil
    end

    if activeSnapTask then
        pcall(task.cancel, activeSnapTask)
        activeSnapTask = nil
    end

    baitHookDone = false
end

----------------------------------------------------------------
-- NOTIFICATION HOOK
----------------------------------------------------------------
local function hookNotificationDelay()
    if notifHooked then return end
    local ok, controller = pcall(function()
        return require(ReplicatedStorage.Controllers.TextNotificationController)
    end)
    if not ok or not controller then return end
    if not controller.DeliverNotification then return end

    local originalDeliver = controller.DeliverNotification
    controller.DeliverNotification = function(self, p24)
        if state.enabled and state.notifDelay > 0 then
            task.spawn(function()
                task.wait(state.notifDelay)
                originalDeliver(self, p24)
            end)
        else
            originalDeliver(self, p24)
        end
    end

    if controller.Tween then
        local originalTween = controller.Tween
        controller.Tween = function(self, tile, duration, options)
            local finalDuration = state.enabled and state.notifDuration > 0
                and duration + state.notifDuration or duration
            return originalTween(self, tile, finalDuration, options)
        end
    end

    notifHooked = true
end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function safeFire(fn)
    task.spawn(function() pcall(fn) end)
end

local function handleCastMode(t0)
    local mode = state.castMode
    if mode == "Perfect" then
        local _, power = waitForPower(t0, 0.97)
        return power
    elseif mode == "Random" then
        local randomElapsed = math.random(0, 100) / 100 * (PI / 4)
        task.wait(randomElapsed)
        return getPowerAtTime(t0, workspace:GetServerTimeNow() - t0)
    else
        return getPowerAtTime(t0, workspace:GetServerTimeNow() - t0)
    end
end

----------------------------------------------------------------
-- ANTI-STUCK LOOP
----------------------------------------------------------------
local function startAntiStuck()
    if stuckTask then return end
    stuckTask = task.spawn(function()
        while state.enabled do
            task.wait(1)
            if not state.antiStuck then continue end
            if os.clock() - state.lastActivity > state.stuckTimeout then
                state.lastActivity = os.clock()
                safeFire(function() RF_CancelFishingInputs:InvokeServer(true) end)
            end
        end
        stuckTask = nil
    end)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, stuckTask)
    end
end

local function stopAntiStuck()
    if stuckTask then
        pcall(task.cancel, stuckTask)
        stuckTask = nil
    end
end

----------------------------------------------------------------
-- CORE LOOP
----------------------------------------------------------------
local function ultraCastLoop()
    while state.enabled do
        if _G._NEXTHUB_TREASURE_ACTIVE then
            task.wait(0.5)
            continue
        end

        if LocalPlayer:GetAttribute("InCutscene") then
            task.wait(0.1)
            continue
        end

        if LocalPlayer:GetAttribute("IsTrading") or LocalPlayer:GetAttribute("SellAll") then
            task.wait(0.1)
            continue
        end

        local now = workspace:GetServerTimeNow()
        state.lastActivity = os.clock()

        safeFire(function()
            RF_ChargeFishingRod:InvokeServer(nil, nil, now, nil)
        end)

        local power = handleCastMode(now)

        safeFire(function()
            RF_RequestFishingMinigameStarted:InvokeServer(0, power, now)
        end)

        task.wait(state.completeDelay)
        state.lastActivity = os.clock()

        safeFire(function()
            RE_CatchFishCompleted:FireServer()
        end)

        task.wait(state.castDelay)
    end
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function SuperInstant.SetCastMode(mode)
    if type(mode) == "string" and table.find(CAST_MODE_LIST, mode) then
        state.castMode = mode
    end
end

function SuperInstant.GetCastModes()
    return CAST_MODE_LIST
end

function SuperInstant.SetCompleteDelay(n)
    local num = tonumber(n)
    if num then state.completeDelay = num end
end
SuperInstant.setCompleteDelay = SuperInstant.SetCompleteDelay

function SuperInstant.SetCastDelay(n)
    local num = tonumber(n)
    if num then state.castDelay = num end
end
SuperInstant.setCastDelay = SuperInstant.SetCastDelay

function SuperInstant.SetAntiStuck(st)
    if type(st) == "boolean" then state.antiStuck = st end
end

function SuperInstant.SetInstantBobber(enabled)
    if type(enabled) ~= "boolean" then return end

    state.instantBobber = enabled

    if not enabled then
        -- Immediately stop any in-flight snap so a stale cast
        -- doesn't get pivoted after the toggle is turned off.
        if activeSnapTask then
            pcall(task.cancel, activeSnapTask)
            activeSnapTask = nil
        end
    end
end

function SuperInstant.IsActive()
    return state.enabled
end

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------
function SuperInstant.Start()
    if state.enabled then return end
    state.enabled = true

    hookNotificationDelay()

    if state.instantBobber then
        startBaitHook()
    end

    startAntiStuck()

    loopTask = task.spawn(ultraCastLoop)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, loopTask)
    end
end

function SuperInstant.Stop()
    state.enabled = false

    if loopTask then
        pcall(task.cancel, loopTask)
        loopTask = nil
    end

    stopAntiStuck()
    stopBaitHook()

    safeFire(function() RF_CancelFishingInputs:InvokeServer() end)
end

return SuperInstant