----------------------------------------------------------------
-- AUTO EXCHANGE PEEP MODULE
----------------------------------------------------------------

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local Players            = game:GetService("Players")

local AutoExchangePeep = {}

----------------------------------------------------------------
-- DEPENDENCIES
----------------------------------------------------------------
local Replion = require(ReplicatedStorage.Packages.Replion).Client

local RF_ExchangeEggMachine = _G.Net.ExchangeEggMachine

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local PEEP_ITEM_NAME  = "Peep"
local PEEP_COST       = 30
local EXCHANGE_DELAY  = 0.3
local MAX_EGG_SLOTS   = 8
local MACHINE_TAG     = "EggMachine"
local MACHINE_PART    = "Part"
local USE_DISTANCE    = 24 
local SAFE_OFFSET     = USE_DISTANCE - 5

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local state = {
    enabled       = false,
    exchanging    = false,
}

local dataReplion  = nil
local peepItemId   = nil
local paragraphRef = nil

----------------------------------------------------------------
-- PARAGRAPH BUILDER
----------------------------------------------------------------
local function buildParagraphText(peepCount, exchangeable)
    local function font(text, color)
        return ("<font color='%s'>%s</font>"):format(color, text)
    end

    local peepColor = peepCount >= PEEP_COST
        and "rgb(100,255,150)"
        or  "rgb(255,220,80)"

    local eggColor = exchangeable > 0
        and "rgb(100,255,150)"
        or  "rgb(160,160,160)"

    return table.concat({
        ("Peep: %s/%s"):format(
            font(tostring(peepCount),    peepColor),
            font(tostring(PEEP_COST),    "rgb(200,200,200)")
        ),
        ("Exchange Egg: %s"):format(
            font(tostring(exchangeable), eggColor)
        ),
    }, "\n")
end

local function refreshParagraph(peepCount, exchangeable)
    if not paragraphRef then return end
    pcall(function()
        paragraphRef:SetText(buildParagraphText(peepCount, exchangeable))
    end)
end

----------------------------------------------------------------
-- MACHINE LOCATOR
----------------------------------------------------------------
local cachedMachinePart = nil

local function findMachinePart()
    if cachedMachinePart and cachedMachinePart.Parent then
        return cachedMachinePart
    end

    for _, tagged in pairs(CollectionService:GetTagged(MACHINE_TAG)) do
        local part = tagged:IsA("BasePart")
            and tagged
            or tagged:FindFirstChild(MACHINE_PART)

        if part and part:IsA("BasePart") then
            cachedMachinePart = part
            return part
        end
    end

    return nil
end

local function getMachineProxyCFrame(machinePart)
    return machinePart.CFrame * CFrame.new(0, 0, -SAFE_OFFSET)
end

----------------------------------------------------------------
-- INVENTORY HELPERS
----------------------------------------------------------------
local function getDataReplion()
    if dataReplion and not dataReplion.Destroyed then
        return dataReplion
    end
    dataReplion = Replion:WaitReplion("Data", 5)
    return dataReplion
end

local function resolvePeepId()
    if peepItemId then return peepItemId end
    local ItemUtil = require(ReplicatedStorage.Shared.ItemUtility)
    local data     = ItemUtil.GetItemDataFromItemType("Items", PEEP_ITEM_NAME)
    if data and data.Data then
        peepItemId = data.Data.Id
    end
    return peepItemId
end

local function getPeepCount()
    local rep = getDataReplion()
    if not rep then return 0 end
    local items = rep:Get({ "Inventory", "Items" }) or {}
    local id    = resolvePeepId()
    if not id then return 0 end
    for _, item in pairs(items) do
        if item.Id == id then
            return item.Quantity or 1
        end
    end
    return 0
end

local function getAvailableEggSlots()
    local player     = Players.LocalPlayer
    local incubating = player:GetAttribute("IncubatingEggCount")
    if typeof(incubating) == "number" then
        return math.max(0, MAX_EGG_SLOTS - math.floor(incubating))
    end
    return MAX_EGG_SLOTS
end

local function calcExchangeable()
    local peepCount  = getPeepCount()
    local availSlots = getAvailableEggSlots()
    local fromPeep   = math.floor(peepCount / PEEP_COST)
    return peepCount, math.min(fromPeep, availSlots)
end

local function getHRP()
    local char = Players.LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportHRP(cf)
    local hrp = getHRP()
    if not hrp then return end
    hrp.CFrame = cf
end

----------------------------------------------------------------
-- EXCHANGE LOGIC
----------------------------------------------------------------
local function doExchange()
    if state.exchanging then return end
    if not state.enabled then return end

    local peepCount, exchangeable = calcExchangeable()
    refreshParagraph(peepCount, exchangeable)

    if exchangeable <= 0 then return end

    local machinePart = findMachinePart()
    if not machinePart then
        state.exchanging = true
        for i = 1, exchangeable do
            if not state.enabled then break end
            pcall(function() RF_ExchangeEggMachine:InvokeServer() end)
            if i < exchangeable then task.wait(EXCHANGE_DELAY) end
        end
        state.exchanging = false
        local newPeep, newEx = calcExchangeable()
        refreshParagraph(newPeep, newEx)
        return
    end

    state.exchanging = true

    local hrp         = getHRP()
    local originalCF  = hrp and hrp.CFrame

    local proxyCF = getMachineProxyCFrame(machinePart)
    teleportHRP(proxyCF)

    task.wait()

    for i = 1, exchangeable do
        if not state.enabled then break end
        pcall(function() RF_ExchangeEggMachine:InvokeServer() end)
        if i < exchangeable then task.wait(EXCHANGE_DELAY) end
    end

    if originalCF then
        teleportHRP(originalCF)
    end

    local newPeep, newEx = calcExchangeable()
    refreshParagraph(newPeep, newEx)

    state.exchanging = false
end

----------------------------------------------------------------
-- INVENTORY CHANGE LISTENER
----------------------------------------------------------------
local function onInventoryChanged()
    local peepCount, exchangeable = calcExchangeable()
    refreshParagraph(peepCount, exchangeable)

    if state.enabled then
        task.spawn(doExchange)
    end
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------

function AutoExchangePeep.Init(paragraphWidget)
    paragraphRef = paragraphWidget

    local peepCount, exchangeable = calcExchangeable()
    refreshParagraph(peepCount, exchangeable)

    local rep = getDataReplion()
    if rep then
        local conn = rep:OnChange({ "Inventory", "Items" }, function()
            onInventoryChanged()
        end)
        if _G._NEXTHUB and _G._NEXTHUB.conns then
            table.insert(_G._NEXTHUB.conns, conn)
        end
        state.inventoryConn = conn
    end
end

function AutoExchangePeep.Start()
    if state.enabled then return end
    state.enabled = true
    task.spawn(doExchange)
end

function AutoExchangePeep.Stop()
    state.enabled    = false
    state.exchanging = false
end

function AutoExchangePeep.IsEnabled()
    return state.enabled
end

function AutoExchangePeep.GetStatus()
    return calcExchangeable()
end

return AutoExchangePeep