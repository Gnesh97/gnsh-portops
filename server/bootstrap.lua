-- Production resource bootstrap.  The direct development path uses explicit
-- memory services, but preserves the same stage gates used by future DB and
-- framework adapters.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Bootstrap = {}
Bootstrap.__index = Bootstrap

local function clockMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function sourceNumber(source)
    local number = tonumber(source)
    return number or source
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function boundedSnapshot(snapshot, maxKeys)
    if type(snapshot) ~= 'table' then return nil, 'snapshot is invalid' end
    local count = 0
    for key, value in pairs(snapshot) do
        count = count + 1
        if count > maxKeys then return nil, 'payload too large' end
        if type(value) == 'table' and key ~= 'state' then return nil, 'nested snapshot payload is invalid' end
    end
    local state = snapshot.state
    if state ~= nil then
        if type(state) ~= 'table' then return nil, 'state payload is invalid' end
        local stateCount = 0
        for _, value in pairs(state) do
            stateCount = stateCount + 1
            if stateCount > maxKeys then return nil, 'payload too large' end
            if type(value) == 'table' then return nil, 'nested state payload is invalid' end
        end
    end
    local candidate = {
        version = snapshot.version,
        sequence = snapshot.sequence or snapshot.seq,
        timestamp = snapshot.timestamp or snapshot.timestampMs,
        craneId = snapshot.craneId,
        sessionId = snapshot.sessionId,
        gantry = snapshot.gantry,
        trolley = snapshot.trolley,
        spreader = snapshot.spreader,
        yaw = snapshot.yaw or snapshot.spreaderYaw
    }
    if state then
        candidate.state = {
            gantry = state.gantry,
            trolley = state.trolley,
            spreader = state.spreader,
            yaw = state.yaw or state.spreaderYaw
        }
    end
    return candidate
end

function Bootstrap.new(options)
    options = options or {}
    return setmetatable({
        config = options.config or PortOps.Config,
        features = options.features or PortOps.Features,
        stage = nil,
        ready = false,
        error = nil,
        registry = nil,
        sessions = nil,
        tokens = nil,
        recovery = nil,
        syncs = {},
        observers = {},
        eventsRegistered = false
    }, Bootstrap)
end

function Bootstrap:_stage(stage)
    self.stage = stage
    PortOps.ResourceStage = stage
end

function Bootstrap:_fail(stage, reason)
    self:_stage(PortOps.Enums.ResourceStage.FAILED)
    self.ready = false
    self.error = { stage = stage, reason = reason }
    if type(print) == 'function' then print(('[PortOps] startup failed at %s: %s'):format(stage, tostring(reason))) end
    return false, self.error
end

function Bootstrap:_operatorId(source)
    return 'standalone:' .. tostring(source)
end

function Bootstrap:_reply(source, eventName, result)
    if type(TriggerClientEvent) == 'function' then TriggerClientEvent(eventName, sourceNumber(source), result) end
end

function Bootstrap:_snapshotFor(craneId)
    local state = self.registry and self.registry:getState(craneId)
    if not state then return nil end
    return {
        version = PortOps.Crane.Protocol.VERSION,
        sequence = state.version,
        timestamp = state.updatedAt > 0 and state.updatedAt or clockMs(),
        craneId = craneId,
        sessionId = state.sessionId,
        state = clone(state.canonical)
    }
end

function Bootstrap:_broadcast(craneId, snapshot)
    local recipients = self.observers[craneId] or {}
    for playerSource in pairs(recipients) do
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent('portops:crane:canonical', sourceNumber(playerSource), craneId, snapshot)
        end
    end
end

function Bootstrap:_onSessionInvalidated(session, reason)
    if self.recovery and self.recovery.inProgress[session.craneId] then return end
    if reason == 'disconnect' and self.recovery then
        self.recovery:freeze(session.craneId, 'operator disconnected', session.invalidatedAt)
        return
    end
    if self.tokens then self.tokens:invalidateSession(session.id) end
    if self.registry then self.registry:release(session.craneId, session.id) end
    local sync = self.syncs[session.craneId]
    if sync then
        PortOps.Crane.ServerSync.clearOperator(sync, session.source)
        PortOps.Crane.ServerSync.setSession(sync, nil, session.craneId)
    end
end

