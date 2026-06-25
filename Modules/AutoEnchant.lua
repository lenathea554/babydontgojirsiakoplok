----------------------------------------------------------------
-- AUTO ENCHANT ROD MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local Replion       = require(ReplicatedStorage.Packages.Replion)
local ItemUtility   = require(ReplicatedStorage.Shared.ItemUtility)

local Data          = Replion.Client:WaitReplion("Data")
local EnchantsFolder = ReplicatedStorage:WaitForChild("Enchants")

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
local RE_ActivateEnchantingAltar = _G.Net.ActivateEnchantingAltar
local RE_EquipToolFromHotbar     = _G.Net.EquipToolFromHotbar
local RE_EquipItem               = _G.Net.EquipItem
local RE_UnequipItem             = _G.Net.UnequipItem

-- ================================================================
-- CONSTANTS
-- ================================================================
local LOCAL_ENCHANT_ID = 10
local RETRY_COUNT      = 4
local RETRY_WAIT       = 0.6
local COOLDOWN         = 5

local ALTAR_CFRAME = CFrame.new(
    3234.83667, -1302.85486, 1398.39087,
     0.464485794, 0, -0.885580599,
     0,           1,  0,
     0.885580599, 0,  0.464485794
)

-- ================================================================
-- ENCHANT MAP
-- ================================================================
local EnchantMap = {}

local function loadEnchantMap()
    table.clear(EnchantMap)
    for _, mod in ipairs(EnchantsFolder:GetChildren()) do
        if mod:IsA("ModuleScript") then
            local ok, data = pcall(require, mod)
            if ok and data and data.Data and data.Data.Id and data.Data.Name then
                EnchantMap[data.Data.Name] = data.Data.Id
            end
        end
    end
end
loadEnchantMap()

-- ================================================================
-- STATE
-- ================================================================
local AutoEnchantRod = {}

