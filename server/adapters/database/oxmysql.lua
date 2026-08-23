-- oxmysql adapter boundary. Domain code only sees this normalized contract;
-- the adapter is the sole place that knows FiveM/oxmysql call shapes.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Database = PortOps.Adapters.Database or {}

local Result = PortOps.Core.Result
local OxMySQL = {}
OxMySQL.__index = OxMySQL

local function splitStatements(sql)
    local statements = {}
    for rawStatement in tostring(sql):gmatch('([^;]+)') do
        local statement = rawStatement
        statement = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if statement ~= '' and not statement:match('^%-%-') then statements[#statements + 1] = statement end
    end
    return statements
end

function OxMySQL.new(options)
    options = options or {}
    return setmetatable({ provider = 'oxmysql', driver = options.driver, connected = false }, OxMySQL)
end

function OxMySQL:_resolveDriver()
    if self.driver then return self.driver end
    if type(MySQL) == 'table' then
        local query = type(MySQL.query) == 'table' and MySQL.query.await or nil
        local single = type(MySQL.single) == 'table' and MySQL.single.await or nil
        local insert = type(MySQL.insert) == 'table' and MySQL.insert.await or nil
        local update = type(MySQL.update) == 'table' and MySQL.update.await or nil
        local transaction = type(MySQL.transaction) == 'table' and MySQL.transaction.await or nil
        if query or single or insert or update or transaction then
            self.driver = { query = query, single = single, insert = insert, update = update, transaction = transaction }
            return self.driver
        end
    end
    return nil
end

function OxMySQL:connect()
    if not self:_resolveDriver() then return Result.err('DATABASE_DRIVER_UNAVAILABLE', 'oxmysql driver is not available') end
    self.connected = true
    return Result.ok({ provider = self.provider, durable = true })
end

function OxMySQL:close()
    self.connected = false
    return Result.ok({ closed = true })
end

function OxMySQL:_call(method, sql, parameters)
    if not self.connected then return Result.err('DATABASE_NOT_READY', 'oxmysql database is not connected') end
    local driver = self:_resolveDriver()
    local callback = driver and driver[method]
    if type(callback) ~= 'function' then return Result.err('DATABASE_METHOD_UNAVAILABLE', 'oxmysql method is unavailable', { method = method }) end
    local ok, value = pcall(callback, sql, parameters or {})
    if not ok then return Result.err('DATABASE_QUERY_FAILED', 'oxmysql query failed', { method = method, reason = value }) end
    return Result.ok(value)
end

function OxMySQL:query(sql, parameters) return self:_call('query', sql, parameters) end
function OxMySQL:single(sql, parameters) return self:_call('single', sql, parameters) end
function OxMySQL:insert(sql, parameters) return self:_call('insert', sql, parameters) end
function OxMySQL:update(sql, parameters) return self:_call('update', sql, parameters) end

function OxMySQL:transaction(statements)
    if not self.connected then return Result.err('DATABASE_NOT_READY', 'oxmysql database is not connected') end
    local driver = self:_resolveDriver()
    if type(driver.transaction) ~= 'function' then return Result.err('DATABASE_METHOD_UNAVAILABLE', 'oxmysql transaction is unavailable') end
    local ok, value = pcall(driver.transaction, statements)
    if not ok then return Result.err('TRANSACTION_FAILED', 'oxmysql transaction failed', { reason = value }) end
    return Result.ok(value)
end

function OxMySQL:getSchemaVersion()
    local result = self:single('SELECT version FROM portops_schema_version WHERE id = 1 LIMIT 1')
    if Result.isOk(result) then
        local row = result.data
        if type(row) ~= 'table' or row.version == nil then return Result.err('SCHEMA_VERSION_MISSING', 'schema version row is missing') end
        return Result.ok(tonumber(row.version) or 0)
    end
    return Result.err('SCHEMA_VERSION_MISSING', 'schema version table is not ready', result.error)
end

function OxMySQL:applyMigration(version, sql)
    if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then return Result.err('MIGRATION_INVALID', 'migration version is invalid') end
    if type(sql) ~= 'string' or #sql == 0 then return Result.err('MIGRATION_INVALID', 'migration SQL is empty') end
    local statements = splitStatements(sql)
    local transaction = {}
    for _, statement in ipairs(statements) do transaction[#transaction + 1] = { query = statement, parameters = {} } end
    transaction[#transaction + 1] = {
        query = 'INSERT INTO portops_schema_version (id, version) VALUES (1, ?) ON DUPLICATE KEY UPDATE version = VALUES(version)',
        parameters = { version }
    }
    local result = self:transaction(transaction)
    if Result.isErr(result) then return result end
    return Result.ok({ version = version, applied = true })
end

PortOps.Adapters.Database.OxMySQL = OxMySQL
return OxMySQL
