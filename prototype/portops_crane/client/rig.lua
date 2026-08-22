-- S01 / PORT-011: canonical local crane rig state.
-- The rig owns transforms and entities only; it has no framework dependency.

PortOpsCrane = PortOpsCrane or {}
PortOpsCrane.Rig = PortOpsCrane.Rig or {}

local Rig = PortOpsCrane.Rig
local PARTS = { 'base', 'gantry', 'trolley', 'spreader' }
local EPSILON = 0.0001

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function number(value, fallback)
    return finite(value) and value or fallback
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, number(value, minimum)))
end

local function normalizedAxis(axis)
    local length = math.sqrt((axis.x * axis.x) + (axis.y * axis.y) + (axis.z * axis.z))
    return axis / length
end

local function vectorLength(axis)
    return math.sqrt((axis.x * axis.x) + (axis.y * axis.y) + (axis.z * axis.z))
end

local function dot(a, b)
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
end

local function cross(a, b)
    return vector3(
        (a.y * b.z) - (a.z * b.y),
        (a.z * b.x) - (a.x * b.z),
        (a.x * b.y) - (a.y * b.x)
    )
end

local function copyVector(value)
    return vector3(value.x, value.y, value.z)
end

local function copyState(state)
    local copy = {
        gantry = state.gantry,
        trolley = state.trolley,
        spreader = state.spreader
    }
    if state.yaw ~= nil then copy.yaw = state.yaw end
    return copy
end

local function copyAxes(axes)
    return {
        gantry = copyVector(axes.gantry),
        trolley = copyVector(axes.trolley),
        spreader = copyVector(axes.spreader)
    }
end

local function validateAxis(profile, name, axis)
    assert(axis and finite(axis.x) and finite(axis.y) and finite(axis.z),
        ('profile %s.axis must be a finite vector'):format(profile.id))
    local length = vectorLength(axis)
    assert(length > EPSILON, ('profile %s.%s.axis must be non-zero'):format(profile.id, name))
    assert(math.abs(length - 1.0) <= EPSILON,
        ('profile %s.%s.axis must be normalized (length %.6f)'):format(profile.id, name, length))
end

local function validateTravel(profile, name, spec)
    assert(spec and spec.axis, ('profile %s.%s is required'):format(profile.id, name))
    assert(finite(spec.min) and finite(spec.max) and spec.min < spec.max,
        ('profile %s.%s min/max are invalid'):format(profile.id, name))
    assert(finite(spec.maxSpeed) and spec.maxSpeed > 0.0,
        ('profile %s.%s.maxSpeed must be positive'):format(profile.id, name))
    assert(finite(spec.acceleration) and spec.acceleration > 0.0,
        ('profile %s.%s.acceleration must be positive'):format(profile.id, name))
    validateAxis(profile, name, spec.axis)
end

