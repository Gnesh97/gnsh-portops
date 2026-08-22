-- S01 / PORT-015. Deterministic local presentation attachment.
-- Server authority is deliberately out of scope; production must revalidate this action.

PortOpsCrane = PortOpsCrane or {}
local Alignment = PortOpsCrane.Alignment
PortOpsCrane.Attachment = PortOpsCrane.Attachment or {}
local Attachment = PortOpsCrane.Attachment
local active = {}
local activeBySpreader = {}

local function validEntity(entity)
    return type(entity) == 'number' and entity ~= 0 and (not DoesEntityExist or DoesEntityExist(entity))
end

local function entityFrom(value)
    return value and (value.entity or value)
end

local function collisionState(entity)
    if GetEntityCollisionDisabled then
        local ok, disabled = pcall(GetEntityCollisionDisabled, entity)
        if ok and type(disabled) == 'boolean' then return not disabled end
    end
    return true
end

local function setCollision(entity, enabled)
    if SetEntityCollision then pcall(SetEntityCollision, entity, enabled, enabled) end
end

local function profileOrDefault(profile, options)
    return profile or (options and options.profile) or (PortOpsCrane.Config and PortOpsCrane.Config.profile)
end

function Attachment.Attach(spreader, container, profile, options)
    options = options or {}
    profile = profileOrDefault(profile, options)
    local spreaderEntity = entityFrom(spreader)
    local containerEntity = entityFrom(container)
    if not validEntity(spreaderEntity) or not validEntity(containerEntity) then
        return false, 'INVALID_ENTITY'
    end
    local target = options.target or 'top'
    if target ~= 'top' and target ~= 'trailer' then return false, 'INVALID_TARGET' end
    if not Alignment or not Alignment.Evaluate then return false, 'ALIGNMENT_UNAVAILABLE' end
    local result = Alignment.Evaluate(spreader, container, profile, options.tolerances)
    if not result then return false, 'ALIGNMENT_UNAVAILABLE' end
    local allowDebugBypass = options.skipAlignment == true and options.debugHarness == true
    if not result.aligned and not allowDebugBypass then
        return false, result.reason, result
    end
    if active[containerEntity] then return false, 'ALREADY_ATTACHED' end
    if activeBySpreader[spreaderEntity] then return false, 'SPREADER_OCCUPIED' end

    local priorCollision = collisionState(containerEntity)
    local record = {
        spreader = spreaderEntity,
        container = containerEntity,
        collision = priorCollision,
        result = result,
        target = target
    }
    setCollision(containerEntity, false)
    if not AttachEntityToEntity or not IsEntityAttachedToEntity then
        setCollision(containerEntity, priorCollision)
        return false, 'NATIVE_ATTACH_UNAVAILABLE', result
    end
    local called = pcall(AttachEntityToEntity, containerEntity, spreaderEntity, options.bone or 0,
        options.offsetX or 0.0, options.offsetY or 0.0, options.offsetZ or 0.0,
        options.rotationX or 0.0, options.rotationY or 0.0, options.rotationZ or 0.0,
        false, false, false, false, 2, true)
    if not called or not IsEntityAttachedToEntity(containerEntity, spreaderEntity) then
        setCollision(containerEntity, priorCollision)
        return false, 'NATIVE_ATTACH_FAILED', result
    end
    active[containerEntity] = record
    activeBySpreader[spreaderEntity] = record
    return true, 'ATTACHED', record
end

function Attachment.AttachNearest(spreader, profile, options)
    options = options or {}
    profile = profileOrDefault(profile, options)
    if not Alignment or not Alignment.FindNearestCandidate then return false, 'ALIGNMENT_UNAVAILABLE' end
    local candidate, result = Alignment.FindNearestCandidate(spreader, profile, options)
    if not candidate then return false, 'NO_CANDIDATE', result end
    local attached, reason, record = Attachment.Attach(spreader, candidate, profile, options)
    return attached, reason, record or result
end

function Attachment.Detach(container)
    local containerEntity = entityFrom(container)
    local record = active[containerEntity]
    if not record then return false, 'NOT_ATTACHED' end
    if not DetachEntity or not IsEntityAttachedToEntity then return false, 'NATIVE_DETACH_UNAVAILABLE' end
    local called = pcall(DetachEntity, containerEntity, true, true)
    if not called or IsEntityAttachedToEntity(containerEntity, record.spreader) then
        return false, 'NATIVE_DETACH_FAILED'
    end
    setCollision(containerEntity, record.collision)
    active[containerEntity] = nil
    if activeBySpreader[record.spreader] == record then activeBySpreader[record.spreader] = nil end
    return true, 'DETACHED', record
end

function Attachment.DetachTarget(container, target)
    local record = Attachment.Get(container)
    if not record then return false, 'NOT_ATTACHED' end
    if target and record.target ~= target then return false, 'WRONG_TARGET' end
    return Attachment.Detach(container)
end

function Attachment.Get(container)
    return active[entityFrom(container)]
end

function Attachment.Count()
    local count = 0
    for _ in pairs(active) do count = count + 1 end
    return count
end

function Attachment.GetFirst()
    for entity in pairs(active) do return entity end
    return nil
end

function Attachment.DetachAll()
    local entities = {}
    for entity in pairs(active) do entities[#entities + 1] = entity end
    for _, entity in ipairs(entities) do Attachment.Detach(entity) end
end

function Attachment.RunCycleHarness(spreader, container, profile, cycles, options)
    cycles = math.max(10, tonumber(cycles) or 10)
    local report = { requested = cycles, passed = 0, failures = {} }
    for index = 1, cycles do
        local attached, attachReason = Attachment.Attach(spreader, container, profile, options)
        local detached, detachReason
        if attached then
            detached, detachReason = Attachment.Detach(container)
        else
            detachReason = 'ATTACH_FAILED'
        end
        if attached and detached and not Attachment.Get(container) then
            report.passed = report.passed + 1
        else
            report.failures[#report.failures + 1] = {
                cycle = index,
                attach = attachReason,
                detach = detachReason
            }
        end
    end
    report.pass = report.passed == report.requested
    return report
end

return Attachment
