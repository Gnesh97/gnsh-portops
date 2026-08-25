PortOps = PortOps or {}; PortOps.State = PortOps.State or {}
local Result = PortOps.Core.Result; local Move = PortOps.Domain.Move
local Machine = {}; Machine.__index = Machine
local TRANSITIONS = {
    PLANNED={RESERVED=true,READY=true,CANCELLED=true}, RESERVED={READY=true,PLANNED=true,CANCELLED=true},
    READY={CLAIMED=true,BLOCKED=true,CANCELLED=true}, CLAIMED={IN_PROGRESS=true,READY=true,BLOCKED=true},
    IN_PROGRESS={COMPLETED=true,BLOCKED=true,RECOVERY_REQUIRED=true}, BLOCKED={READY=true,RECOVERY_REQUIRED=true,CANCELLED=true},
    RECOVERY_REQUIRED={READY=true,IN_PROGRESS=true,CANCELLED=true}, COMPLETED={}, CANCELLED={}
}
function Machine.new(options) options=options or {}; return setmetatable({guards=options.guards or {}, clock=options.clock},Machine) end
function Machine:isAllowed(a,b) return TRANSITIONS[a] ~= nil and TRANSITIONS[a][b] == true end
function Machine:allowed(a) local r={}; for k in pairs(TRANSITIONS[a] or {}) do r[#r+1]=k end; table.sort(r); return r end
function Machine:transition(move, target, context, guard)
    if type(move)~='table' or not Move.STATUSES[move.status] then return Result.err('MOVE_INVALID','move is invalid') end
    if not self:isAllowed(move.status,target) then return Result.err('MOVE_TRANSITION_INVALID','move transition is not allowed',{from=move.status,to=target}) end
    local fn=guard or self.guards[target] or self.guards.before
    if type(fn)=='function' then local ok, allow, reason=pcall(fn,Move.copy(move),target,Move.copy(context or {})); if not ok or allow~=true then return Result.err('MOVE_GUARD_REJECTED',reason or 'move guard rejected') end end
    local next=Move.copy(move); next.status=target; next.version=move.version+1; next.updatedAt=(context and context.timestamp) or (self.clock and self.clock()) or math.floor(os.time()*1000)
    if context and context.blockedReason then next.blockedReason=context.blockedReason end
    return Result.ok(next,{transition={from=move.status,to=target}})
end
Machine.TRANSITIONS=TRANSITIONS; PortOps.State.MoveStateMachine=Machine; return Machine
