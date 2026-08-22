-- Offline contract checks for the S01 pure-Lua surfaces.
-- FiveM natives are stubbed so this file can run with the bundled Lua binary.

local function vector3(x, y, z)
    local value = { x = x, y = y, z = z }
    return setmetatable(value, {
        __add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b)
            if type(a) == 'number' then return vector3(a * b.x, a * b.y, a * b.z) end
            return vector3(a.x * b, a.y * b, a.z * b)
        end,
        __div = function(a, b) return vector3(a.x / b, a.y / b, a.z / b) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    })
end

_G.vector3 = vector3
_G.joaat = function(value) return type(value) == 'number' and value or #value end
_G.DoesEntityExist = function(entity) return entity ~= 0 and entity ~= nil end
_G.GetEntityCoords = function(entity)
    if entity == 1 or entity == 101 then return vector3(10.0, 6.0, 8.0) end
    if entity == 2 or entity == 3 then return vector3(10.05, 6.05, 8.05) end
    return vector3(0.0, 0.0, 0.0)
end
_G.GetEntityHeading = function() return 0.0 end
_G.GetEntityModel = function() return 24 end
_G.GetGamePool = function() return { 101 } end
_G.GetEntityCollisionDisabled = function() return false end
_G.SetEntityCollision = function() end
local attachedPairs = {}
_G.AttachEntityToEntity = function(container, spreader) attachedPairs[container] = spreader end
_G.IsEntityAttachedToEntity = function(container, spreader) return attachedPairs[container] == spreader end
_G.DetachEntity = function(container) attachedPairs[container] = nil end

dofile('prototype/portops_crane/config.lua')
dofile('prototype/portops_crane/client/rig.lua')
dofile('prototype/portops_crane/client/alignment.lua')
dofile('prototype/portops_crane/client/attachment.lua')
dofile('prototype/portops_crane/client/controller.lua')

local profile = PortOpsCrane.Config.profile
local rig = PortOpsCrane.Rig.New(profile)
PortOpsCrane.ActiveRig = rig

local bounded = PortOpsCrane.Rig.SetState(rig, {
    gantry = 99.0,
    trolley = -1.0,
    spreader = 0.5,
    yaw = 999.0
})
assert(bounded.gantry == 1.0 and bounded.trolley == 0.0, 'rig bounds must clamp normalized travel')
assert(bounded.yaw == 1.0, 'rig yaw must clamp to normalized bounds')

local fixture = {
    id = 'coordinate_fixture',
    version = 1,
    origin = vector3(100.0, 200.0, 30.0),
    gantry = { axis = vector3(1.0, 0.0, 0.0), min = -2.0, max = 4.0, maxSpeed = 4.0, acceleration = 2.0 },
    trolley = { axis = vector3(0.0, 1.0, 0.0), min = -12.0, max = 12.0, maxSpeed = 3.0, acceleration = 2.0 },
    spreader = { axis = vector3(0.0, 0.0, 1.0), min = 2.0, max = 25.0, maxSpeed = 2.0, acceleration = 3.0 },
    yaw = { min = -5.0, max = 5.0, maxSpeed = 20.0, acceleration = 40.0 },
    alignment = { horizontalToleranceM = 0.25, verticalToleranceM = 0.15, yawToleranceDegrees = 3.0 }
}
local fixtureRig = PortOpsCrane.Rig.New(fixture)
PortOpsCrane.Rig.SetState(fixtureRig, { gantry = 0.0, trolley = 0.0, spreader = 0.0, yaw = 0.0 })
local fixturePosition = PortOpsCrane.Rig.GetSpreaderPosition(fixtureRig)
assert(fixturePosition.x == 98.0 and fixturePosition.y == 188.0 and fixturePosition.z == 32.0,
    'rig must use profile min values in world transforms')
PortOpsCrane.Rig.SetState(fixtureRig, { gantry = 1.0, trolley = 1.0, spreader = 1.0, yaw = 1.0 })
fixturePosition = PortOpsCrane.Rig.GetSpreaderPosition(fixtureRig)
assert(fixturePosition.x == 104.0 and fixturePosition.y == 212.0 and fixturePosition.z == 55.0,
    'rig must use profile max values in world transforms')

