PortOps = PortOps or {}; PortOps.Core = PortOps.Core or {}
local Result = PortOps.Core.Result
local Idempotency = {}; Idempotency.__index = Idempotency
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[copy(key)] = copy(child) end; return out
end
function Idempotency.new(options)
    options = options or {}; return setmetatable({ records = {}, clock = options.clock, ttlMs = options.ttlMs or 86400000 }, Idempotency)
end
function Idempotency:_now() return self.clock and self.clock() or math.floor(os.time() * 1000) end
function Idempotency:run(scope, key, operation)
    if type(scope) ~= 'string' or scope == '' or #scope > 64 or type(key) ~= 'string' or key == '' or #key > 128 then return Result.err('IDEMPOTENCY_INVALID', 'scope and key are required') end
    local id = scope .. ':' .. key; local current = self:_now(); local prior = self.records[id]
    if prior and prior.expiresAt > current then return Result.ok(copy(prior.value), { idempotent = true }) end
    if type(operation) ~= 'function' then return Result.err('IDEMPOTENCY_OPERATION_INVALID', 'operation is required') end
    local ok, value = pcall(operation); if not ok then return Result.err('IDEMPOTENCY_OPERATION_FAILED', 'operation failed', { reason = value }) end
    if Result.isErr(value) then return value end
    self.records[id] = { value = copy(value.data), expiresAt = current + self.ttlMs }
    return Result.ok(copy(value.data), { idempotent = false })
end
function Idempotency:clear() self.records = {}; return true end
PortOps.Core.Idempotency = Idempotency
return Idempotency
