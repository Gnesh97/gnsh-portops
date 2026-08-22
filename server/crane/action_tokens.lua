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
        active = {},
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
        issuedAt = current, expiresAt = current + self.ttlMs, consumed = false
    }
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
    record.consumed = true
    record.consumedAt = current
    return true, record
end

function Tokens:invalidateSession(sessionId)
    local count = 0
    for token, record in pairs(self.active) do
        if record.sessionId == tostring(sessionId) then self.active[token] = nil; count = count + 1 end
    end
    return count
end

PortOpsCrane.ActionTokens = Tokens
PortOpsCrane.CraneActionTokens = Tokens.new()
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Crane.ActionTokens = Tokens
PortOps.Crane.ActionTokenAuthority = PortOpsCrane.CraneActionTokens
return Tokens
