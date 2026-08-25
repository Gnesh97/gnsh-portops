-- Critical vertical-slice orchestration. Physical clients submit identifiers
-- and measurements; this service delegates lifecycle writes to move/container/
-- placement authorities.
PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result = PortOps.Core.Result
local Service = {}; Service.__index = Service
function Service.new(options) options=options or {}; return setmetatable({ moves=options.moveService, containers=options.containerService, placement=options.placementService },Service) end
function Service:trailerHandoff(moveId, stepId, containerId, expectedMoveVersion, expectedContainerVersion)
    if type(containerId)~='string' then return Result.err('FIELD_OPERATION_INVALID','container is required') end
    if not self.moves or type(self.moves.get)~='function' then return Result.err('FIELD_OPERATION_UNAVAILABLE','move service is unavailable') end
    local move=self.moves:get(moveId)
    if Result.isErr(move) then return move end
    if move.data.containerId~=containerId then return Result.err('FIELD_OPERATION_CONTAINER_MISMATCH','move container does not match handoff container') end
    return self.moves:completeStep(moveId,stepId,expectedMoveVersion,{containerStatus='ON_TERMINAL_TRAILER',containerVersion=expectedContainerVersion,containerContext={location={type='TERMINAL_TRAILER',ref=moveId}}})
end
function Service:tractorTransfer(moveId, stepId, expectedMoveVersion, expectedContainerVersion)
    return self.moves:completeStep(moveId,stepId,expectedMoveVersion,{containerStatus='IN_TERMINAL_TRANSFER',containerVersion=expectedContainerVersion})
end
function Service:yardPlacement(containerId,slotId,physical,ownerId,expectedContainerVersion,expectedSlotVersion)
    return self.placement:place(containerId,slotId,physical,ownerId,expectedContainerVersion,expectedSlotVersion)
end
PortOps.Services.FieldOperation=Service
return Service