local rotated = {
    id = 'rotated_fixture',
    version = 1,
    origin = vector3(100.0, 200.0, 30.0),
    gantry = { axis = vector3(0.0, 1.0, 0.0), min = 0.0, max = 80.0, maxSpeed = 4.0, acceleration = 2.0 },
    trolley = { axis = vector3(-1.0, 0.0, 0.0), min = -12.0, max = 12.0, maxSpeed = 3.0, acceleration = 2.0 },
    spreader = { axis = vector3(0.0, 0.0, 1.0), min = 2.0, max = 25.0, maxSpeed = 2.0, acceleration = 3.0 },
    alignment = { horizontalToleranceM = 0.25, verticalToleranceM = 0.15, yawToleranceDegrees = 3.0 }
}
local rotatedRig = PortOpsCrane.Rig.New(rotated)
assert(math.abs(PortOpsCrane.Rig.GetSpreaderHeading(rotatedRig) - 90.0) < 0.001,
    'rotated profile heading must follow the gantry axis')

local spreader = { position = vector3(10.0, 6.0, 8.0), heading = 0.0 }
local aligned = { position = vector3(10.05, 6.05, 8.05), heading = 1.0 }
local evaluation = PortOpsCrane.Alignment.Evaluate(spreader, aligned, profile)
assert(evaluation.aligned, 'alignment tolerances should accept a close candidate')
assert(evaluation.metrics.horizontalDistanceM > 0.0, 'alignment must expose XY distance')
assert(evaluation.metrics.verticalGapM > 0.0, 'alignment must expose vertical gap')
assert(evaluation.metrics.yawErrorDegrees == 1.0, 'alignment must expose yaw error')

local finalStates = {}
for _, fps in ipairs({ 30, 60, 120 }) do
    PortOpsCrane.Controller.ResetMotion()
    PortOpsCrane.Rig.SetState(rig, { gantry = 0.0, trolley = 0.0, spreader = 0.0, yaw = 0.5 })
    for _ = 1, fps do
        PortOpsCrane.Controller.Step(1.0 / fps, { gantry = 1.0 })
    end
    local state = PortOpsCrane.Rig.GetState(rig)
    assert(state.gantry > 0.0 and state.gantry < 1.0, ('controller bounds failed at %d FPS'):format(fps))
    finalStates[#finalStates + 1] = state.gantry
end
assert(math.abs(finalStates[1] - finalStates[2]) < 0.02 and math.abs(finalStates[2] - finalStates[3]) < 0.02,
    'controller movement should be approximately frame-rate independent')
PortOpsCrane.Controller.ResetMotion()
PortOpsCrane.Rig.SetState(rig, { gantry = 0.0, trolley = 0.0, spreader = 0.0, yaw = 0.5 })
PortOpsCrane.Controller.Step(0 / 0, { gantry = 1.0 })
assert(PortOpsCrane.Rig.GetState(rig).gantry == 0.0, 'invalid dt must not poison controller state')

local spreaderEntity = 1
local containerEntity = 2
local entitySpreader = { entity = spreaderEntity, position = vector3(10.0, 6.0, 8.0), heading = 0.0 }
local entityContainer = { entity = containerEntity, position = vector3(10.05, 6.05, 8.05), heading = 1.0 }
local nearest, nearestResult = PortOpsCrane.Alignment.FindNearestCandidate(entitySpreader, profile, { radiusM = 2.0 })
assert(nearest and nearest.entity == 101 and nearestResult.aligned, 'nearest candidate search must use the spreader position')
local attached = PortOpsCrane.Attachment.Attach(entitySpreader, entityContainer, profile)
assert(attached, 'aligned spreader/container should attach')
local occupied, occupiedReason = PortOpsCrane.Attachment.Attach(entitySpreader,
    { entity = 3, position = vector3(10.05, 6.05, 8.05), heading = 1.0 }, profile)
assert(not occupied and occupiedReason == 'SPREADER_OCCUPIED', 'one spreader must not carry two containers')
local wrongTarget, wrongTargetReason = PortOpsCrane.Attachment.DetachTarget(entityContainer, 'trailer')
assert(not wrongTarget and wrongTargetReason == 'WRONG_TARGET', 'detach must reject a wrong target')
PortOpsCrane.Attachment.Detach(entityContainer)
local report = PortOpsCrane.Attachment.RunCycleHarness(entitySpreader, entityContainer, profile, 10)
assert(report.pass and report.passed == 10, '10-cycle attach/detach harness must be deterministic')
assert(PortOpsCrane.Attachment.Count() == 0, 'cycle harness must leave no attachment state')

print('S01 prototype crane contract: PASS')
