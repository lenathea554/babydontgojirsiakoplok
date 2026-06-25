----------------------------------------------------------------
-- DISABLE FISH NOTIFICATION
----------------------------------------------------------------
local Players    = game:GetService("Players")

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
local DisableFishNotification = {}

local state = {
    enabled     = false,
    scanConn    = nil,
    notifConns  = {},
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================

local function applyToExisting()
    local guiRoot = LP:FindFirstChildOfClass("PlayerGui")
    if not guiRoot then return end

    for _, gui in ipairs(guiRoot:GetDescendants()) do
        if gui.Name == "Small Notification" then
            local display = gui:FindFirstChild("Display")
            if display then
                display.Visible = not state.enabled
            end
        end
    end
end

local function hookNotif(gui)
    if gui.Name ~= "Small Notification" then return end
    local display = gui:FindFirstChild("Display")
    if not display then return end

    display.Visible = not state.enabled

    local conn = display:GetPropertyChangedSignal("Visible"):Connect(function()
        if state.enabled and display.Visible then
            display.Visible = false
        end
    end)

    table.insert(state.notifConns, conn)
    registerConn(conn)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function DisableFishNotification.Start()
    if state.enabled then return end
    state.enabled = true

    applyToExisting()

    local guiRoot = LP:WaitForChild("PlayerGui", 5)
    if guiRoot then
        state.scanConn = guiRoot.DescendantAdded:Connect(hookNotif)
        registerConn(state.scanConn)
    end
end

function DisableFishNotification.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.scanConn then
        pcall(function() state.scanConn:Disconnect() end)
        state.scanConn = nil
    end

    for _, c in ipairs(state.notifConns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(state.notifConns)

    applyToExisting()
end

function DisableFishNotification.IsEnabled()
    return state.enabled
end

return DisableFishNotification