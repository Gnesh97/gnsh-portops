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
function Repository:create(manifest)
    if type(manifest) ~= 'table' or type(manifest.id) ~= 'string' or type(manifest.items) ~= 'table' then return Result.err('MANIFEST_INVALID', 'manifest is invalid') end
    if self.records[manifest.id] then return Result.err('MANIFEST_EXISTS', 'manifest already exists') end
    self.records[manifest.id] = copy(manifest); return Result.ok(copy(manifest))
end
function Repository:get(id)
    local value = self.records[id]; return value and Result.ok(copy(value)) or Result.err('MANIFEST_NOT_FOUND', 'manifest was not found')
end
function Repository:update(manifest)
    if type(manifest) ~= 'table' or type(manifest.id) ~= 'string' or not self.records[manifest.id] then return Result.err('MANIFEST_NOT_FOUND', 'manifest was not found') end
    self.records[manifest.id] = copy(manifest); return Result.ok(copy(manifest))
end
function Repository:list(limit)
    local out = {}; local max = math.min(math.max(tonumber(limit) or 100, 1), 500)
    for _, value in pairs(self.records) do if #out < max then out[#out + 1] = copy(value) end end
    return Result.ok(out)
end
PortOps.Repositories.Manifest = Repository
return Repository
