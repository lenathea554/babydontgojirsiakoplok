----------------------------------------------------------------
-- AUTO TRADE MODULE
----------------------------------------------------------------
local Players           = game:GetService("Players")
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
-- DEPENDENCIES
-- ================================================================
local TradeData     = require(ReplicatedStorage.Shared.Trading.TradeData)
local ItemUtil      = require(ReplicatedStorage.Shared.ItemUtility)
local ReplionClient = require(ReplicatedStorage.Packages.Replion).Client
local DataReplion   = ReplionClient:WaitReplion("Data")
local Remotes       = TradeData.Remotes

-- ================================================================
-- CONSTANTS
-- ================================================================
local ITEM_TYPE_MAP = {
    ["Fish"]           = "Fish",
    ["Rod Skins"]      = "Fishing Rods",
    ["Boats"]          = "Boats",
    ["Charms"]         = "Charms",
    ["Bait Skins"]     = "Baits",
    ["Lanterns"]       = "Lanterns",
    ["Emotes"]         = "Emotes",
    ["Enchant Stones"] = "Enchant Stones",
    ["Trophies"]       = "Trophies",
}

local TRADE_START_TIMEOUT   = 10
local PLAYERS_READY_TIMEOUT = 30
local TRADE_RESULT_TIMEOUT  = 30
local ADD_ITEM_INTERVAL     = 1
local NO_ITEM_RETRY_WAIT    = 2

-- ================================================================
-- STATE
-- ================================================================
local AutoTrade = {
    ITEM_TYPE_LABELS = {
        "Fish", "Rod Skins", "Boats", "Charms",
        "Bait Skins", "Lanterns", "Emotes", "Enchant Stones", "Trophies",
    },
    OnUpdate = nil,
}

local trade = {
    running        = false,
    enabled        = false,
    thread         = nil,
    attempted      = 0,
    targetUserId   = nil,
    targetName     = nil,
    targetInstance = nil,
    dataType       = nil,
    selectedItem   = nil,
    holdFavorite   = true,
    maxTrade       = 0,
    delay          = 3,
    itemsPerTrade  = 1,
}

local indicator = {
    mode          = "idle",
    status        = "idle",
    targetName    = nil,
    selectedType  = nil,
    selectedItem  = nil,
    amount        = 1,
    successCount  = 0,
    failCount     = 0,
    totalCount    = 0,
    incomingFrom  = nil,
    incomingItems = nil,
    incomingType  = nil,
}

local autoAcceptConn = nil

-- ================================================================
-- TEXT BUILDER
-- ================================================================
local function rgb(r, g, b)  return ("rgb(%d,%d,%d)"):format(r, g, b) end
local function font(t, c)    return ("<font color='%s'>%s</font>"):format(c, t) end

local COLOR = {
    gray  = rgb(160, 160, 160),
    blue  = rgb(100, 200, 255),
    gold  = rgb(255, 220, 80),
    green = rgb(100, 255, 150),
    red   = rgb(255, 100, 100),
}

local DASH = font("-", COLOR.gray)

local STATUS_COLOR_MAP = {
    ["Accepted"]         = COLOR.green,
    ["max_reached"]      = COLOR.green,
    ["stopped"]          = COLOR.red,
    ["Declined"]         = COLOR.red,
    ["timeout"]          = COLOR.red,
    ["no_target"]        = COLOR.red,
    ["trading_disabled"] = COLOR.red,
    ["no_eligible_item"] = COLOR.gold,
    ["running"]          = COLOR.gold,
    ["starting"]         = COLOR.gold,
    ["waiting_offer"]    = COLOR.gold,
    ["waiting_accept"]   = COLOR.gold,
    ["waiting_ready"]    = COLOR.gold,
    ["confirming"]       = COLOR.gold,
    ["receiving"]        = COLOR.gold,
}

local function statusColor(status)
    if STATUS_COLOR_MAP[status] then return STATUS_COLOR_MAP[status] end
    local lower = status:lower()
    if lower:find("fail") or lower:find("error") or lower:find("failed") then
        return COLOR.red
    end
    return COLOR.gray
