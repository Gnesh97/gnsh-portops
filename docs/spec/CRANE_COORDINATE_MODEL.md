# PortOps Crane Coordinate Model

Status: S00 / PORT-002 specification
Version: `1.0`
Units: metres, seconds, degrees (unless noted)

## Purpose and invariants

This document defines the profile contract shared by local crane control, server snapshots, and observer interpolation. A controller consumes a `CraneProfile`; it must not contain crane-specific world coordinates.

The canonical state is normalized so one controller can drive different footprints:

```lua
local state = {
    gantry = 0.0,       -- [0, 1], along profile.gantry.axis
    trolley = 0.0,      -- [0, 1], along profile.trolley.axis
    spreader = 0.0,     -- [0, 1], along profile.spreader.axis
    yaw = 0.5,          -- normalized [0, 1], neutral center when yaw is configured
}
```

The server stores this normalized state (and profile identifier/version), not an engine entity position. World coordinates are a derived presentation value. This keeps persistence, restart recovery, and network ownership independent of the client that currently owns an entity.

## Frames and handedness

There are two frames: **World (`W`)**, the game engine world frame, and **Crane (`C`)**, the profile-local frame anchored at `origin`.

`origin` is the world position of the crane datum. `axis` values are unit vectors expressed in world coordinates and must form a right-handed, orthonormal basis. S00 uses `EPSILON = 1e-4` for numeric comparisons: `abs(length(axis) - 1) <= EPSILON`, `abs(dot(axisA, axisB)) <= EPSILON`, and `cross(gantry.axis, trolley.axis):dot(spreader.axis) > EPSILON`. Their names describe motion, not an assumed engine axis:

* `gantry.axis`: rail/gantry travel direction.
* `trolley.axis`: trolley travel direction.
* `spreader.axis`: vertical hoist direction (normally world up).

Every profile must explicitly provide all three axes. Never assume `x` is gantry, `y` is trolley, or `z` is vertical.

## Lua profile contract

`vector3` means the FiveM/Lua vector type or an equivalent immutable three-number value.

```lua
local profile = {
    id = "qc01",
    version = 1,
    origin = vector3(100.0, 200.0, 30.0), -- sample profile datum
    gantry = {
        axis = vector3(1.0, 0.0, 0.0), min = 0.0, max = 80.0,
        maxSpeed = 4.0, acceleration = 2.0,
    },
    trolley = {
        axis = vector3(0.0, 1.0, 0.0), min = -12.0, max = 12.0,
        maxSpeed = 3.0, acceleration = 2.0,
    },
    spreader = {
        axis = vector3(0.0, 0.0, 1.0), min = 2.0, max = 25.0,
        maxSpeed = 2.0, acceleration = 3.0,
    },
    -- Optional; omit when spreader cannot rotate.
    yaw = { min = -5.0, max = 5.0, maxSpeed = 20.0, acceleration = 40.0 },
    alignment = {
        supportedContainerLengthsM = { [20] = 6.058, [40] = 12.192 },
        horizontalToleranceM = 0.25,
        verticalToleranceM = 0.15,
        yawToleranceDegrees = 3.0,
        twistlockOffsetM = 0.0,
    },
}
```

`min` and `max` are scalar distances in metres along the corresponding axis, measured from `origin`; they may be negative and `min < max` is required. `maxSpeed` and `acceleration` are positive, in metres per second and metres per second squared. Sample numbers are fixture data only; production profiles provide their own values.

### Optional yaw

Yaw is a rotation around `spreader.axis`, in degrees, applied after the position transform. It is represented as normalized state only if `profile.yaw` exists. If absent, `yaw` must be omitted or treated as zero and yaw input must be rejected. Yaw does not alter gantry/trolley/spreader axes.

## Normalization and world transform

Use the same formula for every axis:

```lua
local function lerp(minValue, maxValue, normalized)
    return minValue + (maxValue - minValue) * normalized
end

local function stateToWorld(profile, state)
    local gantry = lerp(profile.gantry.min, profile.gantry.max, state.gantry)
    local trolley = lerp(profile.trolley.min, profile.trolley.max, state.trolley)
    local spreader = lerp(profile.spreader.min, profile.spreader.max, state.spreader)
    local position = profile.origin
        + profile.gantry.axis * gantry
        + profile.trolley.axis * trolley
        + profile.spreader.axis * spreader
    local yawDegrees = 0.0
    if profile.yaw then
        yawDegrees = lerp(profile.yaw.min, profile.yaw.max, state.yaw or 0.5)
    end
    return position, yawDegrees
end
```

