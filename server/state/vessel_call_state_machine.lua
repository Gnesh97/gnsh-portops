PortOps = PortOps or {}; PortOps.State=PortOps.State or {}; local Result=PortOps.Core.Result; local M={}; M.__index=M
local transitions={PLANNED={ARRIVAL_EXPECTED=true,CANCELLED=true},ARRIVAL_EXPECTED={ARRIVED=true,CANCELLED=true},ARRIVED={BERTHED=true,DEPARTED=true},BERTHED={OPERATING=true,DEPARTED=true},OPERATING={COMPLETED=true,DEPARTED=true},COMPLETED={},DEPARTED={},CANCELLED={}}
function M.new(o) return setmetatable({clock=o and o.clock},M) end
function M:transition(call,target) if type(call)~='table' or not transitions[call.status] or not transitions[call.status][target] then return Result.err('VESSEL_CALL_TRANSITION_INVALID','transition is not allowed') end; local n={}; for k,v in pairs(call) do n[k]=v end; n.status=target; n.version=(call.version or 1)+1; n.updatedAt=self.clock and self.clock() or math.floor(os.time()*1000); return Result.ok(n) end
M.TRANSITIONS=transitions; PortOps.State.VesselCall=M; return M
