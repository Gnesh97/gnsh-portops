PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result; local Reservations = PortOps.Core.Reservations
local Repository = {}; Repository.__index = Repository
local function copy(v) if type(v) ~= 'table' then return v end local o={}; for k,x in pairs(v) do o[k]=copy(x) end return o end
function Repository.new(options)
    options=options or {}; local config=options.config or (PortOps.Config and PortOps.Config.yard) or { slots={} }; local slots={}; local ids={}
    for _, slot in ipairs(config.slots or {}) do slots[slot.id]=copy(slot); slots[slot.id].state='AVAILABLE'; slots[slot.id].version=1; ids[#ids+1]=slot.id end
    local reservations = options.reservations
    if not reservations then
        reservations = Reservations.new({
            clock = options.clock,
            onExpire = function(record)
                local slot = record and slots[record.slotId]
                if slot and slot.state == 'RESERVED' and slot.reservationOwner == record.ownerId then
                    slot.state = 'AVAILABLE'
                    slot.reservationOwner = nil
                    slot.reservationExpiresAt = nil
                    slot.version = slot.version + 1
                end
            end
        })
    end
    return setmetatable({ config=config, slots=slots, ids=ids, reservations=reservations, clock=options.clock }, Repository)
end
function Repository:_slot(id) return self.slots[id] end
function Repository:get(slotId) local s=self:_slot(slotId); return s and Result.ok(copy(s)) or Result.err('SLOT_NOT_FOUND','yard slot was not found') end
function Repository:list(filters)
    local out={}; for _,id in ipairs(self.ids) do local s=self.slots[id]; if (not filters or not filters.block or s.block==filters.block) and (not filters or not filters.zone or s.zone==filters.zone) then out[#out+1]=copy(s) end end; return Result.ok(out)
end
function Repository:reserve(slotId, ownerId, ttlMs)
    local s=self:_slot(slotId); if not s then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if s.state=='BLOCKED' or s.state=='OCCUPIED' then return Result.err('SLOT_UNAVAILABLE','slot is not available') end
    local result=self.reservations:reserve(slotId,ownerId,ttlMs); if Result.isErr(result) then return result end
    s.state='RESERVED'; s.reservationOwner=ownerId; s.reservationExpiresAt=result.data.expiresAt; s.version=s.version+1
    return Result.ok(copy(s), { token=result.data.token })
end
function Repository:release(slotId, ownerId)
    local s=self:_slot(slotId); if not s then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    local result=self.reservations:release(slotId,ownerId); if Result.isErr(result) then return result end
    if s.state=='RESERVED' then s.state='AVAILABLE'; s.reservationOwner=nil; s.reservationExpiresAt=nil; s.version=s.version+1 end
    return Result.ok(copy(s))
end
function Repository:occupy(slotId, ownerId, containerId, expectedVersion)
    local s=self:_slot(slotId); if not s then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if expectedVersion ~= nil and s.version ~= expectedVersion then return Result.err('SLOT_VERSION_CONFLICT','yard slot version conflict') end
    local r=self.reservations:get(slotId); if Result.isErr(r) or r.data.ownerId~=ownerId then return Result.err('RESERVATION_OWNER_INVALID','reservation owner mismatch') end
    s.state='OCCUPIED'; s.occupantId=containerId; s.reservationOwner=nil; s.reservationExpiresAt=nil; s.version=s.version+1; self.reservations:release(slotId,ownerId); return Result.ok(copy(s))
end
function Repository:unoccupy(slotId, containerId)
    local s=self:_slot(slotId); if not s then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end
    if s.state ~= 'OCCUPIED' or (containerId and s.occupantId ~= containerId) then return Result.err('SLOT_OCCUPANT_INVALID','slot occupant mismatch') end
    s.state='AVAILABLE'; s.occupantId=nil; s.version=s.version+1; return Result.ok(copy(s))
end
function Repository:block(slotId) local s=self:_slot(slotId); if not s then return Result.err('SLOT_NOT_FOUND','yard slot was not found') end; s.state='BLOCKED'; s.version=s.version+1; return Result.ok(copy(s)) end
PortOps.Repositories.Yard=Repository; return Repository