function Bootstrap:handleReserve(source, craneId)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not PortOps.Crane.Validation.requiredIdentifier(craneId, 64) then return PortOps.Errors.err('INPUT_INVALID', 'crane id is invalid') end
    local state = self.registry:get(craneId)
    if not state then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    if state.recoveryRequired or state.frozen then return PortOps.Errors.err('RECOVERY_REQUIRED', 'crane requires recovery') end
    local session, reason = self.sessions:reserve(craneId, source, self:_operatorId(source), clockMs())
    if not session then return PortOps.Errors.err(PortOps.Errors.code(reason, 'CRANE_OCCUPIED'), reason) end
    local ok, registryState = self.registry:reserve(craneId, session)
    if not ok then
        self.sessions:release(session.id, source, clockMs())
        return PortOps.Errors.err(PortOps.Errors.code(registryState, 'CRANE_UNAVAILABLE'), registryState)
    end
    local sync = self.syncs[craneId]
    if sync then
        PortOps.Crane.ServerSync.setSession(sync, session.id, craneId)
        PortOps.Crane.ServerSync.setOperator(sync, source)
    end
    return PortOps.Errors.ok({
        craneId = craneId,
        sessionId = session.id,
        sessionToken = session.token,
        serverTime = clockMs(),
        expiresAt = session.expiresAt,
        state = registryState
    })
end

function Bootstrap:handleRelease(source, sessionId, sessionToken)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not PortOps.Crane.Validation.requiredIdentifier(sessionId, 128) or not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('INPUT_INVALID', 'session credential is invalid') end
    local ok, sessionOrReason = self.sessions:validate(sessionId, nil, source, self:_operatorId(source), clockMs(), sessionToken)
    if not ok then return PortOps.Errors.err(PortOps.Errors.code(sessionOrReason, 'SESSION_INVALID'), sessionOrReason) end
    local released, reason = self.sessions:release(sessionId, source, clockMs())
    if not released then return PortOps.Errors.err(PortOps.Errors.code(reason, 'SESSION_INVALID'), reason) end
    self.registry:release(sessionOrReason.craneId, sessionId)
    local sync = self.syncs[sessionOrReason.craneId]
    if sync then
        PortOps.Crane.ServerSync.clearOperator(sync, source)
        PortOps.Crane.ServerSync.setSession(sync, nil, sessionOrReason.craneId)
    end
    return PortOps.Errors.ok({ craneId = sessionOrReason.craneId, sessionId = sessionId, released = true })
end

function Bootstrap:handleSnapshot(source, craneId, snapshot)
    if not self.ready or type(snapshot) ~= 'table' then return PortOps.Errors.err('SNAPSHOT_INVALID', 'snapshot is invalid') end
    if not PortOps.Crane.Validation.requiredIdentifier(craneId, 64) then return PortOps.Errors.err('SNAPSHOT_INVALID', 'crane id is invalid') end
    if snapshot.version ~= PortOps.Crane.Protocol.VERSION then return PortOps.Errors.err('SNAPSHOT_INVALID', 'protocol version is invalid') end
    local sessionId = snapshot.sessionId
    local sessionToken = snapshot.sessionToken
    if not PortOps.Crane.Validation.requiredIdentifier(sessionId, 128) or not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('SESSION_INVALID', 'session credential is invalid') end
    local valid, sessionOrReason = self.sessions:validate(sessionId, craneId, source, self:_operatorId(source), clockMs(), sessionToken)
    if not valid then return PortOps.Errors.err(PortOps.Errors.code(sessionOrReason, 'SESSION_INVALID'), sessionOrReason) end
    local state = self.registry:get(craneId)
    if not state or state.recoveryRequired or state.frozen then return PortOps.Errors.err('RECOVERY_REQUIRED', 'crane requires recovery') end
    local sync = self.syncs[craneId]
    if not sync then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    PortOps.Crane.ServerSync.setSession(sync, sessionId, craneId)
    PortOps.Crane.ServerSync.setOperator(sync, source)
    local candidate, candidateReason = boundedSnapshot(snapshot, self.config.crane.maxPayloadKeys or 16)
    if not candidate then return PortOps.Errors.err('SNAPSHOT_INVALID', candidateReason) end
    candidate.craneId = craneId
    candidate.sessionId = sessionId
    local accepted, normalizedOrReason = PortOps.Crane.ServerSync.accept(sync, source, candidate, clockMs())
    if not accepted then
        local code = 'SNAPSHOT_INVALID'
        if normalizedOrReason == 'snapshot rate limited' then code = 'SNAPSHOT_RATE_LIMITED'
        elseif normalizedOrReason == 'late sequence' then code = 'SNAPSHOT_STALE'
        elseif type(normalizedOrReason) == 'string' and normalizedOrReason:find('out of bounds', 1, true) then code = 'SNAPSHOT_OUT_OF_BOUNDS'
        elseif type(normalizedOrReason) == 'string' and normalizedOrReason:find('delta too large', 1, true) then code = 'SNAPSHOT_DELTA_TOO_LARGE'
        elseif normalizedOrReason == 'future timestamp' or normalizedOrReason == 'stale timestamp' then code = 'SNAPSHOT_TIMESTAMP_INVALID' end
        return PortOps.Errors.err(code, normalizedOrReason)
    end
    local updated, registryState = self.registry:updateCanonical(craneId, normalizedOrReason.state, sessionId, normalizedOrReason.timestamp)
    if not updated then return PortOps.Errors.err(PortOps.Errors.code(registryState, 'SNAPSHOT_INVALID'), registryState) end
    local outbound = clone(normalizedOrReason)
    outbound.version = registryState.version
    self:_broadcast(craneId, outbound)
    return PortOps.Errors.ok({ snapshot = outbound, state = registryState })
