----------------------------------------------------------------
-- AUTO SELL MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local RF_SellAllItems = _G.Net.SellAllItems
local RE_FishCaught   = _G.Net.FishCaught

-- ================================================================
-- STATE
-- ================================================================
local AutoSell = {}

local state = {
    enabled   = false,
    mode      = "Count",
    value     = 10,
    lastCount = 0,
    selling   = false,
    conn      = nil,
    delayTask = nil,
}

-- ================================================================
-- INTERNAL LOGIC
-- ================================================================
local function doSell()
    if state.selling then return end
    state.selling = true
    pcall(function() RF_SellAllItems:InvokeServer() end)
    task.wait(0.5)
    state.selling = false
end

local function stopDelayTask()
    if state.delayTask then
        pcall(task.cancel, state.delayTask)
        state.delayTask = nil
    end
end

local function stopCountConn()
    if state.conn then
        pcall(function() state.conn:Disconnect() end)
        state.conn = nil
    end
    state.lastCount = 0
end

local function startDelayLoop()
    if state.delayTask then return end

    state.delayTask = task.spawn(function()
        while state.enabled and state.mode == "Delay" do
            local duration    = state.value * 60
            local elapsed     = 0
            local interval    = math.min(5, duration)

            while elapsed < duration do
                if not state.enabled or state.mode ~= "Delay" then
                    state.delayTask = nil
                    return
                end
                task.wait(interval)
                elapsed = elapsed + interval
            end

            if state.enabled and state.mode == "Delay" then
                task.spawn(doSell)
            end
        end
        state.delayTask = nil
    end)

    registerTask(state.delayTask)
end

local function startCountConn()
    if state.conn then return end

    state.conn = RE_FishCaught.OnClientEvent:Connect(function()
        if not state.enabled or state.mode ~= "Count" or state.selling then return end

        state.lastCount = state.lastCount + 1
        if state.lastCount >= state.value then
            state.lastCount = 0
            task.spawn(doSell)
        end
    end)

    registerConn(state.conn)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoSell.SetMode(m)
    if m ~= "Count" and m ~= "Delay" then return end
    if m == state.mode then return end

    state.mode = m

    if not state.enabled then return end

    if m == "Delay" then
        stopCountConn()
        state.lastCount = 0
        startDelayLoop()
    else
        stopDelayTask()
        startCountConn()
    end
end

function AutoSell.SetValue(n)
    n = tonumber(n)
    if not n or n <= 0 then return end
    state.value = n
end

function AutoSell.SellOnce()
    state.lastCount = 0
    task.spawn(doSell)
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function AutoSell.Start()
    if state.enabled then return end
    state.enabled   = true
    state.lastCount = 0

    if state.mode == "Count" then
        startCountConn()
    else
        startDelayLoop()
    end
end

function AutoSell.Stop()
    if not state.enabled then return end
    state.enabled = false
    stopCountConn()
    stopDelayTask()
end

return AutoSell