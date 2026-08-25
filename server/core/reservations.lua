PortOps = PortOps or {}; PortOps.Core = PortOps.Core or {}
local Result = PortOps.Core.Result
local Reservations = {}; Reservations.__index = Reservations
local function now() return type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.time() * 1000) end
function Reservations.new(options)
    options = options or {}
    return setmetatable({ clock = options.clock, records = {}, sequence = 0, onExpire = options.onExpire }, Reservations)
end
function Reservations:_now() return self.clock and self.clock() or now() end
function Reservations:_expire(slotId, record)
    self.records[slotId] = nil
    if type(self.onExpire) == 'function' then pcall(self.onExpire, record) end
end
function Reservations:reserve(slotId, ownerId, ttlMs)
    if type(slotId) ~= 'string' or type(ownerId) ~= 'string' or ownerId == '' then return Result.err('RESERVATION_INVALID', 'slot and owner are required') end
    local existing = self.records[slotId]; local current = self:_now()
    if existing and existing.expiresAt <= current then self:_expire(slotId, existing); existing = nil end
    if existing and existing.expiresAt > current and existing.ownerId ~= ownerId then return Result.err('SLOT_RESERVED', 'slot is reserved') end
    self.sequence = self.sequence + 1
    local reservation = { slotId = slotId, ownerId = ownerId, token = ('res-%s-%d-%d'):format(slotId, current, self.sequence), expiresAt = current + math.max(1000, tonumber(ttlMs) or 30000) }
    self.records[slotId] = reservation; return Result.ok(reservation)
end
function Reservations:get(slotId)
    local r = self.records[slotId]; if r and r.expiresAt <= self:_now() then self:_expire(slotId, r); r = nil end
    return r and Result.ok(r) or Result.err('RESERVATION_NOT_FOUND', 'reservation was not found')
end
function Reservations:restore(record)
    if type(record) ~= 'table' or type(record.slotId) ~= 'string' or type(record.ownerId) ~= 'string' or type(record.expiresAt) ~= 'number' then
        return Result.err('RESERVATION_INVALID', 'reservation record is invalid')
    end
    if record.expiresAt <= self:_now() then return Result.err('RESERVATION_EXPIRED', 'reservation has expired') end
    self.records[record.slotId] = {
        slotId = record.slotId,
        ownerId = record.ownerId,
        token = record.token or ('res-%s-%d'):format(record.slotId, record.expiresAt),
        expiresAt = record.expiresAt
    }
    return Result.ok(self.records[record.slotId])
end
function Reservations:release(slotId, ownerId)
    local r = self:get(slotId); if Result.isErr(r) then return r end
    if ownerId and r.data.ownerId ~= ownerId then return Result.err('RESERVATION_OWNER_INVALID', 'reservation owner mismatch') end
    self.records[slotId] = nil; return Result.ok({ released = true, slotId = slotId })
end
function Reservations:move(fromSlot, toSlot, ownerId, ttlMs)
    local old = self:get(fromSlot); if Result.isErr(old) then return old end
    if old.data.ownerId ~= ownerId then return Result.err('RESERVATION_OWNER_INVALID', 'reservation owner mismatch') end
    local result = self:reserve(toSlot, ownerId, ttlMs); if Result.isErr(result) then return result end
    self.records[fromSlot] = nil; return result
end
PortOps.Core.Reservations = Reservations
return Reservations
