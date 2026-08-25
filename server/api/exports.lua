PortOps = PortOps or {}; PortOps.Api = PortOps.Api or {}
local Result = PortOps.Core.Result; local DTO = PortOps.Api.DTO
local function unavailable(name) return Result.err('API_UNAVAILABLE', name .. ' is not configured') end
local function runtime() return PortOps.Runtime or {} end
local function containerService() return runtime().ContainerService end
local function call(name, ...)
    local service = containerService(); if not service or type(service[name]) ~= 'function' then return unavailable('container service') end
    return service[name](service, ...)
end
local Api = {}
function Api.CreateContainer(value, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local idem = runtime().Idempotency
    local result = idem and idem:run('container.create', key, function() return call('create', value) end) or call('create', value)
    return DTO.result(result)
end
function Api.GetContainer(id) return DTO.result(call('get', id)) end
function Api.CreateVesselCall(value, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local service = runtime().VesselCallService; if not service then return DTO.result(unavailable('vessel call service')) end
    local idem = runtime().Idempotency; local result = idem and idem:run('vessel-call.create', key, function() return service:create(value) end) or service:create(value)
    return DTO.result(result)
end
function Api.GetVesselCall(id) local service=runtime().VesselCallService; return DTO.result(service and service:get(id) or unavailable('vessel call service')) end
function Api.CreateMoveOrder(value, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local service=runtime().MoveService; if not service then return DTO.result(unavailable('move service')) end
    local idem=runtime().Idempotency; local result=idem and idem:run('move.create',key,function() return service:create(value) end) or service:create(value); return DTO.result(result)
end
function Api.CreateGateAppointment(value, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local service=runtime().GateService; if not service then return DTO.result(unavailable('gate service')) end
    local idem=runtime().Idempotency; local result=idem and idem:run('gate.create',key,function() return service:book(value) end) or service:book(value); return DTO.result(result)
end
function Api.SetCustomsHold(containerId, input, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local service=runtime().CustomsService; if not service then return DTO.result(unavailable('customs service')) end
    local idem=runtime().Idempotency; local result=idem and idem:run('customs.hold',key,function() return service:open(containerId,input or {}) end) or service:open(containerId,input or {}); return DTO.result(result)
end
function Api.ReleaseContainer(id, expectedVersion, key)
    if type(key) ~= 'string' or key == '' then return DTO.result(Result.err('IDEMPOTENCY_KEY_REQUIRED', 'idempotency key is required')) end
    local service=containerService(); if not service then return DTO.result(unavailable('container service')) end
    local idem=runtime().Idempotency
    local operation=function()
        local current=service:get(id); if Result.isErr(current) then return current end
        local version=expectedVersion or current.data.version
        return service:transition(id,'READY_FOR_PICKUP',version,{releaseReason='public-api'})
    end
    local result=idem and idem:run('container.release',key,operation) or operation(); return DTO.result(result)
end
function Api.GetHealth()
    local boot = runtime().Bootstrap
    return { ok = true, data = { ready = boot and boot.ready == true, stage = boot and boot.stage, version = PortOps.Config and PortOps.Config.version, schemaVersion = boot and boot.database and boot.database.schemaVersion } }
end
PortOps.Api.Exports = Api
return Api
