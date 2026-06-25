-- =====================================================
-- DISABLE RENDERING
-- =====================================================
local DisableRendering = {}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- =====================================================
-- CONFIGURATION
-- =====================================================
DisableRendering.Settings = {
    AutoPersist = true
}

-- =====================================================
-- STATE VARIABLES
-- =====================================================
local State = {
    RenderingDisabled = false,
}

-- =====================================================
-- PUBLIC API
-- =====================================================
function DisableRendering.Start()
    if State.RenderingDisabled then
        return false, "Already disabled"
    end

    local success, err = pcall(function()
        RunService:Set3dRenderingEnabled(false)
        State.RenderingDisabled = true
    end)

    if not success then
        warn("[DisableRendering] Failed to start:", err)
        return false, "Failed to start"
    end

    return true, "Rendering disabled"
end

function DisableRendering.Stop()
    if not State.RenderingDisabled then
        return false, "Already enabled"
    end

    local success, err = pcall(function()
        RunService:Set3dRenderingEnabled(true)
        State.RenderingDisabled = false
    end)

    if not success then
        warn("[DisableRendering] Failed to stop:", err)
        return false, "Failed to stop"
    end

    return true, "Rendering enabled"
end

function DisableRendering.Toggle()
    if State.RenderingDisabled then
        return DisableRendering.Stop()
    else
        return DisableRendering.Start()
    end
end

function DisableRendering.IsDisabled()
    return State.RenderingDisabled
end

-- =====================================================
-- AUTO-PERSIST ON RESPAWN
-- =====================================================
if DisableRendering.Settings.AutoPersist then
    local charConn = LocalPlayer.CharacterAdded:Connect(function()
        if State.RenderingDisabled then
            task.wait(0.5)
            pcall(function()
                RunService:Set3dRenderingEnabled(false)
            end)
        end
    end)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, charConn)
    end
end

-- =====================================================
-- CLEANUP FUNCTION
-- =====================================================
function DisableRendering.Cleanup()
    if State.RenderingDisabled then
        pcall(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        State.RenderingDisabled = false
    end
end

return DisableRendering