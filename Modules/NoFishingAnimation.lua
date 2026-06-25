----------------------------------------------------------------
-- NO FISHING ANIMATION MODULE
----------------------------------------------------------------
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

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
local NoFishingAnimation = {}

local state = {
    enabled    = false,
    savedPose  = {},
    connStepped = nil,
    connBlock  = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function getHumanoid()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getAnimator()
    local hum = getHumanoid()
    return hum and hum:FindFirstChildOfClass("Animator")
end

local function stopAllAnims()
    local hum = getHumanoid()
    if not hum then return end
    for _, t in ipairs(hum:GetPlayingAnimationTracks()) do
        pcall(function() t:Stop(0) end)
    end
end

local function capturePose()
    table.clear(state.savedPose)
    local char = LP.Character
    if not char then return false end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") then
            state.savedPose[d] = { C0 = d.C0, C1 = d.C1 }
        end
    end
    return next(state.savedPose) ~= nil
end

local function startFreeze()
    state.connStepped = RunService.Stepped:Connect(function()
        if not state.enabled then return end
        stopAllAnims()
        for m, v in pairs(state.savedPose) do
            if m and m.Parent then
                if m.C0 ~= v.C0 then m.C0 = v.C0 end
                if m.C1 ~= v.C1 then m.C1 = v.C1 end
            end
        end
    end)
    registerConn(state.connStepped)
end

local function startBlockNew()
    local animator = getAnimator()
    if not animator then return end
    state.connBlock = animator.AnimationPlayed:Connect(function(track)
        if state.enabled then
            pcall(function()
                track:Stop(0)
                track:Destroy()
            end)
        end
    end)
    registerConn(state.connBlock)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function NoFishingAnimation.Start()
    if state.enabled then return end
    if not capturePose() then return end

    state.enabled = true
    stopAllAnims()
    startBlockNew()
    startFreeze()
end

function NoFishingAnimation.Stop()
    if not state.enabled then return end
    state.enabled = false

    table.clear(state.savedPose)

    if state.connStepped then
        pcall(function() state.connStepped:Disconnect() end)
        state.connStepped = nil
    end

    if state.connBlock then
        pcall(function() state.connBlock:Disconnect() end)
        state.connBlock = nil
    end
end

function NoFishingAnimation.IsEnabled()
    return state.enabled
end

return NoFishingAnimation