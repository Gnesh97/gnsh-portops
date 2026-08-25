PortOps = PortOps or {}
PortOps.Domain = PortOps.Domain or {}
local Result = PortOps.Core.Result
local Yard = {}

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end

function Yard.validateConfig(config)
    if type(config) ~= 'table' or type(config.slots) ~= 'table' then return Result.err('YARD_CONFIG_INVALID', 'yard slots are required') end
    local ids = {}
    for _, slot in ipairs(config.slots) do
        if type(slot) ~= 'table' or type(slot.id) ~= 'string' or ids[slot.id] then return Result.err('YARD_CONFIG_INVALID', 'slot ids must be unique') end
        ids[slot.id] = true
        if type(slot.block) ~= 'string' or type(slot.bay) ~= 'number' or slot.bay < 1 or type(slot.row) ~= 'number' or slot.row < 1 or type(slot.tier) ~= 'number' or slot.tier < 1 or slot.tier % 1 ~= 0 then return Result.err('YARD_CONFIG_INVALID', 'slot coordinates are invalid') end
        if type(slot.isoTypes) ~= 'table' or type(slot.zone) ~= 'string' then return Result.err('YARD_CONFIG_INVALID', 'slot compatibility is invalid') end
        if config.zones and not config.zones[slot.zone] then return Result.err('YARD_CONFIG_INVALID', 'slot zone is not configured') end
        for iso, enabled in pairs(slot.isoTypes) do if type(iso) ~= 'string' or enabled ~= true then return Result.err('YARD_CONFIG_INVALID', 'slot ISO compatibility is invalid') end end
        local t = slot.transform
        if type(t) ~= 'table' or not finite(t.x) or not finite(t.y) or not finite(t.z) or not finite(t.heading or 0) then return Result.err('YARD_CONFIG_INVALID', 'slot transform is invalid') end
    end
    return Result.ok({ id = config.id, version = config.version or 1, slotCount = #config.slots })
end

function Yard.copy(value) return copy(value) end
function Yard.slot(value)
    if type(value) ~= 'table' or type(value.id) ~= 'string' then return Result.err('YARD_SLOT_INVALID', 'slot is invalid') end
    return Result.ok(copy(value))
end

PortOps.Domain.Yard = Yard
return Yard
