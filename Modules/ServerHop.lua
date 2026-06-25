-- ================================================================
-- SERVER HOP MODULE
-- ================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local LP        = Players.LocalPlayer
local maxPlayers = Players.MaxPlayers

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
local _hopRemote = _G.Net.ServerHop

-- ================================================================
-- REPLION
-- ================================================================
local _replion = nil
local function getReplion()
    if _replion then return _replion end
    local ok, r = pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        return Replion.Client:WaitReplion("ServerBrowser", 10)
    end)
    if ok and r then _replion = r end
    return _replion
end

-- ================================================================
-- MODULE STATE
-- ================================================================
local ServerHop = {
    ServerList    = {},
    OnListUpdate  = nil,
    _isRefreshing = false,
    _rawServers   = nil,
    _sortedList   = {},
    _sortMode     = "players_desc",
    SortOptions = { "Most Players", "Least Players", "Best Ping", "Worst Ping" },
    SortDefault = "Most Players",
}

-- ================================================================
-- SORT
-- ================================================================
local sortMap = {
    ["Most Players"]  = "players_desc",
    ["Least Players"] = "players_asc",
    ["Best Ping"]     = "ping_asc",
    ["Worst Ping"]    = "ping_desc",
}

local function applySortTo(list, mode)
    local sorted = {}
    for _, v in ipairs(list) do table.insert(sorted, v) end

    if mode == "players_asc" then
        table.sort(sorted, function(a, b) return a.players < b.players end)
    elseif mode == "players_desc" then
        table.sort(sorted, function(a, b) return a.players > b.players end)
    elseif mode == "ping_asc" then
        table.sort(sorted, function(a, b) return a.ping < b.ping end)
    elseif mode == "ping_desc" then
        table.sort(sorted, function(a, b) return a.ping > b.ping end)
    end

    return sorted
end

function ServerHop.SetSortMode(label)
    local mode = sortMap[label]
    if not mode then return end
    ServerHop._sortMode   = mode
    ServerHop._sortedList = applySortTo(ServerHop.ServerList, mode)
    if ServerHop.OnListUpdate then pcall(ServerHop.OnListUpdate) end
end

function ServerHop.GetSortedList()
    return ServerHop._sortedList
end

-- ================================================================
-- FORMAT HELPERS
-- ================================================================
local function getPingColored(ping)
    local label, color
    if ping < 80 then
        label = ping .. "ms (Excellent)"
        color = "rgb(80, 200, 120)"
    elseif ping < 150 then
        label = ping .. "ms (Good)"
        color = "rgb(180, 210, 80)"
    elseif ping < 250 then
        label = ping .. "ms (Fair)"
        color = "rgb(230, 175, 50)"
    else
        label = ping .. "ms (Poor)"
        color = "rgb(210, 70, 70)"
    end
    return string.format("<font color='%s'>%s</font>", color, label)
end

local function getPlayersColored(players, maxP)
    return string.format("<font color='rgb(230, 200, 50)'>%d/%d</font>", players, maxP)
end

