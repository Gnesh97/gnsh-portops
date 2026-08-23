-- Offline contract for S03 database providers and migration ordering.
PortOps = {}
dofile('server/core/result.lua')
dofile('server/adapters/database/memory.lua')
dofile('server/adapters/database/oxmysql.lua')
dofile('server/adapters/database/interface.lua')
dofile('server/core/migrations.lua')

local Result = PortOps.Core.Result
local Database = PortOps.Adapters.Database.Interface
local Memory = PortOps.Adapters.Database.Memory
local Migrations = PortOps.Core.Migrations

local files = {
    ['001.sql'] = 'CREATE TABLE first (id INT);',
    ['002.sql'] = 'CREATE TABLE second (id INT);'
}
local memory = Memory.new()
local runner = Migrations.new({
    database = memory,
    migrations = { { version = 1, path = '001.sql' }, { version = 2, path = '002.sql' } },
    loader = function(path) return files[path] end
})
local firstRun = runner:run()
assert(Result.isOk(firstRun) and firstRun.data.version == 2 and #firstRun.data.applied == 2, 'memory migrations did not apply in order')
local secondRun = runner:run()
assert(Result.isOk(secondRun) and #secondRun.data.applied == 0, 'memory migrations were not idempotent')
assert(Database.validate(memory), 'memory adapter does not satisfy database contract')

local broken = Migrations.new({ database = Memory.new(), migrations = { { version = 1, path = 'missing.sql' } }, loader = function() return nil, 'missing' end })
local brokenResult = broken:run()
assert(Result.isErr(brokenResult) and brokenResult.error.code == 'MIGRATION_FAILED', 'broken migration did not fail fast')

local invalidMigrations = Migrations.new({ database = Memory.new(), migrations = { { version = 1, path = 'one.sql' }, { version = 1, path = 'duplicate.sql' } } })
local invalidResult = invalidMigrations:run()
assert(Result.isErr(invalidResult) and invalidResult.error.code == 'MIGRATION_CONFIG_INVALID', 'invalid migration metadata did not fail fast')

local newerDatabase = Memory.new()
newerDatabase.schemaVersion = 99
local newerResult = Migrations.new({ database = newerDatabase, migrations = { { version = 1, path = 'one.sql' } }, loader = function() return files['001.sql'] end }):run()
assert(Result.isErr(newerResult) and newerResult.error.code == 'SCHEMA_VERSION_UNSUPPORTED', 'newer database schema was not rejected')

local transactionCalls = 0
local transactionPayload
local driver = {
    single = function() return { version = 2 } end,
    query = function() return {} end,
    insert = function() return 1 end,
    update = function() return 1 end,
    transaction = function(payload) transactionCalls = transactionCalls + 1; transactionPayload = payload; return true end
}
local oxmysql = PortOps.Adapters.Database.OxMySQL.new({ driver = driver })
assert(Result.isOk(oxmysql:connect()), 'injected oxmysql driver did not connect')
assert(Database.validate(oxmysql), 'oxmysql adapter does not satisfy database contract')
assert(Result.isOk(oxmysql:applyMigration(3, 'CREATE TABLE third (id INT);')) and transactionCalls == 1, 'oxmysql migration transaction was not used')
assert(transactionPayload[1].query:find('CREATE TABLE third', 1, true) and type(transactionPayload[1].parameters) == 'table', 'oxmysql transaction payload shape is invalid')

print('database_migrations_contract: PASS')
