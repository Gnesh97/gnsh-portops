-- Explicit development/test database adapter. It mirrors the provider
-- contract without pretending that process memory is durable persistence.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Database = PortOps.Adapters.Database or {}

local Result = PortOps.Core.Result
local Memory = {}
Memory.__index = Memory

function Memory.new(options)
    options = options or {}
    return setmetatable({
        provider = 'memory',
        connected = false,
        schemaVersion = 0,
        applied = {},
        statements = {},
        tables = {}
    }, Memory)
end

function Memory:connect()
    self.connected = true
    return Result.ok({ provider = self.provider, durable = false })
end

function Memory:close()
    self.connected = false
    return Result.ok({ closed = true })
end

function Memory:_ready()
    if self.connected then return true end
    return false, Result.err('DATABASE_NOT_READY', 'memory database is not connected')
end

function Memory:query(sql, parameters)
    local ready, reason = self:_ready()
    if not ready then return reason end
    if type(sql) ~= 'string' or #sql == 0 then return Result.err('QUERY_INVALID', 'query must be a non-empty string') end
    self.statements[#self.statements + 1] = { sql = sql, parameters = parameters }
    return Result.ok({ rows = {}, affectedRows = 0 })
end

function Memory:single(sql, parameters)
    local result = self:query(sql, parameters)
    if not Result.isOk(result) then return result end
    result.data.row = nil
    return result
end

function Memory:insert(sql, parameters)
    return self:query(sql, parameters)
end

function Memory:update(sql, parameters)
    return self:query(sql, parameters)
end

function Memory:transaction(callback)
    local ready, reason = self:_ready()
    if not ready then return reason end
    if type(callback) ~= 'function' then return Result.err('TRANSACTION_INVALID', 'transaction callback is required') end
    local ok, value = pcall(callback, self)
    if not ok then return Result.err('TRANSACTION_FAILED', 'transaction callback failed', { reason = value }) end
    if Result.isErr(value) then return value end
    return Result.ok(value)
end

function Memory:getSchemaVersion()
    local ready, reason = self:_ready()
    if not ready then return reason end
    return Result.ok(self.schemaVersion)
end

function Memory:applyMigration(version, sql)
    local ready, reason = self:_ready()
    if not ready then return reason end
    if self.applied[version] then return Result.ok({ version = version, applied = false }) end
    if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then return Result.err('MIGRATION_INVALID', 'migration version is invalid') end
    if type(sql) ~= 'string' or #sql == 0 then return Result.err('MIGRATION_INVALID', 'migration SQL is empty') end
    self.statements[#self.statements + 1] = { migration = version, sql = sql }
    self.applied[version] = true
    self.schemaVersion = math.max(self.schemaVersion, version)
    return Result.ok({ version = version, applied = true })
end

PortOps.Adapters.Database.Memory = Memory
return Memory
