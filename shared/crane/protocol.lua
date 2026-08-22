PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Protocol = {}

Protocol.VERSION = 1
Protocol.DEFAULTS = {
    snapshotHz = 20,
    snapshotBurst = 1,
    burstWindowMs = 1000,
    maxPayloadKeys = 16,
    maxFutureSkewMs = 250,
    maxAgeMs = 2000,
    maxTimestampSkewMs = 2000,
    interpolationDelayMs = 100,
    bufferSize = 12,
    maxDeltaPerSecond = { gantry = 1.5, trolley = 1.5, spreader = 1.0, yaw = 360.0 }
}

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function number(value, fallback)
    return finite(value) and value or fallback
end

local function stateCopy(state)
    return {
        gantry = number(state and state.gantry, 0.5),
        trolley = number(state and state.trolley, 0.5),
        spreader = number(state and state.spreader, 1.0),
        yaw = number(state and (state.yaw or state.spreaderYaw), 0.0)
    }
end

function Protocol.copyState(state)
    return stateCopy(state)
end

function Protocol.normalize(snapshot, limits)
    if type(snapshot) ~= 'table' then return nil, 'snapshot must be a table' end
    limits = limits or Protocol.DEFAULTS
    if snapshot.version ~= nil and snapshot.version ~= Protocol.VERSION then return nil, 'protocol version' end
    local keyCount = 0
    for _ in pairs(snapshot) do keyCount = keyCount + 1 end
    if type(snapshot.state) == 'table' then for _ in pairs(snapshot.state) do keyCount = keyCount + 1 end end
    if keyCount > (limits.maxPayloadKeys or Protocol.DEFAULTS.maxPayloadKeys or 16) then return nil, 'payload too large' end
    local sequence = tonumber(snapshot.sequence or snapshot.seq)
    local timestamp = tonumber(snapshot.timestamp or snapshot.timestampMs)
    if not finite(sequence) or sequence < 0 or sequence % 1 ~= 0 then return nil, 'invalid sequence' end
    if not finite(timestamp) then return nil, 'invalid timestamp' end
    local rawState = snapshot.state or snapshot
    local required = { 'gantry', 'trolley', 'spreader' }
    for _, key in ipairs(required) do
        if not finite(rawState[key]) then return nil, 'invalid state: ' .. key end
    end
    local yaw = rawState.yaw or rawState.spreaderYaw
    if not finite(yaw) then return nil, 'invalid state: yaw' end
    local state = { gantry = rawState.gantry, trolley = rawState.trolley, spreader = rawState.spreader, yaw = yaw }
    return { version = Protocol.VERSION, sequence = sequence, timestamp = timestamp, state = state }
end

function Protocol.validate(snapshot, previous, nowMs, limits, receiveElapsedMs)
    limits = limits or Protocol.DEFAULTS
    local normalized, errorMessage = Protocol.normalize(snapshot, limits)
    if not normalized then return false, errorMessage end
    if previous and normalized.sequence <= previous.sequence then return false, 'late sequence' end
    for _, key in ipairs({ 'gantry', 'trolley', 'spreader' }) do
        if normalized.state[key] < 0 or normalized.state[key] > 1 then return false, 'state out of bounds: ' .. key end
    end
    if normalized.state.yaw < -360 or normalized.state.yaw > 360 then return false, 'yaw out of bounds' end
    if finite(nowMs) then
        if normalized.timestamp > nowMs + (limits.maxFutureSkewMs or 250) then return false, 'future timestamp' end
        if nowMs - normalized.timestamp > (limits.maxAgeMs or 2000) then return false, 'stale timestamp' end
    end
    if previous then
        -- Server callers pass receiveElapsedMs; client timestamps are not authoritative.
        local elapsed = math.max((finite(receiveElapsedMs) and receiveElapsedMs or (normalized.timestamp - previous.timestamp)) / 1000, 0.001)
        local rates = limits.maxDeltaPerSecond or Protocol.DEFAULTS.maxDeltaPerSecond
        for _, key in ipairs({ 'gantry', 'trolley', 'spreader', 'yaw' }) do
            if math.abs(normalized.state[key] - previous.state[key]) > (rates[key] or 1) * elapsed then
                return false, 'delta too large: ' .. key
            end
        end
    end
    return true, normalized
end

PortOps.Crane.Protocol = Protocol
