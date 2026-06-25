----------------------------------------------------------------
-- ANIMATION SWAP MODULE
----------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationSwap = {}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local state = {
    enabled   = false,
    targetRod = nil,
}

local _AnimController    = nil
local _FishingController = nil
local _AnimationsData    = nil
local _VFXController     = nil

local origGetAnimData = nil
local origVFXHandle   = nil
local cbProxyMeta     = nil

----------------------------------------------------------------
-- RESOLVE MODULES
----------------------------------------------------------------
local function getAnimController()
    if _AnimController then return _AnimController end
    pcall(function() _AnimController = require(ReplicatedStorage.Controllers.AnimationController) end)
    return _AnimController
end

local function getFishingController()
    if _FishingController then return _FishingController end
    pcall(function() _FishingController = require(ReplicatedStorage.Controllers.FishingController) end)
    return _FishingController
end

local function getAnimationsData()
    if _AnimationsData then return _AnimationsData end
    pcall(function() _AnimationsData = require(ReplicatedStorage.Modules.Animations) end)
    return _AnimationsData
end

local function getVFXController()
    if _VFXController then return _VFXController end
    pcall(function() _VFXController = require(ReplicatedStorage.Controllers.VFXController) end)
    return _VFXController
end

----------------------------------------------------------------
-- ROD LIST
----------------------------------------------------------------
local ANIM_TYPES = {
    "EquipIdle", "RodThrow", "FishCaught", "ReelingIdle",
    "ReelStart", "ReelIntermission", "StartRodCharge", "LoopedRodCharge",
}

function AnimationSwap.GetRodList()
    local data = getAnimationsData()
    if not data then return {} end
    local rodSet = {}
    for key in pairs(data) do
        for _, t in ipairs(ANIM_TYPES) do
            local suffix = " - " .. t
            if key:sub(-#suffix) == suffix then
                rodSet[key:sub(1, #key - #suffix)] = true
                break
            end
        end
    end
    local list = {}
    for name in pairs(rodSet) do table.insert(list, name) end
    table.sort(list)
    return list
end

function AnimationSwap.SetTargetRod(r) state.targetRod = r end
function AnimationSwap.GetTargetRod() return state.targetRod end
function AnimationSwap.IsActive() return state.enabled end

local function hookGetAnimationData()
    local ctrl = getAnimController()
    if not ctrl or origGetAnimData then return end

    origGetAnimData = ctrl.GetAnimationData
    ctrl.GetAnimationData = function(self, animName)
        if not state.enabled or not state.targetRod then
            return origGetAnimData(self, animName)
        end

        local data = getAnimationsData()
        if not data then return origGetAnimData(self, animName) end

        local matchedType = nil
        for _, animType in ipairs(ANIM_TYPES) do
            local suffix = " - " .. animType
            if animName:sub(-#suffix) == suffix or animName == animType then
                matchedType = animType
                break
            end
        end

        if matchedType then
            local targetKey = state.targetRod .. " - " .. matchedType
            local d = data[targetKey]
            if d and not d.Disabled then
                return d, targetKey
            end
        end

        return origGetAnimData(self, animName)
    end
end

local function findRodEffectCallbacks(fishing)
    if not fishing then return nil, nil end
    local possibleKeys = {
        "RodEffectCallbacks", "_rodEffectCallbacks",
        "RodEffects", "EffectCallbacks",
    }
    for _, k in ipairs(possibleKeys) do
        if type(fishing[k]) == "table" then
            return fishing[k], k
        end
    end
    return nil, nil
end

local function hookRodEffectCallbacks()
    local fishing = getFishingController()
    if not fishing or cbProxyMeta then return end

    local callbacks, _ = findRodEffectCallbacks(fishing)
    if not callbacks then
        return
    end

    cbProxyMeta = {}
    cbProxyMeta.__index = function(t, rodName)
        if state.enabled and state.targetRod then
            local targetTable = rawget(t, state.targetRod)
            if targetTable then return targetTable end
        end
        return rawget(t, rodName)
    end
    setmetatable(callbacks, cbProxyMeta)
end

local function hookVFXHandle()
    local vfx = getVFXController()
    if not vfx or origVFXHandle then return end

    origVFXHandle = vfx.Handle

    local RodThrowVFXData = nil
    pcall(function()
        RodThrowVFXData = require(ReplicatedStorage.Shared.RodThrowVFXData)
    end)

    vfx.Handle = function(vfxKey, targetArg)
        if not state.enabled or not state.targetRod or not RodThrowVFXData then
            return origVFXHandle(vfxKey, targetArg)
        end

        local target = state.targetRod
        for key, _ in pairs(RodThrowVFXData) do
            if type(key) == "string" and key:find(target, 1, true) then
                return origVFXHandle(key, targetArg)
            end
        end

        return origVFXHandle(vfxKey, targetArg)
    end
end

local function unhookAll()
    local ctrl = getAnimController()
    if ctrl and origGetAnimData then
        ctrl.GetAnimationData = origGetAnimData
        origGetAnimData = nil
    end

    local vfx = getVFXController()
    if vfx and origVFXHandle then
        vfx.Handle = origVFXHandle
        origVFXHandle = nil
    end

    if cbProxyMeta then
        local fishing = getFishingController()
        if fishing then
            local callbacks, _ = findRodEffectCallbacks(fishing)
            if callbacks then
                setmetatable(callbacks, nil)
            end
        end
        cbProxyMeta = nil
    end
end

----------------------------------------------------------------
-- ENABLE / DISABLE
----------------------------------------------------------------
function AnimationSwap.Enable()
    if state.enabled then return end
    state.enabled = true
    hookGetAnimationData()
    hookRodEffectCallbacks()
    hookVFXHandle()
end

function AnimationSwap.Disable()
    if not state.enabled then return end
    state.enabled = false
    unhookAll()
end

return AnimationSwap