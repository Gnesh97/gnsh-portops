PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}
local Repository = {}; Repository.__index = Repository
local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
function Repository.new() return setmetatable({ records = {} }, Repository) end
function Repository:append(value) self.records[#self.records + 1] = copy(value); return copy(value) end
function Repository:list(filter)
    local out = {}; for _, value in ipairs(self.records) do
        if not filter or (not filter.entityId or value.entityId == filter.entityId) then out[#out + 1] = copy(value) end
    end
    return out
end
PortOps.Repositories.Activity = Repository
return Repository
