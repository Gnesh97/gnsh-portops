-- Pure data validation/copy helpers.  No FiveM native or framework call is
-- allowed in this module; it is also used by offline contract tests.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Schema = {}

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function component(vector, key)
    if vector == nil then return nil end
    -- Cfx exposes vector3 values as a dedicated Lua value type rather than a
    -- table/userdata on some runtimes.  Read fields defensively so validation
    -- remains compatible with both FiveM natives and offline table stubs.
    local ok, value = pcall(function() return vector[key] end)
    if not ok then return nil end
    return finite(value) and value or nil
end

local function copyAxis(axis)
    return { x = component(axis, 'x'), y = component(axis, 'y'), z = component(axis, 'z') }
end

function Schema.isFinite(value)
    return finite(value)
end

function Schema.copyState(state)
    state = state or {}
    return {
        gantry = state.gantry,
        trolley = state.trolley,
        spreader = state.spreader,
        yaw = state.yaw
    }
end

function Schema.defaultState()
    return { gantry = 0.5, trolley = 0.5, spreader = 1.0, yaw = 0.0 }
end

function Schema.validateState(state)
    if type(state) ~= 'table' then return false, 'state must be a table' end
    for _, key in ipairs({ 'gantry', 'trolley', 'spreader', 'yaw' }) do
        if not finite(state[key]) then return false, 'invalid state value: ' .. key end
    end
    for _, key in ipairs({ 'gantry', 'trolley', 'spreader' }) do
        if state[key] < 0 or state[key] > 1 then return false, 'state out of bounds: ' .. key end
    end
    if state.yaw < -360 or state.yaw > 360 then return false, 'state out of bounds: yaw' end
    return true, Schema.copyState(state)
end

function Schema.validateProfile(profile)
    if type(profile) ~= 'table' then return false, 'profile must be a table' end
    if type(profile.id) ~= 'string' or profile.id == '' then return false, 'profile id is required' end
    if type(profile.version) ~= 'number' or profile.version < 1 or profile.version % 1 ~= 0 then
        return false, 'profile version is invalid'
    end
    if not component(profile.origin, 'x') or not component(profile.origin, 'y') or not component(profile.origin, 'z') then
        return false, 'profile origin is invalid'
    end
    for _, key in ipairs({ 'gantry', 'trolley', 'spreader' }) do
        local axis = profile[key]
        if type(axis) ~= 'table' then return false, 'missing profile axis: ' .. key end
        local x, y, z = component(axis.axis, 'x'), component(axis.axis, 'y'), component(axis.axis, 'z')
        if not x or not y or not z or (x == 0 and y == 0 and z == 0) then return false, 'invalid profile axis: ' .. key end
        if not finite(axis.min) or not finite(axis.max) or axis.max <= axis.min then return false, 'invalid profile bounds: ' .. key end
        if not finite(axis.maxSpeed) or axis.maxSpeed <= 0 then return false, 'invalid profile maxSpeed: ' .. key end
        if not finite(axis.acceleration) or axis.acceleration <= 0 then return false, 'invalid profile acceleration: ' .. key end
    end
    if profile.yaw then
        if not finite(profile.yaw.min) or not finite(profile.yaw.max) or profile.yaw.max <= profile.yaw.min then return false, 'invalid yaw bounds' end
        if not finite(profile.yaw.maxSpeed) or profile.yaw.maxSpeed <= 0 then return false, 'invalid yaw maxSpeed' end
        if not finite(profile.yaw.acceleration) or profile.yaw.acceleration <= 0 then return false, 'invalid yaw acceleration' end
    end
    return true
end

function Schema.copyProfile(profile)
    local copy = {}
    for key, value in pairs(profile or {}) do
        if type(value) == 'table' then
            copy[key] = {}
            for childKey, childValue in pairs(value) do
                if type(childValue) == 'table' then
                    copy[key][childKey] = {}
                    for axisKey, axisValue in pairs(childValue) do copy[key][childKey][axisKey] = axisValue end
                else
                    copy[key][childKey] = childValue
                end
            end
        else
            copy[key] = value
        end
    end
    return copy
end

PortOps.Crane.Schema = Schema
return Schema
