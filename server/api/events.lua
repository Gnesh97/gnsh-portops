PortOps = PortOps or {}; PortOps.Api = PortOps.Api or {}
local Events = {}
function Events.emit(name, payload)
    local bus = PortOps.Runtime and PortOps.Runtime.Events
    if not bus or type(bus.emit) ~= 'function' then return false, 'EVENT_BUS_UNAVAILABLE' end
    return bus:emit(name, payload, { source = 'public-api' })
end
PortOps.Api.Events = Events
return Events
