PortOps = PortOps or {}; PortOps.Domain=PortOps.Domain or {}; local Result=PortOps.Core.Result; local A={}
function A.validate(v) if type(v)~='table' or type(v.id)~='string' or type(v.containerId)~='string' or type(v.windowStart)~='number' or type(v.windowEnd)~='number' or v.windowEnd<=v.windowStart then return Result.err('APPOINTMENT_INVALID','appointment fields are invalid') end; v.status=v.status or 'BOOKED'; return Result.ok(v) end
function A.new(v) return A.validate(v) end; PortOps.Domain.GateAppointment=A; return A
