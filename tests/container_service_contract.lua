-- Offline contract for container service events, DTOs, and version conflicts.
PortOps = {}
dofile('shared/errors.lua')
dofile('server/core/result.lua')
dofile('server/core/event_bus.lua')
dofile('server/adapters/database/memory.lua')
dofile('server/domain/container.lua')
dofile('server/repositories/container_repository.lua')
dofile('server/state/container_state_machine.lua')
dofile('server/services/container_service.lua')

local Result = PortOps.Core.Result
local EventBus = PortOps.Core.EventBus
local Memory = PortOps.Adapters.Database.Memory
local Repository = PortOps.Repositories.Container
local StateMachine = PortOps.State.ContainerStateMachine
local Service = PortOps.Services.Container

local database = Memory.new()
local events = EventBus.new()
local createdEvents, transitionedEvents, deletedEvents = 0, 0, 0
assert(events:on('portops:containerCreated', function() createdEvents = createdEvents + 1 end))
assert(events:on('portops:containerTransitioned', function() transitionedEvents = transitionedEvents + 1 end))
assert(events:on('portops:containerDeleted', function() deletedEvents = deletedEvents + 1 end))
local service = Service.new({ repository = Repository.new({ database = database }), stateMachine = StateMachine.new(), events = events })

local created = service:create({ containerNumber = 'MSCU1234567', isoType = '20GP' }, { actorId = 'system' })
assert(Result.isOk(created) and created.data.version == 1, 'container service create failed')
assert(createdEvents == 1, 'container created event was not emitted')

local fetched = service:get('MSCU1234567')
assert(Result.isOk(fetched) and fetched.data.containerNumber == 'MSCU1234567', 'container service lookup failed')
fetched.data.cargo.category = 'client-mutation'
local untouched = service:get(fetched.data.id)
assert(untouched.data.cargo.category == nil, 'service returned mutable repository state')

local moved = service:transition(fetched.data.id, 'ON_VESSEL', 1, { actorId = 'system', context = 'manifest' })
assert(Result.isOk(moved) and moved.data.version == 2 and moved.data.status == 'ON_VESSEL', 'container service transition failed')
assert(transitionedEvents == 1, 'container transition event was not emitted')
local conflict = service:transition(fetched.data.id, 'READY_FOR_DISCHARGE', 1, { actorId = 'system' })
assert(Result.isErr(conflict) and conflict.error.code == 'CONTAINER_VERSION_CONFLICT', 'service version conflict was not enforced')
assert(Result.isOk(service:delete(fetched.data.id, 2, { actorId = 'system' })) and deletedEvents == 1, 'container delete event was not emitted')

print('container_service_contract: PASS')