end

local function counterSuffix()
    if indicator.totalCount <= 0 then return "" end
    return (" (%d/%d)"):format(indicator.successCount + indicator.failCount, indicator.totalCount)
end

local function buildStatusText()
    local mode   = indicator.mode
    local status = indicator.status

    if mode == "sending" then
        return table.concat({
            "Target Player: "   .. font(indicator.targetName   or "-", COLOR.blue),
            "Items To Trade: "  .. font(indicator.selectedItem or "-", COLOR.gold),
            "Amount To Trade: " .. font(tostring(indicator.amount),    COLOR.gold),
            "Item Type: "       .. font(indicator.selectedType or "-", COLOR.gold),
            "Trade Info: "      .. font(status .. counterSuffix(),     statusColor(status)),
        }, "\n")
    end

    if mode == "receiving" then
        local count = indicator.totalCount > 0 and tostring(indicator.totalCount) or "1"
        return table.concat({
            "Target Player: "    .. font(indicator.incomingFrom  or "-", COLOR.blue),
            "Items To Accept: "  .. font(indicator.incomingItems or "-", COLOR.gold),
            "Amount To Accept: " .. font(count,                          COLOR.gold),
            "Item Type: "        .. font(indicator.incomingType  or "-", COLOR.gold),
            "Trade Info: "       .. font(status .. counterSuffix(),      statusColor(status)),
        }, "\n")
    end

    return table.concat({
        "Target Player: "   .. DASH,
        "Items To Trade: "  .. DASH,
        "Amount To Trade: " .. DASH,
        "Item Type: "       .. DASH,
        "Trade Info: "      .. font("Idle", COLOR.gray),
    }, "\n")
end

-- ================================================================
-- STATUS PUSH
-- ================================================================
local function pushUpdate()
    if not AutoTrade.OnUpdate then return end
    pcall(AutoTrade.OnUpdate, buildStatusText())
end

local function setStatus(status)
    indicator.status = status
    pushUpdate()
end

-- ================================================================
-- INVENTORY HELPERS
-- ================================================================
local function getInventory()
    if not DataReplion then return nil end
    return DataReplion:GetExpect("Inventory")
end

local function getItemData(category, itemId)
    return ItemUtil.GetItemDataFromItemType(category, itemId)
end

local function getEligibleItems()
    local inv = getInventory()
    if not inv then return {} end

    local targetType = trade.dataType
    local targetId   = trade.selectedItem
    local result     = {}

    for category, items in pairs(inv) do
        for _, it in ipairs(items) do
            local itemData = getItemData(category, it.Id)
            if itemData then
                local dataType  = itemData.Data and itemData.Data.Type
                local typeMatch = (targetType == nil) or (dataType == targetType)
                local idMatch   = (targetId   == nil) or (it.Id   == targetId)
                local notFav    = not (trade.holdFavorite and (it.IsFavorite or it.Favorited))
                local notLocked = not (it.Metadata and it.Metadata.TradeLock)
                local hasUUID   = typeof(it.UUID) == "string"

                if typeMatch and idMatch and notFav and notLocked and hasUUID then
                    result[#result + 1] = {
                        itemType = dataType,
                        uuid     = it.UUID,
                        name     = itemData.Data.Name or tostring(it.Id),
                    }
                end
            end
        end
    end

    return result
end

-- ================================================================
-- TRADE SESSION HELPERS
-- ================================================================
local function waitForTradeStarted()
    local replionId = nil
    local conn = Remotes.TradeStarted.OnClientEvent:Connect(function(id) replionId = id end)

    local deadline = os.clock() + TRADE_START_TIMEOUT
    while replionId == nil and os.clock() < deadline do task.wait(0.2) end
    conn:Disconnect()

    if not replionId then setStatus("trade_not_started") end
    return replionId
end

