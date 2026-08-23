-- Framework-neutral adapter used by direct development and offline tests.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Framework = PortOps.Adapters.Framework or {}

local Result = PortOps.Core.Result
local Standalone = {}
Standalone.__index = Standalone

local function sourceId(source)
    return tostring(tonumber(source) or source or 'unknown')
end

function Standalone.new()
    return setmetatable({ provider = 'standalone' }, Standalone)
end

function Standalone:isAvailable()
    return true
end

function Standalone:getPlayer(source)
    return { source = sourceId(source) }
end

function Standalone:getIdentifier(source)
    return 'standalone:' .. sourceId(source)
end

function Standalone:getCharacter(source)
    local id = sourceId(source)
    return { id = id, name = 'Standalone ' .. id }
end

function Standalone:getJob()
    return { name = 'standalone', grade = 0, gradeName = 'operator' }
end

function Standalone:isOnDuty()
    return true
end

function Standalone:getMoney()
    return 0
end

function Standalone:addMoney()
    return Result.err('MONEY_UNAVAILABLE', 'standalone adapter has no money account')
end

function Standalone:_hook()
    return true, function() return true end
end

function Standalone:onPlayerLoaded(handler) if type(handler) ~= 'function' then return false, 'FRAMEWORK_HANDLER_INVALID' end; return self:_hook() end
function Standalone:onPlayerUnload(handler) if type(handler) ~= 'function' then return false, 'FRAMEWORK_HANDLER_INVALID' end; return self:_hook() end
function Standalone:onJobChange(handler) if type(handler) ~= 'function' then return false, 'FRAMEWORK_HANDLER_INVALID' end; return self:_hook() end

PortOps.Adapters.Framework.Standalone = Standalone
return Standalone
