PortOps = PortOps or {}

local function vector(x, y, z)
    if type(vector3) == 'function' then return vector3(x, y, z) end
    return { x = x, y = y, z = z }
end

PortOps.Config = {
    version = '0.1.0',
    environment = 'development',
    logging = { level = 'info' },
    framework = { provider = 'standalone' },
    database = {
        provider = 'memory',
        required = false,
        migrations = {
            { version = 1, path = 'sql/001_initial.sql' },
            { version = 2, path = 'sql/002_indexes.sql' },
            { version = 3, path = 'sql/003_containers.sql' }
        }
    },
    defaults = {
        craneId = 'qc-01',
        yardId = 'yard-c',
        berthId = 'berth-01'
    },
    craneProfiles = {
        ['qc-01'] = {
            id = 'qc-01',
            version = 1,
            origin = vector(0.0, 0.0, 0.0),
            heading = 0.0,
            gantry = { axis = vector(1.0, 0.0, 0.0), min = 0.0, max = 20.0, maxSpeed = 4.0, acceleration = 8.0 },
            trolley = { axis = vector(0.0, 1.0, 0.0), min = 0.0, max = 12.0, maxSpeed = 3.0, acceleration = 6.0 },
            spreader = { axis = vector(0.0, 0.0, 1.0), min = 0.0, max = 8.0, maxSpeed = 2.0, acceleration = 4.0 },
            yaw = { min = -180.0, max = 180.0, maxSpeed = 30.0, acceleration = 60.0 },
            alignment = { horizontalToleranceM = 0.25, verticalToleranceM = 0.15, yawToleranceDegrees = 3.0 }
        }
    },
    yards = {
        ['yard-c'] = { id = 'yard-c', name = 'Development Yard C' }
    },
    berths = {
        ['berth-01'] = { id = 'berth-01', yardId = 'yard-c', name = 'Development Berth 01' }
    },
    crane = {
        snapshotHz = 20,
        snapshotBurst = 4,
        -- Four-snapshot burst over 200 ms preserves the configured 20 Hz
        -- steady-state rate while still bounding short spikes.
        burstWindowMs = 200,
        maxPayloadKeys = 16,
        futureSkewMs = 250,
        maxSnapshotAgeMs = 2000,
        interpolationDelayMs = 100,
        observerBufferSize = 12,
        sessionTtlMs = 30000,
        actionTokenTtlMs = 5000,
        actionTokenMaxActivePerSession = 32,
        actionTokenMaxIssuesPerWindow = 8,
        actionTokenIssueWindowMs = 1000
    }
}