local function validateProfile(profile)
    assert(profile and type(profile.id) == 'string' and profile.id ~= '', 'crane profile id is required')
    assert(type(profile.version) == 'number' and profile.version > 0 and profile.version % 1 == 0,
        ('profile %s.version must be a positive integer'):format(profile.id))
    assert(profile.origin and finite(profile.origin.x) and finite(profile.origin.y) and finite(profile.origin.z),
        ('profile %s.origin must be a finite vector'):format(profile.id))
    validateTravel(profile, 'gantry', profile.gantry)
    validateTravel(profile, 'trolley', profile.trolley)
    validateTravel(profile, 'spreader', profile.spreader)

    local gantryAxis = normalizedAxis(profile.gantry.axis)
    local trolleyAxis = normalizedAxis(profile.trolley.axis)
    local spreaderAxis = normalizedAxis(profile.spreader.axis)
    assert(math.abs(dot(gantryAxis, trolleyAxis)) <= EPSILON
        and math.abs(dot(gantryAxis, spreaderAxis)) <= EPSILON
        and math.abs(dot(trolleyAxis, spreaderAxis)) <= EPSILON,
        ('profile %s axes must be orthogonal'):format(profile.id))
    assert(dot(cross(gantryAxis, trolleyAxis), spreaderAxis) > EPSILON,
        ('profile %s axes must be right-handed'):format(profile.id))

    if profile.yaw then
        assert(finite(profile.yaw.min) and finite(profile.yaw.max) and profile.yaw.min < profile.yaw.max,
            ('profile %s.yaw min/max are invalid'):format(profile.id))
        assert(finite(profile.yaw.maxSpeed) and profile.yaw.maxSpeed > 0.0,
            ('profile %s.yaw.maxSpeed must be positive'):format(profile.id))
        assert(finite(profile.yaw.acceleration) and profile.yaw.acceleration > 0.0,
            ('profile %s.yaw.acceleration must be positive'):format(profile.id))
    end

    local alignment = profile.alignment
    assert(alignment and finite(alignment.horizontalToleranceM) and alignment.horizontalToleranceM > 0.0,
        ('profile %s alignment horizontal tolerance is invalid'):format(profile.id))
    assert(finite(alignment.verticalToleranceM) and alignment.verticalToleranceM > 0.0,
        ('profile %s alignment vertical tolerance is invalid'):format(profile.id))
    assert(finite(alignment.yawToleranceDegrees) and alignment.yawToleranceDegrees > 0.0,
        ('profile %s alignment yaw tolerance is invalid'):format(profile.id))
end

local function lerp(spec, normalized)
    return spec.min + ((spec.max - spec.min) * clamp(normalized, 0.0, 1.0))
end

local function yawDegrees(profile, state)
    if not profile.yaw then return 0.0 end
    return lerp(profile.yaw, state.yaw or 0.5)
end

local function baseHeading(profile)
    return finite(profile.heading) and profile.heading or 0.0
end

local function axisHeading(profile, axis)
    local horizontalLength = math.sqrt((axis.x * axis.x) + (axis.y * axis.y))
    if horizontalLength <= EPSILON then return baseHeading(profile) end
    return baseHeading(profile) + math.deg(math.atan(axis.y, axis.x))
end

local function calculateTransforms(profile, state)
    local axes = {
        gantry = normalizedAxis(profile.gantry.axis),
        trolley = normalizedAxis(profile.trolley.axis),
        spreader = normalizedAxis(profile.spreader.axis)
    }
    local origin = profile.origin
    local gantryPoint = origin + axes.gantry * lerp(profile.gantry, state.gantry)
    local trolleyPoint = gantryPoint + axes.trolley * lerp(profile.trolley, state.trolley)
    local spreaderPoint = trolleyPoint + axes.spreader * lerp(profile.spreader, state.spreader)
    return {
        base = copyVector(origin),
        gantry = gantryPoint,
        trolley = trolleyPoint,
        spreader = spreaderPoint,
        axes = axes,
        heading = axisHeading(profile, profile.gantry.axis) + yawDegrees(profile, state)
    }
end

local function loadModel(modelName)
    local model = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        return nil, ('invalid model: %s'):format(tostring(modelName))
    end

    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do
        Wait(0)
    end
    if not HasModelLoaded(model) then
        return nil, ('model load timeout: %s'):format(tostring(modelName))
    end
    return model
end

local function releaseModel(model)
    if model then SetModelAsNoLongerNeeded(model) end
end

