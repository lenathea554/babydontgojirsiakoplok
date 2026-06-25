----------------------------------------------------------------
-- BUY BAIT MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuyBait = {}

local RF_PurchaseBait = _G.Net.PurchaseBait
local BaitsFolder = ReplicatedStorage:WaitForChild("Baits")

local BaitMap = {}
local selectedBait = nil

local function isValidBait(item)
    if not item or not item.Data then return false end
    if item.Data.Type ~= "Baits" then return false end
    if item.IsSkin or item.Skin or item.Data.IsSkin then return false end
    if item.Hidden or item.LinkedGamepass then return false end
    return true
end

local function loadBaits()
    table.clear(BaitMap)
    for _, mod in ipairs(BaitsFolder:GetChildren()) do
        if mod:IsA("ModuleScript") then
            local ok, item = pcall(require, mod)
            if ok and isValidBait(item) then
                BaitMap[item.Data.Name] = item.Data.Id
            end
        end
    end
end

loadBaits()

function BuyBait.GetAllBaits()
    if next(BaitMap) == nil then loadBaits() end
    local t = {}
    for name in pairs(BaitMap) do table.insert(t, name) end
    table.sort(t)
    return t
end

function BuyBait.SetBait(name)
    selectedBait = name
end

function BuyBait.Buy()
    local id = selectedBait and BaitMap[selectedBait]
    if not id or not RF_PurchaseBait then return false end

    task.spawn(function()
        pcall(function()
            RF_PurchaseBait:InvokeServer(id)
        end)
    end)
    return true
end

return BuyBait