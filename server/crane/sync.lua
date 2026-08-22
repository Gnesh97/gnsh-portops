PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
local Protocol = PortOps.Crane.Protocol
PortOps.Crane.SyncById = PortOps.Crane.SyncById or {}

local Sync = {}

function Sync.new(options)
    options = options or {}
    local sync = {
        config = options,
        canonical = Protocol.copyState(options.initialState),
        lastSnapshot = nil,
        lastReceivedMs = nil,
        lastArrivalMs = {},
        arrivalWindow = {},
        operator = options.operator,
        craneId = options.craneId,
        sessionId = options.sessionId,
        broadcast = options.broadcast
    }
    if sync.craneId then PortOps.Crane.SyncById[sync.craneId] = sync end
    return sync
end

function Sync.setOperator(sync, source)
    sync.operator = source
end

function Sync.clearOperator(sync, source)
    if not source or sync.operator == source then sync.operator = nil end
end

function Sync.setSession(sync, sessionId, craneId)
    sync.sessionId = sessionId
    sync.craneId = craneId or sync.craneId
    if sync.craneId then PortOps.Crane.SyncById[sync.craneId] = sync end
end

function Sync.accept(sync, source, snapshot, nowMs)
    if type(snapshot) ~= 'table' then return false, 'snapshot invalid' end
    if sync.operator and source ~= sync.operator then return false, 'operator required' end
    if sync.craneId and snapshot.craneId ~= sync.craneId then return false, 'wrong crane' end
    if sync.sessionId and snapshot.sessionId ~= sync.sessionId then return false, 'wrong session' end
    local sourceKey = tostring(source or 'unknown')
    local interval = 1000 / (sync.config.snapshotHz or Protocol.DEFAULTS.snapshotHz)
    if type(nowMs) == 'number' and sync.lastArrivalMs[sourceKey] and nowMs - sync.lastArrivalMs[sourceKey] < interval then
        return false, 'snapshot rate limited'
    end
    local burstWindowMs = sync.config.burstWindowMs or Protocol.DEFAULTS.burstWindowMs
    local burstLimit = sync.config.snapshotBurst or Protocol.DEFAULTS.snapshotBurst
    if type(nowMs) == 'number' then
        local window = sync.arrivalWindow[sourceKey]
        if not window or nowMs - window.startedAt >= burstWindowMs then
            window = { startedAt = nowMs, count = 0 }
            sync.arrivalWindow[sourceKey] = window
        end
        if window.count >= burstLimit then return false, 'snapshot burst limited' end
    end
    local receiveElapsedMs = type(nowMs) == 'number' and sync.lastReceivedMs and nowMs - sync.lastReceivedMs or nil
    local ok, normalized = Protocol.validate(snapshot, sync.lastSnapshot, nowMs, sync.config, receiveElapsedMs)
    if not ok then return false, normalized end
    normalized.craneId = sync.craneId
    normalized.sessionId = sync.sessionId
    if type(nowMs) == 'number' then
        sync.lastArrivalMs[sourceKey] = nowMs
        sync.lastReceivedMs = nowMs
        sync.arrivalWindow[sourceKey].count = sync.arrivalWindow[sourceKey].count + 1
    end
    sync.lastSnapshot = normalized
    sync.canonical = Protocol.copyState(normalized.state)
    if sync.broadcast then sync.broadcast(normalized, source) end
    return true, normalized
end

function Sync.getCanonical(sync)
    return Protocol.copyState(sync.canonical)
end

PortOps.Crane.ServerSync = Sync