end

function Bootstrap:handleObserve(source, craneId)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not PortOps.Crane.Validation.requiredIdentifier(craneId, 64) then return PortOps.Errors.err('INPUT_INVALID', 'crane id is invalid') end
    if not self.registry:get(craneId) then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    self.observers[craneId] = self.observers[craneId] or {}
    self.observers[craneId][tostring(source)] = true
    local state = self.registry:get(craneId)
    if state.recoveryRequired then
        if type(TriggerClientEvent) == 'function' then
            TriggerClientEvent('portops:crane:recovery_required', sourceNumber(source), craneId, {
                reason = state.recoveryReason,
                attachedContainerId = state.attachedContainerId,
                mode = state.mode,
                version = state.version
            })
        end
    else
        local snapshot = self:_snapshotFor(craneId)
        snapshot.resync = true
        if type(TriggerClientEvent) == 'function' then TriggerClientEvent('portops:crane:canonical', sourceNumber(source), craneId, snapshot) end
    end
    return PortOps.Errors.ok({ craneId = craneId, resync = true })
end

function Bootstrap:handleUnobserve(source, craneId)
    if not PortOps.Crane.Validation.requiredIdentifier(craneId, 64) then return PortOps.Errors.err('INPUT_INVALID', 'crane id is invalid') end
    if self.observers[craneId] then self.observers[craneId][tostring(source)] = nil end
    return PortOps.Errors.ok({ craneId = craneId })
end

function Bootstrap:handleTokenIssue(source, craneId, sessionId, containerId, action, sessionToken, targetId)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not PortOps.Crane.Validation.requiredIdentifier(craneId, 64) or not PortOps.Crane.Validation.requiredIdentifier(sessionId, 128) then return PortOps.Errors.err('INPUT_INVALID', 'token session binding is invalid') end
    if not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('INPUT_INVALID', 'session credential is invalid') end
    local profile = self.registry:getProfile(craneId)
    if not profile then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    targetId = targetId or containerId
    local token, reason = self.tokens:issue(self.sessions, sessionId, craneId, containerId, action, source, self:_operatorId(source), clockMs(), sessionToken, targetId, profile.version)
    if not token then return PortOps.Errors.err(PortOps.Errors.code(reason, 'TOKEN_INVALID'), reason) end
    return PortOps.Errors.ok({ token = token, targetId = targetId, profileVersion = profile.version, expiresAt = clockMs() + self.config.crane.actionTokenTtlMs })
end

function Bootstrap:handleTokenConsume(source, token, craneId, sessionId, containerId, action, sessionToken, targetId)
    if not PortOps.Crane.Validation.requiredIdentifier(token, 256) or not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('INPUT_INVALID', 'token credential is invalid') end
    local profile = self.registry:getProfile(craneId)
    if not profile then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    targetId = targetId or containerId
    local consumed, recordOrReason = self.tokens:consume(token, self.sessions, sessionId, craneId, containerId, action, source, self:_operatorId(source), clockMs(), sessionToken, targetId, profile.version)
    if not consumed then return PortOps.Errors.err(PortOps.Errors.code(recordOrReason, 'TOKEN_INVALID'), recordOrReason) end
    return PortOps.Errors.ok({ craneId = recordOrReason.craneId, sessionId = recordOrReason.sessionId, action = recordOrReason.action })
end

