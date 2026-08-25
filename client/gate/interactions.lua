PortOps = PortOps or {}; PortOps.Client=PortOps.Client or {}; PortOps.Client.Gate={}
function PortOps.Client.Gate.validate(input) return type(input)=='table' and type(input.appointmentId)=='string' and type(input.containerId)=='string' end
return PortOps.Client.Gate
