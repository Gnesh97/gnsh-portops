PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
local Protocol = PortOps.Crane.Protocol

local Sync = {}

function Sync.new(options)
    options = options or {}
    return { config = options, buffer = {}, lastSequence = -1, hardResync = true, recovery = true, apply = options.apply }
end

function Sync.clear(observer)
    observer.buffer = {}
    observer.lastSequence = -1
    observer.hardResync = true
    observer.recovery = true
end

function Sync.push(observer, snapshot)
    local normalized, errorMessage = Protocol.normalize(snapshot, observer.config)
    if not normalized then return false, errorMessage end
    if normalized.sequence <= observer.lastSequence then return false, 'late sequence' end
    observer.lastSequence = normalized.sequence
    observer.buffer[#observer.buffer + 1] = normalized
    local max = observer.config.bufferSize or Protocol.DEFAULTS.bufferSize
    while #observer.buffer > max do table.remove(observer.buffer, 1) end
    if observer.hardResync then observer.hardResync = false end
    observer.recovery = false
    return true
end

local function lerp(a, b, t) return a + (b - a) * t end
local function interpolate(a, b, t)
    local result = {}
    for _, key in ipairs({ 'gantry', 'trolley', 'spreader' }) do result[key] = lerp(a[key], b[key], t) end
    local delta = ((b.yaw - a.yaw + 540) % 360) - 180
    result.yaw = a.yaw + delta * t
    return result
end

function Sync.sample(observer, nowMs)
    local buffer = observer.buffer
    if #buffer == 0 then return nil end
    local target = nowMs - (observer.config.interpolationDelayMs or Protocol.DEFAULTS.interpolationDelayMs)
    if observer.hardResync or #buffer == 1 or target >= buffer[#buffer].timestamp then return Protocol.copyState(buffer[#buffer].state) end
    if target <= buffer[1].timestamp then return Protocol.copyState(buffer[1].state) end
    for index = 2, #buffer do
        local before, after = buffer[index - 1], buffer[index]
        if target <= after.timestamp then
            local span = math.max(after.timestamp - before.timestamp, 1)
            return interpolate(before.state, after.state, math.min(math.max((target - before.timestamp) / span, 0), 1))
        end
    end
end

function Sync.update(observer, nowMs)
    local state = Sync.sample(observer, nowMs)
    if state and observer.apply then observer.apply(state) end
    return state
end

PortOps.Crane.ClientSync = Sync
