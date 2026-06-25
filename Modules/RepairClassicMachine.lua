----------------------------------------------------------------
-- REPAIR CLASSIC MACHINE MODULE
----------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

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
local ClassicMachineActivate = _G.Net.ClassicMachineActivate

-- ================================================================
-- DEPENDENCIES
-- ================================================================
local Replion           = require(ReplicatedStorage.Packages.Replion)
local CurrencyUtility   = require(ReplicatedStorage.Modules.CurrencyUtility)
local ClassicMachineConfig = require(ReplicatedStorage.Shared.ClassicMachineConfig)

-- ================================================================
-- REPLION STATE
-- ================================================================
local _machineRep = nil
local _dataRep    = nil

local function getMachineRep()
    if _machineRep then return _machineRep end
    local ok, r = pcall(function()
        return Replion.Client:WaitReplion(ClassicMachineConfig.Channel, 5)
    end)
    if ok and r then _machineRep = r end
    return _machineRep
end

local function getDataRep()
    if _dataRep then return _dataRep end
    local ok, r = pcall(function()
        return Replion.Client:WaitReplion("Data", 5)
    end)
    if ok and r then _dataRep = r end
    return _dataRep
end

-- ================================================================
-- CURRENCY HELPER
-- ================================================================
local _currency = nil
local function getCurrency()
    if _currency then return _currency end
    _currency = CurrencyUtility:GetCurrency(ClassicMachineConfig.CurrencyName)
    return _currency
end

-- ================================================================
-- CONSTANTS
-- ================================================================
local MACHINE_POSITION = Vector3.new(1320.37, 48, 2756.46)

-- ================================================================
-- MODULE STATE
-- ================================================================
local RepairClassicMachine = {
    Enabled       = false,
    SelectedMode  = "Basic",
    OnUpdate      = nil,
    _repairThread = nil,
    _statusThread = nil,
}

-- ================================================================
-- MACHINE WORLD REFERENCES
-- ================================================================
local ClassicMachineFolder = nil
local PiecesFolder         = nil

local function ensureWorldRefs()
    if ClassicMachineFolder and ClassicMachineFolder.Parent then return true end
    ClassicMachineFolder = Workspace:FindFirstChild(ClassicMachineConfig.ModelName)
    if not ClassicMachineFolder then return false end
    PiecesFolder = ClassicMachineFolder:FindFirstChild("Pieces")
    return true
end

-- ================================================================
-- STATUS / TIMER HELPERS
-- ================================================================
local function formatTimer(seconds)
    local s = math.max(math.floor(seconds), 0)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sc = s % 60
    if h > 0 then
        return string.format("%02dh %02dm %02ds", h, m, sc)
    else
        return string.format("%02dm %02ds", m, sc)
    end
end

local function getMachineActiveInfo()
    local rep = getMachineRep()
    if not rep then return false, 0 end
    local isActive  = rep:Get("IsActive") == true
    local endsAt    = rep:Get("ActiveEndsAt") or 0
    local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0)
    return isActive and remaining > 0, remaining
end

local function getActivationCost(mode)
    local cfg = ClassicMachineConfig.ActivationOptions[mode]
    if not cfg then return math.huge end
    local rep   = getMachineRep()
    local count = rep and rep:Get("ActivationCount") or 0
    return (cfg.Cost or 0) + count * (cfg.CostIncrease or 0)
end

local function hasEnoughCurrency(cost)
    local dataRep  = getDataRep()
    local currency = getCurrency()
    if not dataRep or not currency then return false end
    local balance = dataRep:Get(currency.Path) or 0
    return typeof(balance) == "number" and balance >= cost
end

-- ================================================================
-- STATUS PUSH
-- ================================================================
local function buildStatusText()
    local isActive, remaining = getMachineActiveInfo()
    if isActive then
        return string.format(
            "Machine Active: <font color='rgb(100,255,100)'>%s</font>",
            formatTimer(remaining)
        )
    else
        if RepairClassicMachine.Enabled then
            return "<font color='rgb(255,200,100)'>Waiting to repair...</font>"
        else
            return "<font color='rgb(180,180,180)'>Machine Not Active</font>"
        end
    end
end

local function pushUpdate(overrideText)
    if not RepairClassicMachine.OnUpdate then return end
    pcall(RepairClassicMachine.OnUpdate, overrideText or buildStatusText())
end

-- ================================================================
-- PROXIMITY PROMPT HELPER
-- ================================================================
local function firePrompt(prompt)
    if not prompt then return end
    if fireproximityprompt then
        pcall(fireproximityprompt, prompt)
    else
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration + 0.1)
            prompt:InputHoldEnd()
        end)
    end
end