function Bootstrap:handleDisconnect(source)
    local impacted = {}
    for craneId, recipients in pairs(self.observers) do recipients[tostring(source)] = nil end
    for _, session in pairs(self.sessions and self.sessions.bySession or {}) do
        if session.source == tostring(source) then impacted[#impacted + 1] = session.craneId end
    end
    if self.recovery then self.recovery:handleDisconnect(source, clockMs()) end
    for _, craneId in ipairs(impacted) do
        local sync = self.syncs[craneId]
        if sync then PortOps.Crane.ServerSync.clearOperator(sync, source); PortOps.Crane.ServerSync.setSession(sync, nil, craneId) end
        for observerSource in pairs(self.observers[craneId] or {}) do
            if type(TriggerClientEvent) == 'function' then
                local state = self.registry:getState(craneId) or {}
                TriggerClientEvent('portops:crane:recovery_required', sourceNumber(observerSource), craneId, {
                    reason = 'operator disconnected',
                    attachedContainerId = state.attachedContainerId,
                    mode = state.mode,
                    version = state.version
                })
            end
        end
    end
    return #impacted
end

function Bootstrap:_registerEvents()
    if self.eventsRegistered or type(RegisterNetEvent) ~= 'function' or type(AddEventHandler) ~= 'function' then return end
    self.eventsRegistered = true
    local runtime = PortOps.Crane.Runtime
    RegisterNetEvent('portops:crane:reserve')
    AddEventHandler('portops:crane:reserve', function(craneId)
        self:_reply(source, 'portops:crane:session', runtime.handleReserve(source, craneId))
    end)
    RegisterNetEvent('portops:crane:release')
    AddEventHandler('portops:crane:release', function(sessionId, sessionToken)
        self:_reply(source, 'portops:crane:session', runtime.handleRelease(source, sessionId, sessionToken))
    end)
    RegisterNetEvent('portops:crane:snapshot')
    AddEventHandler('portops:crane:snapshot', function(craneId, snapshot)
        runtime.handleSnapshot(source, craneId, snapshot)
    end)
    RegisterNetEvent('portops:crane:observe')
    AddEventHandler('portops:crane:observe', function(craneId)
        self:_reply(source, 'portops:crane:observe_ack', runtime.handleObserve(source, craneId))
    end)
    RegisterNetEvent('portops:crane:unobserve')
    AddEventHandler('portops:crane:unobserve', function(craneId)
        self:_reply(source, 'portops:crane:observe_ack', runtime.handleUnobserve(source, craneId))
    end)
    RegisterNetEvent('portops:crane:action:issue')
    AddEventHandler('portops:crane:action:issue', function(craneId, sessionId, containerId, action, sessionToken, targetId)
        self:_reply(source, 'portops:crane:action:result', runtime.handleTokenIssue(source, craneId, sessionId, containerId, action, sessionToken, targetId))
    end)
    RegisterNetEvent('portops:crane:action:consume')
    AddEventHandler('portops:crane:action:consume', function(token, craneId, sessionId, containerId, action, sessionToken, targetId)
        self:_reply(source, 'portops:crane:action:result', runtime.handleTokenConsume(source, token, craneId, sessionId, containerId, action, sessionToken, targetId))
    end)
    AddEventHandler('playerDropped', function()
        runtime.handleDisconnect(source)
    end)
end

function Bootstrap:run()
    self:_stage(PortOps.Enums.ResourceStage.CONFIG)
    local valid, validationErrors = PortOps.Security.Validation.validateConfig(self.config, self.features)
    if not valid then return self:_fail(PortOps.Enums.ResourceStage.CONFIG, table.concat(validationErrors, '; ')) end
    local Registry = PortOps.Crane.Registry
    local Sessions = PortOps.Crane.Sessions
    local Tokens = PortOps.Crane.ActionTokens
    local ServerSync = PortOps.Crane.ServerSync
    local Recovery = PortOps.Crane.Recovery
    if not Registry or not Sessions or not Tokens or not ServerSync or not Recovery then return self:_fail(PortOps.Enums.ResourceStage.SERVICES, 'required modules are missing') end
    local registry, registryReason = Registry.new(self.config)
    if not registry then return self:_fail(PortOps.Enums.ResourceStage.CONFIG, registryReason) end
    self.registry = registry

    self:_stage(PortOps.Enums.ResourceStage.DB)
    if self.config.database.provider ~= 'memory' then return self:_fail(PortOps.Enums.ResourceStage.DB, 'only explicit memory provider is available in direct development') end
    self:_stage(PortOps.Enums.ResourceStage.ADAPTERS)
    if self.config.framework.provider ~= 'standalone' then return self:_fail(PortOps.Enums.ResourceStage.ADAPTERS, 'framework adapter is not enabled') end

    self:_stage(PortOps.Enums.ResourceStage.SERVICES)
    self.sessions = Sessions.new({ ttlMs = self.config.crane.sessionTtlMs, onInvalidated = function(session, reason) self:_onSessionInvalidated(session, reason) end })
    self.tokens = Tokens.new({
        ttlMs = self.config.crane.actionTokenTtlMs,
        maxActivePerSession = self.config.crane.actionTokenMaxActivePerSession,
        maxIssuesPerWindow = self.config.crane.actionTokenMaxIssuesPerWindow,
        issueWindowMs = self.config.crane.actionTokenIssueWindowMs,
        replayLog = function(event) if type(print) == 'function' and self.config.environment ~= 'production' then print(('[PortOps] token rejected: %s'):format(tostring(event.reason))) end end
    })
    self.recovery = Recovery.new({ registry = self.registry, sessions = self.sessions, tokens = self.tokens, notify = function(craneId, state, reason)
        for observerSource in pairs(self.observers[craneId] or {}) do
            if type(TriggerClientEvent) == 'function' then
                TriggerClientEvent('portops:crane:recovery_required', sourceNumber(observerSource), craneId, {
                    reason = reason,
                    attachedContainerId = state.attachedContainerId,
                    mode = state.mode,
                    version = state.version
                })
            end
        end
    end })
    for craneId, state in pairs(self.registry.states) do
        local profile = self.registry:getProfile(craneId)
        local maxDeltaPerSecond = {
            gantry = profile.gantry.maxSpeed / (profile.gantry.max - profile.gantry.min),
            trolley = profile.trolley.maxSpeed / (profile.trolley.max - profile.trolley.min),
            spreader = profile.spreader.maxSpeed / (profile.spreader.max - profile.spreader.min),
            yaw = profile.yaw and profile.yaw.maxSpeed or 360.0
        }
        self.syncs[craneId] = ServerSync.new({
            craneId = craneId,
            initialState = state.canonical,
            snapshotHz = self.config.crane.snapshotHz,
            snapshotBurst = self.config.crane.snapshotBurst,
            burstWindowMs = self.config.crane.burstWindowMs,
            maxPayloadKeys = self.config.crane.maxPayloadKeys,
            maxFutureSkewMs = self.config.crane.futureSkewMs,
            maxAgeMs = self.config.crane.maxSnapshotAgeMs,
            interpolationDelayMs = self.config.crane.interpolationDelayMs,
            bufferSize = self.config.crane.observerBufferSize,
            maxDeltaPerSecond = maxDeltaPerSecond
        })
    end
    self.ready = true
    self:_stage(PortOps.Enums.ResourceStage.READY)
    PortOps.Crane.Runtime = {
        bootstrap = self,
        handleReserve = function(source, craneId) return self:handleReserve(source, craneId) end,
        handleRelease = function(source, sessionId, sessionToken) return self:handleRelease(source, sessionId, sessionToken) end,
        handleSnapshot = function(source, craneId, snapshot) return self:handleSnapshot(source, craneId, snapshot) end,
        handleObserve = function(source, craneId) return self:handleObserve(source, craneId) end,
        handleUnobserve = function(source, craneId) return self:handleUnobserve(source, craneId) end,
        handleTokenIssue = function(source, craneId, sessionId, containerId, action, sessionToken, targetId) return self:handleTokenIssue(source, craneId, sessionId, containerId, action, sessionToken, targetId) end,
        handleTokenConsume = function(source, token, craneId, sessionId, containerId, action, sessionToken, targetId) return self:handleTokenConsume(source, token, craneId, sessionId, containerId, action, sessionToken, targetId) end,
        handleDisconnect = function(source) return self:handleDisconnect(source) end
    }
    PortOps.Crane.RegistryInstance = self.registry
    PortOps.Crane.SessionAuthority = self.sessions
    PortOps.Crane.ActionTokenAuthority = self.tokens
    self:_registerEvents()
    if self.config.environment == 'development' and type(RegisterCommand) == 'function' then
        RegisterCommand('portops_status', function()
            for craneId in pairs(self.registry.states) do
                local state = self.registry:getState(craneId)
                print(('[PortOps] stage=%s ready=%s crane=%s mode=%s version=%s recovery=%s'):format(
                    tostring(self.stage), tostring(self.ready), craneId, tostring(state.mode), tostring(state.version), tostring(state.recoveryRequired)))
            end
        end, true)
    end
    if type(print) == 'function' then print(('[PortOps] %s ready (%s)'):format(self.config.version, self.config.environment)) end
    return true, self
end

PortOps.Bootstrap = Bootstrap
PortOps.Runtime = PortOps.Runtime or {}
PortOps.Runtime.Bootstrap = Bootstrap.new()
PortOps.Runtime.Bootstrap:run()
