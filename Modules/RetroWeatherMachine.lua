----------------------------------------------------------------
-- RETRO WEATHER MACHINE MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Replion       = require(ReplicatedStorage.Packages.Replion).Client
local EventUtility  = require(ReplicatedStorage.Shared.EventUtility)

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
local RF_PurchaseWeatherEvent = _G.Net.PurchaseWeatherEvent

-- ================================================================
-- STATE
-- ================================================================
local RetroWeatherMachine = {}

local state = {
    enabled       = false,
    selectedEvent = nil,
    eventsRep     = nil,
    dataRep       = nil,
    removeConn    = nil,
    loopTask      = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================

local function getRetroWeatherList()
    local list = {}
    local ok, Events = pcall(require, ReplicatedStorage.Events)
    if not ok or not Events then return list end

    for name, _ in pairs(Events) do
        local eventData = EventUtility:GetEvent(name)
        if eventData and eventData.RetroMachine and eventData.RetroMachinePrice then
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

local function isRetroSlotOccupied()
    if not state.eventsRep then return false end
    local slots = state.eventsRep:GetExpect("RetroMachine") or {}
    return #slots >= 1
end

local function isAlreadyActive(weatherName)
    if not state.eventsRep then return false end
    if state.eventsRep:Find("RetroMachine", weatherName) then return true end
    if state.eventsRep:Find("Events", weatherName) then return true end
    return false
end

local function hasEnoughTix(price)
    if not state.dataRep then return false end
    local tix = state.dataRep:GetExpect("Tix") or 0
    return tix >= price
end

local function tryPurchase(weatherName)
    local eventData = EventUtility:GetEvent(weatherName)
    if not eventData or not eventData.RetroMachinePrice then return false end

    if isAlreadyActive(weatherName) then return false end
    if isRetroSlotOccupied() then return false end
    if not hasEnoughTix(eventData.RetroMachinePrice) then return false end

    local ok, result = pcall(function()
        return RF_PurchaseWeatherEvent:InvokeServer(weatherName)
    end)

    return ok and result == true
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function startLoop()
    if state.loopTask then
        pcall(task.cancel, state.loopTask)
        state.loopTask = nil
    end

    state.loopTask = task.spawn(function()
        while state.enabled do
            if state.selectedEvent then
                if not isRetroSlotOccupied() and not isAlreadyActive(state.selectedEvent) then
                    tryPurchase(state.selectedEvent)
                end
            end
            task.wait(5)
        end
    end)

    registerTask(state.loopTask)
end

local function stopLoop()
    if state.loopTask then
        pcall(task.cancel, state.loopTask)
        state.loopTask = nil
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================

function RetroWeatherMachine.GetWeatherList()
    return getRetroWeatherList()
end

function RetroWeatherMachine.SetWeather(name)
    state.selectedEvent = name
end

function RetroWeatherMachine.Start()
    if state.enabled then return end
    if not state.selectedEvent then return end

    state.eventsRep = Replion:WaitReplion("Events")
    state.dataRep   = Replion:WaitReplion("Data")
    state.enabled   = true

    state.removeConn = state.eventsRep:OnArrayRemove("RetroMachine", function(_, removedName)
        if not state.enabled then return end
        if removedName ~= state.selectedEvent then return end
        task.wait(2)
        if state.enabled and not isAlreadyActive(state.selectedEvent) then
            tryPurchase(state.selectedEvent)
        end
    end)
    registerConn(state.removeConn)

    startLoop()
end

function RetroWeatherMachine.Stop()
    if not state.enabled then return end
    state.enabled = false

    stopLoop()

    if state.removeConn then
        pcall(function() state.removeConn:Disconnect() end)
        state.removeConn = nil
    end
end

function RetroWeatherMachine.IsEnabled()
    return state.enabled
end

return RetroWeatherMachine