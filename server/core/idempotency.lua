PortOps = PortOps or {}; PortOps.Core = PortOps.Core or {}
local Result = PortOps.Core.Result
local Idempotency = {}; Idempotency.__index = Idempotency

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

local function durable(database)
    return type(database) == 'table' and (database.provider == 'oxmysql' or database.durable == true)
end

local function encode(value)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then return nil end
    local ok, result = pcall(json.encode, value)
    return ok and type(result) == 'string' and result or nil
end

local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or type(json) ~= 'table' or type(json.decode) ~= 'function' then return nil end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or nil
end

function Idempotency.new(options)
    options = options or {}
    return setmetatable({
        records = {},
        clock = options.clock,
        ttlMs = options.ttlMs or 86400000,
        claimTtlMs = options.claimTtlMs or math.min(options.ttlMs or 86400000, 60000),
        database = options.database
    }, Idempotency)
end

function Idempotency:_now() return self.clock and self.clock() or math.floor(os.time() * 1000) end

function Idempotency:_deletePersistent(scope, key)
    if not durable(self.database) then return Result.ok(true) end
    local result = self.database:update(
        'DELETE FROM portops_idempotency_keys WHERE scope_name = ? AND idempotency_key = ?',
        { scope, key }
    )
    return result
end

function Idempotency:_readPersistent(scope, key, current)
    if not durable(self.database) then return nil end
    local result = self.database:single(
        'SELECT response_json, expires_at FROM portops_idempotency_keys WHERE scope_name = ? AND idempotency_key = ? LIMIT 1',
        { scope, key }
    )
    if Result.isErr(result) then return nil, Result.err('IDEMPOTENCY_STORAGE_FAILED', 'idempotency lookup failed', result.error) end
    local row = result.data
    if type(row) == 'table' and type(row.row) == 'table' then row = row.row end
    if type(row) ~= 'table' or row.response_json == nil then return nil end
    local expiresAt = tonumber(row.expires_at) or 0
    if expiresAt <= current then
        self:_deletePersistent(scope, key)
        return nil
    end
    local payload = decode(row.response_json)
    if type(payload) ~= 'table' then return nil, Result.err('IDEMPOTENCY_STORAGE_INVALID', 'stored idempotency response is invalid') end
    if payload.pending == true then return { pending = true } end
    return { value = copy(payload.value) }
end

function Idempotency:_claimPersistent(scope, key, current)
    local pending = encode({ pending = true })
    if not pending then return Result.err('IDEMPOTENCY_STORAGE_UNAVAILABLE', 'JSON serializer is unavailable') end
    local result = self.database:insert([[
        INSERT INTO portops_idempotency_keys
            (scope_name, idempotency_key, response_json, expires_at, created_at)
        VALUES (?, ?, ?, ?, ?)
    ]], { scope, key, pending, current + self.claimTtlMs, current })
    if Result.isOk(result) then return Result.ok(true) end
    local existing, readError = self:_readPersistent(scope, key, current)
    if readError then return readError end
    if existing then
        if existing.pending then return Result.err('IDEMPOTENCY_IN_PROGRESS', 'idempotency operation is already in progress') end
        return Result.ok(existing, { idempotent = true })
    end
    return Result.err('IDEMPOTENCY_STORAGE_FAILED', 'idempotency claim failed', result and result.error)
end

function Idempotency:_storePersistent(scope, key, value, current)
    local response = encode({ pending = false, value = copy(value) })
    if not response then return Result.err('IDEMPOTENCY_STORAGE_UNAVAILABLE', 'JSON serializer is unavailable') end
    local result = self.database:update([[
        UPDATE portops_idempotency_keys
           SET response_json = ?, expires_at = ?
         WHERE scope_name = ? AND idempotency_key = ?
    ]], { response, current + self.ttlMs, scope, key })
    if Result.isErr(result) then return Result.err('IDEMPOTENCY_STORAGE_FAILED', 'idempotency response could not be stored', result.error) end
    local affected = type(result.data) == 'number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows))
    if tonumber(affected) ~= 1 then return Result.err('IDEMPOTENCY_STORAGE_FAILED', 'idempotency response update matched no claim') end
    return Result.ok(true)
end

function Idempotency:run(scope, key, operation)
    if type(scope) ~= 'string' or scope == '' or #scope > 64 or type(key) ~= 'string' or key == '' or #key > 128 then
        return Result.err('IDEMPOTENCY_INVALID', 'scope and key are required')
    end
    if type(operation) ~= 'function' then return Result.err('IDEMPOTENCY_OPERATION_INVALID', 'operation is required') end
    local id = scope .. ':' .. key
    local current = self:_now()

    if durable(self.database) then
        local persistent, readError = self:_readPersistent(scope, key, current)
        if readError then return readError end
        if persistent then
            if persistent.pending then return Result.err('IDEMPOTENCY_IN_PROGRESS', 'idempotency operation is already in progress') end
            return Result.ok(copy(persistent.value), { idempotent = true, persisted = true })
        end
        local claim = self:_claimPersistent(scope, key, current)
        if Result.isErr(claim) then return claim end
        if claim.meta and claim.meta.idempotent then return Result.ok(copy(claim.data.value), claim.meta) end
    else
        local prior = self.records[id]
        if prior and prior.expiresAt > current then
            if prior.pending then return Result.err('IDEMPOTENCY_IN_PROGRESS', 'idempotency operation is already in progress') end
            return Result.ok(copy(prior.value), { idempotent = true, persisted = false })
        end
        self.records[id] = { pending = true, expiresAt = current + self.claimTtlMs }
    end

    local ok, value = pcall(operation)
    if not ok then
        if durable(self.database) then self:_deletePersistent(scope, key) else self.records[id] = nil end
        return Result.err('IDEMPOTENCY_OPERATION_FAILED', 'operation failed', { reason = value })
    end
    if not Result.isOk(value) then
        if durable(self.database) then self:_deletePersistent(scope, key) else self.records[id] = nil end
        if Result.isErr(value) then return value end
        return Result.err('RESULT_INVALID', 'operation returned an invalid result envelope')
    end

    if durable(self.database) then
        local stored = self:_storePersistent(scope, key, value.data, current)
        if Result.isErr(stored) then self:_deletePersistent(scope, key); return stored end
        return Result.ok(copy(value.data), { idempotent = false, persisted = true })
    end
    self.records[id] = { value = copy(value.data), expiresAt = current + self.ttlMs }
    return Result.ok(copy(value.data), { idempotent = false, persisted = false })
end

function Idempotency:clear()
    self.records = {}
    return true
end

PortOps.Core.Idempotency = Idempotency
return Idempotency
