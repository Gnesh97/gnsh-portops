-- Shared production enums.  This file is intentionally framework agnostic so
-- the resource can boot before a framework or persistence adapter is chosen.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Enums = PortOps.Enums or {}

PortOps.Enums.ResourceStage = {
    CONFIG = 'CONFIG',
    DB = 'DB',
    ADAPTERS = 'ADAPTERS',
    SERVICES = 'SERVICES',
    READY = 'READY',
    FAILED = 'FAILED'
}

PortOps.Enums.CraneState = {
    OFFLINE = 'OFFLINE',
    AVAILABLE = 'AVAILABLE',
    RESERVED = 'RESERVED',
    OPERATOR_ENTERING = 'OPERATOR_ENTERING',
    OPERATING = 'OPERATING',
    ATTACHED = 'ATTACHED',
    PAUSED = 'PAUSED',
    FAULTED = 'FAULTED',
    OPERATOR_EXITING = 'OPERATOR_EXITING',
    RECOVERY_REQUIRED = 'RECOVERY_REQUIRED',
    MAINTENANCE = 'MAINTENANCE'
}

PortOps.Enums.CraneAction = {
    ATTACH = 'attach',
    DETACH = 'detach',
    ENTER = 'enter',
    EXIT = 'exit',
    RESET = 'reset'
}

PortOps.Enums.TokenStatus = {
    ISSUED = 'ISSUED',
    CONSUMED = 'CONSUMED',
    EXPIRED = 'EXPIRED',
    REVOKED = 'REVOKED'
}

-- S02 modules were authored independently.  Keep this compatibility alias so
-- existing production authority modules share the exact same table.
PortOpsCrane = PortOps.Crane
