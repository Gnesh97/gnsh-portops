-- Logical move order domain. A move is the server-owned workflow that carries
-- a container between canonical locations; world entities are never stored here.
PortOps = PortOps or {}
PortOps.Domain = PortOps.Domain or {}
local Result = PortOps.Core.Result
local Move = {}

Move.STATUSES = { PLANNED=true, RESERVED=true, READY=true, CLAIMED=true, IN_PROGRESS=true,
    COMPLETED=true, BLOCKED=true, RECOVERY_REQUIRED=true, CANCELLED=true }
Move.STEP_STATUSES = { PENDING=true, READY=true, CLAIMED=true, IN_PROGRESS=true,
    COMPLETED=true, BLOCKED=true, RECOVERY_REQUIRED=true, CANCELLED=true }
Move.STEP_TYPES = { CRANE=true, TRANSFER=true, YARD=true, INSPECTION=true, GATE=true, CUSTOMS=true, GENERIC=true }

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function text(v, n) return type(v) == 'string' and v ~= '' and #v <= n end
local function timestamp(v) return v == nil or finite(v) end
local function location(v)
    if type(v) ~= 'table' or type(v.type) ~= 'string' or not text(v.type, 32) then return nil end
    if v.ref ~= nil and not text(v.ref, 128) then return nil end
    return { type=v.type, ref=v.ref, transform=copy(v.transform) }
end
local function invalid(msg) return Result.err('MOVE_INVALID', msg) end

function Move.validate(input, options)
    options = options or {}; if type(input) ~= 'table' then return invalid('move must be a table') end
    local id = input.id
    if id ~= nil and not text(tostring(id), 64) then return invalid('id is invalid') end
    if options.requireId and not id then return invalid('id is required') end
    local number = input.moveNumber or input.idempotencyKey
    if number ~= nil and not text(number, 96) then return invalid('moveNumber is invalid') end
    local containerId = input.containerId or input.containerRef
    if not text(tostring(containerId or ''), 64) then return invalid('containerId is required') end
    local from = location(input.fromLocation or input.from); local to = location(input.toLocation or input.to)
    if not from or not to then return invalid('from and to locations are required') end
    local status = input.status or 'PLANNED'; if not Move.STATUSES[status] then return invalid('status is invalid') end
    local version = input.version or 1
    if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then return invalid('version is invalid') end
    local steps = input.steps or {}
    if type(steps) ~= 'table' or #steps > 100 then return invalid('steps are invalid') end
    local normalized = {}
    for i, step in ipairs(steps) do
        if type(step) ~= 'table' then return invalid('step is invalid') end
        local stepId = step.id or ('step-' .. i)
        if not text(tostring(stepId), 64) then return invalid('step id is invalid') end
        local kind = step.kind or step.type or 'GENERIC'; if not Move.STEP_TYPES[kind] then return invalid('step type is invalid') end
        local stepStatus = step.status or (i == 1 and 'READY' or 'PENDING'); if not Move.STEP_STATUSES[stepStatus] then return invalid('step status is invalid') end
        normalized[i] = { id=tostring(stepId), ordinal=i, kind=kind, status=stepStatus, assignee=copy(step.assignee), reservation=copy(step.reservation), version=step.version or 1, metadata=copy(step.metadata) }
    end
    local now = input.createdAt or math.floor(os.time() * 1000)
    if not timestamp(input.createdAt) or not timestamp(input.updatedAt) then return invalid('timestamps are invalid') end
    return Result.ok({ id=id and tostring(id) or nil, moveNumber=number, containerId=tostring(containerId), fromLocation=from, toLocation=to,
        status=status, steps=normalized, assignments=copy(input.assignments or {}), reservations=copy(input.reservations or {}),
        version=version, idempotencyKey=input.idempotencyKey, createdAt=now, updatedAt=input.updatedAt or now, blockedReason=input.blockedReason })
end
function Move.new(input, options) return Move.validate(input, options) end
function Move.copy(v) return copy(v) end
function Move.toDTO(v) return copy(v) end
PortOps.Domain.Move = Move
return Move
