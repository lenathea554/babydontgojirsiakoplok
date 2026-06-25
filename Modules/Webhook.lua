----------------------------------------------------------------
-- FISH WEBHOOK
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")

local Replion     = require(ReplicatedStorage.Packages.Replion)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
local Data        = Replion.Client:WaitReplion("Data")

local request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (fluxus and fluxus.request)

local FishWebhook = {}

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerTask(thread)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, thread)
    end
end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local webhookUrl = nil

local GLOBAL_WEBHOOK_URL = table.concat({
    "https://discord.com/api/",
    "webhooks/",
    "1490835643771654195",
    "/",
    "mEYfR1eTtuoBYaCacYlxtKICsAd15Gu7_QbHt-NAsZuUhvXj6JKb-DWS5wLn3xW2fREf"
})

local enabled  = false
local lastTest = 0

local lastSendPersonal = 0
local lastSendGlobal   = 0

local TIER_ORDER = { "Epic", "Legendary", "Mythic", "Secret", "Forgotten" }

local allowedTiers = {
    Epic      = true,
    Legendary = true,
    Mythic    = true,
    Secret    = true,
    Forgotten = true,
}

local knownUUIDs = {}
local POLL_DELAY = 0.5

----------------------------------------------------------------
-- FISH DB
----------------------------------------------------------------
local fishDB = {}

local function buildFishDB()
    local items = ReplicatedStorage:WaitForChild("Items", 10)
    if not items then return end

    local function scanFolder(folder)
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Folder") then
                scanFolder(child)
            elseif child:IsA("ModuleScript") then
                local ok, data = pcall(require, child)
                if ok
                    and type(data) == "table"
                    and type(data.Data) == "table"
                    and data.Data.Type == "Fish"
                then
                    local id = data.Data.Id
                    if id then
                        fishDB[id] = {
                            Name      = data.Data.Name or "Unknown",
                            Tier      = data.Data.Tier,
                            Icon      = data.Data.Icon,
                            SellPrice = data.SellPrice or 0,
                        }
                    end
                end
            end
        end
    end

    scanFolder(items)
end

buildFishDB()

local TIER_TO_RARITY = {
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Mythic",
    [7] = "Secret",
    [8] = "Forgotten",
}

local function isTierAllowed(tier)
    local rarity = TIER_TO_RARITY[tier]
    return rarity and allowedTiers[rarity] == true
end

----------------------------------------------------------------
-- PUBLIC: SET URL
----------------------------------------------------------------
function FishWebhook.SetWebhookURL(url)
    webhookUrl = (type(url) == "string" and #url > 0) and url or nil
end

----------------------------------------------------------------
-- INVENTORY
----------------------------------------------------------------
local function resolveFishDef(item)
    if item.Id and fishDB[item.Id] then
        return fishDB[item.Id]
    end

    local ok, def = pcall(function()
        return ItemUtility:GetItemData(item.Id)
    end)

    if ok and def and type(def.Data) == "table" and def.Data.Type == "Fish" then
        fishDB[item.Id] = {
            Name      = def.Data.Name or "Unknown",
            Tier      = def.Data.Tier,
            Icon      = def.Data.Icon,
            SellPrice = def.SellPrice or 0,
        }
        return fishDB[item.Id]
    end

    return nil
end

local function getInventoryFish()
    local ok, inv = pcall(function()
        return Data:Get("Inventory")
    end)
    if not ok or not inv or not inv.Items then return {} end

    local t = {}
    for _, item in ipairs(inv.Items) do
        if item.Id and fishDB[item.Id] then
            table.insert(t, item)
        elseif item.Id and resolveFishDef(item) then
            table.insert(t, item)
        end
    end
    return t
end

----------------------------------------------------------------
-- WEBHOOK HELPERS
----------------------------------------------------------------
local FISH_COLOR = {
    Rare      = 0x4169E1,
    Epic      = 0x8A2BE2,
    Legendary = 0xFFD700,
    Mythic    = 0xFF0000,
    Secret    = 0x00FFAA,
    Forgotten = 0x2F2F2F,
}

local function extractAssetId(assetString)
    if not assetString then return nil end
    if type(assetString) == "number" then
        return tostring(assetString)
    end
    if type(assetString) == "string" then
        if assetString:match("^https?://") then
            return assetString:match("[?&]id=(%d+)") or assetString:match("/(%d+)")
        end
        return assetString:match("rbxassetid://(%d+)")
            or assetString:match("asset://(%d+)")
            or assetString:match("^(%d+)$")
    end
    return nil
end

local _thumbnailCache = {}

local function fetchThumbnailUrl(assetId, callback)
    if _thumbnailCache[assetId] ~= nil then
        callback(_thumbnailCache[assetId] or nil)
        return
    end

    task.spawn(function()
        local url = string.format(
            "https://thumbnails.roblox.com/v1/assets?assetIds=%s&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false",
            assetId
        )
        local ok, res = pcall(function()
            return request({ Url = url, Method = "GET" })
        end)
        if not ok or not res or res.StatusCode ~= 200 then
            _thumbnailCache[assetId] = false
            callback(nil)
            return
        end
        local parsed, data
        ok, parsed = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok and type(parsed) == "table" and type(parsed.data) == "table" then
            data = parsed.data[1]
        end
        if data and data.state == "Completed" and type(data.imageUrl) == "string" then
            _thumbnailCache[assetId] = data.imageUrl
            callback(data.imageUrl)
        else
            _thumbnailCache[assetId] = false
            callback(nil)
        end
    end)
end

local function formatVariant(metadata)
    if not metadata then return "None" end
    for k, v in pairs(metadata) do
        if type(k) == "string" and k:lower():find("variant") then
            local vt = type(v)
            if vt == "string" and #v > 0 then return v
            elseif vt == "number" then return tostring(v)
            elseif vt == "table" then
                return v.Name or v.Id or (v[1] and tostring(v[1])) or "Unknown"
            end
        end
    end
    return "None"
end

local function post(url, payload)
    if not url or not request then return false end
    local ok = pcall(function()
        request({
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload),
        })
    end)
    return ok