-- ================================================================
-- REPAIR CORE
-- ================================================================
local function doRepair()
    if not ensureWorldRefs() then
        pushUpdate("<font color='rgb(255,100,100)'>ClassicMachine folder not found</font>")
        return false
    end

    if not PiecesFolder then
        pushUpdate("<font color='rgb(255,100,100)'>Pieces folder not found</font>")
        return false
    end

    local cost = getActivationCost(RepairClassicMachine.SelectedMode)
    if not hasEnoughCurrency(cost) then
        pushUpdate(string.format(
            "<font color='rgb(255,100,100)'>Not enough %s! (Need %d)</font>",
            ClassicMachineConfig.CurrencyName, cost
        ))
        return false
    end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        pushUpdate("<font color='rgb(255,100,100)'>Character not found</font>")
        return false
    end

    local savedCFrame = hrp.CFrame
    local pieces      = PiecesFolder:GetChildren()
    local total       = #pieces

    for idx, model in ipairs(pieces) do
        if not RepairClassicMachine.Enabled then
            local c2 = LocalPlayer.Character
            local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
            if h2 then h2.CFrame = savedCFrame end
            return false
        end

        pushUpdate(string.format(
            "<font color='rgb(100,200,255)'>Collecting piece %d/%d...</font>",
            idx, total
        ))

        local c = LocalPlayer.Character
        local h = c and c:FindFirstChild("HumanoidRootPart")
        if not h then break end

        h.CFrame = CFrame.new(model:GetPivot().Position + Vector3.new(0, 5, 0))
        task.wait(1.5)

        local piecePrompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if piecePrompt then
            firePrompt(piecePrompt)
            task.wait(1)

            local c3 = LocalPlayer.Character
            local h3 = c3 and c3:FindFirstChild("HumanoidRootPart")
            if h3 then
                h3.CFrame = CFrame.new(MACHINE_POSITION)
                task.wait(1.5)

                local Trigger = ClassicMachineFolder:FindFirstChild("Trigger")
                if Trigger then
                    local machinePrompt = Trigger:FindFirstChildWhichIsA("ProximityPrompt", true)
                    firePrompt(machinePrompt)
                end

                task.wait(2.5)
            end
        else
            warn("[RepairClassicMachine] Prompt not found on: " .. model.Name)
        end
    end

    if not hasEnoughCurrency(getActivationCost(RepairClassicMachine.SelectedMode)) then
        pushUpdate(string.format(
            "<font color='rgb(255,100,100)'>Not enough %s to activate!</font>",
            ClassicMachineConfig.CurrencyName
        ))
        local cFinal = LocalPlayer.Character
        local hFinal = cFinal and cFinal:FindFirstChild("HumanoidRootPart")
        if hFinal then hFinal.CFrame = savedCFrame end
        return false
    end

    pushUpdate(string.format(
        "<font color='rgb(255,200,100)'>Activating (%s)...</font>",
        RepairClassicMachine.SelectedMode
    ))

    local ok, result = pcall(function()
        return ClassicMachineActivate:InvokeServer(RepairClassicMachine.SelectedMode)
    end)

    if ok and result and result.Success then
        pushUpdate("<font color='rgb(100,255,100)'>Machine Activated!</font>")
    else
        local Trigger = ClassicMachineFolder and ClassicMachineFolder:FindFirstChild("Trigger")
        if Trigger then
            local machinePrompt = Trigger:FindFirstChildWhichIsA("ProximityPrompt", true)
            firePrompt(machinePrompt)
        end
        pushUpdate("<font color='rgb(100,255,100)'>Done!</font>")
    end

    task.wait(1)

    local cFinal = LocalPlayer.Character
    local hFinal = cFinal and cFinal:FindFirstChild("HumanoidRootPart")
    if hFinal then hFinal.CFrame = savedCFrame end

    return true
end

-- ================================================================
-- STATUS WATCHER
-- ================================================================
local function startStatusWatcher()
    if RepairClassicMachine._statusThread then
        pcall(task.cancel, RepairClassicMachine._statusThread)
    end

    RepairClassicMachine._statusThread = task.spawn(function()
        while true do
            task.wait(1)
            if not RepairClassicMachine.Enabled then
                pushUpdate()
            else
                local isActive, _ = getMachineActiveInfo()
                if isActive then
                    pushUpdate()
                end
            end
        end
    end)

    registerTask(RepairClassicMachine._statusThread)
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function stopRepairLoop()
    if RepairClassicMachine._repairThread then
        pcall(task.cancel, RepairClassicMachine._repairThread)
        RepairClassicMachine._repairThread = nil
    end
end

local function runRepairLoop()
    stopRepairLoop()

    RepairClassicMachine._repairThread = task.spawn(function()
        while RepairClassicMachine.Enabled do

            local isActive, remaining = getMachineActiveInfo()

            if isActive then
                repeat
                    task.wait(5)
                    isActive, remaining = getMachineActiveInfo()
                until not RepairClassicMachine.Enabled or not isActive
            else
                local cost = getActivationCost(RepairClassicMachine.SelectedMode)
                if not hasEnoughCurrency(cost) then
                    pushUpdate(string.format(
                        "<font color='rgb(255,100,100)'>Not enough %s! Retrying in 30s...</font>",
                        ClassicMachineConfig.CurrencyName
                    ))
                    task.wait(30)
                else
                    local success = doRepair()
                    if not success and RepairClassicMachine.Enabled then
                        task.wait(5)
                    end
                end
            end

            if RepairClassicMachine.Enabled then
                task.wait(3)
            end
        end

        RepairClassicMachine.Enabled = false
        pushUpdate()
    end)

    registerTask(RepairClassicMachine._repairThread)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function RepairClassicMachine.SetMode(mode)
    if mode == "Basic" or mode == "Overdrive" then
        RepairClassicMachine.SelectedMode = mode
    end
end

function RepairClassicMachine.SetOnUpdate(fn)
    RepairClassicMachine.OnUpdate = fn
    startStatusWatcher()
    task.spawn(function()
        task.wait(0.1)
        pushUpdate()
    end)
end

function RepairClassicMachine.Start()
    if RepairClassicMachine.Enabled then return end
    RepairClassicMachine.Enabled = true
    runRepairLoop()
end

function RepairClassicMachine.Stop()
    if not RepairClassicMachine.Enabled then return end
    RepairClassicMachine.Enabled = false
    stopRepairLoop()
    pushUpdate()
end

function RepairClassicMachine.IsEnabled()
    return RepairClassicMachine.Enabled
end

return RepairClassicMachine