local state = {
    enabled    = false,
    target     = nil,
    loopThread = nil,
    enchanting = false,
    lastTick   = 0,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function getEquippedRod()
    local equipped = Data:Get("EquippedItems") or {}
    local rods     = Data:GetExpect({ "Inventory", "Fishing Rods" }) or {}
    for _, uuid in pairs(equipped) do
        for _, rod in pairs(rods) do
            if rod.UUID == uuid then return rod end
        end
    end
end

local function getRodEnchantIds(rod)
    if not rod or not rod.Metadata then return {} end
    local e = rod.Metadata.EnchantId
    return type(e) == "table" and e or (e and { e } or {})
end

local function findEnchantStone()
    local ok, inv = pcall(function() return Data:Get("Inventory") end)
    if not ok or not inv or not inv.Items then return nil end
    for _, item in pairs(inv.Items) do
        if item.Id then
            local def = ItemUtility:GetItemData(item.Id)
            if def and def.Data and def.Data.Type == "Enchant Stones" then
                return { UUID = item.UUID, Quantity = item.Quantity or 1, Id = item.Id }
            end
        end
    end
    return nil
end

local function getHotbarSlotFromUUID(targetUUID)
    local potentialKeys = { "Hotbar", "EquippedItems", "Slots", "BackpackSlots" }
    for _, key in ipairs(potentialKeys) do
        local hotbarData = Data:Get(key)
        if type(hotbarData) == "table" then
            for i, slotData in ipairs(hotbarData) do
                if type(slotData) == "table" and slotData.UUID == targetUUID then return i end
                if slotData == targetUUID then return i end
            end
        end
    end

    local gui = LP:FindFirstChild("PlayerGui")
    if gui then
        local backpack = gui:FindFirstChild("Backpack")
        local display  = backpack and backpack:FindFirstChild("Display")
        if display then
            for i, tile in ipairs(display:GetChildren()) do
                local inner = tile:FindFirstChild("Inner")
                local tags  = inner and inner:FindFirstChild("Tags")
                local nameLabel = tags and tags:FindFirstChild("ItemName")
                if nameLabel and nameLabel:IsA("TextLabel") then
                    if (nameLabel.Text or ""):lower():find("enchant stone") then
                        return i
                    end
                end
            end
        end
    end
    return nil
end

local function tpToAltar()
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local distance = (hrp.Position - ALTAR_CFRAME.Position).Magnitude
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.Parent   = hrp

    local tween = TweenService:Create(hrp, TweenInfo.new(distance / 30, Enum.EasingStyle.Linear), { CFrame = ALTAR_CFRAME })
    tween:Play()
    tween.Completed:Wait()

    tween:Destroy()
    if bv and bv.Parent then bv:Destroy() end
end

-- ================================================================
-- ENCHANT EXECUTION
-- ================================================================
local function runEnchantCycle()
    local targetId = EnchantMap[state.target]
    if not targetId then return end

    local rod = getEquippedRod()
    if not rod then
        tpToAltar()
        return
    end
    for _, id in ipairs(getRodEnchantIds(rod)) do
        if id == targetId then
            AutoEnchantRod.Stop()
            return
        end
    end

    local stone = findEnchantStone()
    if not stone then return end

    state.enchanting = true

    local prevEquipped = {}
    for _, u in ipairs(Data:Get("EquippedItems") or {}) do
        table.insert(prevEquipped, u)
    end

    local function restorePreviousEquipped()
        if #prevEquipped == 0 or not RE_EquipItem then return end
        for _, uuid in ipairs(prevEquipped) do
            pcall(function() RE_EquipItem:FireServer(uuid) end)
            task.wait(0.12)
        end
    end

    tpToAltar()
    task.wait(1.5)

    local slot    = nil
    local methods = {
        { a = stone.UUID,       b = "Enchant Stones"  },
        { a = stone.Id,         b = stone.UUID         },
        { a = LOCAL_ENCHANT_ID, b = "Enchant Stones"  },
    }

    for _, method in ipairs(methods) do
        if method.a then
            for _ = 1, RETRY_COUNT do
                pcall(function()
                    if RE_EquipItem then RE_EquipItem:FireServer(method.a, method.b) end
                end)
                task.wait(RETRY_WAIT)
                slot = getHotbarSlotFromUUID(stone.UUID)
                if slot then break end
            end
        end
        if slot then break end
    end

    if not slot then
        state.enchanting = false
        return
    end

    if RE_EquipToolFromHotbar then RE_EquipToolFromHotbar:FireServer(slot) end
    task.wait(1.5)

    if RE_ActivateEnchantingAltar then RE_ActivateEnchantingAltar:FireServer() end
    task.wait(3)

    if RE_UnequipItem then RE_UnequipItem:FireServer() end
    task.wait(0.12)
    pcall(restorePreviousEquipped)

    state.enchanting = false
    state.lastTick   = tick()
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoEnchantRod.GetAllEnchants()
    local t = {}
    for n in pairs(EnchantMap) do t[#t + 1] = n end
    table.sort(t)
    return t
end

function AutoEnchantRod.SetTargetEnchant(name)
    state.target = name
end

function AutoEnchantRod.TeleportToAltar()
    tpToAltar()
end

function AutoEnchantRod.Start()
    if state.loopThread then return end
    if not state.target or not EnchantMap[state.target] then return end

    state.enabled = true

    state.loopThread = task.spawn(function()
        while state.enabled do
            if not state.enchanting and tick() - state.lastTick >= COOLDOWN then
                task.spawn(runEnchantCycle)
            end
            task.wait(0.5)
        end
        state.loopThread = nil
    end)

    registerTask(state.loopThread)
end

function AutoEnchantRod.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.loopThread then
        pcall(task.cancel, state.loopThread)
        state.loopThread = nil
    end
end

function AutoEnchantRod.IsEnabled()
    return state.enabled
end

return AutoEnchantRod