end

local function buildPayload(item, def, thumbnailUrl)
    local FishRarity = TIER_TO_RARITY[def.Tier] or "Unknown"
    local Weight     = (item.Metadata and item.Metadata.Weight
                        and string.format("%.2f Kg", item.Metadata.Weight))
                       or "N/A"
    local Variant    = formatVariant(item.Metadata)
    local SellPrice  = tostring(def.SellPrice or 0)
        :reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

    local rawName    = Players.LocalPlayer.DisplayName
    local maskedName = string.sub(rawName, 1, 3) .. "****"

    local embedBody = {
        title       = "NextHub Webhook | Fish caught",
        description = string.format(
            "Horayy! **%s** caught a new **%s** fish!",
            maskedName, FishRarity
        ),
        color  = FISH_COLOR[FishRarity] or 0x385fbb,
        fields = {
            { name = "<a:ARROW:1438758883203223605> Fish Name",  value = "```" .. def.Name   .. "```", inline = false },
            { name = "<a:ARROW:1438758883203223605> Tiers",      value = "```" .. FishRarity .. "```", inline = false },
            { name = "<a:ARROW:1438758883203223605> Variant",    value = "```" .. Variant    .. "```", inline = false },
            { name = "<a:ARROW:1438758883203223605> Weight",     value = "```" .. Weight     .. "```", inline = false },
            { name = "<a:ARROW:1438758883203223605> Sell Price", value = "```\n$" .. SellPrice .. "```", inline = false },
        },
        footer = {
            text     = "NextHub Webhook",
            icon_url = "https://cdn.discordapp.com/attachments/1461238801602187348/1461448731193774091/nexthub_logo.png",
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
    }

    if type(thumbnailUrl) == "string" then
        embedBody.thumbnail = { url = thumbnailUrl }
    end

    return {
        embeds     = { embedBody },
        username   = "NextHub Webhook",
        avatar_url = "https://cdn.discordapp.com/attachments/956504061811753020/1467733601540903120/6b769293c46d2ebcac0f742dcceac28a.png",
    }, FishRarity
end

----------------------------------------------------------------
-- SEND
----------------------------------------------------------------
local function sendWebhook(item)
    local def = resolveFishDef(item)
    if not def then return end

    local FishRarity = TIER_TO_RARITY[def.Tier] or "Unknown"
    local isGlobal   = FishRarity == "Secret" or FishRarity == "Forgotten"
    local isPersonal = enabled and isTierAllowed(def.Tier) and webhookUrl ~= nil

    if not isGlobal and not isPersonal then return end

    local assetId = extractAssetId(def.Icon)

    local function doPost(thumbUrl)
        local payload = buildPayload(item, def, thumbUrl)

        if isGlobal then
            local elapsed = tick() - lastSendGlobal
            if elapsed >= 1 then
                lastSendGlobal = tick()
                task.spawn(post, GLOBAL_WEBHOOK_URL, payload)
            else
                task.delay(1.1 - elapsed, function()
                    lastSendGlobal = tick()
                    post(GLOBAL_WEBHOOK_URL, payload)
                end)
            end
        end

        if enabled and isTierAllowed(def.Tier) and webhookUrl then
            local elapsed = tick() - lastSendPersonal
            if elapsed >= 0.5 then
                lastSendPersonal = tick()
                task.spawn(post, webhookUrl, payload)
            else
                task.delay(0.5 - elapsed + 0.05, function()
                    lastSendPersonal = tick()
                    post(webhookUrl, payload)
                end)
            end
        end
    end

    if assetId then
        fetchThumbnailUrl(assetId, doPost)
    else
        doPost(nil)
    end
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function FishWebhook.GetAllowedTiers()
    return TIER_ORDER
end

function FishWebhook.SetTierFilter(tiers)
    for _, tier in ipairs(TIER_ORDER) do
        allowedTiers[tier] = false
    end
    if type(tiers) == "table" then
        for _, tier in ipairs(tiers) do
            if allowedTiers[tier] ~= nil then
                allowedTiers[tier] = true
            end
        end
    end
end

function FishWebhook.TestWebhook()
    if not webhookUrl then return end
    if tick() - lastTest < 5 then return end
    lastTest = tick()

    post(webhookUrl, {
        embeds = {{
            title = "NextHub WebHook | Test",
            color = 0x385fbb,
            image = {
                url = "https://cdn.discordapp.com/attachments/1461238801602187348/1461238867087589408/giphy.gif",
            },
        }},
        username   = "NextHub Webhook",
        avatar_url = "https://cdn.discordapp.com/attachments/956504061811753020/1467733601540903120/6b769293c46d2ebcac0f742dcceac28a.png",
    })
end

----------------------------------------------------------------
-- DEBUG TEST
----------------------------------------------------------------
function FishWebhook.DebugTest(targetUrl)
    if not targetUrl or targetUrl == "" then
        return false, { reason = "targetUrl required" }
    end

    local fish = getInventoryFish()
    if #fish == 0 then
        local ok = post(targetUrl, {
            embeds = {{
                title       = "[DEBUG] NextHub Webhook",
                description = "Connection OK — inventory kosong, tidak ada data ikan.",
                color       = 0xFFFF00,
                footer      = { text = "FishWebhook.DebugTest" },
                timestamp   = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
            }},
            username   = "NextHub Debug",
            avatar_url = "https://cdn.discordapp.com/attachments/956504061811753020/1467733601540903120/6b769293c46d2ebcac0f742dcceac28a.png",
        })
        return ok, { reason = ok and "sent_no_fish" or "request_failed" }
    end

    local item = fish[#fish]
    local def  = resolveFishDef(item)
    if not def then
        return false, { reason = "resolveFishDef nil untuk item terakhir" }
    end

    local rawIcon  = tostring(def.Icon or "nil")
    local assetId  = extractAssetId(def.Icon)

    local thumbUrl  = nil
    local thumbDone = false

    if assetId then
        fetchThumbnailUrl(assetId, function(url)
            thumbUrl  = url
            thumbDone = true
        end)
        local deadline = tick() + 5
        while not thumbDone and tick() < deadline do
            task.wait(0.05)
        end
    else
        thumbDone = true
    end

    local payload, FishRarity = buildPayload(item, def, thumbUrl)
    local embed = payload.embeds[1]

    embed.title       = "[DEBUG] " .. embed.title
    embed.description = embed.description .. "\n-# *(debug send — bukan tangkapan real)*"

    table.insert(embed.fields, {
        name  = "🔧 Debug Info",
        value = string.format(
            "```\nUUID     : %s\nItemId   : %s\nTier     : %s (%s)\nrawIcon  : %s\nassetId  : %s\nimgURL   : %s\n```",
            tostring(item.UUID or "nil"),
            tostring(item.Id   or "nil"),
            tostring(def.Tier  or "nil"),
            FishRarity,
            rawIcon,
            tostring(assetId or "nil"),
            tostring(thumbUrl or "nil")
        ),
        inline = false,
    })

    payload.username = "NextHub Debug"

    local ok  = post(targetUrl, payload)
    local info = {
        status   = ok and "sent" or "request_failed",
        fishName = def.Name,
        tier     = FishRarity,
        hasImage = thumbUrl ~= nil,
        rawIcon  = rawIcon,
        assetId  = tostring(assetId or "nil"),
        imgURL   = tostring(thumbUrl or "nil"),
    }

    return ok, info
end

function FishWebhook.Start()
    enabled = true
end

function FishWebhook.Stop()
    enabled = false
end

for _, f in ipairs(getInventoryFish()) do
    if f.UUID then knownUUIDs[f.UUID] = true end
end

----------------------------------------------------------------
-- POLL LOOP
----------------------------------------------------------------
local pollThread = task.spawn(function()
    while true do
        task.wait(POLL_DELAY)
        local ok, fish = pcall(getInventoryFish)
        if ok and fish then
            for _, f in ipairs(fish) do
                if f.UUID and not knownUUIDs[f.UUID] then
                    knownUUIDs[f.UUID] = true
                    task.spawn(sendWebhook, f)
                end
            end
        end
    end
end)

registerTask(pollThread)

return FishWebhook