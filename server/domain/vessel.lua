PortOps = PortOps or {}; PortOps.Domain = PortOps.Domain or {}; local Result=PortOps.Core.Result; local Vessel={}
local function copy(v) if type(v)~='table' then return v end; local o={}; for k,x in pairs(v) do o[k]=copy(x) end; return o end
function Vessel.validate(v) if type(v)~='table' or type(v.id)~='string' or type(v.name)~='string' then return Result.err('VESSEL_INVALID','vessel identity is required') end; return Result.ok(copy(v)) end
function Vessel.new(v) return Vessel.validate(v) end; function Vessel.copy(v) return copy(v) end
PortOps.Domain.Vessel=Vessel; return Vessel
