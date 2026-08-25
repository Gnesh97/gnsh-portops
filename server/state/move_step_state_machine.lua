-- Ordered step transitions are exposed separately from the move aggregate.
PortOps = PortOps or {}
PortOps.State = PortOps.State or {}
local Result = PortOps.Core.Result
local Move = PortOps.Domain.Move

local Machine = {}
Machine.__index = Machine

local TRANSITIONS = {
    PENDING = { READY = true, CANCELLED = true },
    READY = { CLAIMED = true, BLOCKED = true, CANCELLED = true },
    CLAIMED = { IN_PROGRESS = true, READY = true, BLOCKED = true },
    IN_PROGRESS = { COMPLETED = true, BLOCKED = true, RECOVERY_REQUIRED = true },
    BLOCKED = { READY = true, RECOVERY_REQUIRED = true, CANCELLED = true },
    RECOVERY_REQUIRED = { READY = true, IN_PROGRESS = true, CANCELLED = true },
    COMPLETED = {},
    CANCELLED = {}
}

function Machine.new(options)
    options = options or {}
    return setmetatable({ clock = options.clock }, Machine)
end

function Machine:isAllowed(fromStatus, toStatus)
    return TRANSITIONS[fromStatus] ~= nil and TRANSITIONS[fromStatus][toStatus] == true
end

function Machine:transition(step, target, context)
    if type(step) ~= 'table' or not Move.STEP_STATUSES[step.status] then
        return Result.err('MOVE_STEP_INVALID', 'move step is invalid')
    end
    if not self:isAllowed(step.status, target) then
        return Result.err('MOVE_STEP_TRANSITION_INVALID', 'move step transition is not allowed', { from = step.status, to = target })
    end
    local next = Move.copy(step)
    next.status = target
    next.version = (tonumber(step.version) or 1) + 1
    next.updatedAt = (context and context.timestamp) or (self.clock and self.clock()) or math.floor(os.time() * 1000)
    if context and context.blockedReason then next.blockedReason = context.blockedReason end
    return Result.ok(next, { transition = { from = step.status, to = target } })
end

Machine.TRANSITIONS = TRANSITIONS
PortOps.State.MoveStepStateMachine = Machine
return Machine