local function addItemsToOffer(slots)
    for _, slot in ipairs(slots) do
        local ok, err = Remotes.AddItem:InvokeServer(slot.itemType, slot.uuid)
        if not ok then
            Remotes.CancelTrade:InvokeServer()
            setStatus(("add_failed: %s"):format(tostring(err)))
            return false
        end
        task.wait(ADD_ITEM_INTERVAL)
    end
    return true
end

local function doSetReady()
    local ok, err = Remotes.SetReady:InvokeServer(true)
    if not ok then
        Remotes.CancelTrade:InvokeServer()
        setStatus(("ready_failed: %s"):format(tostring(err)))
        return false
    end
    return true
end

local function waitAndConfirmTrade(replionId)
    local tradeReplion = ReplionClient:GetReplion(replionId)
    if not tradeReplion then
        setStatus("replion_not_found")
        return false
    end

    setStatus("waiting_ready")

    local playersReady = tradeReplion.Data and tradeReplion.Data.PlayersReady

    if not playersReady then
        local conn = tradeReplion:OnChange("PlayersReady", function(v) if v then playersReady = true end end)
        local deadline = os.clock() + PLAYERS_READY_TIMEOUT
        while not playersReady and os.clock() < deadline do task.wait(0.3) end
        conn:Disconnect()
    end

    if not playersReady then
        Remotes.CancelTrade:InvokeServer()
        setStatus("ready_timeout")
        return false
    end

    setStatus("confirming")
    local ok, err = Remotes.ConfirmTrade:InvokeServer()
    if not ok then
        setStatus(("confirm_failed: %s"):format(tostring(err)))
        return false
    end
    return true
end

local function waitForTradeResult()
    local result = nil
    local c1 = Remotes.TradeCompleted.OnClientEvent:Connect(function(_, msg)
        result = { success = true,  msg = tostring(msg or "Accepted") }
    end)
    local c2 = Remotes.TradeEnded.OnClientEvent:Connect(function(msg)
        result = { success = false, msg = tostring(msg or "Declined") }
    end)

    local deadline = os.clock() + TRADE_RESULT_TIMEOUT
    while result == nil and os.clock() < deadline do task.wait(0.3) end

    c1:Disconnect()
    c2:Disconnect()

    if result == nil then setStatus("result_timeout"); return false end
    setStatus(result.msg)
    return result.success
end

