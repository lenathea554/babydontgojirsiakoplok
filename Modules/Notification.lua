----------------------------------------------------------------
-- NOTIFICATION MODULE
----------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer

local Notifier = {}

local STACK = {}
local GAP = 10
local BASE_OFFSET = Vector2.new(40, 40)
local SIZE = Vector2.new(320, 65)

local function relayout()
    for i,frame in ipairs(STACK) do
        TweenService:Create(frame, TweenInfo.new(0.25), {
            Position = UDim2.fromScale(1,1)
                - UDim2.fromOffset(BASE_OFFSET.X, BASE_OFFSET.Y + (i-1)*(SIZE.Y+GAP))
        }):Play()
    end
end

function Notifier.Notify(context, duration)
    duration = duration or 2

    local gui = Instance.new("ScreenGui")
    gui.Name = HttpService:GenerateGUID(false)
    gui.ResetOnSpawn = false
    gui.Parent = LP.PlayerGui

    local frame = Instance.new("Frame", gui)
    frame.Size = UDim2.fromOffset(SIZE.X, SIZE.Y)
    frame.AnchorPoint = Vector2.new(1,1)
    frame.Position = UDim2.fromScale(1,1)
        - UDim2.fromOffset(BASE_OFFSET.X, BASE_OFFSET.Y - 20)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,14)

    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(120,180,255)
    stroke.Transparency = 0.35
    stroke.Thickness = 1.3

    local title = Instance.new("TextLabel", frame)
    title.Position = UDim2.fromOffset(14,9)
    title.Size = UDim2.fromOffset(320,22)
    title.BackgroundTransparency = 1
    title.Text = "NextHub Notifier"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(190,220,255)

    local text = Instance.new("TextLabel", frame)
    text.Position = UDim2.fromOffset(15,34)
    text.Size = UDim2.fromOffset(330,34)
    text.BackgroundTransparency = 1
    text.TextWrapped = true
    text.TextYAlignment = Enum.TextYAlignment.Top
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.Text = context or ""
    text.Font = Enum.Font.Gotham
    text.TextSize = 14
    text.TextColor3 = Color3.fromRGB(210,230,255)

    table.insert(STACK, 1, frame)
    relayout()

    TweenService:Create(frame, TweenInfo.new(0.25), {
        BackgroundTransparency = 0.25,
        Position = UDim2.fromScale(1,1)
            - UDim2.fromOffset(BASE_OFFSET.X, BASE_OFFSET.Y)
    }):Play()

    table.insert(_G._NEXTHUB.instances, gui)

    task.delay(duration, function()
        for i,v in ipairs(STACK) do
            if v == frame then
                table.remove(STACK, i)
                break
            end
        end

        TweenService:Create(frame, TweenInfo.new(0.25), {
            BackgroundTransparency = 1,
            Position = frame.Position + UDim2.fromOffset(0,20)
        }):Play()

        task.wait(0.3)
        gui:Destroy()
        relayout()
    end)
end

return Notifier