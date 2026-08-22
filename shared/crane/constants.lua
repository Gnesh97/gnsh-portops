PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

PortOps.Crane.Constants = {
    protocolVersion = 1,
    normalizedMin = 0.0,
    normalizedMax = 1.0,
    defaultSnapshotHz = 20,
    snapshotBurst = 4,
    futureSkewMs = 250,
    maxSnapshotAgeMs = 2000,
    interpolationDelayMs = 100,
    observerBufferSize = 12,
    sessionTtlMs = 30000,
    actionTokenTtlMs = 5000,
    maxContainerIdLength = 64,
    maxActionLength = 32,
    epsilon = 0.000001
}
