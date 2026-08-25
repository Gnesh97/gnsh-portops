PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Reservations = PortOps.Core.Reservations
local Repository = {}; Repository.__index = Repository

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
local function nowMs() return type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.time() * 1000) end
local function encode(value)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then return nil end
    local ok, result = pcall(json.encode, value or {}); return ok and type(result) == 'string' and result or nil
end
local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or type(json) ~= 'table' or type(json.decode) ~= 'function' then return nil end
    local ok, result = pcall(json.decode, value); return ok and type(result) == 'table' and result or nil
end

function Repository.new(options)
    options = options or {}
    local config = options.config or (PortOps.Config and PortOps.Config.yard) or { id = 'yard', slots = {} }
    local slots, ids = {}, {}
    for _, slot in ipairs(config.slots or {}) do
        slots[slot.id] = copy(slot); slots[slot.id].state = 'AVAILABLE'; slots[slot.id].version = 1; ids[#ids + 1] = slot.id
    end
    local repository = setmetatable({ config = config, slots = slots, ids = ids, database = options.database, clock = options.clock }, Repository)
    repository.reservations = options.reservations or Reservations.new({ clock = options.clock })
    repository.reservations.onExpire = function(record)
        local slot = record and repository.slots[record.slotId]
        if slot and slot.state == 'RESERVED' and slot.reservationOwner == record.ownerId then
            local nextSlot = copy(slot); nextSlot.state = 'AVAILABLE'; nextSlot.reservationOwner = nil; nextSlot.reservationExpiresAt = nil; nextSlot.version = nextSlot.version + 1
            local saved = repository:_persist(nextSlot)
            if Result.isOk(saved) then repository.slots[record.slotId] = nextSlot end
        end
    end
    if repository:_durable() then repository:_loadPersistent() end
    return repository
end

function Repository:_durable()
    return type(self.database) == 'table' and self.database.provider == 'oxmysql'
end
function Repository:_now() return self.clock and self.clock() or nowMs() end
function Repository:_slot(id) return self.slots[id] end

function Repository:_persist(slot)
    if not self:_durable() then return Result.ok(true) end
    local transform = encode(slot.transform); local isoTypes = encode(slot.isoTypes)
    if not transform or not isoTypes then return Result.err('YARD_REPOSITORY_FAILED', 'JSON serializer is unavailable') end
    local result = self.database:insert([[
        INSERT INTO portops_yard_slots
            (slot_id, yard_id, block_id, bay, row_index, tier, zone_tag, transform_json, iso_types_json,
             state, reservation_owner, reservation_expires_at, occupant_id, version, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            yard_id = VALUES(yard_id), block_id = VALUES(block_id), bay = VALUES(bay), row_index = VALUES(row_index),
            tier = VALUES(tier), zone_tag = VALUES(zone_tag), transform_json = VALUES(transform_json),
            iso_types_json = VALUES(iso_types_json), state = VALUES(state), reservation_owner = VALUES(reservation_owner),
            reservation_expires_at = VALUES(reservation_expires_at), occupant_id = VALUES(occupant_id),
            version = VALUES(version), updated_at = VALUES(updated_at)
    ]], {
        slot.id, self.config.id, slot.block, slot.bay, slot.row, slot.tier, slot.zone, transform, isoTypes,
        slot.state, slot.reservationOwner, slot.reservationExpiresAt, slot.occupantId, slot.version, self:_now()
    })
    if Result.isErr(result) then return Result.err('YARD_REPOSITORY_FAILED', 'yard slot persistence failed', result.error) end
    return Result.ok(true)
end

function Repository:_loadPersistent()
    local result = self.database:query('SELECT * FROM portops_yard_slots WHERE yard_id = ?', { self.config.id })
    if Result.isErr(result) then self.startupError = Result.err('YARD_REPOSITORY_FAILED', 'yard slot load failed', result.error); return end
    local seen = {}
    for _, row in ipairs(result.data and (result.data.rows or result.data) or {}) do
        local slot = self.slots[row.slot_id]
        if slot then
            slot.block = row.block_id or slot.block; slot.bay = tonumber(row.bay) or slot.bay; slot.row = tonumber(row.row_index) or slot.row; slot.tier = tonumber(row.tier) or slot.tier
            slot.zone = row.zone_tag or slot.zone; slot.transform = decode(row.transform_json) or slot.transform; slot.isoTypes = decode(row.iso_types_json) or slot.isoTypes
            slot.state = row.state or 'AVAILABLE'; slot.reservationOwner = row.reservation_owner; slot.reservationExpiresAt = tonumber(row.reservation_expires_at); slot.occupantId = row.occupant_id; slot.version = tonumber(row.version) or 1
            seen[row.slot_id] = true
            if slot.state == 'RESERVED' and slot.reservationOwner and slot.reservationExpiresAt and slot.reservationExpiresAt > self:_now() then
                self.reservations:restore({ slotId = slot.id, ownerId = slot.reservationOwner, expiresAt = slot.reservationExpiresAt })
            elseif slot.state == 'RESERVED' then
                slot.state = 'AVAILABLE'; slot.reservationOwner = nil; slot.reservationExpiresAt = nil; slot.version = slot.version + 1
                local saved = self:_persist(slot); if Result.isErr(saved) then self.startupError = saved; return end
            end
        end
    end
    for _, id in ipairs(self.ids) do
        if not seen[id] then
            local saved = self:_persist(self.slots[id]); if Result.isErr(saved) then self.startupError = saved; return end
        end
    end
end

function Repository:get(slotId)
    local slot = self:_slot(slotId)
    return slot and Result.ok(copy(slot)) or Result.err('SLOT_NOT_FOUND', 'yard slot was not found')
end
function Repository:list(filters)
    local out = {}
    for _, id in ipairs(self.ids) do
        local slot = self.slots[id]
        if (not filters or not filters.block or slot.block == filters.block) and (not filters or not filters.zone or slot.zone == filters.zone) then out[#out + 1] = copy(slot) end
    end
    return Result.ok(out)
end
function Repository:reserve(slotId, ownerId, ttlMs)
    local slot = self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND', 'yard slot was not found') end
    if slot.state == 'BLOCKED' or slot.state == 'OCCUPIED' then return Result.err('SLOT_UNAVAILABLE', 'slot is not available') end
    local reservation = self.reservations:reserve(slotId, ownerId, ttlMs); if Result.isErr(reservation) then return reservation end
    local nextSlot = copy(slot); nextSlot.state = 'RESERVED'; nextSlot.reservationOwner = ownerId; nextSlot.reservationExpiresAt = reservation.data.expiresAt; nextSlot.version = nextSlot.version + 1
    local saved = self:_persist(nextSlot)
    if Result.isErr(saved) then self.reservations.records[slotId] = nil; return saved end
    self.slots[slotId] = nextSlot
    return Result.ok(copy(nextSlot), { token = reservation.data.token })
end
function Repository:release(slotId, ownerId)
    local slot=self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    local released=self.reservations:release(slotId,ownerId); if Result.isErr(released) then return released end
    local nextSlot=copy(slot); if nextSlot.state=='RESERVED' then nextSlot.state='AVAILABLE'; nextSlot.reservationOwner=nil; nextSlot.reservationExpiresAt=nil; nextSlot.version=nextSlot.version+1 end
    local saved=self:_persist(nextSlot); if Result.isErr(saved) then self.reservations:restore({slotId=slotId,ownerId=ownerId,expiresAt=slot.reservationExpiresAt or self:_now()+1000}); return saved end
    self.slots[slotId]=nextSlot; return Result.ok(copy(nextSlot))
end
function Repository:occupy(slotId, ownerId, containerId, expectedVersion)
    local slot=self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if expectedVersion~=nil and slot.version~=expectedVersion then return Result.err('SLOT_VERSION_CONFLICT','yard slot version conflict') end
    local reservation=self.reservations:get(slotId); if Result.isErr(reservation) or reservation.data.ownerId~=ownerId then return Result.err('RESERVATION_OWNER_INVALID','reservation owner mismatch') end
    local nextSlot=copy(slot); nextSlot.state='OCCUPIED'; nextSlot.occupantId=containerId; nextSlot.reservationOwner=nil; nextSlot.reservationExpiresAt=nil; nextSlot.version=nextSlot.version+1
    local saved=self:_persist(nextSlot); if Result.isErr(saved) then return saved end
    self.reservations.records[slotId]=nil; self.slots[slotId]=nextSlot; return Result.ok(copy(nextSlot))
end
function Repository:unoccupy(slotId, containerId)
    local slot=self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if slot.state~='OCCUPIED' or (containerId and slot.occupantId~=containerId) then return Result.err('SLOT_OCCUPANT_INVALID','slot occupant mismatch') end
    local nextSlot=copy(slot); nextSlot.state='AVAILABLE'; nextSlot.occupantId=nil; nextSlot.version=nextSlot.version+1; local saved=self:_persist(nextSlot); if Result.isErr(saved) then return saved end; self.slots[slotId]=nextSlot; return Result.ok(copy(nextSlot))
end
function Repository:restoreOccupancy(slotId, containerId)
    local slot=self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if slot.state=='OCCUPIED' and slot.occupantId==containerId then return Result.ok(copy(slot),{idempotent=true}) end
    if slot.state=='BLOCKED' or (slot.state=='OCCUPIED' and slot.occupantId~=containerId) then return Result.err('SLOT_UNAVAILABLE','slot is not available') end
    local nextSlot=copy(slot); nextSlot.state='OCCUPIED'; nextSlot.occupantId=containerId; nextSlot.reservationOwner=nil; nextSlot.reservationExpiresAt=nil; nextSlot.version=nextSlot.version+1; local saved=self:_persist(nextSlot); if Result.isErr(saved) then return saved end; self.slots[slotId]=nextSlot; return Result.ok(copy(nextSlot))
end
function Repository:block(slotId)
    local slot=self:_slot(slotId); if not slot then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    local nextSlot=copy(slot); nextSlot.state='BLOCKED'; nextSlot.version=nextSlot.version+1; local saved=self:_persist(nextSlot); if Result.isErr(saved) then return saved end; self.slots[slotId]=nextSlot; return Result.ok(copy(nextSlot))
end
PortOps.Repositories.Yard=Repository; return Repository