local function deleteEntity(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

local function applyTransforms(self)
    self.transforms = calculateTransforms(self.profile, self.state)
    local transforms = self.transforms
    local entities = self.entities

    if entities.base and DoesEntityExist(entities.base) then
        SetEntityCoordsNoOffset(entities.base, transforms.base.x, transforms.base.y, transforms.base.z, false, false, false)
        SetEntityHeading(entities.base, axisHeading(self.profile, self.profile.gantry.axis))
    end
    if entities.gantry and DoesEntityExist(entities.gantry) then
        SetEntityCoordsNoOffset(entities.gantry, transforms.gantry.x, transforms.gantry.y, transforms.gantry.z, false, false, false)
        SetEntityHeading(entities.gantry, axisHeading(self.profile, self.profile.gantry.axis))
    end
    if entities.trolley and DoesEntityExist(entities.trolley) then
        SetEntityCoordsNoOffset(entities.trolley, transforms.trolley.x, transforms.trolley.y, transforms.trolley.z, false, false, false)
        SetEntityHeading(entities.trolley, axisHeading(self.profile, self.profile.gantry.axis))
    end
    if entities.spreader and DoesEntityExist(entities.spreader) then
        SetEntityCoordsNoOffset(entities.spreader, transforms.spreader.x, transforms.spreader.y, transforms.spreader.z, false, false, false)
        SetEntityHeading(entities.spreader, transforms.heading)
    end
end

function Rig.New(profile)
    validateProfile(profile)
    local state = { gantry = 0.5, trolley = 0.5, spreader = 0.5 }
    if profile.yaw then state.yaw = 0.5 end
    local rig = {
        profile = profile,
        state = state,
        entities = {},
        loadedModels = {},
        active = false,
        transforms = nil
    }
    rig.transforms = calculateTransforms(profile, state)
    return rig
end

function Rig.GetProfile(self)
    return self.profile
end

function Rig.SetState(self, nextState)
    nextState = nextState or {}
    local current = self.state
    local state = {
        gantry = clamp(nextState.gantry or current.gantry, 0.0, 1.0),
        trolley = clamp(nextState.trolley or current.trolley, 0.0, 1.0),
        spreader = clamp(nextState.spreader or current.spreader, 0.0, 1.0)
    }
    if self.profile.yaw then
        state.yaw = clamp(nextState.yaw or current.yaw, 0.0, 1.0)
    end
    self.state = state
    applyTransforms(self)
    return copyState(state)
end

function Rig.GetState(self)
    return copyState(self.state)
end

function Rig.GetTransforms(self)
    local transforms = self.transforms or calculateTransforms(self.profile, self.state)
    return {
        base = copyVector(transforms.base),
        gantry = copyVector(transforms.gantry),
        trolley = copyVector(transforms.trolley),
        spreader = copyVector(transforms.spreader),
        axes = copyAxes(transforms.axes),
        heading = transforms.heading
    }
end

function Rig.GetWorldTransform(self)
    local transforms = self.transforms or calculateTransforms(self.profile, self.state)
    return copyVector(transforms.spreader), copyVector(transforms.trolley), copyAxes(transforms.axes)
end

function Rig.GetSpreaderPosition(self)
    local transforms = self.transforms or calculateTransforms(self.profile, self.state)
    return copyVector(transforms.spreader)
end

function Rig.GetSpreaderHeading(self)
    local transforms = self.transforms or calculateTransforms(self.profile, self.state)
    return transforms.heading
end

function Rig.GetSpreaderEntity(self)
    return self.entities.spreader
end

function Rig.Spawn(self)
    if self.active then
        applyTransforms(self)
        return true
    end

    local models = self.profile.models or {}
    for _, part in ipairs(PARTS) do
        local modelName = models[part]
        if modelName then
            local model, errorMessage = loadModel(modelName)
            if not model then
                Rig.Destroy(self)
                return false, errorMessage
            end
            self.loadedModels[part] = model
            local point = self.transforms[part] or self.transforms.spreader
            local entity = CreateObject(model, point.x, point.y, point.z, false, false, false)
            if not entity or entity == 0 then
                Rig.Destroy(self)
                return false, ('failed to create %s entity'):format(part)
            end
            self.entities[part] = entity
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, false, false)
            releaseModel(model)
            self.loadedModels[part] = nil
        end
    end
    self.active = true
    applyTransforms(self)
    return true
end

function Rig.Destroy(self)
    if PortOpsCrane.Attachment and PortOpsCrane.Attachment.DetachAll then
        PortOpsCrane.Attachment.DetachAll()
    end
    for part, entity in pairs(self.entities) do
        deleteEntity(entity)
        self.entities[part] = nil
    end
    for part, model in pairs(self.loadedModels) do
        releaseModel(model)
        self.loadedModels[part] = nil
    end
    self.active = false
    self.transforms = calculateTransforms(self.profile, self.state)
end

return Rig
