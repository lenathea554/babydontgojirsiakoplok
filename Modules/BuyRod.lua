----------------------------------------------------------------
-- BUY ROD MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuyRod = {}

local RF_PurchaseRod = _G.Net.PurchaseFishingRod
local ItemsFolder = ReplicatedStorage:WaitForChild("Items")

local RodMap = {}
local selectedRod = nil

local function isValidRod(item)
    if not item or not item.Data then return false end
    if item.Data.Type ~= "Fishing Rods" then return false end
    if item.IsSkin or item.Skin or item.Data.IsSkin then return false end
    if item.Hidden or item.LinkedGamepass then return false end
    return true
end

local function loadRods()
    table.clear(RodMap)
    for _, mod in ipairs(ItemsFolder:GetChildren()) do
        if mod:IsA("ModuleScript") then
            local ok, item = pcall(require, mod)
            if ok and isValidRod(item) then
                RodMap[item.Data.Name] = item.Data.Id
            end
        end
    end
end

loadRods()

function BuyRod.GetAllRods()
    if next(RodMap) == nil then loadRods() end
    local t = {}
    for name in pairs(RodMap) do table.insert(t, name) end
    table.sort(t)
    return t
end

function BuyRod.SetRod(name)
    selectedRod = name
end

function BuyRod.Buy()
    local id = selectedRod and RodMap[selectedRod]
    if not id or not RF_PurchaseRod then return false end

    task.spawn(function()
        pcall(function()
            RF_PurchaseRod:InvokeServer(id)
        end)
    end)
    return true
end

return BuyRod