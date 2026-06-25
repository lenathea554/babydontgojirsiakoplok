-- ================================================================
-- AUTO ABILITY ROLL ENGINE
-- ================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local RequestAbilityRoll   = _G.Net.RequestAbilityRoll
local ConvertAbilityShards = _G.Net.ConvertAbilityShards
local GetAbilityRewardProgress = _G.Net.GetAbilityRewardProgress

-- ================================================================
-- REPLION
-- ================================================================
local _replionData = nil
local function getReplionData()
    if _replionData then return _replionData end
    local ok, r = pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        return Replion.Client:WaitReplion("Data", 10)
    end)
    if ok and r then _replionData = r end
    return _replionData
end

-- ================================================================
-- ABILITY LIST
-- ================================================================
local _abilityCache = nil
local function getAbilityList()
    if _abilityCache then return _abilityCache end
    local ok, abilities = pcall(function()
        return require(ReplicatedStorage.Abilities)
    end)
    if not ok or not abilities then return {} end
    _abilityCache = {}
    for name in pairs(abilities) do
        table.insert(_abilityCache, name)
    end
    table.sort(_abilityCache)
    return _abilityCache
end

-- ================================================================
-- MODULE STATE
-- ================================================================
local AutoAbilityRoll = {
    Enabled        = false,
    TargetAbility  = nil,
    LastMessage    = "<font color='rgb(200,200,200)'>Waiting...</font>",
    OnUpdate       = nil,
    _rollThread    = nil,
}

-- ================================================================
-- STATUS PUSH
-- ================================================================
local _lastPushTime = 0
local function pushUpdate(msg)
    if not AutoAbilityRoll.OnUpdate then return end
    AutoAbilityRoll.LastMessage = msg or AutoAbilityRoll.LastMessage
    local now = os.clock()
    if now - _lastPushTime < 0.5 then return end
    _lastPushTime = now
    pcall(AutoAbilityRoll.OnUpdate, AutoAbilityRoll.LastMessage)
end

-- ================================================================
-- HELPERS
-- ================================================================
local function getCurrentAbility()
    local replion = getReplionData()
    if not replion then return nil end

    local ok, equipped = pcall(function()
        return replion:Get({ "Abilities", "Equipped" })
    end)
    if not ok or not equipped or equipped == "" then return nil end

    local ok2, inventory = pcall(function()
        return replion:Get({ "Abilities", "Inventory" })
    end)
    if not ok2 or type(inventory) ~= "table" then return equipped end

    for _, item in ipairs(inventory) do
        if item.UUID == equipped or item.Name == equipped then
            return item.Name
        end
    end
    return equipped
end

local function hasAbilityInInventory(targetName)
    local replion = getReplionData()
    if not replion then return false end
    local ok, inventory = pcall(function()
        return replion:Get({ "Abilities", "Inventory" })
    end)
    if not ok or type(inventory) ~= "table" then return false end
    for _, item in ipairs(inventory) do
        if item.Name == targetName then return true end
    end
    return false
end

local function getFreeRolls()
    local replion = getReplionData()
    if not replion then return 0 end
    local ok, rolls = pcall(function()
        return replion:Get({ "Abilities", "FreeRolls" })
    end)
    return (ok and tonumber(rolls)) or 0
end

-- ================================================================
-- ROLL CORE
-- ================================================================
local function doRoll()
    local ok, abilityName, isDuplicate = pcall(function()
        return RequestAbilityRoll:InvokeServer()
    end)
    if not ok then
        pushUpdate("<font color='rgb(255,100,100)'>Roll request failed</font>")
        return nil, nil
    end
    return abilityName, isDuplicate
end

-- ================================================================
-- THREADS
-- ================================================================
local function stopRollLoop()
    if AutoAbilityRoll._rollThread then
        pcall(task.cancel, AutoAbilityRoll._rollThread)
        AutoAbilityRoll._rollThread = nil
    end
end

local function buildStatusText(extraLine)
    local replion = getReplionData()
    local current = "<font color='rgb(120,120,120)'>None</font>"
    local rolls = 0

    if replion then
        local ok, equipped = pcall(function() return replion:Get({ "Abilities", "Equipped" }) end)
        local ok2, inventory = pcall(function() return replion:Get({ "Abilities", "Inventory" }) end)
        local ok3, freeRolls = pcall(function() return replion:Get({ "Abilities", "FreeRolls" }) end)

        if ok and equipped and equipped ~= "" then
            local resolvedName = equipped
            if ok2 and type(inventory) == "table" then
                for _, item in ipairs(inventory) do
                    if item.UUID == equipped or item.Name == equipped then
                        resolvedName = item.Name
                        break
                    end
                end
            end
            current = resolvedName
        end

        if ok3 then rolls = tonumber(freeRolls) or 0 end
    end

    local target = AutoAbilityRoll.TargetAbility
        and ("<b>" .. AutoAbilityRoll.TargetAbility .. "</b>")
        or  "<font color='rgb(120,120,120)'>-</font>"
    local status = extraLine or AutoAbilityRoll.LastMessage

    return string.format(
        "<font color='rgb(120,120,120)'>Current Ability:  </font>%s\n"..
        "<font color='rgb(120,120,120)'>Target:  </font>%s\n"..
        "<font color='rgb(120,120,120)'>Free Rolls:  </font><font color='rgb(255,200,100)'>%d</font>\n"..
        "<font color='rgb(120,120,120)'>Status:  </font>%s",
        current, target, rolls, status
    )
