-- Short-lived, one-time server action tokens.  A token is never authority by
-- itself: consume validates the current session and every bound identifier.
PortOpsCrane = PortOpsCrane or {}

local Tokens = {}
Tokens.__index = Tokens

local function entropy()
    if type(GetRandomIntInRange) == 'function' then
        return ('%08x%08x'):format(GetRandomIntInRange(0, 0x7fffffff), GetRandomIntInRange(0, 0x7fffffff))
    end
    -- Offline/test fallback: combine independent clock, PRNG and allocation
    -- entropy.  FiveM production uses GetRandomIntInRange above.
    math.randomseed(math.floor(os.clock() * 1000000) + os.time())
    local allocation = tostring({}):match('0x(%x+)') or tostring({})
    return ('%08x%08x%s'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), allocation)
end

local function nowMs(value)
    if type(value) == 'number' then return value end
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

function Tokens.new(options)
    options = options or {}
    return setmetatable({
        ttlMs = tonumber(options.ttlMs) or 5000,
        maxContainerLength = tonumber(options.maxContainerLength) or 64,
        maxActionLength = tonumber(options.maxActionLength) or 32,
        actions = options.actions or { attach = true, detach = true },
        clock = options.clock,
        sequence = 0,
        maxActivePerSession = tonumber(options.maxActivePerSession) or 32,
        maxIssuesPerWindow = tonumber(options.maxIssuesPerWindow) or 8,
        issueWindowMs = tonumber(options.issueWindowMs) or 1000,
        active = {},
        activeCount = {},
        issueWindows = {},
        replayLog = options.replayLog or function() end
    }, Tokens)
end

