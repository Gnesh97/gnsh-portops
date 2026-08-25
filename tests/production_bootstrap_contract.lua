-- Offline contract for the root production resource and its stage gates.
PortOps = {}
local registeredCommands = {}
RegisterCommand = function(name, handler) registeredCommands[name] = handler end
dofile('shared/enums.lua')
dofile('shared/errors.lua')
dofile('shared/crane/constants.lua')
dofile('shared/crane/schema.lua')
dofile('shared/crane/protocol.lua')
dofile('shared/crane/validation.lua')
dofile('config/config.lua')
dofile('config/features.lua')
dofile('config/yard.lua')
dofile('config/berths.lua')
dofile('config/customs.lua')
dofile('config/equipment.lua')
dofile('server/core/result.lua')
dofile('server/core/logger.lua')
dofile('server/core/event_bus.lua')
dofile('server/core/idempotency.lua')
dofile('server/core/migrations.lua')
dofile('server/adapters/database/memory.lua')
dofile('server/adapters/database/oxmysql.lua')
dofile('server/adapters/database/interface.lua')
dofile('server/adapters/framework/standalone.lua')
dofile('server/adapters/framework/qbcore.lua')
dofile('server/adapters/framework/qbox.lua')
dofile('server/adapters/framework/esx.lua')
dofile('server/adapters/framework/interface.lua')
dofile('server/security/validation.lua')
dofile('server/security/crane_tokens.lua')
dofile('server/api/dto.lua')
dofile('server/api/events.lua')
dofile('server/api/callbacks.lua')
dofile('server/api/exports.lua')
dofile('server/domain/container.lua')
dofile('server/domain/yard.lua')
dofile('server/domain/move.lua')
dofile('server/domain/move_order.lua')
dofile('server/domain/exception.lua')
dofile('server/repositories/container_repository.lua')
dofile('server/core/reservations.lua')
dofile('server/repositories/yard_repository.lua')
dofile('server/repositories/move_repository.lua')
dofile('server/repositories/vessel_repository.lua')
dofile('server/repositories/vessel_call_repository.lua')
dofile('server/repositories/manifest_repository.lua')
dofile('server/repositories/gate_repository.lua')
dofile('server/repositories/customs_repository.lua')
dofile('server/repositories/employee_repository.lua')
dofile('server/repositories/equipment_repository.lua')
dofile('server/repositories/exception_repository.lua')
dofile('server/repositories/activity_repository.lua')
dofile('server/repositories/audit_repository.lua')
dofile('server/repositories/analytics_repository.lua')
dofile('server/state/container_state_machine.lua')
dofile('server/state/move_state_machine.lua')
dofile('server/state/move_step_state_machine.lua')
dofile('server/state/vessel_call_state_machine.lua')
dofile('server/services/container_service.lua')
dofile('server/services/yard_service.lua')
dofile('server/services/placement_service.lua')
dofile('server/services/move_service.lua')
dofile('server/services/move_assignment.lua')
dofile('server/services/assignment_service.lua')
dofile('server/services/crane_service.lua')
dofile('server/services/field_operation_service.lua')
dofile('server/services/recovery_service.lua')
dofile('server/services/vessel_call_service.lua')
dofile('server/services/berth_service.lua')
dofile('server/services/manifest_service.lua')
dofile('server/services/discharge_planning_service.lua')
dofile('server/services/gate_service.lua')
dofile('server/services/customs_risk_service.lua')
dofile('server/services/customs_service.lua')
dofile('server/services/employee_service.lua')
dofile('server/services/equipment_service.lua')
dofile('server/services/exception_service.lua')
dofile('server/services/activity_service.lua')
dofile('server/services/audit_service.lua')
dofile('server/services/analytics_service.lua')
dofile('server/services/streaming_service.lua')
dofile('server/crane/registry.lua')
dofile('server/crane/sessions.lua')
dofile('server/crane/action_tokens.lua')
dofile('server/crane/sync.lua')
dofile('server/crane/recovery.lua')
dofile('server/bootstrap.lua')

