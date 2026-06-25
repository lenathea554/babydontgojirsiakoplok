----------------------------------------------------------------
-- DISABLE FISHING EFFECT
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerConn(conn)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, conn)
    end
end

-- ================================================================
-- DATA
-- ================================================================
local KEYWORDS = {
    "fish", "fishing", "rod", "cast",
    "hook", "reel",    "bite", "splash", "storm",
}

local VFX = ReplicatedStorage:WaitForChild("VFX")

-- ================================================================
-- STATE
-- ================================================================
local DisableFishingEffect = {}

local state = {
    enabled = false,
    conn    = nil,
}

-- ================================================================
-- INTERNAL HELPERS
-- ================================================================
local function isFishingEffect(obj)
    local name = obj.Name:lower()
    for _, k in ipairs(KEYWORDS) do
        if name:find(k, 1, true) then
            return true
        end
    end
    return false
end

local function killEffect(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
        obj.Enabled = false
    elseif obj:IsA("BasePart") then
        obj.Transparency = 1
        obj.CanCollide   = false
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        obj.Transparency = 1
    elseif obj:IsA("Sound") then
        obj.Volume = 0
    end
end

local function process(obj)
    if not state.enabled then return end
    if isFishingEffect(obj) then killEffect(obj) end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function DisableFishingEffect.Start()
    if state.enabled then return end
    state.enabled = true

    for _, obj in ipairs(VFX:GetDescendants()) do
        process(obj)
    end

    state.conn = VFX.DescendantAdded:Connect(process)
    registerConn(state.conn)
end

function DisableFishingEffect.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.conn then
        pcall(function() state.conn:Disconnect() end)
        state.conn = nil
    end
end

function DisableFishingEffect.IsEnabled()
    return state.enabled
end

return DisableFishingEffect