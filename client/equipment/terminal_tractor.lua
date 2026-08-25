PortOps = PortOps or {}; PortOps.Client = PortOps.Client or {}; PortOps.Client.TerminalTractor={}
function PortOps.Client.TerminalTractor.validate(input)
    return type(input)=='table' and type(input.tractorId)=='string' and type(input.trailerId)=='string' and type(input.containerId)=='string'
end
return PortOps.Client.TerminalTractor
