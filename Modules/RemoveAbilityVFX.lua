----------------------------------------------------------------
-- REMOVE ABILITY VFX MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

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
-- SERVICES / REFERENCES
-- ================================================================
local LocalPlayer = Players.LocalPlayer

-- ================================================================
-- STATE
-- ================================================================
local RemoveAbilityVFX = {}

local state = {
    enabled     = false,
    scope       = "All",
    conn        = nil,
    watchThread = nil,
}

-- ================================================================
-- INTERNAL LOGIC
-- ================================================================
local function purgeCharacterVFX(character)
    if not character then return end
    for _, v in ipairs(character:GetDescendants()) do
        if v:GetAttribute("AbilityVFX") == true or v:GetAttribute("AbilityAuraVFX") == true then
            pcall(function() v:Destroy() end)
        end
    end
end

local function purgeWorldVFX()
    for _, v in ipairs(workspace:GetChildren()) do
        if v:GetAttribute("AbilityVFX") == true then
            pcall(function() v:Destroy() end)
        end
    end
end

local function inScope(player)
    if state.scope == "All"    then return true end
    if state.scope == "Self"   then return player == LocalPlayer end
    if state.scope == "Others" then return player ~= LocalPlayer end
    return false
end

local function purgeAll()
    for _, player in ipairs(Players:GetPlayers()) do
        if inScope(player) then
            purgeCharacterVFX(player.Character)
        end
    end
    purgeWorldVFX()
end

-- ================================================================
-- WATCHERS
-- ================================================================
local function startNetConn()
    if state.conn then return end
    local Net = _G.Net
    if not Net or not Net.PlayAbilityVFX then return end

    state.conn = Net.PlayAbilityVFX.OnClientEvent:Connect(function(abilityName, player, _position)
        if not state.enabled then return end
        if not inScope(player) then return end
        task.defer(function()
            purgeCharacterVFX(player and player.Character)
            purgeWorldVFX()
        end)
    end)
    registerConn(state.conn)
end

local function stopNetConn()
    if state.conn then
        pcall(function() state.conn:Disconnect() end)
        state.conn = nil
    end
end

local function startWatchThread()
    if state.watchThread then return end
    state.watchThread = task.spawn(function()
        while state.enabled do
            task.wait(1)
            if state.enabled then
                purgeAll()
            end
        end
        state.watchThread = nil
    end)
    registerTask(state.watchThread)
end

local function stopWatchThread()
    if state.watchThread then
        pcall(task.cancel, state.watchThread)
        state.watchThread = nil
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function RemoveAbilityVFX.SetScope(scope)
    if scope ~= "All" and scope ~= "Self" and scope ~= "Others" then return end
    state.scope = scope
end

function RemoveAbilityVFX.GetScope()
    return state.scope
end

function RemoveAbilityVFX.PurgeNow()
    purgeAll()
end

-- ================================================================
-- LIFECYCLE
-- ================================================================
function RemoveAbilityVFX.Start()
    if state.enabled then return end
    state.enabled = true
    startNetConn()
    startWatchThread()
    purgeAll()
end

function RemoveAbilityVFX.Stop()
    if not state.enabled then return end
    state.enabled = false
    stopNetConn()
    stopWatchThread()
end

function RemoveAbilityVFX.IsActive()
    return state.enabled
end

return RemoveAbilityVFX