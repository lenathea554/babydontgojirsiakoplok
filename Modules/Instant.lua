----------------------------------------------------------------
-- INSTANT FISH MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Instant = {}

----------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------
local RF_ChargeFishingRod               = _G.Net.ChargeFishingRod
local RE_CatchFishCompleted             = _G.Net.CatchFishCompleted
local RF_RequestFishingMinigameStarted  = _G.Net.RequestFishingMinigameStarted

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
    running       = false,
    castMode      = "Fast",
    completeDelay = 3,
    castDelay     = 0.3,
    notifDelay    = 1.6,
    notifDuration = 4.3,
}

local loopTask      = nil
local notifHooked   = false

local function hookNotificationDelay()
    if notifHooked then return end

    local ok, controller = pcall(function()
        return require(ReplicatedStorage.Controllers.TextNotificationController)
    end)

    if not ok or not controller then
        return
    end

    if not controller.DeliverNotification then
        return
    end

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
            local finalDuration = duration
            if state.enabled and state.notifDuration > 0 then
                finalDuration = duration + state.notifDuration
            end
            return originalTween(self, tile, finalDuration, options)
        end
    end

    notifHooked = true
end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function safeInvoke(remote, ...)
    if not remote then return end
    local args = { ... }
    task.spawn(function()
        pcall(function()
            remote:InvokeServer(unpack(args))
        end)
    end)
end

local function safeFire(remote, ...)
    if not remote then return end
    task.spawn(function()
        pcall(function()
            remote:FireServer()
        end)
    end)
end

local function handleCastMode(t0)
    local mode = state.castMode

    if mode == "Perfect" then
        local _, power = waitForPower(t0, 0.97)
        return power

    elseif mode == "Random" then
        local randomElapsed = math.random(0, 100) / 100 * (PI / 4)
        task.wait(randomElapsed)
        local elapsed = workspace:GetServerTimeNow() - t0
        return getPowerAtTime(t0, elapsed)

    else
        local elapsed = workspace:GetServerTimeNow() - t0
        return getPowerAtTime(t0, elapsed)
    end
end

----------------------------------------------------------------
-- CORE LOOP
----------------------------------------------------------------
local function startLoop()
    if state.running then return end
    state.running = true

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

        local t0 = workspace:GetServerTimeNow()

        safeInvoke(RF_ChargeFishingRod, nil, nil, t0, nil)

        local power = handleCastMode(t0)

        safeInvoke(RF_RequestFishingMinigameStarted, 0, power, t0)

        task.wait(state.completeDelay)
        task.wait(0.01)

        safeFire(RE_CatchFishCompleted)

        task.wait(state.castDelay)
    end

    state.running = false
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function Instant.SetCastMode(mode)
    if table.find(CAST_MODE_LIST, mode) then
        state.castMode = mode
    end
end

function Instant.SetCompleteDelay(v)
    local num = tonumber(v)
    if num and num >= 0 then
        state.completeDelay = num
    end
end

function Instant.SetCastDelay(v)
    local num = tonumber(v)
    if num and num >= 0 then
        state.castDelay = num
    end
end

function Instant.Start()
    if state.enabled then return end
    state.enabled = true

    hookNotificationDelay()

    loopTask = task.spawn(startLoop)

    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, loopTask)
    end
end

function Instant.Stop()
    state.enabled = false

    if loopTask then
        pcall(task.cancel, loopTask)
        loopTask = nil
    end

    state.running = false
end

function Instant.IsActive()
    return state.enabled
end

return Instant