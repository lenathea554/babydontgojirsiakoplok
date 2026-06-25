-- ================================================================
-- HIDE IDENTIFIER MODULE  (v2 - fixed)
-- ================================================================

local Players    = game:GetService("Players")

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

local LP = Players.LocalPlayer

-- ================================================================
-- MODULE STATE
-- ================================================================
local HideIdentifier = {
    Enabled       = false,
    CustomName    = "",
    CustomLevel   = "",
    _loopThread   = nil,
    _overhead     = nil,

    _defaults     = nil,

    _titleContainer = nil,
    _titleLabel     = nil,
    _titleGradient  = nil,

    _originalDisplayName = nil,
}

-- ================================================================
-- OVERHEAD RESOLVER
-- ================================================================
local function resolveOverhead()
    if HideIdentifier._overhead and HideIdentifier._overhead.Parent then
        return HideIdentifier._overhead
    end

    local char = LP.Character
    if not char then return nil end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local overhead = hrp:FindFirstChild("Overhead")
    if not overhead then return nil end

    HideIdentifier._overhead = overhead
    return overhead
end

-- ================================================================
-- SNAPSHOT DEFAULTS
-- ================================================================
local function snapshotDefaults(overhead)
    if HideIdentifier._defaults then return end

    local content    = overhead:FindFirstChild("Content")
    local header     = content and content:FindFirstChild("Header")
    local lc         = overhead:FindFirstChild("LevelContainer")
    local levelLabel = lc and lc:FindFirstChild("Label")

    if not (header and levelLabel) then return end

    HideIdentifier._defaults = {
        headerText = header.Text,
        levelText  = levelLabel.Text,
    }
end

-- ================================================================
-- TITLECONTAINER BUILDER
-- ================================================================
local function buildTitleContainer(overhead)
    local existing = HideIdentifier._titleContainer
    if existing and existing.Parent == overhead then
        return existing, HideIdentifier._titleLabel, HideIdentifier._titleGradient
    end

    local content = overhead:FindFirstChild("Content")
    if not content then return nil, nil, nil end

    local tc = Instance.new("Frame")
    tc.Name             = "TitleContainer"
    tc.BackgroundTransparency = 1
    tc.Size             = UDim2.new(1, 0, 0, 20)
    tc.Position         = UDim2.new(
        content.Position.X.Scale,
        content.Position.X.Offset,
        content.Position.Y.Scale - 0.35,
        content.Position.Y.Offset
    )
    tc.ZIndex           = content.ZIndex + 1
    tc.Visible          = false
    tc.Parent           = overhead

    local lbl = Instance.new("TextLabel")
    lbl.Name                  = "Label"
    lbl.Size                  = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = "NextHub"
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 13
    lbl.TextColor3            = Color3.new(1, 1, 1)
    lbl.TextStrokeTransparency = 0.5
    lbl.TextXAlignment        = Enum.TextXAlignment.Center
    lbl.Parent                = tc

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(150, 80,  255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80,  180, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(120, 255, 220)),
    })
    grad.Rotation = 0
    grad.Parent   = lbl

    HideIdentifier._titleContainer = tc
    HideIdentifier._titleLabel     = lbl
    HideIdentifier._titleGradient  = grad

    return tc, lbl, grad
end

-- ================================================================
-- APPLY
-- ================================================================
local function applyToOverhead(overhead)
    snapshotDefaults(overhead)

    local content    = overhead:FindFirstChild("Content")
    local header     = content and content:FindFirstChild("Header")
    local lc         = overhead:FindFirstChild("LevelContainer")
    local levelLabel = lc and lc:FindFirstChild("Label")

    if not (header and levelLabel) then return end

    local tc, lbl, grad = buildTitleContainer(overhead)
    if tc then tc.Visible = true end

    if HideIdentifier.CustomName ~= "" then
        header.Text = HideIdentifier.CustomName
    end

    if HideIdentifier.CustomLevel ~= "" then
        levelLabel.Text = "Lvl. " .. HideIdentifier.CustomLevel
    end
