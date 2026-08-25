PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Repository = {}
Repository.__index = Repository
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
function Repository.new(options) return setmetatable({ records = {}, database = options and options.database }, Repository) end
function Repository:create(value)
    if type(value) ~= 'table' or type(value.id) ~= 'string' then return Result.err('APPOINTMENT_INVALID', 'appointment id is required') end
    if self.records[value.id] then return Result.err('APPOINTMENT_EXISTS', 'appointment already exists') end
    self.records[value.id] = copy(value); return Result.ok(copy(value))
end
function Repository:get(id)
    local value = self.records[id]; return value and Result.ok(copy(value)) or Result.err('APPOINTMENT_NOT_FOUND', 'appointment was not found')
end
function Repository:update(value, expectedVersion)
    local current = self.records[value and value.id]
    if not current then return Result.err('APPOINTMENT_NOT_FOUND', 'appointment was not found') end
    if expectedVersion ~= nil and current.version and current.version ~= expectedVersion then return Result.err('APPOINTMENT_VERSION_CONFLICT', 'appointment version conflict') end
    self.records[value.id] = copy(value); return Result.ok(copy(value))
end
function Repository:list(limit)
    local out = {}; local max = math.min(math.max(tonumber(limit) or 100, 1), 500)
    for _, value in pairs(self.records) do if #out < max then out[#out + 1] = copy(value) end end
    return Result.ok(out)
end
PortOps.Repositories.Gate = Repository
return Repository
