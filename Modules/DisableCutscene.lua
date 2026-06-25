----------------------------------------------------------------
-- DISABLE CUTSCENE MODULE
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

-- ================================================================
-- STATE
-- ================================================================
local DisableCutscene = {}

local state = {
    enabled    = false,
    conns      = {},
    hooked     = false,
    controller = nil,
    oldPlay    = nil,
    oldStop    = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function disconnectAll()
    for _, c in ipairs(state.conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(state.conns)
end

local function tryRequireController()
    local ps    = Players.LocalPlayer:FindFirstChild("PlayerScripts")
    local ctrls = ps and ps:FindFirstChild("Controllers")
    local m     = ctrls and ctrls:FindFirstChild("CutsceneController")
    if m then
        local ok, mod = pcall(require, m)
        if ok then return mod end
    end

    local ok, mod = pcall(function()
        return require(
            ReplicatedStorage:WaitForChild("Controllers", 2):WaitForChild("CutsceneController", 2)
        )
    end)
    return ok and mod or nil
end

local function hookController()
    if state.hooked then return end

    state.controller = tryRequireController()
    if not state.controller then return end

    if type(state.controller.Play) == "function" then
        state.oldPlay           = state.controller.Play
        state.controller.Play   = function(...)
            if state.enabled then return end
            return state.oldPlay(...)
        end
    end

    if type(state.controller.Stop) == "function" then
        state.oldStop           = state.controller.Stop
        state.controller.Stop   = function(...)
            if state.enabled then return end
            return state.oldStop(...)
        end
    end

    state.hooked = true
end

local function hookRemotes()
    local RE_Replicate = _G.Net.ReplicateCutscene
    local RE_Stop      = _G.Net.StopCutscene

    if RE_Replicate then
        local c = RE_Replicate.OnClientEvent:Connect(function() end)
        table.insert(state.conns, c)
        registerConn(c)
    end

    if RE_Stop then
        local c = RE_Stop.OnClientEvent:Connect(function() end)
        table.insert(state.conns, c)
        registerConn(c)
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function DisableCutscene.Start()
    if state.enabled then return end
    state.enabled = true

    hookController()
    hookRemotes()
end

function DisableCutscene.Stop()
    if not state.enabled then return end
    state.enabled = false

    disconnectAll()

    if state.hooked and state.controller then
        if state.oldPlay then state.controller.Play = state.oldPlay end
        if state.oldStop then state.controller.Stop = state.oldStop end
    end
end

function DisableCutscene.IsEnabled()
    return state.enabled
end

return DisableCutscene