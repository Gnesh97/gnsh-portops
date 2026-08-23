-- In-process event bus with isolated handlers.  Network boundaries remain in
-- bootstrap; domain services use this bus for committed lifecycle events.
PortOps = PortOps or {}
PortOps.Core = PortOps.Core or {}

local EventBus = {}
EventBus.__index = EventBus

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function validName(name)
    return type(name) == 'string' and #name > 0 and #name <= 128
end

function EventBus.new(options)
    options = options or {}
    return setmetatable({ handlers = {}, logger = options.logger, maxHandlers = tonumber(options.maxHandlers) or 64 }, EventBus)
end

function EventBus:on(name, handler)
    if not validName(name) then return false, 'EVENT_NAME_INVALID' end
    if type(handler) ~= 'function' then return false, 'EVENT_HANDLER_INVALID' end
    local listeners = self.handlers[name] or {}
    if #listeners >= self.maxHandlers then return false, 'EVENT_HANDLER_LIMIT' end
    listeners[#listeners + 1] = handler
    self.handlers[name] = listeners
    return true, function() return self:off(name, handler) end
end

function EventBus:off(name, handler)
    local listeners = self.handlers[name]
    if not listeners then return false, 'EVENT_NOT_FOUND' end
    for index, candidate in ipairs(listeners) do
        if candidate == handler then
            table.remove(listeners, index)
            if #listeners == 0 then self.handlers[name] = nil end
            return true
        end
    end
    return false, 'EVENT_HANDLER_NOT_FOUND'
end

function EventBus:emit(name, payload, context)
    if not validName(name) then return false, 'EVENT_NAME_INVALID' end
    local listeners = self.handlers[name] or {}
    local delivered, failures = 0, 0
    for _, handler in ipairs(listeners) do
        local ok, reason = pcall(handler, copy(payload), copy(context))
        if ok then
            delivered = delivered + 1
        else
            failures = failures + 1
            if self.logger and self.logger.error then self.logger:error('event handler failed', { event = name, reason = reason }) end
        end
    end
    return true, { delivered = delivered, failures = failures }
end

function EventBus:clear(name)
    if name == nil then self.handlers = {}; return true end
    if not validName(name) then return false, 'EVENT_NAME_INVALID' end
    self.handlers[name] = nil
    return true
end

PortOps.Core.EventBus = EventBus
return EventBus
