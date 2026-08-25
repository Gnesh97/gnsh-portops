-- Production resource bootstrap.  The direct development path uses explicit
-- memory services, but preserves the same stage gates used by future DB and
-- framework adapters.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Core = PortOps.Core or {}
PortOps.Adapters = PortOps.Adapters or {}

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

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function validPosition(position)
    local kind = type(position)
    return (kind == 'table' or kind == 'vector3' or kind == 'userdata') and finite(position.x) and finite(position.y) and finite(position.z)
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function reasonText(reason)
    if type(reason) == 'table' and reason.error then
        return ('%s: %s'):format(tostring(reason.error.code), tostring(reason.error.message))
    end
    return tostring(reason)
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
    local logger = options.logger
    if not logger and PortOps.Core.Logger then logger = PortOps.Core.Logger.new({ category = 'portops' }) end
    return setmetatable({
        config = options.config or PortOps.Config,
        features = options.features or PortOps.Features,
        logger = logger,
        events = options.events,
        database = nil,
        migrations = nil,
        framework = nil,
        containerRepository = nil,
        containerStateMachine = nil,
        containerService = nil,
        streamingService = nil,
        yardRepository = nil,
        yardService = nil,
        placementService = nil,
        moveRepository = nil,
        moveStateMachine = nil,
        moveStepStateMachine = nil,
        moveAssignment = nil,
        moveService = nil,
        craneService = nil,
        fieldOperationService = nil,
        recoveryService = nil,
        vesselRepository = nil,
        vesselCallRepository = nil,
        vesselCallStateMachine = nil,
        vesselCallService = nil,
        berthService = nil,
        manifestRepository = nil,
        manifestService = nil,
        dischargePlanningService = nil,
        gateRepository = nil,
        gateService = nil,
        customsRepository = nil,
        customsRiskService = nil,
        customsService = nil,
        employeeRepository = nil,
        employeeService = nil,
        equipmentRepository = nil,
        equipmentService = nil,
        exceptionRepository = nil,
        exceptionService = nil,
        activityRepository = nil,
        activityService = nil,
        auditRepository = nil,
        auditService = nil,
        analyticsRepository = nil,
        analyticsService = nil,
        idempotency = nil,
        playerPositionResolver = options.playerPositionResolver,
        stage = nil,
        ready = false,
        error = nil,
        registry = nil,
        sessions = nil,
        tokens = nil,
        recovery = nil,
        syncs = {},
        observers = {},
        eventsRegistered = false,
        eventUnsubscribers = {},
        recoveryRequired = false,
        recoveryWarnings = {}
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
    if PortOps.Crane and PortOps.Crane.Runtime and PortOps.Crane.Runtime.bootstrap == self then PortOps.Crane.Runtime = nil end
    if PortOps.Runtime and PortOps.Runtime.Bootstrap == self then PortOps.Runtime = {} end
    if self.database and self.database.close then pcall(self.database.close, self.database) end
    if self.logger and self.logger.error then self.logger:error('startup failed', { stage = stage, reason = reason }) end
    if type(print) == 'function' then print(('[PortOps] startup failed at %s: %s'):format(stage, reasonText(reason))) end
    return false, self.error
end

function Bootstrap:stop()
    if self.events and self.events.emit then self.events:emit('portops:resource.stop', { version = self.config and self.config.version }) end
    if self.database and self.database.close then self.database:close() end
    -- Make in-process authority state inert across a resource restart.
    self.observers = {}
    self.syncs = {}
    self.sessions = nil
    self.tokens = nil
    self.recovery = nil
    self.registry = nil
    self.streamingService = nil
    self.containerService = nil
    self.containerRepository = nil
    self.placementService = nil
    self.yardService = nil
    self.yardRepository = nil
    self.moveService = nil
    self.moveAssignment = nil
    self.moveStepStateMachine = nil
    self.moveStateMachine = nil
    self.moveRepository = nil
    self.craneService = nil
    self.fieldOperationService = nil
    self.recoveryService = nil
    self.vesselCallService = nil
    self.vesselCallStateMachine = nil
    self.vesselRepository = nil
    self.vesselCallRepository = nil
    self.berthService = nil
    self.manifestService = nil
    self.manifestRepository = nil
    self.dischargePlanningService = nil
    self.gateService = nil
    self.gateRepository = nil
    self.customsService = nil
    self.customsRiskService = nil
    self.customsRepository = nil
    self.employeeService = nil
    self.employeeRepository = nil
    self.equipmentService = nil
    self.equipmentRepository = nil
    self.exceptionService = nil
    self.exceptionRepository = nil
    self.activityService = nil
    self.activityRepository = nil
    self.auditService = nil
    self.auditRepository = nil
    self.analyticsService = nil
    self.analyticsRepository = nil
    self.idempotency = nil
    self.recoveryRequired = false
    self.recoveryWarnings = {}
    if PortOps.Crane.Runtime and PortOps.Crane.Runtime.bootstrap == self then PortOps.Crane.Runtime = nil end
    if PortOps.Runtime and PortOps.Runtime.Bootstrap == self then PortOps.Runtime = {} end
    self.ready = false
    self.eventsRegistered = false
    for _, unsubscribe in ipairs(self.eventUnsubscribers or {}) do pcall(unsubscribe) end
    self.eventUnsubscribers = {}
    return true
end

function Bootstrap:_operatorId(source)
    local provider = self.framework and self.framework.provider or (self.config.framework and self.config.framework.provider)
    if self.framework and type(self.framework.getIdentifier) == 'function' then
        local ok, identifier = pcall(self.framework.getIdentifier, self.framework, source)
        if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
    end
    if provider == 'standalone' or provider == nil then return 'standalone:' .. tostring(source) end
    return nil
end

function Bootstrap:_operator(source)
    local identifier = self:_operatorId(source)
    if identifier then return identifier end
    return nil, PortOps.Errors.err('FRAMEWORK_IDENTITY_UNAVAILABLE', 'framework identity is unavailable')
end

function Bootstrap:_reply(source, eventName, result)
    if type(TriggerClientEvent) == 'function' then TriggerClientEvent(eventName, sourceNumber(source), result) end
end

function Bootstrap:_registerExports()
    if type(exports) ~= 'function' or not (PortOps.Api and PortOps.Api.Exports) then return true end
    local failures = {}
    for name, handler in pairs(PortOps.Api.Exports) do
        if type(handler) == 'function' then
            local ok, reason = pcall(exports, name, handler)
            if not ok then failures[#failures + 1] = ('%s: %s'):format(tostring(name), tostring(reason)) end
        end
    end
    if #failures > 0 then return false, 'API_EXPORT_REGISTRATION_FAILED: ' .. table.concat(failures, '; ') end
    return true
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
    local operatorId, identityError = self:_operator(source)
    if not operatorId then return identityError end
    local state = self.registry:get(craneId)
    if not state then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    if state.recoveryRequired or state.frozen then return PortOps.Errors.err('RECOVERY_REQUIRED', 'crane requires recovery') end
    local session, reason = self.sessions:reserve(craneId, source, operatorId, clockMs())
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
    local operatorId, identityError = self:_operator(source)
    if not operatorId then return identityError end
    local ok, sessionOrReason = self.sessions:validate(sessionId, nil, source, operatorId, clockMs(), sessionToken)
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
    local operatorId, identityError = self:_operator(source)
    if not operatorId then return identityError end
    local sessionId = snapshot.sessionId
    local sessionToken = snapshot.sessionToken
    if not PortOps.Crane.Validation.requiredIdentifier(sessionId, 128) or not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('SESSION_INVALID', 'session credential is invalid') end
    local valid, sessionOrReason = self.sessions:validate(sessionId, craneId, source, operatorId, clockMs(), sessionToken)
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
    local operatorId, identityError = self:_operator(source)
    if not operatorId then return identityError end
    local profile = self.registry:getProfile(craneId)
    if not profile then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    targetId = targetId or containerId
    local token, reason = self.tokens:issue(self.sessions, sessionId, craneId, containerId, action, source, operatorId, clockMs(), sessionToken, targetId, profile.version)
    if not token then return PortOps.Errors.err(PortOps.Errors.code(reason, 'TOKEN_INVALID'), reason) end
    return PortOps.Errors.ok({ token = token, targetId = targetId, profileVersion = profile.version, expiresAt = clockMs() + self.config.crane.actionTokenTtlMs })
end

function Bootstrap:handleTokenConsume(source, token, craneId, sessionId, containerId, action, sessionToken, targetId)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not PortOps.Crane.Validation.requiredIdentifier(token, 256) or not PortOps.Crane.Validation.requiredIdentifier(sessionToken, 256) then return PortOps.Errors.err('INPUT_INVALID', 'token credential is invalid') end
    local operatorId, identityError = self:_operator(source)
    if not operatorId then return identityError end
    local profile = self.registry:getProfile(craneId)
    if not profile then return PortOps.Errors.err('CRANE_NOT_FOUND', 'crane does not exist') end
    targetId = targetId or containerId
    local consumed, recordOrReason = self.tokens:consume(token, self.sessions, sessionId, craneId, containerId, action, source, operatorId, clockMs(), sessionToken, targetId, profile.version)
    if not consumed then return PortOps.Errors.err(PortOps.Errors.code(recordOrReason, 'TOKEN_INVALID'), recordOrReason) end
    return PortOps.Errors.ok({ craneId = recordOrReason.craneId, sessionId = recordOrReason.sessionId, action = recordOrReason.action })
end

function Bootstrap:handleDisconnect(source)
    local impacted = {}
    for craneId, recipients in pairs(self.observers) do recipients[tostring(source)] = nil end
    if self.streamingService then self.streamingService:unsubscribe(source) end
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

function Bootstrap:handleContainerStream(source, position, options)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not self.streamingService then return PortOps.Errors.err('STREAMING_UNAVAILABLE', 'container streaming is unavailable') end
    local authoritativePosition
    if type(self.playerPositionResolver) == 'function' then
        local ok, resolved = pcall(self.playerPositionResolver, source)
        if ok and validPosition(resolved) then authoritativePosition = resolved end
    elseif type(GetPlayerPed) == 'function' and type(GetEntityCoords) == 'function' then
        local pedOk, ped = pcall(GetPlayerPed, sourceNumber(source))
        if pedOk and ped and tonumber(ped) ~= 0 then
            local coordsOk, coords = pcall(GetEntityCoords, ped)
            if coordsOk and validPosition(coords) then
                authoritativePosition = { x = coords.x, y = coords.y, z = coords.z }
            end
        end
    end
    if not authoritativePosition and type(self.playerPositionResolver) ~= 'function' and self.config and self.config.environment == 'development' and validPosition(position) then
        -- The development memory profile can run without OneSync natives. A
        -- production profile never falls back to a client-supplied position.
        authoritativePosition = { x = position.x, y = position.y, z = position.z }
    end
    if not authoritativePosition then return PortOps.Errors.err('STREAM_POSITION_INVALID', 'authoritative player position is unavailable') end
    return self.streamingService:subscribe(source, authoritativePosition, options)
end

function Bootstrap:_authoritativePosition(source, proposed)
    local authoritativePosition
    if type(self.playerPositionResolver) == 'function' then
        local ok, resolved = pcall(self.playerPositionResolver, source)
        if ok and validPosition(resolved) then authoritativePosition = resolved end
    elseif type(GetPlayerPed) == 'function' and type(GetEntityCoords) == 'function' then
        local pedOk, ped = pcall(GetPlayerPed, sourceNumber(source))
        if pedOk and ped and tonumber(ped) ~= 0 then
            local coordsOk, coords = pcall(GetEntityCoords, ped)
            if coordsOk and validPosition(coords) then authoritativePosition = { x = coords.x, y = coords.y, z = coords.z } end
        end
    end
    if not authoritativePosition and type(self.playerPositionResolver) ~= 'function' and self.config and self.config.environment == 'development' and validPosition(proposed) then
        authoritativePosition = { x = proposed.x, y = proposed.y, z = proposed.z }
    end
    return authoritativePosition
end

function Bootstrap:handleYardStream(source, position, options)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not self.yardService then return PortOps.Errors.err('YARD_UNAVAILABLE', 'yard service is unavailable') end
    local authoritative = self:_authoritativePosition(source, position)
    if not authoritative then return PortOps.Errors.err('STREAM_POSITION_INVALID', 'authoritative player position is unavailable') end
    options = type(options) == 'table' and options or {}
    local radius = math.min(math.max(tonumber(options.radius) or 90, 10), 200)
    local result = self.yardService:list({ block = options.block })
    if PortOps.Core.Result.isErr(result) then return PortOps.Errors.err(result.error.code, result.error.message, result.error.details) end
    local descriptors = {}
    for _, descriptor in ipairs(result.data or {}) do
        local transform = descriptor.transform or {}
        local dx, dy, dz = (transform.x or 0) - authoritative.x, (transform.y or 0) - authoritative.y, (transform.z or 0) - authoritative.z
        if math.sqrt(dx * dx + dy * dy + dz * dz) <= radius then descriptors[#descriptors + 1] = descriptor end
    end
    return PortOps.Errors.ok(descriptors, { requestId = options.requestId })
end

function Bootstrap:handleYardPlacement(source, containerId, slotId, physical, ownerId, expectedVersion, expectedSlotVersion)
    if not self.ready then return PortOps.Errors.err('RESOURCE_NOT_READY', 'resource is not ready') end
    if not self.placementService then return PortOps.Errors.err('YARD_UNAVAILABLE', 'placement service is unavailable') end
    if type(containerId) ~= 'string' or type(slotId) ~= 'string' then return PortOps.Errors.err('INPUT_INVALID', 'placement identifiers are invalid') end
    local owner = self:_operatorId(source)
    if not owner then return PortOps.Errors.err('FRAMEWORK_IDENTITY_UNAVAILABLE', 'framework identity is unavailable') end
    if ownerId ~= nil and tostring(ownerId) ~= tostring(owner) then return PortOps.Errors.err('NOT_AUTHORIZED', 'placement owner mismatch') end
    return self.placementService:place(containerId, slotId, physical, owner, expectedVersion, expectedSlotVersion)
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
        self:_reply(source, 'portops:crane:snapshot:result', runtime.handleSnapshot(source, craneId, snapshot))
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
    RegisterNetEvent('portops:containers:stream:request')
    AddEventHandler('portops:containers:stream:request', function(position, options)
        self:_reply(source, 'portops:containers:stream:response', runtime.handleContainerStream(source, position, options))
    end)
    RegisterNetEvent('portops:yard:stream:request')
    AddEventHandler('portops:yard:stream:request', function(position, options)
        self:_reply(source, 'portops:yard:stream:response', runtime.handleYardStream(source, position, options))
    end)
    RegisterNetEvent('portops:yard:place')
    AddEventHandler('portops:yard:place', function(containerId, slotId, physical, ownerId, expectedVersion, expectedSlotVersion)
        self:_reply(source, 'portops:yard:place:result', runtime.handleYardPlacement(source, containerId, slotId, physical, ownerId, expectedVersion, expectedSlotVersion))
    end)
    AddEventHandler('playerDropped', function()
        runtime.handleDisconnect(source)
    end)
    AddEventHandler('onResourceStop', function(resourceName)
        local current = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or nil
        if current and resourceName == current then self:stop() end
    end)
end

function Bootstrap:run()
    self:_stage(PortOps.Enums.ResourceStage.CONFIG)
    local valid, validationErrors = PortOps.Security.Validation.validateConfig(self.config, self.features)
    if not valid then return self:_fail(PortOps.Enums.ResourceStage.CONFIG, table.concat(validationErrors, '; ')) end
    if not self.logger and PortOps.Core.Logger then self.logger = PortOps.Core.Logger.new({ category = 'portops', level = self.config.logging and self.config.logging.level }) end
    if not self.events and PortOps.Core.EventBus then self.events = PortOps.Core.EventBus.new({ logger = self.logger }) end
    local Registry = PortOps.Crane.Registry
    local Sessions = PortOps.Crane.Sessions
    local Tokens = PortOps.Crane.ActionTokens
    local ServerSync = PortOps.Crane.ServerSync
    local Recovery = PortOps.Crane.Recovery
    local Result = PortOps.Core.Result
    local Migrations = PortOps.Core.Migrations
    local Database = PortOps.Adapters.Database and PortOps.Adapters.Database.Interface
    local Framework = PortOps.Adapters.Framework and PortOps.Adapters.Framework.Interface
    local ContainerDomain = PortOps.Domain and PortOps.Domain.Container
    local ContainerRepository = PortOps.Repositories and PortOps.Repositories.Container
    local ContainerStateMachine = PortOps.State and PortOps.State.ContainerStateMachine
    local ContainerService = PortOps.Services and PortOps.Services.Container
    local StreamingService = PortOps.Services and PortOps.Services.Streaming
    local YardDomain = PortOps.Domain and PortOps.Domain.Yard
    local YardRepository = PortOps.Repositories and PortOps.Repositories.Yard
    local YardService = PortOps.Services and PortOps.Services.Yard
    local PlacementService = PortOps.Services and PortOps.Services.Placement
    local MoveDomain = PortOps.Domain and PortOps.Domain.Move
    local MoveRepository = PortOps.Repositories and PortOps.Repositories.Move
    local MoveStateMachine = PortOps.State and PortOps.State.MoveStateMachine
    local MoveStepStateMachine = PortOps.State and PortOps.State.MoveStepStateMachine
    local MoveService = PortOps.Services and PortOps.Services.Move
    local MoveAssignment = PortOps.Services and (PortOps.Services.MoveAssignment or PortOps.Services.Assignment)
    local VesselRepository = PortOps.Repositories and PortOps.Repositories.Vessel
    local VesselCallRepository = PortOps.Repositories and PortOps.Repositories.VesselCall
    local VesselCallStateMachine = PortOps.State and PortOps.State.VesselCall
    local VesselCallService = PortOps.Services and PortOps.Services.VesselCall
    local BerthService = PortOps.Services and PortOps.Services.Berth
    local ManifestRepository = PortOps.Repositories and PortOps.Repositories.Manifest
    local ManifestService = PortOps.Services and PortOps.Services.Manifest
    local DischargePlanningService = PortOps.Services and PortOps.Services.DischargePlanning
    local GateRepository = PortOps.Repositories and PortOps.Repositories.Gate
    local GateService = PortOps.Services and PortOps.Services.Gate
    local CustomsRepository = PortOps.Repositories and PortOps.Repositories.Customs
    local CustomsRiskService = PortOps.Services and PortOps.Services.CustomsRisk
    local CustomsService = PortOps.Services and PortOps.Services.Customs
    local EmployeeRepository = PortOps.Repositories and PortOps.Repositories.Employee
    local EmployeeService = PortOps.Services and PortOps.Services.Employee
    local EquipmentRepository = PortOps.Repositories and PortOps.Repositories.Equipment
    local EquipmentService = PortOps.Services and PortOps.Services.Equipment
    local ExceptionRepository = PortOps.Repositories and PortOps.Repositories.Exception
    local ExceptionDomain = PortOps.Domain and PortOps.Domain.Exception
    local ExceptionService = PortOps.Services and PortOps.Services.Exceptions
    local ActivityRepository = PortOps.Repositories and PortOps.Repositories.Activity
    local ActivityService = PortOps.Services and PortOps.Services.Activity
    local AuditRepository = PortOps.Repositories and PortOps.Repositories.Audit
    local AuditService = PortOps.Services and PortOps.Services.Audit
    local AnalyticsRepository = PortOps.Repositories and PortOps.Repositories.Analytics
    local AnalyticsService = PortOps.Services and PortOps.Services.Analytics
    local CraneService = PortOps.Services and PortOps.Services.Crane
    local FieldOperationService = PortOps.Services and PortOps.Services.FieldOperation
    local RecoveryService = PortOps.Services and PortOps.Services.Recovery
    local CraneTokens = PortOps.Security and PortOps.Security.CraneTokens
    local Idempotency = PortOps.Core.Idempotency
    local missingModules = {}
    local requiredModules = {
        { name = 'Registry', value = Registry },
        { name = 'Sessions', value = Sessions },
        { name = 'Tokens', value = Tokens },
        { name = 'ServerSync', value = ServerSync },
        { name = 'Recovery', value = Recovery },
        { name = 'Result', value = Result },
        { name = 'Migrations', value = Migrations },
        { name = 'Database', value = Database },
        { name = 'Framework', value = Framework },
        { name = 'ContainerDomain', value = ContainerDomain },
        { name = 'ContainerRepository', value = ContainerRepository },
        { name = 'ContainerStateMachine', value = ContainerStateMachine },
        { name = 'ContainerService', value = ContainerService },
        { name = 'StreamingService', value = StreamingService },
        { name = 'YardDomain', value = YardDomain },
        { name = 'YardRepository', value = YardRepository },
        { name = 'YardService', value = YardService },
        { name = 'PlacementService', value = PlacementService },
        { name = 'MoveDomain', value = MoveDomain },
        { name = 'MoveRepository', value = MoveRepository },
        { name = 'MoveStateMachine', value = MoveStateMachine },
        { name = 'MoveStepStateMachine', value = MoveStepStateMachine },
        { name = 'MoveService', value = MoveService },
        { name = 'MoveAssignment', value = MoveAssignment },
        { name = 'VesselRepository', value = VesselRepository },
        { name = 'VesselCallRepository', value = VesselCallRepository },
        { name = 'VesselCallStateMachine', value = VesselCallStateMachine },
        { name = 'VesselCallService', value = VesselCallService },
        { name = 'BerthService', value = BerthService },
        { name = 'ManifestRepository', value = ManifestRepository },
        { name = 'ManifestService', value = ManifestService },
        { name = 'DischargePlanningService', value = DischargePlanningService },
        { name = 'GateRepository', value = GateRepository },
        { name = 'GateService', value = GateService },
        { name = 'CustomsRepository', value = CustomsRepository },
        { name = 'CustomsRiskService', value = CustomsRiskService },
        { name = 'CustomsService', value = CustomsService },
        { name = 'EmployeeRepository', value = EmployeeRepository },
        { name = 'EmployeeService', value = EmployeeService },
        { name = 'EquipmentRepository', value = EquipmentRepository },
        { name = 'EquipmentService', value = EquipmentService },
        { name = 'ExceptionRepository', value = ExceptionRepository },
        { name = 'ExceptionDomain', value = ExceptionDomain },
        { name = 'ExceptionService', value = ExceptionService },
        { name = 'ActivityRepository', value = ActivityRepository },
        { name = 'ActivityService', value = ActivityService },
        { name = 'AuditRepository', value = AuditRepository },
        { name = 'AuditService', value = AuditService },
        { name = 'AnalyticsRepository', value = AnalyticsRepository },
        { name = 'AnalyticsService', value = AnalyticsService },
        { name = 'CraneService', value = CraneService },
        { name = 'FieldOperationService', value = FieldOperationService },
        { name = 'RecoveryService', value = RecoveryService },
        { name = 'EventBus', value = self.events },
        { name = 'Idempotency', value = Idempotency }
    }
    for _, required in ipairs(requiredModules) do
        if not required.value then missingModules[#missingModules + 1] = required.name end
    end
    if #missingModules > 0 then
        table.sort(missingModules)
        return self:_fail(PortOps.Enums.ResourceStage.SERVICES, 'required modules are missing: ' .. table.concat(missingModules, ', '))
    end
    local yardConfigResult = YardDomain.validateConfig(self.config.yard or {})
    if Result.isErr(yardConfigResult) then return self:_fail(PortOps.Enums.ResourceStage.CONFIG, yardConfigResult) end
    local registry, registryReason = Registry.new(self.config)
    if not registry then return self:_fail(PortOps.Enums.ResourceStage.CONFIG, registryReason) end
    self.registry = registry

    self:_stage(PortOps.Enums.ResourceStage.DB)
    local database, databaseReason = Database.create(self.config.database)
    if not database then return self:_fail(PortOps.Enums.ResourceStage.DB, databaseReason) end
    local databaseValid, databaseValidationReason = Database.validate(database)
    if not databaseValid then return self:_fail(PortOps.Enums.ResourceStage.DB, databaseValidationReason) end
    self.database = database
    self.idempotency = Idempotency.new({ clock = clockMs, database = self.database })
    local migrationRunner = Migrations.new({ database = database, migrations = self.config.database.migrations })
    local migrationResult = migrationRunner:run()
    if Result.isErr(migrationResult) then return self:_fail(PortOps.Enums.ResourceStage.DB, migrationResult) end
    self.migrations = migrationRunner

    self:_stage(PortOps.Enums.ResourceStage.ADAPTERS)
    local framework, frameworkReason = Framework.create(self.config.framework)
    if not framework then return self:_fail(PortOps.Enums.ResourceStage.ADAPTERS, frameworkReason) end
    local frameworkValid, frameworkValidationReason = Framework.validate(framework)
    if not frameworkValid then return self:_fail(PortOps.Enums.ResourceStage.ADAPTERS, frameworkValidationReason) end
    if framework.provider ~= 'standalone' and not framework:isAvailable() then
        return self:_fail(PortOps.Enums.ResourceStage.ADAPTERS, 'FRAMEWORK_PROVIDER_UNAVAILABLE')
    end
    self.framework = framework

    self:_stage(PortOps.Enums.ResourceStage.SERVICES)
    self.containerRepository = ContainerRepository.new({ database = self.database, clock = clockMs })
    self.containerStateMachine = ContainerStateMachine.new({ clock = clockMs })
    self.containerService = ContainerService.new({
        repository = self.containerRepository,
        stateMachine = self.containerStateMachine,
        events = self.events,
        logger = self.logger
    })
    self.streamingService = StreamingService.new({ repository = self.containerRepository, clock = clockMs })
    self.yardRepository = YardRepository.new({ config = self.config.yard or PortOps.Config.yard, database = self.database, clock = clockMs })
    if self.yardRepository.startupError then return self:_fail(PortOps.Enums.ResourceStage.SERVICES, self.yardRepository.startupError) end
    self.yardService = YardService.new({ repository = self.yardRepository, containerRepository = self.containerRepository, clock = clockMs })
    self.placementService = PlacementService.new({
        yardService = self.yardService,
        containerRepository = self.containerRepository,
        containerService = self.containerService,
        clock = clockMs,
        limits = (self.config.yard and self.config.yard.snap) or { distance = 1.5, vertical = 0.5, heading = 5.0 }
    })
    self.moveRepository = MoveRepository.new({ database = self.database, clock = clockMs })
    self.moveStateMachine = MoveStateMachine.new({ clock = clockMs })
    self.moveStepStateMachine = MoveStepStateMachine.new({ clock = clockMs })
    self.moveAssignment = MoveAssignment.new({ repository = self.moveRepository, stateMachine = self.moveStateMachine, framework = self.framework, clock = clockMs })
    self.moveService = MoveService.new({
        repository = self.moveRepository,
        stateMachine = self.moveStateMachine,
        stepStateMachine = self.moveStepStateMachine,
        containerService = self.containerService,
        yardService = self.yardService,
        assignmentService = self.moveAssignment,
        events = self.events,
        logger = self.logger,
        clock = clockMs
    })
    self.sessions = Sessions.new({ ttlMs = self.config.crane.sessionTtlMs, onInvalidated = function(session, reason) self:_onSessionInvalidated(session, reason) end })
    self.tokens = Tokens.new({
        ttlMs = self.config.crane.actionTokenTtlMs,
        maxActivePerSession = self.config.crane.actionTokenMaxActivePerSession,
        maxIssuesPerWindow = self.config.crane.actionTokenMaxIssuesPerWindow,
        issueWindowMs = self.config.crane.actionTokenIssueWindowMs,
        replayLog = function(event) if type(print) == 'function' and self.config.environment ~= 'production' then print(('[PortOps] token rejected: %s'):format(tostring(event.reason))) end end
    })
    self.vesselRepository = VesselRepository.new({ database = self.database })
    self.vesselCallRepository = VesselCallRepository.new({ database = self.database })
    self.vesselCallStateMachine = VesselCallStateMachine.new({ clock = clockMs })
    self.vesselCallService = VesselCallService.new({ repository = self.vesselCallRepository, machine = self.vesselCallStateMachine })
    self.berthService = BerthService.new({ slots = PortOps.Config.berthSlots or {}, callRepository = self.vesselCallRepository, clock = clockMs })
    if self.berthService.startupError then return self:_fail(PortOps.Enums.ResourceStage.SERVICES, self.berthService.startupError) end
    self.manifestRepository = ManifestRepository.new({ database = self.database })
    self.manifestService = ManifestService.new({ repository = self.manifestRepository, containerService = self.containerService })
    self.dischargePlanningService = DischargePlanningService.new({ manifestService = self.manifestService, yardService = self.yardService, moveService = self.moveService, clock = clockMs })
    self.customsRepository = CustomsRepository.new()
    self.customsRiskService = CustomsRiskService.new(self.config.customs or PortOps.CustomsConfig or {})
    self.customsService = CustomsService.new({ repository = self.customsRepository, caseDomain = PortOps.Domain.CustomsCase })
    self.gateRepository = GateRepository.new({ database = self.database })
    self.gateService = GateService.new({ repository = self.gateRepository, containerService = self.containerService, customsService = self.customsService, clock = clockMs })
    self.employeeRepository = EmployeeRepository.new()
    self.employeeService = EmployeeService.new({ repository = self.employeeRepository })
    self.equipmentRepository = EquipmentRepository.new()
    self.equipmentService = EquipmentService.new({ repository = self.equipmentRepository, employeeService = self.employeeService })
    self.exceptionRepository = ExceptionRepository.new()
    self.exceptionService = ExceptionService.new({ repository = self.exceptionRepository, domain = ExceptionDomain })
    self.activityRepository = ActivityRepository.new()
    self.activityService = ActivityService.new({ repository = self.activityRepository })
    self.auditRepository = AuditRepository.new()
    self.auditService = AuditService.new({ repository = self.auditRepository })
    self.analyticsRepository = AnalyticsRepository.new()
    self.analyticsService = AnalyticsService.new({ repository = self.analyticsRepository })
    if CraneService and CraneTokens then
        self.craneService = CraneService.new({ sessions = self.sessions, tokens = CraneTokens.new({ clock = clockMs, ttlMs = self.config.crane.actionTokenTtlMs }), moves = self.moveService, containers = self.containerService, clock = clockMs })
    end
    self.recoveryService = RecoveryService.new({ containers = self.containerService, yard = self.yardService, moves = self.moveService, clock = clockMs })
    local recoveryResult = self.recoveryService:restore()
    if Result.isErr(recoveryResult) then return self:_fail(PortOps.Enums.ResourceStage.SERVICES, recoveryResult) end
    self.recoveryRequired = recoveryResult.data and recoveryResult.data.requiresRecovery == true or false
    self.recoveryWarnings = recoveryResult.data and recoveryResult.data.warnings or {}
    if recoveryResult.data and not recoveryResult.data.coherent and self.logger and type(self.logger.warn) == 'function' then
        self.logger:warn('recovery completed with warnings', recoveryResult.data)
    end
    self.fieldOperationService = FieldOperationService.new({ moveService = self.moveService, containerService = self.containerService, placementService = self.placementService })
    for _, eventName in ipairs({ 'portops:containerCreated', 'portops:containerTransitioned', 'portops:moveCreated', 'portops:moveTransitioned' }) do
        local _, unsubscribe = self.events:on(eventName, function(payload)
            local entityId = payload and (payload.id or (payload.container and payload.container.id))
            self.activityService:record(eventName, entityId, payload or {})
        end)
        if type(unsubscribe) == 'function' then self.eventUnsubscribers[#self.eventUnsubscribers + 1] = unsubscribe end
    end
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
        handleContainerStream = function(source, position, options) return self:handleContainerStream(source, position, options) end,
        handleYardStream = function(source, position, options) return self:handleYardStream(source, position, options) end,
        handleYardPlacement = function(source, containerId, slotId, physical, ownerId, expectedVersion, expectedSlotVersion) return self:handleYardPlacement(source, containerId, slotId, physical, ownerId, expectedVersion, expectedSlotVersion) end,
        handleDisconnect = function(source) return self:handleDisconnect(source) end
    }
    PortOps.Crane.RegistryInstance = self.registry
    PortOps.Crane.SessionAuthority = self.sessions
    PortOps.Crane.ActionTokenAuthority = self.tokens
    PortOps.Runtime = PortOps.Runtime or {}
    PortOps.Runtime.Database = self.database
    PortOps.Runtime.Migrations = self.migrations
    PortOps.Runtime.Framework = self.framework
    PortOps.Runtime.ContainerRepository = self.containerRepository
    PortOps.Runtime.ContainerStateMachine = self.containerStateMachine
    PortOps.Runtime.ContainerService = self.containerService
    PortOps.Runtime.StreamingService = self.streamingService
    PortOps.Runtime.YardRepository = self.yardRepository
    PortOps.Runtime.YardService = self.yardService
    PortOps.Runtime.PlacementService = self.placementService
    PortOps.Runtime.MoveRepository = self.moveRepository
    PortOps.Runtime.MoveStateMachine = self.moveStateMachine
    PortOps.Runtime.MoveStepStateMachine = self.moveStepStateMachine
    PortOps.Runtime.MoveAssignment = self.moveAssignment
    PortOps.Runtime.MoveService = self.moveService
    PortOps.Runtime.CraneService = self.craneService
    PortOps.Runtime.FieldOperationService = self.fieldOperationService
    PortOps.Runtime.RecoveryService = self.recoveryService
    PortOps.Runtime.VesselRepository = self.vesselRepository
    PortOps.Runtime.VesselCallRepository = self.vesselCallRepository
    PortOps.Runtime.VesselCallStateMachine = self.vesselCallStateMachine
    PortOps.Runtime.VesselCallService = self.vesselCallService
    PortOps.Runtime.BerthService = self.berthService
    PortOps.Runtime.ManifestRepository = self.manifestRepository
    PortOps.Runtime.ManifestService = self.manifestService
    PortOps.Runtime.DischargePlanningService = self.dischargePlanningService
    PortOps.Runtime.GateRepository = self.gateRepository
    PortOps.Runtime.GateService = self.gateService
    PortOps.Runtime.CustomsRepository = self.customsRepository
    PortOps.Runtime.CustomsRiskService = self.customsRiskService
    PortOps.Runtime.CustomsService = self.customsService
    PortOps.Runtime.EmployeeRepository = self.employeeRepository
    PortOps.Runtime.EmployeeService = self.employeeService
    PortOps.Runtime.EquipmentRepository = self.equipmentRepository
    PortOps.Runtime.EquipmentService = self.equipmentService
    PortOps.Runtime.ExceptionRepository = self.exceptionRepository
    PortOps.Runtime.ExceptionService = self.exceptionService
    PortOps.Runtime.ActivityRepository = self.activityRepository
    PortOps.Runtime.ActivityService = self.activityService
    PortOps.Runtime.AuditRepository = self.auditRepository
    PortOps.Runtime.AuditService = self.auditService
    PortOps.Runtime.AnalyticsRepository = self.analyticsRepository
    PortOps.Runtime.AnalyticsService = self.analyticsService
    PortOps.Runtime.Idempotency = self.idempotency
    PortOps.Runtime.RecoveryRequired = self.recoveryRequired
    PortOps.Runtime.Logger = self.logger
    PortOps.Runtime.Events = self.events
    local exportsReady, exportsReason = self:_registerExports()
    if not exportsReady then return self:_fail(PortOps.Enums.ResourceStage.SERVICES, exportsReason) end
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
    self.events:emit('portops:resource.ready', { version = self.config.version, stage = self.stage })
    return true, self
end

PortOps.Bootstrap = Bootstrap
PortOps.Runtime = PortOps.Runtime or {}
PortOps.Runtime.Bootstrap = Bootstrap.new()
PortOps.Runtime.Bootstrap:run()
