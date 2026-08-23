-- Nearby-only client container streaming with request throttling and
-- hysteresis.  The client never asks for the complete container dataset.
PortOps = PortOps or {}
PortOps.Client = PortOps.Client or {}

local Streaming = {}
Streaming.__index = Streaming

local function ok(data)
    return { ok = true, data = data }
end

local function err(code, message)
    return { ok = false, error = { code = code, message = message } }
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function distanceSquared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return dx * dx + dy * dy + dz * dz
end

local function positionValid(position)
    local function finite(value)
        return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
    end
    local kind = type(position)
    return (kind == 'table' or kind == 'vector3' or kind == 'userdata') and finite(position.x) and finite(position.y) and finite(position.z)
end

local function defaultPosition()
    if type(PlayerPedId) ~= 'function' or type(GetEntityCoords) ~= 'function' then return nil end
    local coords = GetEntityCoords(PlayerPedId())
    if not coords then return nil end
    return { x = coords.x, y = coords.y, z = coords.z }
end

function Streaming.new(options)
    options = options or {}
    local enterRadius = math.max(1.0, tonumber(options.enterRadius) or 20.0)
    local leaveRadius = math.max(enterRadius, tonumber(options.leaveRadius) or 30.0)
    return setmetatable({
        visuals = options.visuals,
        getPlayerPosition = options.getPlayerPosition or defaultPosition,
        requestDescriptors = options.requestDescriptors or function() end,
        enterRadius = enterRadius,
        leaveRadius = leaveRadius,
        requestIntervalMs = math.max(0, tonumber(options.requestIntervalMs) or 1000),
        refreshIntervalMs = math.max(0, tonumber(options.refreshIntervalMs) or 5000),
        lastPosition = nil,
        lastRequestAt = nil,
        interestCenter = nil,
        requestSequence = 0,
        lastAppliedRequestId = 0,
        descriptors = {},
        active = true
    }, Streaming)
end

function Streaming:_now(value)
    if type(value) == 'number' then return value end
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

function Streaming:update(timestamp)
    if not self.active then return err('STREAMING_STOPPED', 'container streaming is stopped') end
    local position = self.getPlayerPosition()
    if not positionValid(position) then return err('STREAM_POSITION_INVALID', 'player position is unavailable') end
    local now = self:_now(timestamp)
    local moved = not self.lastPosition or distanceSquared(position, self.lastPosition) >= self.enterRadius * self.enterRadius
    local due = not self.lastRequestAt or now - self.lastRequestAt >= self.requestIntervalMs
    local refreshDue = self.lastRequestAt and now - self.lastRequestAt >= self.refreshIntervalMs
    local outside = self.interestCenter and distanceSquared(position, self.interestCenter) > self.leaveRadius * self.leaveRadius
    if outside then self:clear() end
    local requested = false
    if due and (not self.interestCenter or outside or moved or refreshDue) then
        self.lastPosition = copy(position)
        self.lastRequestAt = now
        self.interestCenter = copy(position)
        self.requestSequence = self.requestSequence + 1
        local requestId = self.requestSequence
        requested = true
        local callbackOk, response = pcall(self.requestDescriptors, copy(position), { radius = self.leaveRadius, requestId = requestId })
        if callbackOk and type(response) == 'table' and self.visuals then
            if response.ok and type(response.data) == 'table' then self:receive(response.data, response.meta and response.meta.requestId or requestId)
            elseif response[1] then self:receive(response, requestId) end
        end
    end
    return ok({ requested = requested, position = copy(position), active = self.active, descriptorCount = #self.descriptors })
end

function Streaming:receive(descriptors, requestId)
    if not self.active then return err('STREAMING_STOPPED', 'container streaming is stopped') end
    if type(descriptors) ~= 'table' then return err('STREAM_DESCRIPTOR_INVALID', 'descriptor batch is invalid') end
    if requestId ~= nil then
        if type(requestId) ~= 'number' or requestId % 1 ~= 0 or requestId < 1 or requestId > self.requestSequence or requestId <= self.lastAppliedRequestId then
            return err('STREAM_STALE_RESPONSE', 'container stream response is stale')
        end
        self.lastAppliedRequestId = requestId
    end
    self.descriptors = copy(descriptors)
    if not self.visuals or type(self.visuals.reconcile) ~= 'function' then return err('VISUAL_RESOLVER_UNAVAILABLE', 'visual resolver is unavailable') end
    local result = self.visuals:reconcile(self.descriptors)
    if result and result.ok == false then return result end
    return ok({ descriptorCount = #self.descriptors, visual = result and result.data or nil })
end

function Streaming:clear()
    self.descriptors = {}
    if self.visuals and type(self.visuals.reconcile) == 'function' then self.visuals:reconcile({}) end
    return ok({ cleared = true })
end

function Streaming:stop()
    self.active = false
    self:clear()
    return ok({ stopped = true })
end

PortOps.Client.ContainerStreaming = Streaming
return Streaming
