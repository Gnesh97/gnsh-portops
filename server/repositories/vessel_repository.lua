PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Vessel = PortOps.Domain.Vessel
local Repository = {}
Repository.__index = Repository

local function copy(value) return Vessel.copy(value) end
function Repository.new(options)
    options = options or {}
    return setmetatable({ records = {}, database = options.database }, Repository)
end
function Repository:create(value)
    local checked = Vessel.new(value)
    if Result.isErr(checked) then return checked end
    if self.records[checked.data.id] then return Result.err('VESSEL_EXISTS', 'vessel already exists') end
    self.records[checked.data.id] = copy(checked.data)
    return Result.ok(copy(checked.data))
end
function Repository:get(id)
    local value = self.records[id]
    return value and Result.ok(copy(value)) or Result.err('VESSEL_NOT_FOUND', 'vessel was not found')
end
function Repository:update(value, expectedVersion)
    local current = self.records[value and value.id]
    if not current then return Result.err('VESSEL_NOT_FOUND', 'vessel was not found') end
    if expectedVersion ~= nil and current.version ~= expectedVersion then return Result.err('VESSEL_VERSION_CONFLICT', 'vessel version conflict') end
    local checked = Vessel.new(value)
    if Result.isErr(checked) then return checked end
    self.records[checked.data.id] = copy(checked.data)
    return Result.ok(copy(checked.data))
end
function Repository:list(limit)
    local out = {}; local max = math.min(math.max(tonumber(limit) or 100, 1), 500)
    for _, value in pairs(self.records) do if #out < max then out[#out + 1] = copy(value) end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return Result.ok(out)
end
PortOps.Repositories.Vessel = Repository
return Repository
