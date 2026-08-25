PortOps = PortOps or {}; PortOps.Client = PortOps.Client or {}; PortOps.Client.YardHandler={}
function PortOps.Client.YardHandler.validate(input)
    return type(input)=='table' and type(input.handlerId)=='string' and type(input.slotId)=='string' and type(input.containerId)=='string'
end
return PortOps.Client.YardHandler
