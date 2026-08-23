-- Logical container visual resolver.  Deleting/recreating an entity never
-- touches the server-side container record.
PortOps = PortOps or {}
PortOps.Client = PortOps.Client or {}

local Visuals = {}
Visuals.__index = Visuals

local DEFAULT_MODELS = {
    ['20GP'] = 'container_20gp',
    ['40GP'] = 'container_40gp',
    ['40HC'] = 'container_40hc',
    ['45HC'] = 'container_45hc',
    ['20RF'] = 'container_20rf',
    ['40RF'] = 'container_40rf'
}

local function ok(data)
    return { ok = true, data = data }
end

local function err(code, message)
    return { ok = false, error = { code = code, message = message } }
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function transformValid(transform)
    if type(transform) ~= 'table' then return false end
    for _, key in ipairs({ 'x', 'y', 'z' }) do
        if type(transform[key]) ~= 'number' or transform[key] ~= transform[key] then return false end
    end
    return true
end

local function defaultCreate(model, transform)
    if type(CreateObjectNoOffset) ~= 'function' then return nil end
    local hash = type(joaat) == 'function' and joaat(model) or model
    return CreateObjectNoOffset(hash, transform.x, transform.y, transform.z, false, false, false)
end

local function defaultDelete(entity)
    if type(DeleteEntity) == 'function' then DeleteEntity(entity) end
end

local function defaultTransform(entity, transform)
    if type(SetEntityCoordsNoOffset) == 'function' then
        SetEntityCoordsNoOffset(entity, transform.x, transform.y, transform.z, false, false, false)
    end
    if type(SetEntityHeading) == 'function' and transform.heading then SetEntityHeading(entity, transform.heading) end
end

local function defaultMetadata(entity, value)
    if type(Entity) ~= 'function' then return end
    local wrapper = Entity(entity)
    if wrapper and wrapper.state and type(wrapper.state.set) == 'function' then
        wrapper.state:set('portopsContainer', value, true)
    end
end

function Visuals.new(options)
    options = options or {}
    local models = copy(options.models or DEFAULT_MODELS)
    return setmetatable({
        models = models,
        spawned = {},
        createObject = options.createObject or defaultCreate,
        deleteEntity = options.deleteEntity or defaultDelete,
        setTransform = options.setTransform or defaultTransform,
        setMetadata = options.setMetadata or defaultMetadata
    }, Visuals)
end

function Visuals:_model(isoType)
    return self.models[isoType]
end

function Visuals:spawn(descriptor)
    if type(descriptor) ~= 'table' or type(descriptor.id) ~= 'string' or descriptor.id == '' then
        return err('VISUAL_DESCRIPTOR_INVALID', 'container visual descriptor is invalid')
    end
    if not self:_model(descriptor.isoType) then return err('VISUAL_MODEL_UNAVAILABLE', 'container ISO model is unavailable') end
    if not transformValid(descriptor.transform) then return err('VISUAL_TRANSFORM_REQUIRED', 'container transform is required') end
    local existing = self.spawned[descriptor.id]
    if existing and existing.isoType ~= descriptor.isoType then
        local removed = self:despawn(descriptor.id)
        if not removed.ok then return removed end
        existing = nil
    end
    if existing then
        local moved = self:updateTransform(descriptor.id, descriptor.transform)
        if not moved.ok then return moved end
        existing.version = descriptor.version
        existing.metadata.version = descriptor.version
        pcall(self.setMetadata, existing.entity, copy(existing.metadata), descriptor)
        return ok({ id = descriptor.id, entity = existing.entity, spawned = false })
    end
    local success, entity = pcall(self.createObject, self:_model(descriptor.isoType), descriptor.transform, descriptor)
    if not success or entity == nil or entity == false or entity == 0 then return err('VISUAL_SPAWN_FAILED', 'container visual could not be spawned') end
    if type(DoesEntityExist) == 'function' then
        local existsOk, exists = pcall(DoesEntityExist, entity)
        if not existsOk or not exists then return err('VISUAL_SPAWN_FAILED', 'container visual entity is invalid') end
    end
    local record = {
        id = descriptor.id,
        entity = entity,
        isoType = descriptor.isoType,
        version = descriptor.version,
        metadata = { containerId = descriptor.id, isoType = descriptor.isoType, version = descriptor.version, logical = true }
    }
    self.spawned[descriptor.id] = record
    pcall(self.setTransform, entity, descriptor.transform, descriptor)
    pcall(self.setMetadata, entity, copy(record.metadata), descriptor)
    return ok({ id = descriptor.id, entity = entity, spawned = true })
end

function Visuals:despawn(id)
    local record = self.spawned[id]
    if not record then return ok({ id = id, despawned = false }) end
    local success = pcall(self.deleteEntity, record.entity, record)
    if not success then return err('VISUAL_DESPAWN_FAILED', 'container visual could not be deleted') end
    self.spawned[id] = nil
    return ok({ id = id, despawned = true })
end

function Visuals:updateTransform(id, transform)
    local record = self.spawned[id]
    if not record then return err('VISUAL_NOT_SPAWNED', 'container visual is not spawned') end
    if not transformValid(transform) then return err('VISUAL_TRANSFORM_REQUIRED', 'container transform is invalid') end
    local success = pcall(self.setTransform, record.entity, transform)
    if not success then return err('VISUAL_TRANSFORM_FAILED', 'container visual transform failed') end
    return ok({ id = id, entity = record.entity })
end

function Visuals:get(id)
    return self.spawned[id] and copy(self.spawned[id]) or nil
end

function Visuals:reconcile(descriptors)
    if type(descriptors) ~= 'table' then return err('VISUAL_DESCRIPTOR_INVALID', 'descriptor batch is invalid') end
    local desired = {}
    local spawned, failed = 0, 0
    for _, descriptor in ipairs(descriptors) do
        if type(descriptor) == 'table' and type(descriptor.id) == 'string' and descriptor.id ~= '' then
            desired[descriptor.id] = true
            local result = self:spawn(descriptor)
            if result.ok and result.data.spawned then spawned = spawned + 1 elseif not result.ok then failed = failed + 1 end
        else
            failed = failed + 1
        end
    end
    local despawned = 0
    for id in pairs(self.spawned) do
        if not desired[id] then
            local result = self:despawn(id)
            if result.ok and result.data.despawned then despawned = despawned + 1 end
        end
    end
    return ok({ spawned = spawned, despawned = despawned, failed = failed, active = #descriptors })
end

PortOps.Client.ContainerVisuals = Visuals
return Visuals
