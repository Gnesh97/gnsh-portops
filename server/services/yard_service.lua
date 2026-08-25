PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result=PortOps.Core.Result; local Service={}; Service.__index=Service
local function copy(v) if type(v)~='table' then return v end local o={}; for k,x in pairs(v) do o[k]=copy(x) end return o end
local function length(iso) return iso and (iso:sub(1,2)=='40' and 40 or 20) end
function Service.new(options) options=options or {}; return setmetatable({repository=options.repository, containerRepository=options.containerRepository, clock=options.clock},Service) end
function Service:get(slotId) return self.repository:get(slotId) end
function Service:compatible(container, slot)
    if type(container)~='table' or type(slot)~='table' then return Result.err('YARD_COMPATIBILITY_INVALID','container and slot are required') end
    if slot.state=='OCCUPIED' or slot.state=='BLOCKED' then return Result.err('SLOT_UNAVAILABLE','slot is not available') end
    if not slot.isoTypes[container.isoType] then return Result.err('ISO_INCOMPATIBLE','container ISO type is not supported by slot') end
    if length(container.isoType)==40 and slot.isoTypes[container.isoType]~=true then return Result.err('ISO_INCOMPATIBLE','40 foot container is not supported') end
    if container.cargo and container.cargo.reefer and slot.zone~='REEFER' then return Result.err('ZONE_INCOMPATIBLE','reefer requires reefer zone') end
    if container.cargo and container.cargo.hazardousClass and slot.zone~='HAZMAT' then return Result.err('ZONE_INCOMPATIBLE','hazardous cargo requires hazmat zone') end
    return Result.ok(true)
end
function Service:reserve(container, slotId, ownerId, ttlMs)
    local slot=self.repository:get(slotId); if Result.isErr(slot) then return slot end
    local check=self:compatible(container,slot.data); if Result.isErr(check) then return check end
    return self.repository:reserve(slotId,ownerId,ttlMs)
end
function Service:release(slotId,ownerId) return self.repository:release(slotId,ownerId) end
function Service:occupy(container,slotId,ownerId,expectedVersion)
    local slot=self.repository:get(slotId); if Result.isErr(slot) then return slot end
    local check=self:compatible(container,slot.data); if Result.isErr(check) and slot.data.state~='RESERVED' then return check end
    return self.repository:occupy(slotId,ownerId,container.id,expectedVersion)
end
function Service:unoccupy(slotId, containerId) return self.repository:unoccupy(slotId, containerId) end
function Service:descriptor(slot)
    return { id=slot.id, block=slot.block, bay=slot.bay, row=slot.row, tier=slot.tier, zone=slot.zone, state=slot.state, version=slot.version, transform=copy(slot.transform), occupantId=slot.occupantId }
end
function Service:list(filters) local result=self.repository:list(filters); if Result.isErr(result) then return result end; local out={}; for _,s in ipairs(result.data) do out[#out+1]=self:descriptor(s) end; return Result.ok(out) end
PortOps.Services.Yard=Service; return Service
