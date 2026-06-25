----------------------------------------------------------------
-- AUTO POTION MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Replion     = require(ReplicatedStorage.Packages.Replion).Client
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local LP = Players.LocalPlayer

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
local RF_ConsumePotion = _G.Net.ConsumePotion

-- ================================================================
-- STATE
-- ================================================================
local AutoPotion = {}

local state = {
    enabled       = false,
    selectedNames = {},
    amount        = 1,
    dataRep       = nil,
    OnUpdate      = nil,
    loopTask      = nil,
    removeConn    = nil,
    statusTask    = nil,
}

-- ================================================================
-- STATUS BUILDER
-- ================================================================
local function font(text, color)
    return ("<font color='%s'>%s</font>"):format(color, text)
end

local function buildStatusText()
    if not state.dataRep then
        return "Status: "..font("Waiting...", "rgb(255,200,0)")
    end

    local ok, equipped = pcall(function()
        return state.dataRep:GetExpect("EquippedPotions") or {}
    end)
    if not ok then equipped = {} end

    local activeNames = {}
    for _, entry in ipairs(equipped) do
        local potionData = ItemUtility:GetPotionData(entry.Id)
        if potionData and potionData.Data and potionData.Data.Name then
            table.insert(activeNames, potionData.Data.Name)
        end
    end

    if #activeNames == 0 then
        return "Active Potions: "..font("None", "rgb(180,180,180)")
    end

    local lines = {}
    for _, name in ipairs(activeNames) do
        table.insert(lines, font("• "..name, "rgb(0,255,150)"))
    end
    return "Active Potions:\n"..table.concat(lines, "\n")
end

local function pushUpdate()
    if not state.OnUpdate then return end
    pcall(state.OnUpdate, buildStatusText())
end

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function collectPotionGroups()
    if not state.dataRep then return {} end

    local ok, inv = pcall(function()
        return state.dataRep:GetExpect("Inventory") or {}
    end)
    if not ok or type(inv) ~= "table" then return {} end

    local bucket = inv["Potions"]
    if type(bucket) ~= "table" then return {} end

    local groups = {}

    for _, item in ipairs(bucket) do
        if type(item) == "table" and item.Id ~= nil and item.UUID ~= nil then
            local ok2, potionData = pcall(function()
                return ItemUtility:GetPotionData(item.Id)
            end)
            if ok2 and type(potionData) == "table"
                and type(potionData.Data) == "table"
                and type(potionData.Data.Name) == "string" then

                local name = potionData.Data.Name
                local qty  = tonumber(item.Quantity) or 1

                if not groups[name] then
                    groups[name] = { Id = item.Id, Name = name, Stacks = {} }
                end

                table.insert(groups[name].Stacks, { UUID = item.UUID, Quantity = qty })
            end
        end
    end

    return groups
end

local function isPotionActive(potionId)
    if not state.dataRep then return false end
    local ok, equipped = pcall(function()
        return state.dataRep:GetExpect("EquippedPotions") or {}
    end)
    if not ok then return false end
    for _, entry in ipairs(equipped) do
        if tonumber(entry.Id) == tonumber(potionId) then return true end
    end
    return false
end

local function consumePotionGroup(group, amount)
    if not RF_ConsumePotion then return 0 end
    if amount <= 0 then return 0 end

    local remaining = amount
    local consumed  = 0

    for _, stack in ipairs(group.Stacks) do
        if remaining <= 0 then break end

        local takeFromStack = math.min(stack.Quantity, remaining)
        if takeFromStack <= 0 then continue end

        local ok, result = pcall(function()
            return RF_ConsumePotion:InvokeServer(stack.UUID, takeFromStack)
        end)

        if ok and result ~= false then
            consumed  = consumed + takeFromStack
            remaining = remaining - takeFromStack
        end

        task.wait(0.3)
    end

    return consumed
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function stopLoop()
    if state.loopTask then
        pcall(task.cancel, state.loopTask)
        state.loopTask = nil
    end
end

local function runLoop()
    stopLoop()
    state.loopTask = task.spawn(function()
        while state.enabled do
            local groups = collectPotionGroups()

            for name in pairs(state.selectedNames) do
                if not state.enabled then break end

                local group = groups[name]
                if group and not isPotionActive(group.Id) then
                    consumePotionGroup(group, state.amount)
                    task.wait(0.5)
                end
            end

            task.wait(10)
        end
    end)
    registerTask(state.loopTask)
end

-- ================================================================
-- STATUS WATCHER
-- ================================================================
local function stopStatusWatcher()
    if state.statusTask then
        pcall(task.cancel, state.statusTask)
        state.statusTask = nil
    end
end

local function startStatusWatcher()
    stopStatusWatcher()
    state.statusTask = task.spawn(function()
        while state.enabled do
            task.wait(3)
            if state.enabled then pushUpdate() end
        end
    end)
    registerTask(state.statusTask)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoPotion.GetPotionList()
    local dataRep = state.dataRep or Replion:WaitReplion("Data", 5)
    if not dataRep then return {} end

    state.dataRep = state.dataRep or dataRep

    local groups = collectPotionGroups()

    local list = {}
    for name in pairs(groups) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

function AutoPotion.SetSelectedPotions(nameList)
    table.clear(state.selectedNames)
    for _, name in ipairs(nameList or {}) do
        state.selectedNames[name] = true
    end
end

function AutoPotion.SetAmount(n)
    n = tonumber(n)
    if not n or n < 1 then return end
    state.amount = math.floor(n)
end

function AutoPotion.GetAmount()
    return state.amount
end

function AutoPotion.SetOnUpdate(fn)
    state.OnUpdate = fn
    if state.enabled then
        startStatusWatcher()
    end
    task.spawn(function()
        task.wait(0.1)
        pushUpdate()
    end)
end

function AutoPotion.Start()
    if state.enabled then return end
    if not next(state.selectedNames) then return end

    state.dataRep = Replion:WaitReplion("Data")
    state.enabled = true

    state.removeConn = state.dataRep:OnArrayRemove("EquippedPotions", function(_, removedEntry)
        if not state.enabled then return end
        local potionData = ItemUtility:GetPotionData(removedEntry.Id)
        if not potionData or not potionData.Data then return end
        local name = potionData.Data.Name
        if not state.selectedNames[name] then return end

        task.spawn(function()
            task.wait(1)
            if not state.enabled then return end

            local groups = collectPotionGroups()
            local group  = groups[name]
            if group then
                consumePotionGroup(group, state.amount)
            end

            pushUpdate()
        end)
    end)
    registerConn(state.removeConn)

    runLoop()
    startStatusWatcher()
    pushUpdate()
end

function AutoPotion.Stop()
    if not state.enabled then return end
    state.enabled = false

    stopLoop()
    stopStatusWatcher()

    if state.removeConn then
        pcall(function() state.removeConn:Disconnect() end)
        state.removeConn = nil
    end

    pushUpdate()
end

function AutoPotion.IsEnabled()
    return state.enabled
end

return AutoPotion