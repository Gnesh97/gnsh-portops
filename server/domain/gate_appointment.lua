PortOps = PortOps or {}; PortOps.Domain=PortOps.Domain or {}; local Result=PortOps.Core.Result; local A={}
local function copy(v) if type(v)~='table' then return v end; local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out end
function A.validate(v)
    if type(v)~='table' or type(v.id)~='string' or type(v.containerId)~='string' or type(v.windowStart)~='number' or type(v.windowEnd)~='number' or v.windowEnd<=v.windowStart then return Result.err('APPOINTMENT_INVALID','appointment fields are invalid') end
    local candidate=copy(v); candidate.status=candidate.status or 'BOOKED'; candidate.version=candidate.version or 1
    return Result.ok(candidate)
end
function A.new(v) return A.validate(v) end; PortOps.Domain.GateAppointment=A; return A
