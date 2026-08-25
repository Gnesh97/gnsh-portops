PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result = PortOps.Core.Result
local Service = {}; Service.__index = Service

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
local function overlaps(a, b)
    local aStart, aEnd = tonumber(a and (a.start or a.windowStart or a[1])), tonumber(a and (a.finish or a.windowEnd or a[2]))
    local bStart, bEnd = tonumber(b and (b.start or b.windowStart or b[1])), tonumber(b and (b.finish or b.windowEnd or b[2]))
    return aStart and aEnd and bStart and bEnd and aStart < bEnd and bStart < aEnd
end
local function sameWindow(a, b)
    local aStart, aEnd = tonumber(a and (a.start or a.windowStart or a[1])), tonumber(a and (a.finish or a.windowEnd or a[2]))
    local bStart, bEnd = tonumber(b and (b.start or b.windowStart or b[1])), tonumber(b and (b.finish or b.windowEnd or b[2]))
    return aStart and aEnd and bStart and bEnd and aStart == bStart and aEnd == bEnd
end

function Service.new(options)
    options = options or {}
    local service = setmetatable({ slots = options.slots or {}, assignments = {}, reservationLocks = {}, callRepository = options.callRepository, clock = options.clock }, Service)
    service:_load()
    return service
end

function Service:_load()
    if not self.callRepository or type(self.callRepository.list) ~= 'function' then return end
    local result = self.callRepository:list(500)
    if Result.isErr(result) then self.startupError = result; return end
    for _, call in ipairs(result.data or {}) do
        local window = call.metadata and call.metadata.berthWindow
        if call.berthId and window then
            self.assignments[call.berthId] = self.assignments[call.berthId] or {}
            self.assignments[call.berthId][#self.assignments[call.berthId] + 1] = { berthId = call.berthId, callId = call.id, window = copy(window) }
        end
    end
end

function Service:_slot(berthId)
    for _, candidate in ipairs(self.slots or {}) do if candidate.id == berthId then return candidate end end
    return nil
end

function Service:_persistCall(callId, berthId, window, release)
    if not self.callRepository then return Result.ok(true) end
    local current = self.callRepository:get(callId)
    if Result.isErr(current) then return current end
    local nextCall = copy(current.data)
    nextCall.berthId = release and nil or berthId
    nextCall.metadata = copy(nextCall.metadata or {})
    nextCall.metadata.berthWindow = release and nil or copy(window)
    nextCall.version = (nextCall.version or 1) + 1
    nextCall.updatedAt = self.clock and self.clock() or math.floor(os.time() * 1000)
    return self.callRepository:update(nextCall, current.data.version or 1)
end

function Service:reserve(berthId, callId, window, vesselType, craneId)
    local slot = self:_slot(berthId)
    if not slot and #(self.slots or {}) > 0 then return Result.err('BERTH_NOT_FOUND', 'berth is not configured') end
    if slot and slot.available == false then return Result.err('BERTH_UNAVAILABLE', 'berth is unavailable') end
    if vesselType and slot and slot.compatibleVesselTypes and not slot.compatibleVesselTypes[vesselType] then return Result.err('BERTH_INCOMPATIBLE', 'vessel type is not compatible') end
    if craneId and slot and slot.craneIds and not slot.craneIds[craneId] then return Result.err('BERTH_CRANE_UNAVAILABLE', 'crane coverage is unavailable') end
    local current = self.assignments[berthId] or {}
    for _, assignment in ipairs(current) do
        if assignment.callId == callId and sameWindow(assignment.window, window) then
            return Result.ok(copy(assignment), { idempotent = true })
        end
        if not window or not assignment.window or overlaps(assignment.window, window) then return Result.err('BERTH_CONFLICT', 'berth window overlaps an existing assignment') end
    end
    if self.reservationLocks[berthId] then return Result.err('BERTH_CONFLICT', 'berth reservation is being committed') end
    self.reservationLocks[berthId] = true
    local persisted = self:_persistCall(callId, berthId, window, false)
    self.reservationLocks[berthId] = nil
    if Result.isErr(persisted) then return persisted end
    local created = { berthId = berthId, callId = callId, window = copy(window) }
    current[#current + 1] = created; self.assignments[berthId] = current
    return Result.ok(copy(created))
end

function Service:release(berthId, callId)
    if self.reservationLocks[berthId] then return Result.err('BERTH_CONFLICT', 'berth reservation is being committed') end
    local list = self.assignments[berthId]
    if not list then return Result.err('BERTH_NOT_FOUND', 'assignment not found') end
    self.reservationLocks[berthId] = true
    local kept, released = {}, false
    for _, assignment in ipairs(list) do
        if not callId or assignment.callId == callId then
            local persisted = self:_persistCall(assignment.callId, berthId, assignment.window, true)
            if Result.isErr(persisted) then self.reservationLocks[berthId] = nil; return persisted end
            released = true
        else
            kept[#kept + 1] = assignment
        end
    end
    self.reservationLocks[berthId] = nil
    if not released then return Result.err('BERTH_OWNER_INVALID', 'call does not own berth') end
    self.assignments[berthId] = #kept > 0 and kept or nil
    return Result.ok({ released = true, berthId = berthId })
end

PortOps.Services.Berth = Service
return Service