local function assertf(value, message) assert(value, message); return value end
local manifestHandle = assertf(io.open('fxmanifest.lua', 'r'), 'root fxmanifest is missing')
local manifest = manifestHandle:read('*a')
manifestHandle:close()
assertf(manifest:find("'server/bootstrap.lua'", 1, true), 'root manifest does not load server bootstrap')
assertf(not manifest:find('prototype/', 1, true), 'root manifest must not load prototype files')
local runtime = assertf(PortOps.Crane.Runtime, 'runtime bootstrap missing')
local bootstrap = assertf(runtime.bootstrap, 'bootstrap instance missing')
assertf(bootstrap.ready, 'production bootstrap is not ready')
assertf(bootstrap.stage == PortOps.Enums.ResourceStage.READY, 'resource stage did not reach READY')
assertf(bootstrap.registry:get('qc-01'), 'default crane was not registered')
assertf(registeredCommands.portops_status, 'development status command was not registered')
assertf(bootstrap.database and bootstrap.database.provider == 'memory', 'memory database adapter was not wired')
assertf(bootstrap.migrations and bootstrap.migrations.database == bootstrap.database, 'migration runner was not wired')
assertf(bootstrap.database.schemaVersion == 13, 'database migrations did not reach latest version')
assertf(bootstrap.framework and bootstrap.framework.provider == 'standalone', 'standalone framework adapter was not wired')
assertf(bootstrap.logger and bootstrap.events, 'core utilities were not wired')
assertf(bootstrap.containerService and bootstrap.streamingService, 'container services were not wired')
assertf(bootstrap.yardService and bootstrap.placementService, 'yard services were not wired')
assertf(bootstrap.moveService and bootstrap.moveAssignment, 'move services were not wired')
assertf(bootstrap.fieldOperationService, 'field operation service was not wired')
assertf(bootstrap.recoveryService and bootstrap.recoveryService.yard == bootstrap.yardService, 'recovery service was not wired')
assertf(bootstrap.idempotency and bootstrap.idempotency.database == bootstrap.database, 'idempotency persistence was not wired')
assertf(bootstrap.recoveryRequired == false, 'clean startup unexpectedly requires recovery')
assertf(bootstrap.vesselCallService and bootstrap.berthService and bootstrap.manifestService, 'vessel services were not wired')
assertf(bootstrap.dischargePlanningService, 'discharge planning service was not wired')
assertf(bootstrap.gateService and bootstrap.customsService, 'gate/customs services were not wired')
assertf(bootstrap.employeeService and bootstrap.equipmentService, 'workforce services were not wired')
assertf(bootstrap.auditService and bootstrap.analyticsService, 'audit/analytics services were not wired')
assertf(PortOps.Runtime.ContainerService == bootstrap.containerService and PortOps.Runtime.StreamingService == bootstrap.streamingService, 'container runtime services were not published')
local streamResult = runtime.handleContainerStream(11, { x = 0, y = 0, z = 0 }, { radius = 10 })
assertf(streamResult.ok and #streamResult.data == 0, 'empty container stream request failed')
local invalidStream = runtime.handleContainerStream(11, { x = 0 / 0, y = 0, z = 0 }, { radius = 10 })
assertf(not invalidStream.ok and invalidStream.error.code == 'STREAM_POSITION_INVALID', 'invalid stream position was accepted')
local previousGetPlayerPed, previousGetEntityCoords = GetPlayerPed, GetEntityCoords
GetPlayerPed = function() return 0 end
GetEntityCoords = function() return nil end
local developmentFallbackStream = runtime.handleContainerStream(12, { x = 0, y = 0, z = 0 }, { radius = 10 })
assertf(developmentFallbackStream.ok, 'development stream fallback failed without authoritative ped coordinates')
GetPlayerPed, GetEntityCoords = previousGetPlayerPed, previousGetEntityCoords

local originalProvider = PortOps.Config.framework.provider
PortOps.Config.framework.provider = 'qbox'
local qboxConfigValid = PortOps.Security.Validation.validateConfig(PortOps.Config, PortOps.Features)
assertf(qboxConfigValid, 'qbox framework provider was rejected by config validation')
PortOps.Config.framework.provider = originalProvider

local originalMigrations = PortOps.Config.database.migrations
PortOps.Config.database.migrations = { { version = 1, path = '' }, { version = 1, path = 'duplicate.sql' } }
local badMigrationsConfig = PortOps.Security.Validation.validateConfig(PortOps.Config, PortOps.Features)
assertf(not badMigrationsConfig, 'invalid migration metadata was accepted by config validation')
PortOps.Config.database.migrations = originalMigrations

local originalFramework = bootstrap.framework
bootstrap.framework = { provider = 'qbcore', getIdentifier = function() return nil end }
local missingIdentity = runtime.handleReserve(11, 'qc-01')
assertf(not missingIdentity.ok and missingIdentity.error.code == 'FRAMEWORK_IDENTITY_UNAVAILABLE', 'missing framework identity was not rejected')
bootstrap.framework = originalFramework

local first = runtime.handleReserve(11, 'qc-01')
assertf(first.ok and first.data.sessionId, 'first reserve failed')
assertf(first.data.serverTime, 'reserve response did not include server time')
assertf(bootstrap.sessions.bySession[first.data.sessionId].operatorId == 'standalone:11', 'standalone framework identity was not used')
local second = runtime.handleReserve(12, 'qc-01')
assertf(not second.ok and second.error.code == 'CRANE_OCCUPIED', 'concurrent reserve was not rejected')
local released = runtime.handleRelease(11, first.data.sessionId, first.data.sessionToken)
assertf(released.ok and released.data.released, 'release response did not confirm release')
first = runtime.handleReserve(11, 'qc-01')
assertf(first.ok and first.data.sessionId, 'reserve after release failed')

local notifications = {}
TriggerClientEvent = function(eventName, target)
    notifications[#notifications + 1] = { event = eventName, target = target }
end
assertf(runtime.handleObserve(21, 'qc-01').ok, 'observer registration failed')

local now = math.floor(os.time() * 1000)
local accepted = runtime.handleSnapshot(11, 'qc-01', {
    version = PortOps.Crane.Protocol.VERSION,
    sessionId = first.data.sessionId,
    sessionToken = first.data.sessionToken,
    sequence = 1,
    timestamp = now,
    gantry = 0.5,
    trolley = 0.5,
    spreader = 1.0,
    yaw = 0.0
})
assertf(accepted.ok and accepted.data.state.version == 1, 'canonical snapshot was not accepted')
for _, notification in ipairs(notifications) do
    assertf(notification.target == 21, 'canonical broadcast escaped observer scope')
end
local malformed = runtime.handleSnapshot(11, 'qc-01', {
    version = PortOps.Crane.Protocol.VERSION,
    sessionId = first.data.sessionId,
    sessionToken = first.data.sessionToken,
    sequence = 2,
    timestamp = now + 1,
    state = { gantry = { nested = true }, trolley = 0.5, spreader = 1.0, yaw = 0.0 }
})
assertf(not malformed.ok and malformed.error.code == 'SNAPSHOT_INVALID', 'nested untrusted snapshot was not rejected')
local wrongCredential = runtime.handleSnapshot(11, 'qc-01', {
    version = PortOps.Crane.Protocol.VERSION,
    sessionId = first.data.sessionId,
    sessionToken = 'wrong-session-token',
    sequence = 2,
    timestamp = now + 1,
    gantry = 0.5,
    trolley = 0.5,
    spreader = 1.0,
    yaw = 0.0
})
assertf(not wrongCredential.ok and wrongCredential.error.code == 'SESSION_INVALID', 'wrong session credential was accepted')

local tokenResult = runtime.handleTokenIssue(11, 'qc-01', first.data.sessionId, 'MSCU-001', 'attach', first.data.sessionToken)
assertf(tokenResult.ok and tokenResult.data.token, 'action token was not issued')
local consumed = runtime.handleTokenConsume(11, tokenResult.data.token, 'qc-01', first.data.sessionId, 'MSCU-001', 'attach', first.data.sessionToken)
assertf(consumed.ok, 'valid action token was not consumed')
local replay = runtime.handleTokenConsume(11, tokenResult.data.token, 'qc-01', first.data.sessionId, 'MSCU-001', 'attach', first.data.sessionToken)
assertf(not replay.ok and replay.error.code == 'TOKEN_REPLAY', 'action token replay was accepted')

local attached, attachedState = bootstrap.registry:setAttachment('qc-01', 'MSCU-001', first.data.sessionId)
assertf(attached and attachedState.attachedContainerId == 'MSCU-001', 'opaque attachment marker was not recorded')
runtime.handleDisconnect(11)
for _, notification in ipairs(notifications) do
    assertf(notification.target ~= -1, 'recovery broadcast escaped observer scope')
end
local recoveredState = bootstrap.registry:getState('qc-01')
assertf(recoveredState.recoveryRequired and recoveredState.mode == PortOps.Enums.CraneState.RECOVERY_REQUIRED and recoveredState.attachedContainerId == 'MSCU-001', 'disconnect did not freeze attached crane')
local stale = runtime.handleSnapshot(11, 'qc-01', {
    version = PortOps.Crane.Protocol.VERSION,
    sessionId = first.data.sessionId,
    sessionToken = first.data.sessionToken,
    sequence = 2,
    timestamp = now + 1,
    gantry = 0.5,
    trolley = 0.5,
    spreader = 1.0,
    yaw = 0.0
})
assertf(not stale.ok and stale.error.code == 'SESSION_INVALID', 'stale disconnected session was accepted')

TriggerClientEvent = nil

print('production_bootstrap_contract: PASS')
