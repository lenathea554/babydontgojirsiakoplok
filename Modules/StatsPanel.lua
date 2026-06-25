----------------------------------------------------------------
-- STATS PANEL MODULE
-- Real FPS, Ping, CPU + Boss Spawn Timer dari BossTimerSync
----------------------------------------------------------------
if _G.StatsPanel then
    _G.StatsPanel = nil
end

local Players           = game:GetService("Players")
local Stats             = game:GetService("Stats")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP        = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

local StatsPanel = {}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local enabled      = false
local gui, mainFrame
local conns        = {}
local bossTimers   = {}   -- [id] = { displayName, timer, isAlive, isRotationWaiting }
local bossRowItems = {}   -- [id] = { row, dot, nameL, timerL }
local bossRowContainer

local function connect(c) table.insert(conns, c) end
local function disconnectAll()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
end

local function GetHiddenContainer()
    if type(gethui) == "function" then
        local ok, c = pcall(gethui)
        if ok and c then return c end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return PlayerGui
end

----------------------------------------------------------------
-- METRICS
----------------------------------------------------------------

-- FPS REAL: sample tiap RenderStepped, rata-rata 60 frame terakhir
local fpsHistory    = {}
local lastRenderT   = tick()
local cachedFPS     = 0

local function sampleFPS()
    local now = tick()
    local dt  = now - lastRenderT
    lastRenderT = now
    if dt <= 0 then return end
    local fps = 1 / dt
    table.insert(fpsHistory, fps)
    if #fpsHistory > 60 then table.remove(fpsHistory, 1) end
    local sum = 0
    for _, v in ipairs(fpsHistory) do sum = sum + v end  -- fix: + v bukan + 1
    cachedFPS = math.floor(math.clamp(sum / #fpsHistory, 0, 240))
end

-- PING REAL: GetNetworkPing() dari engine, bukan Stats heuristic
local function getRealPing()
    local ok, ms = pcall(function()
        return math.floor(LP:GetNetworkPing() * 1000)
    end)
    return ok and ms or 0
end

-- CPU REAL: HeartbeatTimeMs = waktu CPU tiap frame dalam ms
-- Nilai kecil = CPU longgar, nilai besar = CPU berat
local function getCPU()
    local ok, ms = pcall(function()
        return math.floor(Stats.HeartbeatTimeMs * 10) / 10
    end)
    return ok and ms or 0
end

----------------------------------------------------------------
-- BOSS TIMER SYNC
-- Mirror logika game (dokumen 3) tanpa BillboardGui
----------------------------------------------------------------
local timerAccum = 0

local function hookBossTimers()
    local remFolder   = ReplicatedStorage:FindFirstChild("Remotes")
    local syncRemote  = remFolder and remFolder:FindFirstChild("BossTimerSync")
    local eventRemote = remFolder and remFolder:FindFirstChild("BossTimerEvent")

    if syncRemote then
        connect(syncRemote.OnClientEvent:Connect(function(data)
            if not data then return end
            for id, info in pairs(data) do
                if not bossTimers[id] then
                    bossTimers[id] = {}
                end
                local e = bossTimers[id]
                e.displayName       = info.displayName or id
                e.timer             = info.timer or 0
                e.isAlive           = info.isAlive or false
                e.isRotationWaiting = info.isRotationWaiting or false
            end
        end))
    end

    if eventRemote then
        connect(eventRemote.OnClientEvent:Connect(function(id, event, value)
            local e = bossTimers[id]
            if not e then return end
            if event == "SPAWNED" then
                e.isAlive           = true
                e.isRotationWaiting = false
                e.timer             = 0
            elseif event == "DIED" then
                e.isAlive           = false
                e.isRotationWaiting = false
                e.timer             = value or 0
            elseif event == "WAITING" then
                e.isAlive           = false
                e.isRotationWaiting = false
                e.timer             = value or 0
            elseif event == "ROTATION_WAITING" then
                e.isAlive           = false
                e.isRotationWaiting = true
                e.timer             = 0
            end
        end))
    end

    -- Decrement timer lokal tiap detik (sama persis dengan logika game)
    connect(RunService.Heartbeat:Connect(function(dt)
        timerAccum = timerAccum + dt
        if timerAccum >= 1 then
            timerAccum = timerAccum - 1
            for _, e in pairs(bossTimers) do
                if not e.isAlive and not e.isRotationWaiting then
                    e.timer = math.max(0, e.timer - 1)
                end
            end
        end
    end))
end

local function formatTimer(t)
    if t <= 0 then return "Segera Spawn" end
    local m = math.floor(t / 60)
    local s = math.floor(t) % 60
    return m > 0 and string.format("%d:%02d", m, s) or string.format("0:%02d", s)
end

----------------------------------------------------------------
-- COLORS & THEME
----------------------------------------------------------------
local C = {
    bg        = Color3.fromRGB(12, 14, 22),
    bgRow     = Color3.fromRGB(20, 24, 38),
    border    = Color3.fromRGB(70, 120, 220),
    title     = Color3.fromRGB(170, 205, 255),
    subtitle  = Color3.fromRGB(110, 140, 190),
    text      = Color3.fromRGB(200, 215, 240),
    dimText   = Color3.fromRGB(100, 115, 150),
    divider   = Color3.fromRGB(35, 45, 75),
    blue      = Color3.fromRGB(100, 175, 255),
    green     = Color3.fromRGB(75, 215, 130),
    yellow    = Color3.fromRGB(225, 200, 75),
    orange    = Color3.fromRGB(255, 155, 75),
    red       = Color3.fromRGB(255, 80, 80),
    alive     = Color3.fromRGB(75, 215, 130),
    aliveText = Color3.fromRGB(75, 215, 130),
    deadDot   = Color3.fromRGB(255, 80, 80),
    timerText = Color3.fromRGB(200, 200, 120),
    spawning  = Color3.fromRGB(75, 215, 130),
}

local function tw(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.2), props):Play()
end

----------------------------------------------------------------
-- UI FACTORY
----------------------------------------------------------------
local function mkLabel(parent, pos, size, text, textSize, color, xAlign)
    local l = Instance.new("TextLabel")
    l.Position            = pos
    l.Size                = size
    l.BackgroundTransparency = 1
    l.BorderSizePixel     = 0
    l.Font                = Enum.Font.GothamBold
    l.TextSize            = textSize or 12
    l.TextColor3          = color or C.text
    l.Text                = text or ""
    l.TextXAlignment      = xAlign or Enum.TextXAlignment.Left
    l.TextTruncate        = Enum.TextTruncate.AtEnd
    l.Parent              = parent
    return l
end

local function mkFrame(parent, pos, size, color, transp)
    local f = Instance.new("Frame")
    f.Position               = pos
    f.Size                   = size
    f.BackgroundColor3       = color or C.bg
    f.BackgroundTransparency = transp or 1
    f.BorderSizePixel        = 0
    f.Parent                 = parent
    return f
end

local function mkDivider(parent, yOff)
    local d = mkFrame(parent,
        UDim2.fromOffset(12, yOff),
        UDim2.new(1, -24, 0, 1),
        C.divider, 0)
    return d
end

----------------------------------------------------------------
-- BOSS ROWS (dynamic)
----------------------------------------------------------------
local function ensureBossRow(id, displayName)
    if bossRowItems[id] then return bossRowItems[id] end

    local row = mkFrame(bossRowContainer,
        UDim2.fromOffset(0, 0),
        UDim2.new(1, 0, 0, 22),
        C.bgRow, 0.6)
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    -- status dot
    local dot = mkLabel(row,
        UDim2.fromOffset(6, 4),
        UDim2.fromOffset(10, 14),
        "●", 9, C.deadDot, Enum.TextXAlignment.Center)

    -- boss name
    local nameL = mkLabel(row,
        UDim2.fromOffset(20, 4),
        UDim2.new(0.55, -20, 0, 14),
        displayName, 11, C.text)

    -- timer / status
    local timerL = mkLabel(row,
        UDim2.new(0.55, 0, 0, 4),
        UDim2.new(0.45, -8, 0, 14),
        "---", 11, C.timerText, Enum.TextXAlignment.Right)

    bossRowItems[id] = { row = row, dot = dot, nameL = nameL, timerL = timerL }
    return bossRowItems[id]
end

local noDataLabel

local function updateBossRows()
    -- Kumpulkan & urutkan berdasarkan nama
    local list = {}
    for id, e in pairs(bossTimers) do
        table.insert(list, { id = id, e = e })
    end
    table.sort(list, function(a, b)
        return a.e.displayName < b.e.displayName
    end)

    local hasData = #list > 0
    if noDataLabel then noDataLabel.Visible = not hasData end

    local y = 0
    for _, item in ipairs(list) do
        local id  = item.id
        local e   = item.e
        local row = ensureBossRow(id, e.displayName)

        row.row.Position = UDim2.fromOffset(0, y)
        y = y + 25

        if e.isAlive then
            row.dot.TextColor3   = C.alive
            row.timerL.Text      = "ALIVE"
            row.timerL.TextColor3 = C.aliveText
        elseif e.isRotationWaiting then
            row.dot.TextColor3    = C.yellow
            row.timerL.Text       = "Rotasi..."
            row.timerL.TextColor3 = C.yellow
        else
            local spawning = e.timer <= 0
            row.dot.TextColor3    = spawning and C.green or C.deadDot
            row.timerL.Text       = formatTimer(e.timer)
            row.timerL.TextColor3 = spawning and C.spawning or C.timerText
        end
    end

    -- Resize container agar pas dengan jumlah row
    if bossRowContainer then
        bossRowContainer.Size = UDim2.new(1, 0, 0, math.max(y, 22))
    end
end

----------------------------------------------------------------
-- CREATE UI
----------------------------------------------------------------
local fpsLabel, pingLabel, cpuLabel

local PANEL_W = 238

local function createUI()
    gui = Instance.new("ScreenGui")
    gui.Name          = HttpService:GenerateGUID(false)
    gui.ResetOnSpawn  = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent        = GetHiddenContainer()
    if _G._NEXTHUB and _G._NEXTHUB.instances then
        table.insert(_G._NEXTHUB.instances, gui)
    end

    ----------------------------------------------------------------
    -- MAIN FRAME (AutomaticSize Y agar menyesuaikan boss count)
    ----------------------------------------------------------------
    mainFrame = Instance.new("Frame", gui)
    mainFrame.Name              = "StatsFrame"
    mainFrame.Size              = UDim2.fromOffset(PANEL_W, 10)
    mainFrame.AutomaticSize     = Enum.AutomaticSize.Y
    mainFrame.AnchorPoint       = Vector2.new(1, 1)
    mainFrame.Position          = UDim2.fromScale(1, 1) - UDim2.fromOffset(38, 165)
    mainFrame.BackgroundColor3  = C.bg
    mainFrame.BackgroundTransparency = 0.12
    mainFrame.BorderSizePixel   = 0
    mainFrame.ClipsDescendants  = false

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", mainFrame)
    stroke.Thickness    = 1.5
    stroke.Transparency = 0.3
    stroke.Color        = C.border

    -- Layout vertical otomatis
    local layout = Instance.new("UIListLayout", mainFrame)
    layout.SortOrder   = Enum.SortOrder.LayoutOrder
    layout.Padding     = UDim.new(0, 0)

    ----------------------------------------------------------------
    -- PADDING TOP
    ----------------------------------------------------------------
    local padTop = mkFrame(mainFrame, UDim2.fromOffset(0,0), UDim2.new(1,0,0,10))
    padTop.LayoutOrder = 0

    ----------------------------------------------------------------
    -- TITLE ROW
    ----------------------------------------------------------------
    local titleRow = mkFrame(mainFrame,
        UDim2.fromOffset(0,0), UDim2.new(1,0,0,22))
    titleRow.LayoutOrder = 1

    mkLabel(titleRow,
        UDim2.fromOffset(14, 2), UDim2.new(1,-28,1,0),
        "✦  Nexthub Stats", 13, C.title)

    ----------------------------------------------------------------
    -- DIVIDER
    ----------------------------------------------------------------
    local div1Row = mkFrame(mainFrame, UDim2.fromOffset(0,0), UDim2.new(1,0,0,10))
    div1Row.LayoutOrder = 2
    mkDivider(div1Row, 5)

    ----------------------------------------------------------------
    -- STATS ROW: FPS | Ping | CPU
    ----------------------------------------------------------------
    local statsRow = mkFrame(mainFrame,
        UDim2.fromOffset(0,0), UDim2.new(1,0,0,36))
    statsRow.LayoutOrder = 3

    local colW = math.floor(PANEL_W / 3)

    -- FPS
    local fpsBox = mkFrame(statsRow,
        UDim2.fromOffset(4, 4),
        UDim2.fromOffset(colW - 6, 28),
        C.bgRow, 0.5)
    Instance.new("UICorner", fpsBox).CornerRadius = UDim.new(0, 6)

    mkLabel(fpsBox,
        UDim2.fromOffset(0,2), UDim2.new(1,0,0,11),
        "FPS", 9, C.subtitle, Enum.TextXAlignment.Center)
    fpsLabel = mkLabel(fpsBox,
        UDim2.fromOffset(0,13), UDim2.new(1,0,0,13),
        "--", 13, C.blue, Enum.TextXAlignment.Center)

    -- Ping
    local pingBox = mkFrame(statsRow,
        UDim2.fromOffset(colW + 2, 4),
        UDim2.fromOffset(colW - 4, 28),
        C.bgRow, 0.5)
    Instance.new("UICorner", pingBox).CornerRadius = UDim.new(0, 6)

    mkLabel(pingBox,
        UDim2.fromOffset(0,2), UDim2.new(1,0,0,11),
        "PING", 9, C.subtitle, Enum.TextXAlignment.Center)
    pingLabel = mkLabel(pingBox,
        UDim2.fromOffset(0,13), UDim2.new(1,0,0,13),
        "--", 13, C.blue, Enum.TextXAlignment.Center)

    -- CPU
    local cpuBox = mkFrame(statsRow,
        UDim2.fromOffset(colW * 2, 4),
        UDim2.fromOffset(colW - 4, 28),
        C.bgRow, 0.5)
    Instance.new("UICorner", cpuBox).CornerRadius = UDim.new(0, 6)

    mkLabel(cpuBox,
        UDim2.fromOffset(0,2), UDim2.new(1,0,0,11),
        "CPU", 9, C.subtitle, Enum.TextXAlignment.Center)
    cpuLabel = mkLabel(cpuBox,
        UDim2.fromOffset(0,13), UDim2.new(1,0,0,13),
        "--", 13, C.blue, Enum.TextXAlignment.Center)

    ----------------------------------------------------------------
    -- DIVIDER
    ----------------------------------------------------------------
    local div2Row = mkFrame(mainFrame, UDim2.fromOffset(0,0), UDim2.new(1,0,0,10))
    div2Row.LayoutOrder = 4
    mkDivider(div2Row, 5)

    ----------------------------------------------------------------
    -- BOSS TIMER HEADER
    ----------------------------------------------------------------
    local bossHeader = mkFrame(mainFrame,
        UDim2.fromOffset(0,0), UDim2.new(1,0,0,20))
    bossHeader.LayoutOrder = 5

    mkLabel(bossHeader,
        UDim2.fromOffset(14,3), UDim2.new(1,-28,1,0),
        "⏱  Boss Spawn Timer", 11, C.subtitle)

    ----------------------------------------------------------------
    -- BOSS ROWS SECTION
    ----------------------------------------------------------------
    local bossSection = mkFrame(mainFrame,
        UDim2.fromOffset(0,0), UDim2.new(1,0,0,22))
    bossSection.AutomaticSize = Enum.AutomaticSize.Y
    bossSection.LayoutOrder   = 6

    bossRowContainer = mkFrame(bossSection,
        UDim2.fromOffset(8, 0),
        UDim2.new(1, -16, 0, 22))
    bossRowContainer.AutomaticSize = Enum.AutomaticSize.Y

    -- Label saat belum ada data
    noDataLabel = mkLabel(bossRowContainer,
        UDim2.fromOffset(0, 4),
        UDim2.new(1, 0, 0, 16),
        "Menunggu data timer...", 10, C.dimText,
        Enum.TextXAlignment.Center)

    ----------------------------------------------------------------
    -- PADDING BOTTOM
    ----------------------------------------------------------------
    local padBot = mkFrame(mainFrame, UDim2.fromOffset(0,0), UDim2.new(1,0,0,10))
    padBot.LayoutOrder = 7

    ----------------------------------------------------------------
    -- DRAG (titleRow sebagai handle)
    ----------------------------------------------------------------
    local dragging, dragStart, startPos = false, nil, nil

    connect(mainFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = i.Position
            startPos  = mainFrame.Position
        end
    end))
    connect(mainFrame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    connect(UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - dragStart
            mainFrame.Position = startPos + UDim2.fromOffset(d.X, d.Y)
        end
    end))

    ----------------------------------------------------------------
    -- UPDATE LOOPS
    ----------------------------------------------------------------

    -- FPS: sample tiap frame, tampil tiap 0.2 detik
    local fpsAcc = 0
    connect(RunService.RenderStepped:Connect(function(dt)
        sampleFPS()
        fpsAcc = fpsAcc + dt
        if fpsAcc < 0.2 then return end
        fpsAcc = 0
        local fps = cachedFPS
        fpsLabel.Text = fps
        local col = fps >= 55 and C.green
                 or fps >= 40 and C.yellow
                 or fps >= 25 and C.orange
                 or C.red
        tw(fpsLabel, { TextColor3 = col })
    end))

    -- Ping + CPU: tiap 0.5 detik
    local statAcc = 0
    connect(RunService.Heartbeat:Connect(function(dt)
        statAcc = statAcc + dt
        if statAcc < 0.5 then return end
        statAcc = 0

        -- Ping
        local ping = getRealPing()
        pingLabel.Text = ping .. "ms"
        local pc = ping <= 60  and C.green
                or ping <= 120 and C.yellow
                or ping <= 200 and C.orange
                or C.red
        tw(pingLabel, { TextColor3 = pc })

        -- CPU
        local cpu = getCPU()
        cpuLabel.Text = cpu .. "ms"
        local cc = cpu <= 5  and C.green
                or cpu <= 12 and C.yellow
                or cpu <= 25 and C.orange
                or C.red
        tw(cpuLabel, { TextColor3 = cc })
    end))

    -- Boss timers: refresh tampilan tiap 0.5 detik
    local bossAcc = 0
    connect(RunService.Heartbeat:Connect(function(dt)
        bossAcc = bossAcc + dt
        if bossAcc < 0.5 then return end
        bossAcc = 0
        updateBossRows()
    end))
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function StatsPanel.Enable()
    if enabled then return end
    enabled = true
    hookBossTimers()
    createUI()
end

function StatsPanel.Disable()
    if not enabled then return end
    enabled = false
    disconnectAll()
    bossTimers   = {}
    bossRowItems = {}
    timerAccum   = 0
    if gui then
        gui:Destroy()
        gui, mainFrame = nil, nil
    end
end

_G.StatsPanel = StatsPanel
return StatsPanel