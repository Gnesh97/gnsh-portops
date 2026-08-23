-- Startup validation is deliberately fail-fast.  A malformed profile or
-- missing cross-reference must stop the resource before it can accept events.
PortOps = PortOps or {}
PortOps.Security = PortOps.Security or {}

local Security = {}
local Schema = PortOps.Crane.Schema

local function invalid(errors, message)
    errors[#errors + 1] = message
end

local function validateMigrations(migrations, errors)
    if migrations == nil then return end
    if type(migrations) ~= 'table' then
        invalid(errors, 'database migrations must be a table')
        return
    end
    local seen = {}
    for index, migration in pairs(migrations) do
        if type(index) ~= 'number' or index < 1 or index % 1 ~= 0 then
            invalid(errors, 'database migration indexes must be positive integers')
        end
        if type(migration) ~= 'table' then
            invalid(errors, ('database migration %s must be a table'):format(tostring(index)))
        else
            local version = migration.version
            if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then
                invalid(errors, ('database migration %s version must be a positive integer'):format(tostring(index)))
            elseif seen[version] then
                invalid(errors, ('database migration version is duplicated: %s'):format(tostring(version)))
            else
                seen[version] = true
            end
            if type(migration.path) ~= 'string' or migration.path == '' then
                invalid(errors, ('database migration %s path is required'):format(tostring(index)))
            end
        end
    end
end

function Security.validateConfig(config, features)
    local errors = {}
    if type(config) ~= 'table' then return false, { 'config must be a table' } end
    if type(config.version) ~= 'string' or config.version == '' then invalid(errors, 'version is required') end
    if config.environment ~= 'development' and config.environment ~= 'staging' and config.environment ~= 'production' then
        invalid(errors, 'environment is invalid')
    end
    if config.logging and (type(config.logging) ~= 'table' or (config.logging.level ~= nil and not ({ debug = true, info = true, warn = true, error = true })[config.logging.level])) then
        invalid(errors, 'logging level is invalid')
    end
    local frameworkProvider = config.framework and config.framework.provider
    if frameworkProvider ~= 'standalone' and frameworkProvider ~= 'qbcore' and frameworkProvider ~= 'qbox' and frameworkProvider ~= 'esx' then
        invalid(errors, 'framework provider is invalid')
    end
    local databaseProvider = config.database and config.database.provider
    if databaseProvider ~= 'memory' and databaseProvider ~= 'oxmysql' then
        invalid(errors, 'database provider is invalid')
    end
    validateMigrations(config.database and config.database.migrations, errors)
    if type(config.defaults) ~= 'table' then
        invalid(errors, 'defaults are required')
    else
        if type(config.defaults.craneId) ~= 'string' then invalid(errors, 'default craneId is required') end
        if type(config.defaults.yardId) ~= 'string' then invalid(errors, 'default yardId is required') end
        if type(config.defaults.berthId) ~= 'string' then invalid(errors, 'default berthId is required') end
    end
    if type(config.craneProfiles) ~= 'table' or next(config.craneProfiles) == nil then
        invalid(errors, 'at least one crane profile is required')
    else
        for id, profile in pairs(config.craneProfiles) do
            local ok, reason = Schema.validateProfile(profile)
            if not ok then invalid(errors, ('profile %s: %s'):format(tostring(id), reason)) end
        end
    end
    if type(config.yards) ~= 'table' or not config.defaults or not config.yards[config.defaults.yardId] then
        invalid(errors, 'default yard reference is missing')
    end
    if type(config.berths) ~= 'table' or not config.defaults or not config.berths[config.defaults.berthId] then
        invalid(errors, 'default berth reference is missing')
    end
    if config.defaults and config.craneProfiles and not config.craneProfiles[config.defaults.craneId] then
        invalid(errors, 'default crane reference is missing')
    end
    if type(config.crane) ~= 'table' then
        invalid(errors, 'crane runtime config is required')
    else
        for _, key in ipairs({ 'snapshotHz', 'snapshotBurst', 'burstWindowMs', 'maxPayloadKeys', 'futureSkewMs', 'maxSnapshotAgeMs', 'interpolationDelayMs', 'observerBufferSize', 'sessionTtlMs', 'actionTokenTtlMs', 'actionTokenMaxActivePerSession', 'actionTokenMaxIssuesPerWindow', 'actionTokenIssueWindowMs' }) do
            if type(config.crane[key]) ~= 'number' or config.crane[key] <= 0 then invalid(errors, 'crane.' .. key .. ' must be positive') end
        end
    end
    if type(features) ~= 'table' then
        invalid(errors, 'features are required')
    else
        for _, key in ipairs({ 'craneAuthority', 'snapshotProtocol', 'observerInterpolation', 'actionTokens', 'disconnectRecovery', 'memoryPersistence', 'frameworkAdapters', 'containerDomain', 'yardDomain', 'berthDomain', 'rewards' }) do
            if type(features[key]) ~= 'boolean' then invalid(errors, 'feature flag must be boolean: ' .. key) end
        end
    end
    if #errors > 0 then return false, errors end
    return true
end

PortOps.Security.Validation = Security
return Security
