-- Single NUI callback boundary. Feature pages call named operations here;
-- services still own validation, permissions, and state transitions.
PortOps = PortOps or {}
PortOps.Api = PortOps.Api or {}
local Result = PortOps.Core.Result
local Callbacks = {}

local function runtime() return PortOps.Runtime or {} end
local function invoke(serviceName, method, payload)
    local service = runtime()[serviceName]
    if not service or type(service[method]) ~= 'function' then return Result.err('API_UNAVAILABLE', serviceName .. '.' .. method .. ' is unavailable') end
    local ok, result = pcall(service[method], service, table.unpack(payload or {}))
    if not ok then return Result.err('API_FAILED', 'NUI operation failed', { reason = result }) end
    return result
end

Callbacks.operations = {
    health = function() return PortOps.Api.Exports and PortOps.Api.Exports.GetHealth() or Result.ok({ ready = false }) end,
    containers = function(payload) return invoke('ContainerService', 'list', { payload and payload.filters or {}, payload and payload.options or {} }) end,
    moves = function(payload) return invoke('MoveService', 'list', { payload and payload.filters or {}, payload and payload.options or {} }) end,
    yard = function(payload) return invoke('YardService', 'list', { payload and payload.filters or {} }) end,
    appointments = function(payload) return invoke('GateService', 'list', { payload and payload.filters or {} }) end
}

function Callbacks.handle(name, payload)
    local operation = Callbacks.operations[name]
    if type(operation) ~= 'function' then return Result.err('API_NOT_FOUND', 'NUI operation is not registered') end
    local ok, result = pcall(operation, payload or {})
    if not ok then return Result.err('API_FAILED', 'NUI operation failed', { reason = result }) end
    return result
end

if type(RegisterNUICallback) == 'function' then
    for name in pairs(Callbacks.operations) do
        RegisterNUICallback(name, function(payload, cb)
            local result = Callbacks.handle(name, payload)
            if type(cb) == 'function' then cb(result) end
        end)
    end
end
PortOps.Api.Callbacks = Callbacks
return Callbacks
