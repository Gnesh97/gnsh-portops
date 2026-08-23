-- Normalized framework contract and provider selector.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Framework = PortOps.Adapters.Framework or {}

local Framework = PortOps.Adapters.Framework
local Result = PortOps.Core.Result

local REQUIRED = {
    'isAvailable', 'getPlayer', 'getIdentifier', 'getCharacter', 'getJob', 'isOnDuty', 'getMoney', 'addMoney',
    'onPlayerLoaded', 'onPlayerUnload', 'onJobChange'
}

function Framework.validate(adapter)
    if type(adapter) ~= 'table' then return false, 'FRAMEWORK_ADAPTER_INVALID' end
    for _, method in ipairs(REQUIRED) do
        if type(adapter[method]) ~= 'function' then return false, 'FRAMEWORK_METHOD_MISSING:' .. method end
    end
    return true
end

function Framework.create(config)
    local provider = config and config.provider
    local adapters = Framework
    if provider == 'standalone' and adapters.Standalone then return adapters.Standalone.new(config) end
    if provider == 'qbcore' and adapters.QBCore then return adapters.QBCore.new(config) end
    if provider == 'qbox' and adapters.Qbox then return adapters.Qbox.new(config) end
    if provider == 'esx' and adapters.ESX then return adapters.ESX.new(config) end
    return nil, Result.err('FRAMEWORK_PROVIDER_UNSUPPORTED', 'framework provider is unsupported', { provider = provider })
end

PortOps.Adapters.Framework.Interface = Framework
return Framework
