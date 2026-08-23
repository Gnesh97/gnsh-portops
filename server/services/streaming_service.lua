-- Server-side interest filtering for logical container visuals.  Cargo,
-- customs, and other private fields never cross this descriptor boundary.
PortOps = PortOps or {}
PortOps.Services = PortOps.Services or {}

local Result = PortOps.Core.Result
local Streaming = {}
Streaming.__index = Streaming

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function positiveInteger(value)
    return type(value) == 'number' and value >= 1 and value % 1 == 0
end

local function distanceSquared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return dx * dx + dy * dy + dz * dz
end

local function validPosition(position)
    local kind = type(position)
    return (kind == 'table' or kind == 'vector3' or kind == 'userdata') and finite(position.x) and finite(position.y) and finite(position.z)
end

local function normalizeOptions(options)
    if options == nil then return {} end
    if type(options) ~= 'table' then return nil, 'stream options are invalid' end
    local normalized = {}
    for _, key in ipairs({ 'radius', 'limit', 'offset', 'requestId' }) do
        if options[key] ~= nil then normalized[key] = options[key] end
    end
    if options.filters ~= nil then
        if type(options.filters) ~= 'table' then return nil, 'stream filters are invalid' end
        normalized.filters = {}
        for _, key in ipairs({ 'status', 'isoType', 'locationType' }) do
            if options.filters[key] ~= nil then
                if type(options.filters[key]) ~= 'string' or #options.filters[key] > 64 then return nil, 'stream filter is invalid' end
                normalized.filters[key] = options.filters[key]
            end
        end
    end
    return normalized
end

function Streaming.new(options)
    options = options or {}
    return setmetatable({
        repository = options.repository,
        subscriptions = {},
        lastRequestAt = {},
        requestIntervalMs = math.max(50, tonumber(options.requestIntervalMs) or 250),
        clock = options.clock
    }, Streaming)
end

function Streaming:_now()
    return self.clock and self.clock() or nowMs()
end

function Streaming:_descriptor(record)
    local location = record.location
    if not location or not location.transform then return nil end
    return {
        id = record.id,
        containerNumber = record.containerNumber,
        isoType = record.isoType,
        status = record.status,
        version = record.version,
        location = { type = location.type, ref = location.ref },
        transform = {
            x = location.transform.x,
            y = location.transform.y,
            z = location.transform.z,
            heading = location.transform.heading
        }
    }
end

function Streaming:descriptorsFor(position, options)
    local normalizedOptions, optionsReason = normalizeOptions(options)
    if not normalizedOptions then return Result.err('STREAM_DESCRIPTOR_INVALID', optionsReason) end
    options = normalizedOptions
    if options.requestId ~= nil and not positiveInteger(options.requestId) then return Result.err('STREAM_DESCRIPTOR_INVALID', 'stream request id is invalid') end
    if not validPosition(position) then return Result.err('STREAM_POSITION_INVALID', 'stream position is invalid') end
    local radius = tonumber(options.radius) or 100.0
    radius = math.min(math.max(radius, 1.0), 500.0)
    if not self.repository or type(self.repository.list) ~= 'function' then return Result.err('STREAMING_UNAVAILABLE', 'container repository is unavailable') end
    local listed = self.repository:list(options.filters, { limit = options.limit or 500, offset = options.offset or 0 })
    if Result.isErr(listed) then return listed end
    local descriptors = {}
    local radiusSquared = radius * radius
    for _, record in ipairs(listed.data or {}) do
        local descriptor = self:_descriptor(record)
        if descriptor and distanceSquared(position, descriptor.transform) <= radiusSquared then
            descriptors[#descriptors + 1] = descriptor
        end
    end
    return Result.ok(descriptors, { radius = radius, requestId = options.requestId })
end

function Streaming:subscribe(source, position, options)
    local request, optionsReason = normalizeOptions(options)
    if not request then return Result.err('STREAM_DESCRIPTOR_INVALID', optionsReason) end
    local key = tostring(source)
    local now = self:_now()
    local last = self.lastRequestAt[key]
    if last and now - last < self.requestIntervalMs then
        return Result.err('STREAM_RATE_LIMITED', 'container stream request is rate limited', { retryAfterMs = self.requestIntervalMs - (now - last) })
    end
    local result = self:descriptorsFor(position, request)
    if Result.isErr(result) then return result end
    self.lastRequestAt[key] = now
    self.subscriptions[key] = { position = { x = position.x, y = position.y, z = position.z }, options = request }
    return result
end

function Streaming:unsubscribe(source)
    local key = tostring(source)
    self.subscriptions[key] = nil
    self.lastRequestAt[key] = nil
    return Result.ok({ source = source, unsubscribed = true })
end

PortOps.Services.Streaming = Streaming
return Streaming
