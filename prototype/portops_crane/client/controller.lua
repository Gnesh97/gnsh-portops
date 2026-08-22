-- S01 / PORT-012: local, frame-independent crane controller.
-- This module owns input and prediction only; it has no framework calls.

PortOpsCrane = PortOpsCrane or {}
PortOpsCrane.Controller = PortOpsCrane.Controller or {}

local Controller = PortOpsCrane.Controller
local running = false
local debugEnabled = false
local commandRegistered = false
local velocity = { gantry = 0.0, trolley = 0.0, spreader = 0.0, yaw = 0.0 }

local defaults = {
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
}

local function config()
    local shared = PortOpsCrane.Config or {}
    return shared.Controls or defaults
end

local function finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function controlId(controls, name)
    return controls[name] or defaults[name]
end

local function activeRig()
    return PortOpsCrane.ActiveRig
end

local function profile()
    local rig = activeRig()
    return rig and rig.profile
end

local function getState()
    local rig = activeRig()
    if not rig then return nil end
    return PortOpsCrane.Rig.GetState(rig)
end

local function setState(state)
    local rig = activeRig()
    if not rig then return false end
    PortOpsCrane.Rig.SetState(rig, state)
    return true
end

local function axisMotion(p, name)
    local axis = p and p[name]
    if not axis then return nil end
    local minimum, maximum = tonumber(axis.min), tonumber(axis.max)
    if not finite(minimum) or not finite(maximum) then return nil end
    local range = maximum - minimum
    if not finite(range) or range <= 0.0 then return nil end
    local maxSpeed = tonumber(axis.maxSpeed)
    local acceleration = tonumber(axis.acceleration)
    if not finite(maxSpeed) or not finite(acceleration) then return nil end
    return maxSpeed / range, acceleration / range
end

local function yawMotion(p)
    local axis = p and p.yaw
    if not axis then return nil end
    local minimum, maximum = tonumber(axis.min), tonumber(axis.max)
    if not finite(minimum) or not finite(maximum) then return nil end
    local range = maximum - minimum
    if not finite(range) or range <= 0.0 then return nil end
    local maxSpeed, acceleration = tonumber(axis.maxSpeed), tonumber(axis.acceleration)
    if not finite(maxSpeed) or not finite(acceleration) then return nil end
    return maxSpeed / range, acceleration / range
end

local function inputAxis(positive, negative)
    local value = 0.0
    if IsControlPressed(0, positive) then value = value + 1.0 end
    if IsControlPressed(0, negative) then value = value - 1.0 end
    return value
end

local function approach(current, target, change)
    if current < target then return math.min(current + change, target) end
    if current > target then return math.max(current - change, target) end
    return current
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function boundedInput(value)
    if not finite(value) then return 0.0 end
    return clamp(value, -1.0, 1.0)
end

local function moveAxis(state, p, name, input, dt)
    local maxSpeed, acceleration = axisMotion(p, name)
    if not maxSpeed then
        velocity[name] = 0.0
        return state[name]
    end
    local targetVelocity = boundedInput(input) * maxSpeed
    velocity[name] = approach(velocity[name], targetVelocity, acceleration * dt)
    local nextValue = clamp((state[name] or 0.0) + velocity[name] * dt, 0.0, 1.0)
    if (nextValue == 0.0 and velocity[name] < 0.0) or (nextValue == 1.0 and velocity[name] > 0.0) then
        velocity[name] = 0.0
    end
    return nextValue
end

local function moveYaw(state, p, input, dt)
    local maxSpeed, acceleration = yawMotion(p)
    if not maxSpeed then
        velocity.yaw = 0.0
        return state.yaw
    end
    local targetVelocity = boundedInput(input) * maxSpeed
    velocity.yaw = approach(velocity.yaw, targetVelocity, acceleration * dt)
    local nextValue = clamp((state.yaw or 0.5) + velocity.yaw * dt, 0.0, 1.0)
    if (nextValue == 0.0 and velocity.yaw < 0.0) or (nextValue == 1.0 and velocity.yaw > 0.0) then
        velocity.yaw = 0.0
    end
    return nextValue
end

function Controller.SetDebug(enabled)
    debugEnabled = enabled == true
    PortOpsCrane.Debug = debugEnabled
    return debugEnabled
end

function Controller.IsDebugEnabled()
    return debugEnabled
end

-- Step is exposed so a test harness can compare the same input at 30/60/120 FPS.
function Controller.Step(dt, input)
    local p, state = profile(), getState()
    if not p or not state then
        for key in pairs(velocity) do velocity[key] = 0.0 end
        return false
    end
    dt = tonumber(dt)
    if not finite(dt) then dt = 0.0 end
    dt = clamp(dt, 0.0, 0.1)
    input = input or {}
    local nextState = {
        gantry = moveAxis(state, p, 'gantry', input.gantry, dt),
        trolley = moveAxis(state, p, 'trolley', input.trolley, dt),
        spreader = moveAxis(state, p, 'spreader', input.spreader, dt)
    }
    if p.yaw then
        nextState.yaw = moveYaw(state, p, input.yaw, dt)
    end
    setState(nextState)
    return true, nextState
end

function Controller.Update(dt)
    local controls = config()
    return Controller.Step(dt, {
        gantry = inputAxis(controlId(controls, 'gantryPositive'), controlId(controls, 'gantryNegative')),
        trolley = inputAxis(controlId(controls, 'trolleyPositive'), controlId(controls, 'trolleyNegative')),
        spreader = inputAxis(controlId(controls, 'spreaderPositive'), controlId(controls, 'spreaderNegative')),
        yaw = inputAxis(controlId(controls, 'yawPositive'), controlId(controls, 'yawNegative'))
    })
end

function Controller.Start()
    if running then return end
    running = true
    if RegisterCommand and not commandRegistered then
        RegisterCommand(config().debugCommand or defaults.debugCommand, function()
            Controller.SetDebug(not debugEnabled)
        end, false)
        commandRegistered = true
    end
    if not CreateThread then return end
    CreateThread(function()
        while running do
            Controller.Update(GetFrameTime())
            Wait(0)
        end
    end)
end

function Controller.Stop()
    running = false
    Controller.ResetMotion()
end

function Controller.ResetMotion()
    for key in pairs(velocity) do velocity[key] = 0.0 end
end

if AddEventHandler then
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then Controller.Stop() end
    end)
end