local function getUptimeColored(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    local str
    if h >= 1 then
        str = string.format("%dh %02dm", h, m)
    else
        str = string.format("%dm %02ds", m, s)
    end
    return string.format("<font color='rgb(80, 160, 230)'>%s</font>", str)
end

local function getEventsStr(events)
    if not events or #events == 0 then return nil end
    if #events <= 3 then return table.concat(events, ", ") end
    local short = {}
    for i = 1, 3 do short[i] = events[i] end
    return table.concat(short, ", ") .. string.format(" (+%d more)", #events - 3)
end

-- ================================================================
-- FORMAT PUBLIC API
-- ================================================================
function ServerHop.FormatServerInfo(entry)
    if not entry then return "—" end

    local maxP = maxPlayers
    local lines = {
        "Players: " .. getPlayersColored(entry.players, maxP),
        "Ping: "    .. getPingColored(entry.ping),
        "Uptime: "  .. getUptimeColored(entry.uptime),
    }

    if entry.region and entry.region ~= "??" then
        table.insert(lines, "Region: " .. entry.region)
    end

    local evStr = getEventsStr(entry.events)
    if evStr then
        table.insert(lines, "Events: " .. evStr)
    end

    return table.concat(lines, "\n")
end

function ServerHop.GetSlotTitle(index, hasData)
    return hasData
        and string.format("Server %d", index)
        or  string.format("Server %d", index)
end

function ServerHop.GetStatusText(count)
    return string.format("Loaded %d server(s). Last refresh: just now.", count)
end

-- ================================================================
-- HELPERS (INTERNAL)
-- ================================================================
local MAX_DISPLAY = 10

local function buildList(rawServers)
    local list = {}

    for jobId, data in pairs(rawServers) do
        if jobId ~= game.JobId and jobId ~= "" then
            table.insert(list, {
                jobId   = jobId,
                players = data.Players and #data.Players or 0,
                ping    = data.Ping or 999,
                uptime  = data.Uptime or 0,
                events  = data.Events or {},
                locale  = data.Locale or "??",
                region  = data.Region or "??",
                rap     = data.RAP,
            })
        end
    end

    local trimmed = {}
    for i = 1, math.min(#list, MAX_DISPLAY) do
        trimmed[i] = list[i]
    end

    return trimmed
end

local function buildListFewest(rawServers)
    local list = {}

    for jobId, data in pairs(rawServers) do
        if jobId ~= game.JobId and jobId ~= "" then
            local playerCount = data.Players and #data.Players or 0
            if playerCount > 0 then
                table.insert(list, {
                    jobId   = jobId,
                    players = playerCount,
                    ping    = data.Ping or 999,
                    uptime  = data.Uptime or 0,
                    events  = data.Events or {},
                    locale  = data.Locale or "??",
                    region  = data.Region or "??",
                })
            end
        end
    end

    table.sort(list, function(a, b)
        return a.players < b.players
    end)

    return list[1]
end

-- ================================================================
-- REFRESH
-- ================================================================
function ServerHop.Refresh(callback)
    if ServerHop._isRefreshing then return end
    ServerHop._isRefreshing = true

    task.spawn(function()
        local replion = getReplion()
        if not replion then
            ServerHop._isRefreshing = false
            if callback then pcall(callback, {}, "Replion not available") end
            return
        end

        local ok, rawServers = pcall(function()
            return replion:GetExpect("Servers")
        end)

        if not ok or type(rawServers) ~= "table" then
            ok, rawServers = pcall(function()
                return replion:Get("Servers")
            end)
        end

        if not ok or type(rawServers) ~= "table" then
            ServerHop._isRefreshing = false
            if callback then pcall(callback, {}, "Failed to fetch server list") end
            return
        end

        ServerHop.ServerList  = buildList(rawServers)
        ServerHop._sortedList = applySortTo(ServerHop.ServerList, ServerHop._sortMode)
        ServerHop._rawServers = rawServers
        ServerHop._isRefreshing = false

        if ServerHop.OnListUpdate then
            pcall(ServerHop.OnListUpdate)
        end
        if callback then pcall(callback, ServerHop.ServerList, nil) end
    end)
end

-- ================================================================
-- HOP TO
-- ================================================================
function ServerHop.HopTo(jobId)
    if not jobId or jobId == "" then
        warn("[ServerHop] No jobId provided")
        return false
    end

    local ok = pcall(function()
        _hopRemote:FireServer(jobId)
    end)
    if ok then return true end

    local ok2 = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LP)
    end)
    return ok2
end

-- ================================================================
-- HOP RANDOM
-- ================================================================
function ServerHop.HopRandom()
    local list = ServerHop.ServerList
    if not list or #list == 0 then
        warn("[ServerHop] Server list empty, call Refresh() first")
        return false
    end
    local pick = list[math.random(1, #list)]
    return ServerHop.HopTo(pick.jobId), pick
end

-- ================================================================
-- HOP TO FEWEST
-- ================================================================
function ServerHop.HopToFewest()
    local raw = ServerHop._rawServers
    if not raw then
        warn("[ServerHop] No raw servers, call Refresh() first")
        return false
    end
    local entry = buildListFewest(raw)
    if not entry then
        warn("[ServerHop] No suitable server found")
        return false
    end
    return ServerHop.HopTo(entry.jobId), entry
end

return ServerHop