end

local function runRollLoop()
    stopRollLoop()

    AutoAbilityRoll._rollThread = task.spawn(function()
        if not AutoAbilityRoll.TargetAbility or AutoAbilityRoll.TargetAbility == "" then
            pushUpdate(buildStatusText("<font color='rgb(255,100,100)'>No Target Selected</font>"))
            AutoAbilityRoll.Enabled = false
            return
        end

        if hasAbilityInInventory(AutoAbilityRoll.TargetAbility) then
            pushUpdate(buildStatusText(
                "<font color='rgb(100,255,100)'>Already owned: <b>"..AutoAbilityRoll.TargetAbility.."</b></font>"
            ))
            AutoAbilityRoll.Enabled = false
            return
        end

        pushUpdate(buildStatusText("<font color='rgb(100,200,255)'>Starting roll loop...</font>"))

        while AutoAbilityRoll.Enabled do
            local rolls = getFreeRolls()
            if rolls <= 0 then
                if ConvertAbilityShards then
                    pcall(function() ConvertAbilityShards:InvokeServer() end)
                    task.wait(0.5)
                    rolls = getFreeRolls()
                    if rolls <= 0 then
                        pushUpdate(buildStatusText("<font color='rgb(255,150,100)'>No rolls & not enough shards</font>"))
                        task.wait(3)
                        continue
                    end
                else
                    pushUpdate(buildStatusText("<font color='rgb(255,100,100)'>No free rolls remaining</font>"))
                    AutoAbilityRoll.Enabled = false
                    break
                end
            end

            pushUpdate(buildStatusText(
                string.format("<font color='rgb(100,200,255)'>Rolling... (%d rolls left)</font>", rolls)
            ))

            local result, isDuplicate = doRoll()

            if result then
                local dupText = isDuplicate
                    and " <font color='rgb(180,180,180)'>(dup)</font>"
                    or  " <font color='rgb(255,220,80)'>(new!)</font>"

                pushUpdate(buildStatusText(
                    "<font color='rgb(200,200,200)'>Got: <b>"..result.."</b>"..dupText.."</font>"
                ))

                if result == AutoAbilityRoll.TargetAbility then
                    pushUpdate(buildStatusText(
                        "<font color='rgb(100,255,100)'>✓ Got target: <b>"..result.."</b>!</font>"
                    ))
                    AutoAbilityRoll.Enabled = false
                    break
                end

                task.wait(1.7)
            else
                task.wait(1)
            end
        end

        AutoAbilityRoll.Enabled = false
    end)

    registerTask(AutoAbilityRoll._rollThread)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AutoAbilityRoll.SetEnabled(state)
    if state == AutoAbilityRoll.Enabled then return end
    AutoAbilityRoll.Enabled = state

    if state then
        runRollLoop()
    else
        stopRollLoop()
        pushUpdate(buildStatusText("<font color='rgb(200,200,200)'>Stopped</font>"))
    end
end

function AutoAbilityRoll.SetTarget(abilityName)
    AutoAbilityRoll.TargetAbility = abilityName
    if AutoAbilityRoll.OnUpdate then
        pcall(AutoAbilityRoll.OnUpdate, buildStatusText(
            "<font color='rgb(200,200,200)'>Target set: <b>"..(abilityName or "-").."</b></font>"
        ))
    end
end

function AutoAbilityRoll.GetAbilityList()
    return getAbilityList()
end

function AutoAbilityRoll.SetOnUpdate(fn)
    AutoAbilityRoll.OnUpdate = fn
    task.spawn(function()
        task.wait(0.5)
        if AutoAbilityRoll.OnUpdate then
            pcall(AutoAbilityRoll.OnUpdate, buildStatusText(
                "<font color='rgb(200,200,200)'>Ready</font>"
            ))
        end
    end)
end

function AutoAbilityRoll.Start() AutoAbilityRoll.SetEnabled(true) end
function AutoAbilityRoll.Stop()  AutoAbilityRoll.SetEnabled(false) end

return AutoAbilityRoll