-- ================================================================
-- TRADE LOOP
-- ================================================================
local function tradeLoop()
    setStatus("running")

    while trade.running do
        local limitReached = trade.maxTrade > 0 and trade.attempted >= trade.maxTrade
        if limitReached then
            setStatus("max_reached")
            break
        end

        local eligible = getEligibleItems()
        if #eligible == 0 then
            setStatus("no_eligible_item")
            task.wait(NO_ITEM_RETRY_WAIT)
        else
            local slots = {}
            for i = 1, math.min(trade.itemsPerTrade, #eligible) do
                slots[i] = eligible[i]
            end

            if not trade.targetInstance or not trade.targetInstance.Parent then
                trade.targetInstance = nil
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.UserId == trade.targetUserId then
                        trade.targetInstance = plr
                        break
                    end
                end
            end

            if not trade.targetInstance then
                setStatus("target_left")
                task.wait(2)
            else
                setStatus("sending_offer")
                local sendOk, sendErr = Remotes.SendTradeOffer:InvokeServer(trade.targetInstance)

                if not sendOk then
                    setStatus(("send_failed: %s"):format(tostring(sendErr or "")))
                    task.wait(trade.delay)
                else
                    setStatus("waiting_accept")
                    local replionId = waitForTradeStarted()

                    if replionId then
                        setStatus("running")
                        local addOk = addItemsToOffer(slots)

                        if addOk then
                            local readyOk = doSetReady()
                            if readyOk then
                                local confirmed = waitAndConfirmTrade(replionId)
                                if confirmed then
                                    local success = waitForTradeResult()
                                    trade.attempted = trade.attempted + 1

                                    if success then
                                        indicator.successCount = math.min(
                                            indicator.successCount + 1,
                                            indicator.totalCount
                                        )
                                    else
                                        indicator.failCount = math.min(
                                            indicator.failCount + 1,
                                            indicator.totalCount
                                        )
                                    end
                                    pushUpdate()
                                end
                            end
                        end
                    end

                    task.wait(trade.delay)
                end
            end
        end
    end

    trade.running = false
    trade.enabled = false

    if indicator.status ~= "max_reached" then setStatus("stopped") end
end

-- ================================================================
-- PUBLIC: PROVIDER
-- ================================================================
function AutoTrade.GetPlayerOptions()
    local list, map = {}, {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Players.LocalPlayer then
            list[#list + 1] = plr.Name
            map[plr.Name]   = plr.UserId
        end
    end
    return list, map
end

function AutoTrade.GetItemNamesForCategory(dataType)
    local inv = getInventory()
    if not inv then return {}, {} end

    local itemStats = {}

    for category, items in pairs(inv) do
        for _, it in ipairs(items) do
            local itemData = getItemData(category, it.Id)
            if itemData and itemData.Data and itemData.Data.Type == dataType then
                local id   = it.Id
                local name = itemData.Data.Name or tostring(id)
                if not itemStats[id] then itemStats[id] = { name = name, count = 0 } end
                itemStats[id].count = itemStats[id].count + 1
            end
        end
    end

    local labels, nameMap = {}, {}
    for itemId, stats in pairs(itemStats) do
        local label = ("%s x%d"):format(stats.name, stats.count)
        labels[#labels + 1] = label
        nameMap[label]       = itemId
    end

    table.sort(labels)
    return labels, nameMap
end

local currentNameMap = {}

function AutoTrade.GetItemOptionsForType(label)
    local dataType = ITEM_TYPE_MAP[label]
    if not dataType then currentNameMap = {}; return {} end
    local labels, nameMap = AutoTrade.GetItemNamesForCategory(dataType)
    currentNameMap = nameMap
    return #labels > 0 and labels or {"(empty)"}
end

function AutoTrade.GetItemOptionsForCurrentType()
    if not indicator.selectedType then return {} end
    return AutoTrade.GetItemOptionsForType(indicator.selectedType)
end

function AutoTrade.ResolveItemId(label)
    return currentNameMap[label]
end

function AutoTrade.CountItem(dataType, itemId)
    local inv = getInventory()
    if not inv then return 0 end
    local count = 0
    for category, items in pairs(inv) do
        for _, it in ipairs(items) do
            if it.Id == itemId then
                local itemData = getItemData(category, it.Id)
                if itemData and itemData.Data and itemData.Data.Type == dataType then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- ================================================================
-- PUBLIC: SETTER
-- ================================================================
function AutoTrade.SetTargetPlayer(name, userId)
    trade.targetName      = name
    trade.targetUserId    = userId
    trade.targetInstance  = nil

    if userId then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.UserId == userId then trade.targetInstance = plr; break end
        end
    end

    indicator.targetName = name
    pushUpdate()
end

function AutoTrade.SetItemType(label)
    trade.dataType         = ITEM_TYPE_MAP[label]
    trade.selectedItem     = nil
    indicator.selectedType = label
    indicator.selectedItem = nil
    pushUpdate()
end

function AutoTrade.SetSelectedItem(label, itemId)
    local displayName = nil
    if label and label ~= "(empty)" then
        displayName = label:match("^(.-)%s*x%d+$") or label
    end
    trade.selectedItem     = itemId
    indicator.selectedItem = displayName
    pushUpdate()
end

function AutoTrade.SetAmount(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    trade.maxTrade   = n
    indicator.amount = n
    pushUpdate()
end

function AutoTrade.SetDelay(seconds)
    local v = tonumber(seconds)
    if v and v > 0 then trade.delay = v end
end

function AutoTrade.SetHoldFavorite(state)
    trade.holdFavorite = state == true
end

-- ================================================================
-- PUBLIC: LIFECYCLE
-- ================================================================
function AutoTrade.SetOnUpdate(fn)
    AutoTrade.OnUpdate = fn

    local refreshTask = task.spawn(function()
        while true do
            task.wait(0.5)
            if indicator.mode ~= "idle" then pushUpdate() end
        end
    end)
    registerTask(refreshTask)

    task.spawn(function()
        task.wait(0.1)
        pushUpdate()
    end)
end

function AutoTrade.Init(paragraphRef)
    if not paragraphRef then return end
    AutoTrade.SetOnUpdate(function(text)
        pcall(function() paragraphRef:SetText(text) end)
    end)
end

function AutoTrade.StartTrade()
    if trade.running or trade.enabled then return false, "Already running" end
    if not trade.targetUserId            then return false, "Select a target player first!" end
    if not trade.targetInstance          then return false, "Target player not found in server!" end
    if not indicator.selectedType        then return false, "Select an item type first!" end
    if not trade.selectedItem            then return false, "Select an item first!" end
    if not TradeData.IsEnabled()         then return false, "Trading is currently disabled!" end

    local inInventory = AutoTrade.CountItem(trade.dataType, trade.selectedItem)
    if inInventory < indicator.amount then
        return false, ("Not enough items! Have %d, need %d"):format(inInventory, indicator.amount)
    end

    trade.attempted        = 0
    trade.running          = true
    trade.enabled          = true
    indicator.mode         = "sending"
    indicator.status       = "starting"
    indicator.successCount = 0
    indicator.failCount    = 0
    indicator.totalCount   = indicator.amount
    pushUpdate()

    trade.thread = task.spawn(tradeLoop)
    registerTask(trade.thread)

    return true, nil
end

function AutoTrade.StopTrade()
    if not trade.running and not trade.enabled then return end

    trade.running = false
    trade.enabled = false

    if trade.thread then
        pcall(task.cancel, trade.thread)
        trade.thread = nil
    end

    indicator.mode   = "idle"
    indicator.status = "idle"
    pushUpdate()
end

function AutoTrade.StartAutoAccept()
    if autoAcceptConn then return end

    autoAcceptConn = Remotes.TradeOfferReceived.OnClientEvent:Connect(function(offerPlayer)
        local senderName = (offerPlayer and offerPlayer.Name) or "Unknown"

        indicator.mode          = "receiving"
        indicator.incomingFrom  = senderName
        indicator.successCount  = 0
        indicator.failCount     = 0
        indicator.totalCount    = 1
        indicator.status        = "receiving"
        indicator.incomingItems = "?"
        indicator.incomingType  = "-"
        pushUpdate()

        local acceptOk, acceptErr = Remotes.AcceptTradeOffer:InvokeServer(offerPlayer)
        if not acceptOk then
            indicator.failCount = 1
            setStatus(("accept_failed: %s"):format(tostring(acceptErr or "")))
            return
        end

        setStatus("waiting_accept")
        local replionId = waitForTradeStarted()
        if not replionId then
            indicator.failCount = 1
            setStatus("trade_not_started")
            return
        end

        setStatus("running")
        local readyOk, readyErr = Remotes.SetReady:InvokeServer(true)
        if not readyOk then
            Remotes.CancelTrade:InvokeServer()
            indicator.failCount = 1
            setStatus(("ready_failed: %s"):format(tostring(readyErr or "")))
            return
        end

        local confirmed = waitAndConfirmTrade(replionId)
        if not confirmed then indicator.failCount = 1; return end

        local success = waitForTradeResult()
        if success then indicator.successCount = 1 else indicator.failCount = 1 end
    end)

    registerConn(autoAcceptConn)
end

function AutoTrade.StopAutoAccept()
    if autoAcceptConn then
        pcall(function() autoAcceptConn:Disconnect() end)
        autoAcceptConn = nil
    end

    indicator.mode   = "idle"
    indicator.status = "idle"
    pushUpdate()
end

-- ================================================================
-- PUBLIC: GETTER
-- ================================================================
function AutoTrade.GetStatus()    return indicator.status end
function AutoTrade.GetAttempted() return trade.attempted  end
function AutoTrade.IsEnabled()    return trade.enabled    end

return AutoTrade