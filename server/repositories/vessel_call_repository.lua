PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result; local Repository={}; Repository.__index=Repository
local function copy(v) if type(v)~='table' then return v end; local o={}; for k,x in pairs(v) do o[k]=copy(x) end; return o end
function Repository.new(options) return setmetatable({records={},database=options and options.database},Repository) end
function Repository:create(value) if type(value)~='table' or type(value.id)~='string' then return Result.err('VESSEL_CALL_INVALID','call id is required') end; if self.records[value.id] then return Result.err('VESSEL_CALL_EXISTS','call already exists') end; self.records[value.id]=copy(value); return Result.ok(copy(value)) end
function Repository:get(id) local v=self.records[id]; return v and Result.ok(copy(v)) or Result.err('VESSEL_CALL_NOT_FOUND','call not found') end
function Repository:update(value,expectedVersion) local old=self.records[value and value.id]; if not old then return Result.err('VESSEL_CALL_NOT_FOUND','call not found') end; if expectedVersion and old.version~=expectedVersion then return Result.err('VESSEL_CALL_VERSION_CONFLICT','call version conflict') end; self.records[value.id]=copy(value); return Result.ok(copy(value)) end
function Repository:list() local a={}; for _,v in pairs(self.records) do a[#a+1]=copy(v) end; return Result.ok(a) end
PortOps.Repositories.VesselCall=Repository; return Repository
