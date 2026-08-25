PortOps={Core={}}; dofile('server/core/result.lua'); dofile('server/domain/move.lua'); dofile('server/state/move_state_machine.lua')
local m=PortOps.Domain.Move.new({containerId='c',from={type='VESSEL'},to={type='YARD_SLOT'}}).data; local sm=PortOps.State.MoveStateMachine.new({clock=function() return 10 end})
assert(sm:transition(m,'RESERVED').ok); assert(not sm:transition(m,'COMPLETED').ok); assert(sm:transition(m,'RESERVED',{},function() return false,'no' end).error.code=='MOVE_GUARD_REJECTED')
print('move-state-machine-contract: PASS')
