-- Compatibility entry point for the plan's MoveOrder name. The domain
-- implementation stays in move.lua so runtime and offline contracts share one
-- validated immutable representation.
PortOps = PortOps or {}
PortOps.Domain = PortOps.Domain or {}
return PortOps.Domain.Move
