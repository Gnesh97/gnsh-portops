-- Provider selector and normalized database contract.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Database = PortOps.Adapters.Database or {}

local Database = PortOps.Adapters.Database
local Result = PortOps.Core.Result

local REQUIRED = { 'connect', 'close', 'query', 'single', 'insert', 'update', 'transaction', 'getSchemaVersion', 'applyMigration' }

function Database.validate(adapter)
    if type(adapter) ~= 'table' then return false, 'DATABASE_ADAPTER_INVALID' end
    for _, method in ipairs(REQUIRED) do
        if type(adapter[method]) ~= 'function' then return false, 'DATABASE_METHOD_MISSING:' .. method end
    end
    return true
end

function Database.create(config)
    local provider = config and config.provider
    if provider == 'memory' and Database.Memory then return Database.Memory.new(config) end
    if provider == 'oxmysql' and Database.OxMySQL then return Database.OxMySQL.new(config) end
    return nil, Result.err('DATABASE_PROVIDER_UNSUPPORTED', 'database provider is unsupported', { provider = provider })
end

PortOps.Adapters.Database.Interface = Database
return Database
