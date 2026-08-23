-- Application service for logical containers.  Persistence, lifecycle, and
-- event emission are kept behind one version-aware API.
PortOps = PortOps or {}
PortOps.Services = PortOps.Services or {}

local Result = PortOps.Core.Result
local Container = PortOps.Domain.Container
local Service = {}
Service.__index = Service

local function positiveInteger(value)
    return type(value) == 'number' and value >= 1 and value % 1 == 0
end

function Service.new(options)
    options = options or {}
    return setmetatable({
        repository = options.repository,
        stateMachine = options.stateMachine,
        events = options.events,
        logger = options.logger
    }, Service)
end

function Service:_emit(name, payload, context)
    if self.events and self.events.emit then self.events:emit(name, payload, context) end
end

function Service:_lookup(idOrNumber)
    if idOrNumber == nil then return Result.err('CONTAINER_NOT_FOUND', 'container identifier is required') end
    local key = tostring(idOrNumber)
    local byId = self.repository:getById(key)
    if Result.isOk(byId) then return byId end
    if type(idOrNumber) == 'string' then return self.repository:getByNumber(idOrNumber) end
    return byId
end

function Service:create(input, context)
    local validated = Container.new(input or {})
    if Result.isErr(validated) then return validated end
    local created = self.repository:create(validated.data)
    if Result.isErr(created) then return created end
    local dto = Container.toDTO(created.data)
    self:_emit('portops:containerCreated', dto, context)
    self:_emit('portops:container.created', dto, context)
    return Result.ok(dto)
end

function Service:get(idOrNumber)
    local result = self:_lookup(idOrNumber)
    if Result.isErr(result) then return result end
    return Result.ok(Container.toDTO(result.data))
end

function Service:getStatus(idOrNumber)
    local result = self:get(idOrNumber)
    if Result.isErr(result) then return result end
    return Result.ok({ id = result.data.id, containerNumber = result.data.containerNumber, status = result.data.status, version = result.data.version })
end

function Service:list(filters, options)
    local result = self.repository:list(filters, options)
    if Result.isErr(result) then return result end
    local dtos = {}
    for _, record in ipairs(result.data or {}) do dtos[#dtos + 1] = Container.toDTO(record) end
    return Result.ok(dtos)
end

function Service:transition(idOrNumber, targetStatus, expectedVersion, context, guards)
    if not positiveInteger(expectedVersion) then return Result.err('CONTAINER_VERSION_INVALID', 'expected version is required') end
    local current = self:_lookup(idOrNumber)
    if Result.isErr(current) then return current end
    if current.data.version ~= expectedVersion then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
    local transitioned = self.stateMachine:transition(current.data, targetStatus, context, guards)
    if Result.isErr(transitioned) then return transitioned end
    local validated = Container.validate(transitioned.data, { requireId = true })
    if Result.isErr(validated) then return validated end
    local updated = self.repository:update(validated.data, expectedVersion)
    if Result.isErr(updated) then return updated end
    local dto = Container.toDTO(updated.data)
    local meta = transitioned.meta and transitioned.meta.transition
    self:_emit('portops:containerTransitioned', { container = dto, transition = meta }, context)
    self:_emit('portops:container.transitioned', { container = dto, transition = meta }, context)
    if targetStatus == 'AT_YARD' or targetStatus == 'YARD_RECEIVING' then
        self:_emit('portops:containerMoved', { container = dto, transition = meta }, context)
    elseif targetStatus == 'DAMAGED' then
        self:_emit('portops:containerDamaged', { container = dto, transition = meta }, context)
    end
    return Result.ok(dto, { transition = meta })
end

function Service:delete(idOrNumber, expectedVersion, context)
    if not positiveInteger(expectedVersion) then return Result.err('CONTAINER_VERSION_INVALID', 'expected version is required') end
    local current = self:_lookup(idOrNumber)
    if Result.isErr(current) then return current end
    if current.data.version ~= expectedVersion then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
    local deleted = self.repository:delete(current.data.id, expectedVersion)
    if Result.isErr(deleted) then return deleted end
    self:_emit('portops:containerDeleted', { id = current.data.id, containerNumber = current.data.containerNumber, version = expectedVersion }, context)
    self:_emit('portops:container.deleted', { id = current.data.id, containerNumber = current.data.containerNumber, version = expectedVersion }, context)
    return deleted
end

PortOps.Services.Container = Service
return Service
