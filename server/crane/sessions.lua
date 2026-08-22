-- Production crane session authority.  This module is framework agnostic and
-- deliberately keeps all ownership checks on the server side.
PortOpsCrane = PortOpsCrane or {}

local Sessions = {}
Sessions.__index = Sessions

local function nowMs(value)
    if type(value) == 'number' then return value end
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function required(value)
    return value ~= nil and tostring(value) ~= ''
end

local function makeId(prefix, sequence, now)
    if type(GetRandomIntInRange) == 'function' then
        return ('%s_%08x%08x_%d'):format(prefix,
            GetRandomIntInRange(0, 0x7fffffff), GetRandomIntInRange(0, 0x7fffffff), sequence)
    end
    math.randomseed(math.floor(os.clock() * 1000000) + os.time())
    local allocation = tostring({}):match('0x(%x+)') or tostring({})
    return ('%s_%08x%08x%s_%d'):format(prefix,
        math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), allocation, sequence)
end

function Sessions.new(options)
    options = options or {}
    return setmetatable({
        ttlMs = tonumber(options.ttlMs) or 30000,
        clock = options.clock,
        sequence = 0,
        byCrane = {},
        bySession = {},
        invalidated = {},
        maxInvalidated = tonumber(options.maxInvalidated) or 1024,
        onInvalidated = options.onInvalidated
    }, Sessions)
end

function Sessions:_now(value)
    return nowMs(self.clock and self.clock() or value)
end

function Sessions:_invalidate(session, reason, timestamp)
    if not session or not session.active then return false end
    session.active = false
    session.invalidatedAt = timestamp or self:_now()
    session.invalidatedReason = reason or 'released'
    self.invalidated[session.id] = session
    local count = 0
    local oldestId, oldestAt
    for id, candidate in pairs(self.invalidated) do
        count = count + 1
        if not oldestAt or candidate.invalidatedAt < oldestAt then
            oldestId, oldestAt = id, candidate.invalidatedAt
        end
    end
    if count > self.maxInvalidated and oldestId then self.invalidated[oldestId] = nil end
    if self.byCrane[session.craneId] == session then self.byCrane[session.craneId] = nil end
    self.bySession[session.id] = nil
    if self.onInvalidated then self.onInvalidated(session, session.invalidatedReason) end
    return true
end

function Sessions:cleanup(timestamp)
    local current = self:_now(timestamp)
    local expired = 0
    for _, session in pairs(self.bySession) do
        if session.expiresAt <= current and self:_invalidate(session, 'expired', current) then
            expired = expired + 1
        end
    end
    return expired
end

function Sessions:reserve(craneId, source, operatorId, timestamp)
    if not required(craneId) or not required(source) or not required(operatorId) then
        return nil, 'INVALID_SESSION_BINDING'
    end
    local current = self:_now(timestamp)
    self:cleanup(current)
    local existing = self.byCrane[craneId]
    if existing and existing.active then return nil, 'CRANE_OCCUPIED' end

    self.sequence = self.sequence + 1
    local id = makeId('cs', self.sequence, current)
    local session = {
        id = id,
        token = makeId('st', self.sequence, current),
        craneId = craneId,
        source = tostring(source),
        operatorId = tostring(operatorId),
        createdAt = current,
        expiresAt = current + self.ttlMs,
        active = true
    }
    self.byCrane[craneId] = session
    self.bySession[id] = session
    return session
end

function Sessions:get(sessionId, timestamp)
    if not required(sessionId) then return nil end
    local session = self.bySession[sessionId]
    if session and session.expiresAt <= self:_now(timestamp) then
        self:_invalidate(session, 'expired')
        return nil
    end
    return session
end

function Sessions:validate(sessionId, craneId, source, operatorId, timestamp, sessionToken)
    local session = self:get(sessionId, timestamp)
    if not session or not session.active then return false, 'INVALID_SESSION' end
    if craneId ~= nil and tostring(craneId) ~= tostring(session.craneId) then return false, 'WRONG_CRANE' end
    if source ~= nil and tostring(source) ~= session.source then return false, 'WRONG_SOURCE' end
    if operatorId ~= nil and tostring(operatorId) ~= session.operatorId then return false, 'WRONG_OPERATOR' end
    if sessionToken ~= nil and tostring(sessionToken) ~= session.token then return false, 'WRONG_SESSION_TOKEN' end
    return true, session
end

function Sessions:release(sessionId, source, timestamp)
    local session = self:get(sessionId, timestamp)
    if not session then
        local invalidated = self.invalidated[sessionId]
        if not invalidated then return false, 'INVALID_SESSION' end
        if source ~= nil and tostring(source) ~= invalidated.source then return false, 'WRONG_SOURCE' end
        return true, 'ALREADY_RELEASED'
    end
    if source ~= nil and tostring(source) ~= session.source then return false, 'WRONG_SOURCE' end
    self:_invalidate(session, 'released', self:_now(timestamp))
    return true
end

function Sessions:invalidateSource(source, timestamp)
    if not required(source) then return 0 end
    local count = 0
    for _, session in pairs(self.bySession) do
        if session.source == tostring(source) and self:_invalidate(session, 'disconnect', self:_now(timestamp)) then
            count = count + 1
        end
    end
    return count
end

PortOpsCrane.Sessions = Sessions
PortOpsCrane.CraneSessions = Sessions.new()
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Crane.Sessions = Sessions
PortOps.Crane.SessionAuthority = PortOpsCrane.CraneSessions
return Sessions
