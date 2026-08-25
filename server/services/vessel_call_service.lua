PortOps = PortOps or {}; PortOps.Services=PortOps.Services or {}; local Result=PortOps.Core.Result; local S={}; S.__index=S
local function copy(value) local out={}; for k,v in pairs(value or {}) do out[k]=v end; return out end
function S.new(o) o=o or {}; return setmetatable({calls=o.calls or {},repository=o.repository,machine=o.machine},S) end
function S:create(call)
    if type(call)~='table' or type(call.id)~='string' then return Result.err('VESSEL_CALL_INVALID','call id is required') end
    local candidate={}; for k,v in pairs(call) do candidate[k]=v end; candidate.status=candidate.status or 'PLANNED'; candidate.version=candidate.version or 1
    if self.repository then return self.repository:create(candidate) end
    if self.calls[candidate.id] then return Result.err('VESSEL_CALL_EXISTS','call already exists') end
    self.calls[candidate.id]=candidate; return Result.ok(copy(candidate))
end
function S:get(id) if self.repository then return self.repository:get(id) end; local value=self.calls[id]; return value and Result.ok(copy(value)) or Result.err('VESSEL_CALL_NOT_FOUND','call not found') end
function S:transition(id,target)
    local current=self:get(id); if Result.isErr(current) then return current end
    local r=self.machine:transition(current.data,target); if Result.isErr(r) then return r end
    if self.repository then return self.repository:update(r.data,current.data.version) end
    self.calls[id]=r.data; return r
end
PortOps.Services.VesselCall=S; return S
