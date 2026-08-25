PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}
local Repository = {}; Repository.__index = Repository
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
function Repository.new() return setmetatable({ records = {} }, Repository) end
function Repository:save(value) self.records[value.id] = copy(value); return copy(value) end
function Repository:get(id) local value = self.records[id]; return value and copy(value) or nil end
function Repository:list() local out = {}; for _, value in pairs(self.records) do out[#out + 1] = copy(value) end; return out end
PortOps.Repositories.Exception = Repository
return Repository
