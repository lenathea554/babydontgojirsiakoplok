-- ================================================================
-- SKIN CHANGER MODULE
-- Copy karakter player lain semirip mungkin (client-side)
--
-- FIX: ApplyDescription() hanya bisa dipanggil server-side.
--      Solusi: manipulasi appearance langsung di karakter lokal —
--      clone accessories, ganti Shirt/Pants/ShirtGraphic,
--      salin BodyColors, dan terapkan skin color ke setiap BasePart.
--      Hasilnya identik secara visual dengan karakter target.
-- ================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")

local LP = Players.LocalPlayer

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
-- MODULE STATE
-- ================================================================
local SkinChanger = {
    Applied        = false,
    _loopThread    = nil,
    _originalData  = nil,  -- snapshot penampilan asli
    _targetData    = nil,  -- data target yang sedang dipakai
}

-- ================================================================
-- HELPERS — ambil data penampilan dari karakter
-- ================================================================

-- Kumpulkan semua data visual dari karakter target secara langsung
local function collectAppearanceFromCharacter(targetChar)
    if not targetChar then return nil end

    local data = {
        accessories  = {},
        bodyColors   = nil,
        shirt        = nil,
        pants        = nil,
        shirtGraphic = nil,
        bodyParts    = {},  -- MeshPart / SpecialMesh pengganti body (R15)
    }

    for _, obj in ipairs(targetChar:GetDescendants()) do
        -- Accessories (hat, hair, face, dll.)
        if obj:IsA("Accessory") then
            table.insert(data.accessories, obj:Clone())

        -- BodyColors (warna kulit setiap bagian)
        elseif obj:IsA("BodyColors") then
            data.bodyColors = obj:Clone()

        -- Pakaian
        elseif obj:IsA("Shirt") then
            data.shirt = obj:Clone()
        elseif obj:IsA("Pants") then
            data.pants = obj:Clone()
        elseif obj:IsA("ShirtGraphic") then
            data.shirtGraphic = obj:Clone()
        end
    end

    -- Ambil warna & material setiap BasePart tubuh (untuk fallback skin color)
    local bodyPartNames = {
        "Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "RightUpperLeg", "RightLowerLeg", "RightFoot",
        -- R6
        "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    }
    for _, name in ipairs(bodyPartNames) do
        local part = targetChar:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            data.bodyParts[name] = {
                Color    = part.Color,
                Material = part.Material,
            }
        end
    end

    return data
end

-- Kumpulkan data penampilan via HumanoidDescription (untuk UserId lookup)
-- Karena kita tidak bisa ApplyDescription, kita ekstrak properti yang
-- bisa kita terapkan manual: warna kulit (HeadColor, dll.)
local function collectAppearanceFromDescription(desc)
    if not desc then return nil end

    local data = {
        accessories  = {},
        bodyColors   = nil,
        shirt        = nil,
        pants        = nil,
        shirtGraphic = nil,
        bodyParts    = {},
    }

    -- Buat BodyColors dari desc
    local bc = Instance.new("BodyColors")
    bc.HeadColor3        = desc.HeadColor
    bc.TorsoColor3       = desc.TorsoColor
    bc.LeftArmColor3     = desc.LeftArmColor
    bc.RightArmColor3    = desc.RightArmColor
    bc.LeftLegColor3     = desc.LeftLegColor
    bc.RightLegColor3    = desc.RightLegColor
    data.bodyColors = bc

    -- Shirt & Pants via assetId
    if desc.Shirt and desc.Shirt ~= 0 then
        local s = Instance.new("Shirt")
        s.ShirtTemplate = "rbxassetid://" .. desc.Shirt
        data.shirt = s
    end
    if desc.Pants and desc.Pants ~= 0 then
        local p = Instance.new("Pants")
        p.PantsTemplate = "rbxassetid://" .. desc.Pants
        data.pants = p
    end
    if desc.GraphicTShirt and desc.GraphicTShirt ~= 0 then
        local sg = Instance.new("ShirtGraphic")
        sg.Graphic = "rbxassetid://" .. desc.GraphicTShirt
        data.shirtGraphic = sg
    end

    -- Accessories dari desc (array of {AssetId, AccessoryType})
    -- Kita tidak bisa clone Instance dari desc, tapi kita bisa buat Accessory
    -- dengan InsertService — namun itu async dan mungkin gagal.
    -- Untuk UserId lookup, kita skip accessories dan hanya terapkan warna + pakaian.
    -- Accessories tetap bisa diterapkan jika target ada di server (via collectAppearanceFromCharacter).

    return data
end

-- ================================================================
-- TERAPKAN DATA KE KARAKTER LOKAL
-- ================================================================
local function applyAppearanceData(data)
    local char = LP.Character
    if not char then return false end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    -- 1. Hapus accessories lama
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Accessory") then
            obj:Destroy()
        end
    end

    -- 2. Hapus pakaian lama
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
            obj:Destroy()
        end
    end

    -- 3. Hapus BodyColors lama
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("BodyColors") then
            obj:Destroy()
        end
    end

    -- 4. Pasang accessories baru (clone agar tidak ter-consume)
    for _, acc in ipairs(data.accessories) do
        local cloned = acc:Clone()
        cloned.Parent = char
    end

    -- 5. Pasang BodyColors
    if data.bodyColors then
        local bc = data.bodyColors:Clone()
        bc.Parent = char

        -- Terapkan warna ke setiap BasePart tubuh secara eksplisit
        -- agar benar-benar identik (beberapa game override BodyColors)
        local partColorMap = {
            Head          = bc.HeadColor3,
            UpperTorso    = bc.TorsoColor3,
            LowerTorso    = bc.TorsoColor3,
            Torso         = bc.TorsoColor3,
            LeftUpperArm  = bc.LeftArmColor3,
            LeftLowerArm  = bc.LeftArmColor3,
            LeftHand      = bc.LeftArmColor3,
            ["Left Arm"]  = bc.LeftArmColor3,
            RightUpperArm = bc.RightArmColor3,
            RightLowerArm = bc.RightArmColor3,
            RightHand     = bc.RightArmColor3,
            ["Right Arm"] = bc.RightArmColor3,
            LeftUpperLeg  = bc.LeftLegColor3,
            LeftLowerLeg  = bc.LeftLegColor3,
            LeftFoot      = bc.LeftLegColor3,
            ["Left Leg"]  = bc.LeftLegColor3,
            RightUpperLeg = bc.RightLegColor3,
            RightLowerLeg = bc.RightLegColor3,
            RightFoot     = bc.RightLegColor3,
            ["Right Leg"] = bc.RightLegColor3,
        }
        for partName, color in pairs(partColorMap) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                part.Color = color
            end
        end
    end

    -- 6. Terapkan warna body part eksplisit (dari collectAppearanceFromCharacter)
    if data.bodyParts then
        for partName, info in pairs(data.bodyParts) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                part.Color    = info.Color
                part.Material = info.Material
            end
        end
    end

    -- 7. Pasang pakaian
    if data.shirt then
        local s = data.shirt:Clone()
        s.Parent = char
    end
    if data.pants then
        local p = data.pants:Clone()
        p.Parent = char
    end
    if data.shirtGraphic then
        local sg = data.shirtGraphic:Clone()
        sg.Parent = char
    end

    return true
end

-- ================================================================
-- SNAPSHOT PENAMPILAN ASLI
-- ================================================================
local function snapshotOriginal()
    if SkinChanger._originalData then return end
    local char = LP.Character
    if not char then return end
    -- Kumpulkan penampilan saat ini sebagai data asli
    SkinChanger._originalData = collectAppearanceFromCharacter(char)
end

-- ================================================================
-- LOOP — reapply tiap beberapa detik agar tidak di-reset oleh game
-- ================================================================
local function stopLoop()
    if SkinChanger._loopThread then
        pcall(task.cancel, SkinChanger._loopThread)
        SkinChanger._loopThread = nil
    end
end

local function startLoop(data)
    SkinChanger._targetData = data
    SkinChanger.Applied = true

    stopLoop()
    SkinChanger._loopThread = task.spawn(function()
        while SkinChanger.Applied do
            pcall(applyAppearanceData, SkinChanger._targetData)
            task.wait(5)
        end
    end)
    registerTask(SkinChanger._loopThread)
end

-- ================================================================
-- CHARACTER ADDED — reapply setelah respawn
-- ================================================================
registerConn(LP.CharacterAdded:Connect(function()
    task.wait(2)
    if SkinChanger.Applied and SkinChanger._targetData then
        pcall(applyAppearanceData, SkinChanger._targetData)
    end
end))

-- ================================================================
-- PUBLIC API
-- ================================================================
function SkinChanger.GetPlayerList()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            table.insert(list, p.Name)
        end
    end
    table.sort(list)
    return list
end

-- Apply skin dari player yang ada di server (by name)
-- Ini metode paling akurat karena bisa clone accessories langsung
function SkinChanger.ApplyFromPlayer(playerName)
    snapshotOriginal()

    local targetPlayer = Players:FindFirstChild(playerName)
    if not targetPlayer then
        warn("[SkinChanger] Player not found:", playerName)
        return false
    end

    -- Coba dari karakter di Workspace (paling akurat, accessories included)
    local data = collectAppearanceFromCharacter(targetPlayer.Character)

    -- Fallback: gunakan HumanoidDescription (accessories tidak bisa di-clone,
    -- tapi warna & pakaian tetap bisa diterapkan)
    if not data or (not data.bodyColors and #data.accessories == 0) then
        local ok, desc = pcall(function()
            local hum = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            return hum and hum:GetAppliedDescription()
        end)
        if ok and desc then
            data = collectAppearanceFromDescription(desc)
        end
    end

    if not data then
        warn("[SkinChanger] Could not collect appearance for:", playerName)
        return false
    end

    local ok = pcall(applyAppearanceData, data)
    if ok then startLoop(data) end
    return ok
end

-- Apply skin dari UserId (input manual)
-- Catatan: accessories tidak tersedia via metode ini karena
-- GetHumanoidDescriptionFromUserId tidak mengembalikan Instance.
-- Warna kulit dan pakaian tetap diterapkan secara akurat.
function SkinChanger.ApplyFromUserId(userId)
    local id = tonumber(userId)
    if not id then
        warn("[SkinChanger] Invalid UserId:", userId)
        return false
    end

    snapshotOriginal()

    local ok, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(id)
    end)
    if not ok or not desc then
        warn("[SkinChanger] Could not get description for UserId:", id)
        return false
    end

    local data = collectAppearanceFromDescription(desc)
    if not data then
        warn("[SkinChanger] Could not build appearance data for UserId:", id)
        return false
    end

    local applied = pcall(applyAppearanceData, data)
    if applied then startLoop(data) end
    return applied
end

-- Kembalikan ke karakter asli
function SkinChanger.Restore()
    stopLoop()
    SkinChanger.Applied     = false
    SkinChanger._targetData = nil

    if SkinChanger._originalData then
        pcall(applyAppearanceData, SkinChanger._originalData)
        SkinChanger._originalData = nil
    end
end

return SkinChanger