For an orthonormal basis, the inverse uses dot products with each axis. This is for diagnostics/reconciliation only; canonical gameplay state must not be reconstructed from an untrusted client entity position.

```lua
local function worldToState(profile, worldPosition, yawDegrees)
    local delta = worldPosition - profile.origin
    local function normalize(minValue, maxValue, value)
        return (value - minValue) / (maxValue - minValue)
    end
    local state = {
        gantry = normalize(profile.gantry.min, profile.gantry.max, delta:dot(profile.gantry.axis)),
        trolley = normalize(profile.trolley.min, profile.trolley.max, delta:dot(profile.trolley.axis)),
        spreader = normalize(profile.spreader.min, profile.spreader.max, delta:dot(profile.spreader.axis)),
    }
    if profile.yaw then
        state.yaw = normalize(profile.yaw.min, profile.yaw.max, yawDegrees or 0.0)
    end
    return state
end
```

## Reference transform examples

For the sample profile:

| State | Gantry | Trolley | Spreader | Derived position |
| --- | ---: | ---: | ---: | --- |
| minimum `(0, 0, 0)` | `0` | `-12` | `2` | `origin + (0, -12, 2)` |
| center `(0.5, 0.5, 0.5)` | `40` | `0` | `13.5` | `origin + (40, 0, 13.5)` |
| maximum `(1, 1, 1)` | `80` | `12` | `25` | `origin + (80, 12, 25)` |

With sample `origin = (100, 200, 30)`, these are `(100, 188, 32)`, `(140, 200, 43.5)`, and `(180, 212, 55)`. These values validate the transform; they are not controller constants.

## Frame delta and movement standard

Input changes normalized targets; the motion integrator moves current state toward target using profile limits. It receives `dt` in seconds and must be frame-rate independent:

```lua
dt = math.min(math.max(dt, 0.0), 0.1) -- defensive simulation-step cap
```

For each linear axis, convert profile speed to normalized speed with `maxSpeed / (max - min)`, then apply acceleration/deceleration in normalized units per second. A fixed-step accumulator may be used for deterministic server simulation. Do not multiply a per-frame constant by input and call that speed. Yaw uses degrees per second and degrees per second squared before normalization.

## 20 ft / 40 ft container alignment

The controller aligns the spreader reference point to the container canonical center/lock pattern. ISO lengths are profile data (`6.058 m` for nominal 20 ft and `12.192 m` for nominal 40 ft), not branching constants in the controller. A future 45 ft or non-ISO profile adds an `alignment.supportedContainerLengthsM` entry and its lock geometry.

Alignment validation uses active container profile length, lock pattern, and the profile's horizontal, vertical, and yaw tolerances. The sample values match the S00 test-contract defaults (`0.25 m`, `0.15 m`, and `3°`); production profiles may override them. It rejects unsupported lengths and reports the reason; it must not infer 20 vs 40 from a model name or hardcoded world point. Width, height, corner-lock offsets, and oversize rules belong in container geometry profile and can extend `alignment` without changing normalized crane state.

## Profile validation

Profile is accepted only when all conditions below hold; otherwise load-time validation rejects it:

1. `id` is non-empty and `version` is a positive integer.
2. `origin` and all three axes are finite vectors; each axis has non-zero length.
3. Axes are normalized within `EPSILON` (or normalized once while loading and retained as a new profile value).
4. Pairwise dot products are within `EPSILON` of zero and `cross(gantry.axis, trolley.axis):dot(spreader.axis) > EPSILON`.
5. Every `min < max`; speeds and accelerations are finite and positive.
6. State values, targets, and yaw (when configured) are finite and in `[0, 1]`.
7. Alignment lengths and horizontal/vertical/yaw tolerances are positive; each supported length has complete lock geometry.

Validation errors are configuration errors, not movement corrections. Include profile ID, field, and observed value in diagnostics without accepting the profile.

## Authority and persistence boundary

The client may predict local movement and render the derived transform. The server validates profile ID/version, normalized bounds, speed/acceleration, session ownership, and action context before publishing a snapshot. Attach, detach, move completion, and container alignment remain server-authoritative. Network ownership or a client-supplied world coordinate never changes logical crane state.
