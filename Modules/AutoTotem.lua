----------------------------------------------------------------
-- AUTO TOTEM MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Replion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Replion")).Client

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerTask(thread)
    if _G._NEXTHUB and _G._NEXTHUB.tasks then
        table.insert(_G._NEXTHUB.tasks, thread)
    end
end

-- ================================================================
-- REMOTES
-- ================================================================
local RE_SpawnTotem          = _G.Net.SpawnTotem
local RE_EquipToolFromHotbar = _G.Net.EquipToolFromHotbar

-- ================================================================
-- DATA
-- ================================================================
local TOTEMS         = {}
local TOTEM_DURATION = 3600

local function loadTotemsData()
    local totemsFolder = ReplicatedStorage:WaitForChild("Totems", 10)
    if not totemsFolder then
        warn("[AutoTotem] Totems folder not found")
        return
    end
    table.clear(TOTEMS)
    for _, totemObj in ipairs(totemsFolder:GetChildren()) do
        if totemObj:IsA("ModuleScript") then
            local ok, TotemData = pcall(require, totemObj)
            if ok and TotemData and TotemData.Data then
                TOTEMS[TotemData.Data.Name] = {
                    Id       = tonumber(TotemData.Data.Id),
                    Duration = TOTEM_DURATION,
                }
            end
        end
    end
    if not next(TOTEMS) then
        TOTEMS = {
            ["Luck Totem"]     = { Id = 1, Duration = TOTEM_DURATION },
            ["Mutation Totem"] = { Id = 2, Duration = TOTEM_DURATION },
            ["Shiny Totem"]    = { Id = 3, Duration = TOTEM_DURATION },
        }
    end
end

task.spawn(loadTotemsData)

-- ================================================================
-- STATE
-- ================================================================
local AutoTotem = {
    Enabled       = false,
    OnUpdate      = nil,
    _thread       = nil,
    _statusThread = nil,
}

local selectedTotem = nil
local currentExpiry = 0
local playerDataRep = nil

-- ================================================================
-- REPLION HELPER
-- ================================================================
local function getPlayerData()
    if playerDataRep then return playerDataRep end
    playerDataRep = Replion:WaitReplion("Data", 5)
    return playerDataRep
end

-- ================================================================
-- STATUS BUILDER
-- ================================================================
local function font(text, color)
    return ("<font color='%s'>%s</font>"):format(color, text)
end

local function buildStatusText()
    local name    = selectedTotem or "--"
    local timeLeft = math.max(currentExpiry - os.time(), 0)
    local minutes  = math.floor(timeLeft / 60)
    local seconds  = timeLeft % 60
    local timeStr  = ("%02d:%02d"):format(minutes, seconds)

    local totemColor = AutoTotem.Enabled and "rgb(0,255,0)" or "rgb(255,255,255)"
    local timeColor  = minutes <= 5  and "rgb(255,0,0)"
                    or minutes <= 15 and "rgb(255,200,0)"
                    or "rgb(0,255,0)"

    return ("Current Totem: %s\nTime Left: %s"):format(
        font(name,    totemColor),
        font(timeStr, timeColor)
    )
end

-- ================================================================
-- STATUS PUSH
-- ================================================================
local _lastPush = 0
local function pushUpdate()
    if not AutoTotem.OnUpdate then return end
    local now = os.clock()
    if now - _lastPush < 0.5 then return end
    _lastPush = now
    pcall(AutoTotem.OnUpdate, buildStatusText())
end

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function getTotemUUID(name)
    local rep = getPlayerData()
    if not rep then return nil end
    local ok, data = pcall(function() return rep:GetExpect("Inventory") end)
    if not ok or not data or not data.Totems then return nil end

    local targetId = TOTEMS[name] and TOTEMS[name].Id
    if not targetId then return nil end

    for _, item in ipairs(data.Totems) do
        if tonumber(item.Id) == targetId and (item.Count or 1) >= 1 then
            return item.UUID
        end
    end
    return nil
end

local function reequipRod()
    task.spawn(function()
        task.wait(0.5)
        if RE_EquipToolFromHotbar then
            pcall(RE_EquipToolFromHotbar.FireServer, RE_EquipToolFromHotbar, 1)
        end
    end)