end

-- ================================================================
-- RESTORE
-- ================================================================
local function restoreOverhead(overhead)
    local d = HideIdentifier._defaults
    if not d then return end

    local tc = HideIdentifier._titleContainer
    if tc and tc.Parent then
        tc.Visible = false
    end

    local content    = overhead:FindFirstChild("Content")
    local header     = content and content:FindFirstChild("Header")
    local lc         = overhead:FindFirstChild("LevelContainer")
    local levelLabel = lc and lc:FindFirstChild("Label")

    if header     then header.Text     = d.headerText end
    if levelLabel then levelLabel.Text = d.levelText  end
end

-- ================================================================
-- DISPLAY NAME SPOOF
-- ================================================================
local function applyDisplayName()
    if HideIdentifier.CustomName == "" then return end
    if sethiddenproperty then
        pcall(sethiddenproperty, LP, "DisplayName", HideIdentifier.CustomName)
    else
        pcall(function() LP.DisplayName = HideIdentifier.CustomName end)
    end
end

local function restoreDisplayName()
    local orig = HideIdentifier._originalDisplayName
    if not orig then return end
    if sethiddenproperty then
        pcall(sethiddenproperty, LP, "DisplayName", orig)
    else
        pcall(function() LP.DisplayName = orig end)
    end
end

-- ================================================================
-- MAIN LOOP
-- ================================================================
local function startLoop()
    if HideIdentifier._loopThread then
        pcall(task.cancel, HideIdentifier._loopThread)
    end

    if not HideIdentifier._originalDisplayName then
        HideIdentifier._originalDisplayName = LP.DisplayName
    end

    HideIdentifier._loopThread = task.spawn(function()
        while HideIdentifier.Enabled do
            local overhead = resolveOverhead()
            if overhead then
                pcall(applyToOverhead, overhead)
            end
            pcall(applyDisplayName)
            task.wait(0.3)
        end
    end)

    registerTask(HideIdentifier._loopThread)
end

local function stopLoop()
    if HideIdentifier._loopThread then
        pcall(task.cancel, HideIdentifier._loopThread)
        HideIdentifier._loopThread = nil
    end
end

-- ================================================================
-- CHARACTER ADDED
-- ================================================================
registerConn(LP.CharacterAdded:Connect(function()
    HideIdentifier._overhead        = nil
    HideIdentifier._defaults        = nil
    HideIdentifier._titleContainer  = nil
    HideIdentifier._titleLabel      = nil
    HideIdentifier._titleGradient   = nil

    if HideIdentifier.Enabled then
        task.wait(2)
        local deadline = os.clock() + 8
        while os.clock() < deadline do
            if resolveOverhead() then break end
            task.wait(0.5)
        end
    end
end))

-- ================================================================
-- PUBLIC API
-- ================================================================
function HideIdentifier.SetHeader(text)
    HideIdentifier.CustomName = tostring(text or "")
end

function HideIdentifier.SetLevel(text)
    local n = tonumber(text)
    HideIdentifier.CustomLevel = n and tostring(math.floor(n)) or tostring(text or "")
end

function HideIdentifier.Enable()
    if HideIdentifier.Enabled then return end
    HideIdentifier.Enabled = true

    if not resolveOverhead() then
        task.spawn(function()
            local deadline = os.clock() + 8
            while os.clock() < deadline do
                if resolveOverhead() then break end
                task.wait(0.5)
            end
            if HideIdentifier.Enabled then startLoop() end
        end)
    else
        startLoop()
    end
end

function HideIdentifier.Disable()
    if not HideIdentifier.Enabled then return end
    HideIdentifier.Enabled = false
    stopLoop()

    local overhead = resolveOverhead()
    if overhead then pcall(restoreOverhead, overhead) end
    pcall(restoreDisplayName)
end

task.spawn(function()
    task.wait(1)
    resolveOverhead()
end)

return HideIdentifier