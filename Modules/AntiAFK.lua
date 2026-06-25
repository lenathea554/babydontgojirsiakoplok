----------------------------------------------------------------
-- ADVANCED ANTI-AFK
----------------------------------------------------------------
local Players = game:GetService("Players")

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
-- STATE
-- ================================================================
local AntiAFK = {}

local state = {
    enabled   = false,
    conns     = {},
    nudgeTask = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function nudgeCamera()
    pcall(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, math.rad(0.0001))
        task.wait()
        cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, math.rad(-0.0001))
    end)
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AntiAFK.Start()
    if state.enabled then return end
    state.enabled = true

    local lp = Players.LocalPlayer

    if getconnections then
        for _, conn in pairs(getconnections(lp.Idled)) do
            if conn.Disable then
                conn:Disable()
                table.insert(state.conns, conn)
            elseif conn.Disconnect then
                conn:Disconnect()
            end
        end
    end

    local idledConn = lp.Idled:Connect(nudgeCamera)
    table.insert(state.conns, idledConn)
    registerConn(idledConn)

    state.nudgeTask = task.spawn(function()
        while state.enabled do
            task.wait(240)
            if not state.enabled then break end
            local char = lp.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.CFrame = hrp.CFrame * CFrame.new(0, 1e-5, 0)
                end)
            end
        end
    end)
    registerTask(state.nudgeTask)
end

function AntiAFK.Stop()
    if not state.enabled then return end
    state.enabled = false

    for _, conn in ipairs(state.conns) do
        pcall(function()
            if conn.Enable     then conn:Enable()     end
            if conn.Disconnect then conn:Disconnect()  end
        end)
    end
    table.clear(state.conns)

    if state.nudgeTask then
        pcall(task.cancel, state.nudgeTask)
        state.nudgeTask = nil
    end
end

function AntiAFK.IsEnabled()
    return state.enabled
end

return AntiAFK