-- Central container lifecycle authority.  Callers receive a new record;
-- direct status assignment is intentionally not part of this API.
PortOps = PortOps or {}
PortOps.State = PortOps.State or {}

local Result = PortOps.Core.Result
local Container = PortOps.Domain.Container
local Machine = {}
Machine.__index = Machine

local function positiveInteger(value)
    return type(value) == 'number' and value >= 1 and value % 1 == 0
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local TRANSITIONS = {
    EXPECTED = { ON_VESSEL = true, BLOCKED = true, CANCELLED = true },
    ON_VESSEL = { READY_FOR_DISCHARGE = true, DAMAGED = true, BLOCKED = true },
    READY_FOR_DISCHARGE = { CRANE_RESERVED = true, DAMAGED = true, BLOCKED = true },
    CRANE_RESERVED = { CRANE_ATTACHED = true, READY_FOR_DISCHARGE = true, RECOVERY_REQUIRED = true },
    CRANE_ATTACHED = { DISCHARGING = true, CRANE_RESERVED = true, RECOVERY_REQUIRED = true },
    DISCHARGING = { ON_TERMINAL_TRAILER = true, DAMAGED = true, RECOVERY_REQUIRED = true },
    ON_TERMINAL_TRAILER = { IN_TERMINAL_TRANSFER = true, YARD_RECEIVING = true, DAMAGED = true, MISROUTED = true, RECOVERY_REQUIRED = true },
    IN_TERMINAL_TRANSFER = { YARD_RECEIVING = true, MISROUTED = true, RECOVERY_REQUIRED = true },
    YARD_RECEIVING = { AT_YARD = true, MISROUTED = true, RECOVERY_REQUIRED = true },
    AT_YARD = { CUSTOMS_PENDING = true, CUSTOMS_CLEARED = true, READY_FOR_PICKUP = true, DAMAGED = true, MISROUTED = true },
    CUSTOMS_PENDING = { CUSTOMS_HOLD = true, CUSTOMS_CLEARED = true, BLOCKED = true },
    CUSTOMS_HOLD = { INSPECTION = true, BLOCKED = true, RECOVERY_REQUIRED = true },
    INSPECTION = { CUSTOMS_CLEARED = true, SEIZED = true, CUSTOMS_HOLD = true },
    CUSTOMS_CLEARED = { READY_FOR_PICKUP = true, BLOCKED = true },
    SEIZED = { CANCELLED = true, RECOVERY_REQUIRED = true },
    READY_FOR_PICKUP = { PICKUP_IN_PROGRESS = true, BLOCKED = true },
    PICKUP_IN_PROGRESS = { GATE_OUT = true, RECOVERY_REQUIRED = true },
    GATE_OUT = { LEFT_TERMINAL = true },
    LEFT_TERMINAL = {},
    DAMAGED = { INSPECTION = true, RECOVERY_REQUIRED = true, CANCELLED = true },
    MISROUTED = { YARD_RECEIVING = true, RECOVERY_REQUIRED = true, CANCELLED = true },
    BLOCKED = { CUSTOMS_PENDING = true, RECOVERY_REQUIRED = true, CANCELLED = true },
    RECOVERY_REQUIRED = { CRANE_RESERVED = true, ON_TERMINAL_TRAILER = true, YARD_RECEIVING = true, AT_YARD = true, CANCELLED = true },
    CANCELLED = {}
}

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function copy(value)
    return Container.copy(value)
end

function Machine.new(options)
    options = options or {}
    return setmetatable({ guards = options.guards or {}, clock = options.clock }, Machine)
end

function Machine:isAllowed(fromStatus, toStatus)
    return TRANSITIONS[fromStatus] ~= nil and TRANSITIONS[fromStatus][toStatus] == true
end

function Machine:allowed(fromStatus)
    local result = {}
    for status in pairs(TRANSITIONS[fromStatus] or {}) do result[#result + 1] = status end
    table.sort(result)
    return result
end

local function runGuard(guard, container, target, context)
    if type(guard) ~= 'function' then return true end
    local ok, allowed, reason = pcall(guard, copy(container), target, copy(context or {}))
    if not ok then return false, 'guard failed' end
    if allowed ~= true then return false, reason or 'guard rejected transition' end
    return true
end

function Machine:transition(container, targetStatus, context, guards)
    if type(container) ~= 'table' then return Result.err('CONTAINER_INVALID', 'container is required') end
    if container.version ~= nil and not positiveInteger(container.version) then
        return Result.err('CONTAINER_INVALID', 'container version is invalid')
    end
    if type(targetStatus) ~= 'string' or not Container.STATUSES[targetStatus] then
        return Result.err('CONTAINER_TRANSITION_INVALID', 'target status is invalid')
    end
    local currentStatus = container.status
    if not self:isAllowed(currentStatus, targetStatus) then
        return Result.err('CONTAINER_TRANSITION_INVALID', 'container transition is not allowed', { from = currentStatus, to = targetStatus })
    end
    context = type(context) == 'table' and copy(context) or {}
    if context.timestamp ~= nil and not finite(context.timestamp) then
        return Result.err('CONTAINER_TRANSITION_INVALID', 'transition timestamp is invalid')
    end
    if context.condition ~= nil and (not finite(context.condition) or context.condition < 0 or context.condition > 100) then
        return Result.err('CONTAINER_TRANSITION_INVALID', 'transition condition is invalid')
    end
    local guard
    if type(guards) == 'function' then
        guard = guards
    elseif type(guards) == 'table' then
        guard = guards.before or guards[targetStatus]
    end
    if not guard and type(self.guards) == 'function' then
        guard = self.guards
    elseif not guard and type(self.guards) == 'table' then
        guard = self.guards.before or self.guards[targetStatus]
    end
    local guardOk, guardReason = runGuard(guard, container, targetStatus, context)
    if not guardOk then return Result.err('CONTAINER_GUARD_REJECTED', guardReason) end

    local next = copy(container)
    next.status = targetStatus
    next.version = (tonumber(container.version) or 0) + 1
    next.updatedAt = context.timestamp or (self.clock and self.clock() or nowMs())
    if context.location then next.location = copy(context.location) end
    if context.customs then next.customs = copy(context.customs) end
    if context.condition ~= nil then next.condition = context.condition end
    if context.sealStatus then next.sealStatus = context.sealStatus end
    return Result.ok(next, { transition = { from = currentStatus, to = targetStatus, context = context } })
end

Machine.TRANSITIONS = TRANSITIONS
PortOps.State.ContainerStateMachine = Machine
return Machine
