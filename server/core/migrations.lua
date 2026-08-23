-- Ordered, idempotent migration runner. SQL stays inside the database
-- adapter boundary; callers receive a stable Result envelope.
PortOps = PortOps or {}
PortOps.Core = PortOps.Core or {}

local Result = PortOps.Core.Result
local Migrations = {}
Migrations.__index = Migrations

local DEFAULTS = {
    { version = 1, path = 'sql/001_initial.sql' },
    { version = 2, path = 'sql/002_indexes.sql' }
}

local function sortedCopy(items)
    if type(items) ~= 'table' then return nil, 'migration list must be a table' end
    local copy = {}
    local seen = {}
    for index, item in pairs(items) do
        if type(index) ~= 'number' or index < 1 or index % 1 ~= 0 then
            return nil, 'migration indexes must be positive integers'
        end
        if type(item) ~= 'table' then return nil, ('migration %s must be a table'):format(tostring(index)) end
        if type(item.version) ~= 'number' or item.version < 1 or item.version % 1 ~= 0 then
            return nil, ('migration %s version must be a positive integer'):format(tostring(index))
        end
        if seen[item.version] then return nil, ('migration version is duplicated: %s'):format(tostring(item.version)) end
        if type(item.path) ~= 'string' or item.path == '' then return nil, ('migration %s path is required'):format(tostring(index)) end
        seen[item.version] = true
        copy[#copy + 1] = { version = item.version, path = item.path }
    end
    table.sort(copy, function(left, right) return left.version < right.version end)
    return copy
end

function Migrations.new(options)
    options = options or {}
    local source = options.migrations
    if source == nil then source = DEFAULTS end
    local migrations, configReason = sortedCopy(source)
    return setmetatable({
        database = options.database,
        migrations = migrations or {},
        configReason = configReason,
        loader = options.loader,
        applied = {}
    }, Migrations)
end

function Migrations:_load(path)
    if type(self.loader) == 'function' then return self.loader(path) end
    if type(LoadResourceFile) == 'function' and type(GetCurrentResourceName) == 'function' then return LoadResourceFile(GetCurrentResourceName(), path) end
    if type(io) == 'table' and type(io.open) == 'function' then
        local handle = io.open(path, 'r')
        if not handle then return nil, 'MIGRATION_FILE_NOT_FOUND' end
        local sql = handle:read('*a')
        handle:close()
        return sql
    end
    return nil, 'MIGRATION_LOADER_UNAVAILABLE'
end

function Migrations:run()
    if self.configReason then return Result.err('MIGRATION_CONFIG_INVALID', self.configReason) end
    if not self.database then return Result.err('DATABASE_NOT_READY', 'migration database is missing') end
    local connected = self.database:connect()
    if Result.isErr(connected) then return connected end
    local currentResult = self.database:getSchemaVersion()
    local current = 0
    if Result.isOk(currentResult) then
        current = tonumber(currentResult.data) or 0
    elseif currentResult.error.code ~= 'SCHEMA_VERSION_MISSING' then
        return currentResult
    end
    local latestSupported = self.migrations[#self.migrations] and self.migrations[#self.migrations].version or 0
    if current > latestSupported then
        return Result.err('SCHEMA_VERSION_UNSUPPORTED', 'database schema is newer than supported migrations', {
            current = current,
            latestSupported = latestSupported
        })
    end
    local applied = {}
    for _, migration in ipairs(self.migrations) do
        if migration.version <= current then
            self.applied[migration.version] = false
        else
            local sql, loadReason = self:_load(migration.path)
            if type(sql) ~= 'string' or sql == '' then
                return Result.err('MIGRATION_FAILED', 'migration SQL could not be loaded', { version = migration.version, path = migration.path, reason = loadReason })
            end
            local result = self.database:applyMigration(migration.version, sql)
            if Result.isErr(result) then return Result.err('MIGRATION_FAILED', 'migration application failed', { version = migration.version, reason = result.error }) end
            self.applied[migration.version] = true
            applied[#applied + 1] = migration.version
            current = migration.version
        end
    end
    return Result.ok({ version = current, applied = applied })
end

PortOps.Core.Migrations = Migrations
return Migrations
