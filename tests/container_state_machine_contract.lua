-- Offline transition matrix contract for container lifecycle authority.
PortOps = {}
dofile('shared/errors.lua')
dofile('server/core/result.lua')
dofile('server/domain/container.lua')
dofile('server/state/container_state_machine.lua')

local Result = PortOps.Core.Result
local StateMachine = PortOps.State.ContainerStateMachine
local machine = StateMachine.new()

local expected = { id = 'ctr-001', status = 'EXPECTED', version = 1 }
local onVessel = machine:transition(expected, 'ON_VESSEL', { actorId = 'operator-1' })
assert(Result.isOk(onVessel) and onVessel.data.status == 'ON_VESSEL', 'allowed transition was rejected')
assert(expected.status == 'EXPECTED', 'state machine mutated source container')

local illegal = machine:transition(onVessel.data, 'AT_YARD', { actorId = 'operator-1' })
assert(Result.isErr(illegal) and illegal.error.code == 'CONTAINER_TRANSITION_INVALID', 'illegal transition was accepted')

local denied = machine:transition(onVessel.data, 'READY_FOR_DISCHARGE', { actorId = 'operator-1' }, {
    before = function() return false, 'manifest step is not ready' end
})
assert(Result.isErr(denied) and denied.error.code == 'CONTAINER_GUARD_REJECTED', 'guard rejection was ignored')
local indeterminate = machine:transition(onVessel.data, 'READY_FOR_DISCHARGE', { actorId = 'operator-1' }, {
    before = function() return nil end
})
assert(Result.isErr(indeterminate) and indeterminate.error.code == 'CONTAINER_GUARD_REJECTED', 'indeterminate guard result was accepted')

local damaged = machine:transition(onVessel.data, 'DAMAGED', { actorId = 'operator-1', reason = 'seal impact' })
assert(Result.isOk(damaged) and damaged.data.status == 'DAMAGED', 'side-state transition was rejected')

local recovery = machine:transition(damaged.data, 'RECOVERY_REQUIRED', { actorId = 'system', reason = 'resource restart' })
assert(Result.isOk(recovery) and recovery.data.status == 'RECOVERY_REQUIRED', 'recovery transition was rejected')

print('container_state_machine_contract: PASS')
