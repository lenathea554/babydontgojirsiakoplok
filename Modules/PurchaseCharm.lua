----------------------------------------------------------------
-- PURCHASE CHARM MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemUtility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemUtility", 10))

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
local RF_PurchaseCharm = _G.Net.PurchaseCharm

-- ================================================================
-- STATE
-- ================================================================
local PurchaseCharm = {}

local _thread   = nil
local _running  = false

local _selectedCharms = {}
local _amount         = 1

local _charmNameToId = nil

-- ================================================================
-- INTERNAL
-- ================================================================
local function isValidCharmEntry(charmData)
    return type(charmData) == "table"
        and type(charmData.Data) == "table"
        and type(charmData.Data.Name) == "string"
        and (type(charmData.Data.Id) == "string" or type(charmData.Data.Id) == "number")
end

local function fetchCharms()
    for _ = 1, 20 do
        local ok, charms = pcall(function()
            return ItemUtility:GetCharms()
        end)

        if ok and type(charms) == "table" and #charms > 0 then
            return charms
        end

        task.wait(0.5)
    end

    return nil
end

local function buildCharmNameMap()
    if _charmNameToId then return end

    local charms = fetchCharms()
    if not charms then return end

    _charmNameToId = {}
    for _, charmData in ipairs(charms) do
        if isValidCharmEntry(charmData) then
            _charmNameToId[charmData.Data.Name] = charmData.Data.Id
        end
    end
end

-- ================================================================
-- INTERNAL LOGIC
-- ================================================================
local function doPurchaseOne(charmId)
    local ok, err = pcall(function()
        RF_PurchaseCharm:InvokeServer(charmId)
    end)
    return ok
end

local function runPurchase()
    if _running then return end
    if #_selectedCharms == 0 then return end
    if _amount <= 0 then return end

    _running = true

    _thread = task.spawn(function()
        for _, charmId in ipairs(_selectedCharms) do
            for i = 1, _amount do
                if not _running then break end
                doPurchaseOne(charmId)
                task.wait(0.4)
            end
            if not _running then break end
            task.wait(0.2)
        end
        _running = false
        _thread  = nil
    end)

    registerTask(_thread)
end

-- ================================================================
-- UI HELPERS
-- ================================================================
function PurchaseCharm.GetAllCharmNames()
    local result = {}

    local charms = fetchCharms()
    if charms then
        for _, charmData in ipairs(charms) do
            if isValidCharmEntry(charmData) then
                result[#result + 1] = charmData.Data.Name
            end
        end
    end

    table.sort(result)
    return result
end

-- ================================================================
-- CONFIG API
-- ================================================================
function PurchaseCharm.SetSelectedCharms(nameList)
    buildCharmNameMap()
    _selectedCharms = {}
    for _, name in ipairs(nameList or {}) do
        local id = _charmNameToId and _charmNameToId[name]
        if id then
            _selectedCharms[#_selectedCharms + 1] = id
        end
    end
end

function PurchaseCharm.SetAmount(n)
    n = tonumber(n)
    if not n or n < 1 then return end
    _amount = math.floor(n)
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function PurchaseCharm.Buy()
    if _running then return false end
    if #_selectedCharms == 0 then return false end
    task.spawn(runPurchase)
    return true
end

function PurchaseCharm.Stop()
    if not _running then return end
    _running = false
    if _thread then
        pcall(task.cancel, _thread)
        _thread = nil
    end
end

function PurchaseCharm.IsRunning()
    return _running
end

function PurchaseCharm.Start() return PurchaseCharm.Buy()  end

return PurchaseCharm