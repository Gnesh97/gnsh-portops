local root = os.getenv('PORTOPS_ROOT') or '.'
local function load(path) dofile(root .. '/' .. path) end
PortOps = { Core = {} }
load('server/core/result.lua')
load('server/domain/container.lua')
load('server/repositories/container_repository.lua')
load('server/state/container_state_machine.lua')
load('server/services/container_service.lua')
load('config/yard.lua')
load('server/domain/yard.lua')
load('server/core/reservations.lua')
load('server/repositories/yard_repository.lua')
load('server/services/yard_service.lua')
load('server/services/recovery_service.lua')
load('server/domain/gate_appointment.lua')
load('server/repositories/gate_repository.lua')
load('server/services/gate_service.lua')

local memory = { provider = 'memory' }
local containers = PortOps.Repositories.Container.new({ database = memory, clock = function() return 1000 end })
local containerService = PortOps.Services.Container.new({
    repository = containers,
    stateMachine = PortOps.State.ContainerStateMachine.new({ clock = function() return 1000 end })
})
local created = containerService:create({ containerNumber = 'MSCU1234566', isoType = '40GP' }, { manifestId = 'manifest-1' })
assert(created.ok and created.data.manifestId == 'manifest-1', 'manifest linkage was not applied at create')

local yard = PortOps.Repositories.Yard.new({ config = PortOps.Config.yard, clock = function() return 1000 end })
local yardService = PortOps.Services.Yard.new({ repository = yard })
local recovery = PortOps.Services.Recovery.new({ containers = containerService, yard = yardService })
local restored = recovery:restore({ { id = 'container:' .. created.data.id, containerId = created.data.id, slotId = 'C-14-03-1', status = 'AT_YARD' } })
assert(restored.ok and yard:get('C-14-03-1').data.state == 'OCCUPIED', 'startup recovery did not restore yard occupancy')

local gate = PortOps.Services.Gate.new({ repository = PortOps.Repositories.Gate.new({ database = memory }), clock = function() return 1.5 end })
assert(gate:book({ id = 'appointment-1', containerId = created.data.id, windowStart = 1, windowEnd = 2 }).ok, 'appointment setup failed')
local listed = gate:list({ limit = 10 })
assert(listed.ok and #listed.data == 1, 'gate list callback contract is unavailable')
assert(gate:transition('appointment-1', 'ARRIVED').ok, 'appointment window arrival failed')
assert(gate:transition('appointment-1', 'PICKUP_CLAIMED').ok, 'pickup claim failed')
assert(gate:transition('appointment-1', 'GATE_IN').ok, 'gate-in failed')
assert(gate:transition('appointment-1', 'SERVICED').ok, 'service completion failed')
local mismatch = gate:gateOut('appointment-1', { id = 'other-container', status = 'READY_FOR_PICKUP' })
assert(not mismatch.ok and mismatch.error.code == 'APPOINTMENT_CONTAINER_MISMATCH', 'gate-out accepted a different container')
print('recovery_and_api_contract: PASS')