end

local function placeTotem()
    if not selectedTotem or not TOTEMS[selectedTotem] then return false end
    local uuid = getTotemUUID(selectedTotem)
    if not uuid then return false end

    local ok = pcall(function()
        if RE_SpawnTotem then RE_SpawnTotem:FireServer(uuid) end
    end)

    if ok then
        currentExpiry = os.time() + TOTEMS[selectedTotem].Duration
        reequipRod()
        return true
    end

    warn("[AutoTotem] Failed to place totem")
    return false
end

-- ================================================================
-- BACKGROUND STATUS WATCHER
-- ================================================================
local function startStatusWatcher()
    if AutoTotem._statusThread then
        pcall(task.cancel, AutoTotem._statusThread)
    end
    AutoTotem._statusThread = task.spawn(function()
        while AutoTotem.Enabled do
            task.wait(1)
            pushUpdate()
        end
        AutoTotem._statusThread = nil
    end)
    registerTask(AutoTotem._statusThread)
end

local function stopStatusWatcher()
    if AutoTotem._statusThread then
        pcall(task.cancel, AutoTotem._statusThread)
        AutoTotem._statusThread = nil
    end
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function stopLoop()
    if AutoTotem._thread then
        pcall(task.cancel, AutoTotem._thread)
        AutoTotem._thread = nil
    end
end

local function runLoop()
    stopLoop()
    AutoTotem._thread = task.spawn(function()
        while AutoTotem.Enabled do
            if selectedTotem and TOTEMS[selectedTotem] then
                local timeLeft = currentExpiry - os.time()

                if timeLeft <= 0 then
                    local success = placeTotem()
                    pushUpdate()
                    task.wait(success and 10 or 30)
                else
                    pushUpdate()
                    if    timeLeft > 300 then task.wait(60)
                    elseif timeLeft > 60  then task.wait(30)
                    elseif timeLeft > 10  then task.wait(5)
                    else                       task.wait(1)
                    end
                end
            else
                task.wait(5)
            end
        end
    end)
    registerTask(AutoTotem._thread)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoTotem.SetOnUpdate(fn)
    AutoTotem.OnUpdate = fn
    task.spawn(function()
        task.wait(0.1)
        pushUpdate()
    end)
end

function AutoTotem.SetTotem(name)
    if TOTEMS[name] then
        selectedTotem = name
        if currentExpiry - os.time() <= 0 then
            currentExpiry = 0
        end
        pushUpdate()
    end
end

function AutoTotem.GetTotemList()
    local t = {}
    for n in pairs(TOTEMS) do t[#t + 1] = n end
    table.sort(t)
    return t
end

function AutoTotem.GetTotemStock(name)
    local rep = getPlayerData()
    if not rep then return 0 end
    local ok, data = pcall(function() return rep:GetExpect("Inventory") end)
    if not ok or not data or not data.Totems then return 0 end

    local targetId = TOTEMS[name] and TOTEMS[name].Id
    if not targetId then return 0 end

    local total = 0
    for _, item in ipairs(data.Totems) do
        if tonumber(item.Id) == targetId then
            total = total + (item.Count or 1)
        end
    end
    return total
end

function AutoTotem.IsActive()
    return AutoTotem.Enabled
end

function AutoTotem.GetStatus()
    local timeLeft = math.max(currentExpiry - os.time(), 0)
    local m = math.floor(timeLeft / 60)
    local s = timeLeft % 60
    return selectedTotem or "None", ("%02d:%02d"):format(m, s)
end

function AutoTotem.ForcePlaceTotem()
    return placeTotem()
end

function AutoTotem.ResetTimer()
    currentExpiry = 0
    pushUpdate()
end

function AutoTotem.Start()
    if AutoTotem.Enabled then return end
    AutoTotem.Enabled = true
    runLoop()
    startStatusWatcher()
end

function AutoTotem.Stop()
    if not AutoTotem.Enabled then return end
    AutoTotem.Enabled = false
    stopLoop()
    stopStatusWatcher()
    pushUpdate()
end

return AutoTotem