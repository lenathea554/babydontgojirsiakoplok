----------------------------------------------------------------
-- BOOST FPS MODULE
----------------------------------------------------------------
local Lighting  = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local BoostFPS = {}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local currentMode = "Low"
local addConn = nil

----------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------
local function disconnectAddConn()
    if addConn then
        pcall(function() addConn:Disconnect() end)
        addConn = nil
    end
end

----------------------------------------------------------------
-- LOW
----------------------------------------------------------------
local function applyLow()
    disconnectAddConn()

    Lighting.GlobalShadows = false

    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
            v.Enabled = false
        end
    end
end

----------------------------------------------------------------
-- MEDIUM
----------------------------------------------------------------
local function applyMedium()
    disconnectAddConn()

    Lighting.GlobalShadows = false
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0

    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") then fx.Enabled = false end
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter")
        or v:IsA("Trail")
        or v:IsA("Beam")
        or v:IsA("Smoke")
        or v:IsA("Fire") then
            v.Enabled = false
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1
        end
    end
end

----------------------------------------------------------------
-- EXTREME
----------------------------------------------------------------
local function applyExtreme()
    disconnectAddConn()

    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.Brightness = 1
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") then fx:Destroy() end
    end

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        terrain.WaterWaveSize     = 0
        terrain.WaterWaveSpeed    = 0
        terrain.WaterReflectance  = 0
        terrain.WaterTransparency = 1
        terrain.Decoration        = false
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter")
        or v:IsA("Trail")
        or v:IsA("Beam")
        or v:IsA("Smoke")
        or v:IsA("Fire")
        or v:IsA("Sparkles")
        or v:IsA("Decal")
        or v:IsA("Texture")
        or v:IsA("BillboardGui")
        or v:IsA("SurfaceGui")
        or v:IsA("Highlight")
        or v:IsA("SelectionBox")
        or v:IsA("SelectionSphere") then
            v:Destroy()
        elseif v:IsA("BasePart") then
            v.CastShadow   = false
            v.Material     = Enum.Material.Plastic
            v.Reflectance  = 0
            v.TopSurface   = Enum.SurfaceType.Smooth
            v.BottomSurface = Enum.SurfaceType.Smooth
            v.LeftSurface  = Enum.SurfaceType.Smooth
            v.RightSurface = Enum.SurfaceType.Smooth
            v.FrontSurface = Enum.SurfaceType.Smooth
            v.BackSurface  = Enum.SurfaceType.Smooth
        end
    end

    local CosmeticFolder = Workspace:FindFirstChild("CosmeticFolder")

    addConn = Workspace.DescendantAdded:Connect(function(obj)
        if currentMode ~= "Extreme" then return end

        local parent = obj.Parent
        while parent and parent ~= Workspace do
            if parent == CosmeticFolder then return end
            parent = parent.Parent
        end

        if obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("Smoke")
        or obj:IsA("Fire")
        or obj:IsA("Sparkles")
        or obj:IsA("Decal")
        or obj:IsA("Texture")
        or obj:IsA("BillboardGui")
        or obj:IsA("SurfaceGui")
        or obj:IsA("Highlight")
        or obj:IsA("SelectionBox")
        or obj:IsA("SelectionSphere") then
            task.defer(function()
                if obj.Parent then obj:Destroy() end
            end)
        elseif obj:IsA("BasePart") then
            obj.CastShadow  = false
            obj.Material    = Enum.Material.Plastic
            obj.Reflectance = 0
        end
    end)

    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, addConn)
    end
end

----------------------------------------------------------------
-- EXTREME+
----------------------------------------------------------------
local function applyExtremePlus()
    disconnectAddConn()

    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0

    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") then fx:Destroy() end
    end

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        terrain.WaterWaveSize     = 0
        terrain.WaterWaveSpeed    = 0
        terrain.WaterReflectance  = 0
        terrain.WaterTransparency = 1
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter")
        or v:IsA("Trail")
        or v:IsA("Beam")
        or v:IsA("Smoke")
        or v:IsA("Fire")
        or v:IsA("Sparkles")
        or v:IsA("Decal")
        or v:IsA("Texture") then
            v:Destroy()
        elseif v:IsA("BasePart") then
            v.CastShadow  = false
            v.Material    = Enum.Material.Plastic
            v.Reflectance = 0
        end
    end

    local CosmeticFolder = Workspace:FindFirstChild("CosmeticFolder")

    addConn = Workspace.DescendantAdded:Connect(function(obj)
        if currentMode ~= "Extreme+" then return end

        local parent = obj.Parent
        while parent and parent ~= Workspace do
            if parent == CosmeticFolder then return end
            parent = parent.Parent
        end

        if obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("Smoke")
        or obj:IsA("Fire")
        or obj:IsA("Sparkles")
        or obj:IsA("Decal")
        or obj:IsA("Texture") then
            task.defer(function()
                if obj.Parent then obj:Destroy() end
            end)
        elseif obj:IsA("BasePart") then
            obj.CastShadow  = false
            obj.Material    = Enum.Material.Plastic
            obj.Reflectance = 0
        end
    end)

    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, addConn)
    end
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function BoostFPS.SetMode(mode)
    if mode == "Low" or mode == "Medium" or mode == "Extreme" or mode == "Extreme+" then
        currentMode = mode
    end
end

function BoostFPS.Apply()
    if     currentMode == "Low"      then applyLow()
    elseif currentMode == "Medium"   then applyMedium()
    elseif currentMode == "Extreme"  then applyExtreme()
    elseif currentMode == "Extreme+" then applyExtremePlus()
    end
end

function BoostFPS.GetModes()
    return {"Low", "Medium", "Extreme", "Extreme+"}
end

function BoostFPS.GetMode()
    return currentMode
end

return BoostFPS