----------------------------------------------------------------
-- DISABLE ROD DIVE EFFECT
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXFolder = ReplicatedStorage:WaitForChild("VFX")

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
local DisableRodEffect = {}

local state = {
    enabled   = false,
    childConn = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function isDiveEffect(child)
    return child.Name:lower():find("dive", 1, true) ~= nil
end

local function killDiveFx()
    for _, v in ipairs(VFXFolder:GetChildren()) do
        if isDiveEffect(v) then
            pcall(function() v:Destroy() end)
        end
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function DisableRodEffect.Start()
    if state.enabled then return end
    state.enabled = true

    killDiveFx()

    state.childConn = VFXFolder.ChildAdded:Connect(function(child)
        if state.enabled and isDiveEffect(child) then
            pcall(function() child:Destroy() end)
        end
    end)
    registerConn(state.childConn)
end

function DisableRodEffect.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.childConn then
        pcall(function() state.childConn:Disconnect() end)
        state.childConn = nil
    end
end

function DisableRodEffect.IsEnabled()
    return state.enabled
end

return DisableRodEffect