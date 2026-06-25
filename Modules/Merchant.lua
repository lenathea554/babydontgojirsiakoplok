----------------------------------------------------------------
-- MERCHANT MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Replion           = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Replion")).Client

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

----------------------------------------------------------------
-- REMOTE & DATA
----------------------------------------------------------------
local RF_PurchaseMarketItem = _G.Net.PurchaseMarketItem
local MarketItemData        = require(ReplicatedStorage.Shared.MarketItemData)
local MarketItemById        = {}

for _, data in ipairs(MarketItemData) do
    if data.Id then MarketItemById[data.Id] = data end
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local Merchant = {
    Enabled        = false,
    LastMessage    = "<font color='rgb(200,200,200)'>Waiting...</font>",
    OnUpdate       = nil,
    _countdownTask = nil,
    _stockConn     = nil,
}

local merchantRep  = nil
local cachedStock  = {}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function font(text, color)
    return ("<font color='%s'>%s</font>"):format(color, text)
end

local function formatCountdown(seconds)
    local s = math.max(math.floor(seconds), 0)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sc = s % 60
    return ("%02d:%02d:%02d"):format(h, m, sc)
end

local function parseStock(items)
    table.clear(cachedStock)
    if type(items) ~= "table" then return cachedStock end

    for _, itemId in ipairs(items) do
        local data = MarketItemById[itemId]
        if data and data.Price then
            table.insert(cachedStock, {
                Id       = itemId,
                Name     = data.Identifier or "Unknown",
                Price    = data.Price,
                Currency = data.Currency or "Coins",
            })
        end
    end

    return cachedStock
end

-- ================================================================
-- STATUS BUILDERS
-- ================================================================
local function buildStatusText()
    local stock   = cachedStock
    local seconds = Merchant.GetNextRefreshSeconds()
    local lines   = {}

    lines[#lines + 1] = "Stock:"

    if #stock == 0 then
        lines[#lines + 1] = font("  (empty)", "rgb(160,160,160)")
    else
        for _, item in ipairs(stock) do
            lines[#lines + 1] = ("- %s"):format(font(item.Name, "rgb(100,200,255)"))
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Refresh in: " .. font(formatCountdown(seconds), "rgb(255,220,80)")

    return table.concat(lines, "\n")
end

local function buildStockOptions()
    local options = {}

    for _, item in ipairs(cachedStock) do
        options[#options + 1] = ("%s - %s %s"):format(
            item.Name,
            tostring(item.Price),
            item.Currency
        )
    end

    if #options == 0 then
        options[1] = "(no stock)"
    end

    return options
end

-- ================================================================
-- STATUS PUSH
-- ================================================================
local function pushUpdate()
    if not Merchant.OnUpdate then return end
    pcall(Merchant.OnUpdate, buildStatusText(), buildStockOptions())
end

-- ================================================================
-- COUNTDOWN WATCHER
-- ================================================================
local function startCountdownLoop()
    if Merchant._countdownTask then
        pcall(task.cancel, Merchant._countdownTask)
    end

    Merchant._countdownTask = task.spawn(function()
        while Merchant.Enabled do
            task.wait(1)
            pushUpdate()
        end
    end)

    registerTask(Merchant._countdownTask)
end

local function stopCountdownLoop()
    if Merchant._countdownTask then
        pcall(task.cancel, Merchant._countdownTask)
        Merchant._countdownTask = nil
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function Merchant.GetStock()
    return cachedStock
end

function Merchant.GetNextRefreshSeconds()
    local now     = Workspace:GetServerTimeNow()
    local day     = 86400
    local nextReset = (math.floor(now / day) + 1) * day
    return math.max(nextReset - now, 0)
end

function Merchant.GetStatusText()
    return buildStatusText()
end

function Merchant.GetStockOptions()
    return buildStockOptions()
end

function Merchant.BuyByLabel(label)
    if not label or label == "" or label == "(no stock)" then return false end

    local itemName = label:match("^(.-)%s*%-%s*%d") or label:match("^(.-)%s*%-") or label
    itemName = itemName:match("^%s*(.-)%s*$") -- trim

    return Merchant.BuyByName(itemName)
end

function Merchant.BuyByName(name)
    if not RF_PurchaseMarketItem then return false end
    for _, item in ipairs(cachedStock) do
        if item.Name == name then
            task.spawn(function()
                pcall(function() RF_PurchaseMarketItem:InvokeServer(item.Id) end)
            end)
            return true
        end
    end
    return false
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function Merchant.SetOnUpdate(fn)
    Merchant.OnUpdate = fn
    task.spawn(function()
        task.wait(0.1)
        pushUpdate()
    end)
end

function Merchant.Start()
    if Merchant.Enabled then return end
    Merchant.Enabled = true

    merchantRep = Replion:WaitReplion("Merchant", 5)
    if not merchantRep then
        Merchant.Enabled = false
        return
    end

    parseStock(merchantRep.Data.Items)
    pushUpdate()

    Merchant._stockConn = merchantRep:OnChange("Items", function(newItems)
        if not Merchant.Enabled then return end
        parseStock(newItems)
        pushUpdate()
    end)

    registerConn(Merchant._stockConn)
    startCountdownLoop()
end

function Merchant.Stop()
    if not Merchant.Enabled then return end
    Merchant.Enabled = false

    stopCountdownLoop()

    if Merchant._stockConn then
        Merchant._stockConn:Disconnect()
        Merchant._stockConn = nil
    end
end

return Merchant