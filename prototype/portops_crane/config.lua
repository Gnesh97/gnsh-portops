PortOpsCrane = PortOpsCrane or {}

PortOpsCrane.Config = {
    debug = true,
    commandPrefix = 'portops_crane',

    -- Controls are deliberately local to this prototype.  Production input
    -- mapping and operator permissions belong to the host resource.
    Controls = {
        gantryPositive = 172,
        gantryNegative = 173,
        trolleyPositive = 174,
        trolleyNegative = 175,
        spreaderPositive = 171,
        spreaderNegative = 178,
        yawPositive = 39,
        yawNegative = 44,
        cameraNext = 244,
        debugCommand = 'portops_crane_debug'
    },

    Cameras = {
        default = { x = 0.0, y = -8.0, z = 4.0, fov = 55.0 },
        cabin = { x = 0.0, y = 0.0, z = 2.0, fov = 65.0 },
        top = { x = 0.0, y = 0.0, z = 22.0, fov = 50.0 },
        spreader = { x = 0.0, y = -5.0, z = 1.5, fov = 60.0 },
        side = { x = 8.0, y = 0.0, z = 3.0, fov = 55.0 }
    },

    -- Development-only profile. Production coordinates belong in a profile
    -- selected by the host resource, never in controller logic.
    profile = {
        id = 'prototype_qc_01',
        version = 1,
        origin = vector3(0.0, 0.0, 0.0),
        heading = 0.0,
        gantry = {
            axis = vector3(1.0, 0.0, 0.0),
            min = 0.0,
            max = 20.0,
            maxSpeed = 4.0,
            acceleration = 8.0
        },
        trolley = {
            axis = vector3(0.0, 1.0, 0.0),
            min = 0.0,
            max = 12.0,
            maxSpeed = 3.0,
            acceleration = 6.0
        },
        spreader = {
            axis = vector3(0.0, 0.0, 1.0),
            min = 0.0,
            max = 8.0,
            maxSpeed = 2.0,
            acceleration = 4.0
        },
        yaw = {
            min = -180.0,
            max = 180.0,
            maxSpeed = 30.0,
            acceleration = 60.0
        },
        alignment = {
            supportedContainerLengthsM = { [20] = 6.058, [40] = 12.192 },
            horizontalToleranceM = 0.25,
            verticalToleranceM = 0.15,
            yawToleranceDegrees = 3.0
        },
        models = {
            base = 'prop_byard_rampold_cr',
            gantry = 'prop_byard_rampold_cr',
            trolley = 'prop_container_01a',
            spreader = 'prop_container_01a',
            container = 'prop_container_01a'
        },
        spawn = {
            enabled = false,
            container = false
        }
    }
}
