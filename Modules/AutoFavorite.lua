----------------------------------------------------------------
-- AUTO FAVORITE MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemUtility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemUtility", 10))
local TierUtility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TierUtility", 10))

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerTask(thread)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, thread)
    end
end

-- ================================================================
-- REMOTE
-- ================================================================
local RE_FavoriteItem = _G.Net.FavoriteItem

-- ================================================================
-- CONSTANTS
-- ================================================================
local TierMap = { "COMMON","UNCOMMON","RARE","EPIC","LEGENDARY","MYTHIC","SECRET","FORGOTTEN" }

-- ================================================================
-- STATE
-- ================================================================
local AutoFavorite = {}

local enabled = false
local _thread = nil

local raritySet   = {}
local nameSet     = {}
local mutationSet = {}

local _playerDataRep = nil
local itemInfoCache  = {}
local favoritedCache = {}

-- ================================================================
-- REPLION
-- ================================================================
local function getPlayerDataReplion()
    if _playerDataRep then return _playerDataRep end
    local ok, pkg = pcall(function()
        return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Replion", 10)
    end)
    if not ok or not pkg then return nil end
    _playerDataRep = require(pkg).Client:WaitReplion("Data", 5)
    return _playerDataRep
end

-- ================================================================
-- ITEM INFO
-- ================================================================
local function getItemInfo(item)
    local id = item.Id
    if id and itemInfoCache[id] then
        local c = itemInfoCache[id]
        return c[1], c[2]
    end

    local name   = item.Identifier or "Unknown"
    local rarity = "COMMON"
    local itemData

    if ItemUtility and id then
        pcall(function() itemData = ItemUtility:GetItemData(id) end)
    end

    if itemData and itemData.Data and itemData.Data.Name then
        name = itemData.Data.Name
    end

    if item.Metadata and item.Metadata.Rarity then
        rarity = tostring(item.Metadata.Rarity):upper()
    elseif itemData and itemData.Probability and TierUtility then
        local tierObj
        pcall(function()
            tierObj = TierUtility:GetTierFromRarity(itemData.Probability.Chance)
        end)
        if tierObj and tierObj.Name then
            rarity = tostring(tierObj.Name):upper()
        end
    end

    if id then itemInfoCache[id] = { name, rarity } end
    return name, rarity
end

local function getMutation(item)
    if item.Metadata then
        if item.Metadata.Shiny == true then return "Shiny" end
        if item.Metadata.VariantId ~= nil then
            return tostring(item.Metadata.VariantId)
        end
    end
    return ""
end

-- ================================================================
-- FILTER REBUILD
-- ================================================================
local function rebuildSets(rarities, names, mutations)
    table.clear(raritySet)
    table.clear(nameSet)
    table.clear(mutationSet)

    for _, r in ipairs(rarities  or {}) do raritySet[tostring(r):upper()] = true end
    for _, n in ipairs(names     or {}) do nameSet[n]                      = true end
    for _, m in ipairs(mutations or {}) do mutationSet[m]                  = true end
end

-- ================================================================
-- INVENTORY SCAN
-- ================================================================
local function getItemsToFavorite()
    if not next(raritySet) and not next(nameSet) and not next(mutationSet) then
        return {}
    end

    local rep = getPlayerDataReplion()
    if not rep then return {} end

    local ok, inv = pcall(function() return rep:Get("Inventory") end)
    if not ok or not inv or not inv.Items then return {} end

    local result = {}

    for _, item in ipairs(inv.Items) do
        local uuid = item.UUID
        if type(uuid) ~= "string" then continue end

        if item.IsFavorite or item.Favorited or favoritedCache[uuid] then
            favoritedCache[uuid] = true
            continue
        end

        local name, rarity = getItemInfo(item)
        local mutation      = getMutation(item)

        if raritySet[rarity] or nameSet[name] or mutationSet[mutation] then
            result[#result + 1] = uuid
        end
    end

    return result
end

local function favoriteItem(uuid)
    pcall(function()
        if RE_FavoriteItem then RE_FavoriteItem:FireServer(uuid) end
    end)
    favoritedCache[uuid] = true
end

-- ================================================================
-- LOOP
-- ================================================================
local function runLoop()
    if _thread then pcall(task.cancel, _thread) end

    _thread = task.spawn(function()
        local idleCount = 0

        while enabled do
            local list = getItemsToFavorite()

            if #list > 0 then
                idleCount = 0
                for _, uuid in ipairs(list) do
                    if not enabled then break end
                    favoriteItem(uuid)
                    task.wait(0.35)
                end
                task.wait(1)
            else
                idleCount = idleCount + 1
                local waitTime = math.min(2 + (idleCount - 1) * 3, 15)
                task.wait(waitTime)
            end
        end
    end)

    registerTask(_thread)
end

-- ================================================================
-- CONFIG API
-- ================================================================
local _rarities, _names, _mutations = {}, {}, {}

function AutoFavorite.SetSelectedRarities(v)
    _rarities = v or {}
    rebuildSets(_rarities, _names, _mutations)
end

function AutoFavorite.SetSelectedItemNames(v)
    _names = v or {}
    rebuildSets(_rarities, _names, _mutations)
end

function AutoFavorite.SetSelectedMutations(v)
    _mutations = v or {}
    rebuildSets(_rarities, _names, _mutations)
end

-- ================================================================
-- UI HELPERS
-- ================================================================
function AutoFavorite.GetAllTierNames()
    return TierMap
end

function AutoFavorite.GetAllVariantNames()
    local result   = {}
    local variants = ReplicatedStorage:FindFirstChild("Variants")
    if not variants then return result end
    for _, v in ipairs(variants:GetChildren()) do
        if v:IsA("ModuleScript") and type(v.Name) == "string" then
            result[#result + 1] = v.Name
        end
    end
    table.sort(result)
    return result
end

function AutoFavorite.GetAllFishNames()
    local result      = {}
    local itemsFolder = ReplicatedStorage:FindFirstChild("Items")
    if not itemsFolder then return result end

    local function scanFolder(folder)
        for _, v in ipairs(folder:GetChildren()) do
            if v:IsA("Folder") then
                scanFolder(v)
            elseif v:IsA("ModuleScript") then
                local ok, data = pcall(require, v)
                if ok and type(data) == "table"
                    and type(data.Data) == "table"
                    and data.Data.Type == "Fish"
                    and type(data.Data.Name) == "string"
                then
                    result[#result + 1] = data.Data.Name
                end
            end
        end
    end

    scanFolder(itemsFolder)
    table.sort(result)
    return result
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function AutoFavorite.Enable()
    if enabled then return true end
    if not getPlayerDataReplion() or not ItemUtility or not TierUtility then
        return false
    end
    enabled = true
    runLoop()
    return true
end

function AutoFavorite.Disable()
    if not enabled then return end
    enabled = false
    if _thread then
        pcall(task.cancel, _thread)
        _thread = nil
    end
end

function AutoFavorite.Start() return AutoFavorite.Enable()  end
function AutoFavorite.Stop()         AutoFavorite.Disable() end

return AutoFavorite