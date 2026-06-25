----------------------------------------------------------------
-- AUTO BUY WEATHER
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Replion = require(ReplicatedStorage.Packages.Replion).Client

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerConn(conn)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, conn)
    end
end

-- ================================================================
-- REMOTES
-- ================================================================
local RF_PurchaseWeatherEvent = _G.Net.PurchaseWeatherEvent

-- ================================================================
-- DATA
-- ================================================================
local ALL_WEATHERS = {
    "Cloudy", "Storm", "Wind", "Snow", "Radiant", "Shark Hunt",
}

-- ================================================================
-- STATE
-- ================================================================
local AutoBuyWeather = {}

local state = {
    enabled        = false,
    removeConn     = nil,
    selectedLookup = {},
    weathers       = {},
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function rebuildLookup()
    table.clear(state.selectedLookup)
    for _, w in ipairs(state.weathers) do
        state.selectedLookup[w] = true
    end
end

local function tryBuy(weather)
    if not RF_PurchaseWeatherEvent then return end
    pcall(function()
        RF_PurchaseWeatherEvent:InvokeServer(weather)
    end)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoBuyWeather.GetAllWeathers()
    return ALL_WEATHERS
end

function AutoBuyWeather.SetWeathers(list)
    state.weathers = list or {}
    rebuildLookup()
end

function AutoBuyWeather.Start()
    if state.enabled then return end
    state.enabled = true

    rebuildLookup()

    local eventsRep = Replion:WaitReplion("Events")

    state.removeConn = eventsRep:OnArrayRemove("Events", function(_, weather)
        if not state.enabled then return end
        if not state.selectedLookup[weather] then return end
        tryBuy(weather)
    end)
    registerConn(state.removeConn)

    local ok, active = pcall(function() return eventsRep:GetExpect("Events") or {} end)
    if not ok then active = {} end

    local activeSet = {}
    for _, w in ipairs(active) do
        activeSet[w] = true
    end

    for _, weather in ipairs(ALL_WEATHERS) do
        if state.enabled and state.selectedLookup[weather] and not activeSet[weather] then
            tryBuy(weather)
        end
    end
end

function AutoBuyWeather.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.removeConn then
        pcall(function() state.removeConn:Disconnect() end)
        state.removeConn = nil
    end
end

function AutoBuyWeather.IsEnabled()
    return state.enabled
end

return AutoBuyWeather