local function boundedString(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
end

function Tokens:_validBinding(containerId, action)
    if not boundedString(containerId, self.maxContainerLength)
        or not boundedString(action, self.maxActionLength)
        or not self.actions[action] then
        return false
    end
    return true
end

local function canonicalVersion(version)
    if version == nil then return nil end
    if type(version) ~= 'string' and type(version) ~= 'number' then return nil end
    local value = tostring(version)
    if #value == 0 or #value > 32 then return nil end
    return value
end

function Tokens:_now(value)
    return nowMs(self.clock and self.clock() or value)
end

function Tokens:_decrementActive(record)
    if not record or not record.activeCounted then return end
    local sessionKey = tostring(record.sessionId)
    local count = (self.activeCount[sessionKey] or 1) - 1
    self.activeCount[sessionKey] = count > 0 and count or nil
    record.activeCounted = false
end

function Tokens:_remove(token)
    local record = self.active[token]
    if not record then return end
    self:_decrementActive(record)
    self.active[token] = nil
end

function Tokens:_pruneExpired(current)
    for token, record in pairs(self.active) do
        if record.expiresAt <= current then self:_remove(token) end
    end
end

function Tokens:_allowIssue(sessionId, current)
    local key = tostring(sessionId)
    local window = self.issueWindows[key]
    if not window or current - window.startedAt >= self.issueWindowMs then
        window = { startedAt = current, count = 0 }
        self.issueWindows[key] = window
    end
    if window.count >= self.maxIssuesPerWindow then return false end
    window.count = window.count + 1
    return true
end

function Tokens:issue(sessionAuthority, sessionId, craneId, containerId, action, source, operatorId, timestamp, sessionToken, targetId, profileVersion)
    if not sessionAuthority or not sessionAuthority.validate then return nil, 'SESSION_AUTHORITY_REQUIRED' end
    local ok, sessionOrReason = sessionAuthority:validate(sessionId, craneId, source, operatorId, timestamp, sessionToken)
    if not ok then return nil, sessionOrReason end
    if not self:_validBinding(containerId, action) then return nil, 'INVALID_TOKEN_BINDING' end
    targetId = targetId or containerId
    if not boundedString(targetId, self.maxContainerLength) then return nil, 'INVALID_TOKEN_BINDING' end
    local rawProfileVersion = profileVersion
    profileVersion = canonicalVersion(rawProfileVersion)
    if rawProfileVersion ~= nil and profileVersion == nil then return nil, 'INVALID_TOKEN_BINDING' end
    local current = self:_now(timestamp)
    self:_pruneExpired(current)
    local sessionKey = tostring(sessionOrReason.id)
    if (self.activeCount[sessionKey] or 0) >= self.maxActivePerSession then return nil, 'TOKEN_RATE_LIMITED' end
    if not self:_allowIssue(sessionKey, current) then return nil, 'TOKEN_RATE_LIMITED' end
    self.sequence = self.sequence + 1
    local token
    repeat
        token = ('at_%s_%d'):format(entropy(), self.sequence)
    until not self.active[token]
    self.active[token] = {
        token = token, sessionId = sessionOrReason.id, craneId = tostring(craneId),
        containerId = tostring(containerId), action = tostring(action),
        targetId = tostring(targetId), profileVersion = profileVersion,
        source = sessionOrReason.source, operatorId = sessionOrReason.operatorId,
        issuedAt = current, expiresAt = current + self.ttlMs, consumed = false, activeCounted = true
    }
    self.activeCount[sessionKey] = (self.activeCount[sessionKey] or 0) + 1
    return token
end

function Tokens:consume(token, sessionAuthority, sessionId, craneId, containerId, action, source, operatorId, timestamp, sessionToken, targetId, profileVersion)
    if not self:_validBinding(containerId, action) then return false, 'INVALID_TOKEN_BINDING' end
    targetId = targetId or containerId
    if not boundedString(targetId, self.maxContainerLength) then return false, 'INVALID_TOKEN_BINDING' end
    local canonicalProfileVersion = canonicalVersion(profileVersion)
    if profileVersion ~= nil and canonicalProfileVersion == nil then return false, 'INVALID_TOKEN_BINDING' end
    local record = self.active[token]
    local current = self:_now(timestamp)
    if not record then self.replayLog({ reason = 'missing_or_replay' }); return false, 'TOKEN_INVALID' end
    if record.consumed then self.replayLog({ reason = 'replay', sessionId = record.sessionId, craneId = record.craneId }); return false, 'TOKEN_REPLAY' end
    if record.expiresAt <= current then
        self:_decrementActive(record)
        record.consumed = true
        self.replayLog({ reason = 'expired', sessionId = record.sessionId, craneId = record.craneId })
        return false, 'TOKEN_EXPIRED'
    end
    local ok, reason = sessionAuthority:validate(sessionId, craneId, source, operatorId, current, sessionToken)
    if not ok then self.replayLog({ reason = reason, sessionId = record.sessionId, craneId = record.craneId }); return false, reason end
    local matches = record.sessionId == tostring(sessionId)
        and record.craneId == tostring(craneId)
        and record.containerId == tostring(containerId)
        and record.action == tostring(action)
        and record.targetId == tostring(targetId)
        and record.profileVersion == canonicalProfileVersion
        and record.source == tostring(source)
        and record.operatorId == tostring(operatorId)
    if not matches then self.replayLog({ reason = 'token_binding_mismatch', sessionId = record.sessionId, craneId = record.craneId }); return false, 'TOKEN_BINDING_MISMATCH' end
    self:_decrementActive(record)
    record.consumed = true
    record.consumedAt = current
    return true, record
end

function Tokens:invalidateSession(sessionId)
    local count = 0
    for token, record in pairs(self.active) do
        if record.sessionId == tostring(sessionId) then self:_remove(token); count = count + 1 end
    end
    self.activeCount[tostring(sessionId)] = nil
    self.issueWindows[tostring(sessionId)] = nil
    return count
end

PortOpsCrane.ActionTokens = Tokens
PortOpsCrane.CraneActionTokens = Tokens.new()
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Crane.ActionTokens = Tokens
PortOps.Crane.ActionTokenAuthority = PortOpsCrane.CraneActionTokens
return Tokens
