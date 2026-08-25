PortOps=PortOps or {}; PortOps.Repositories=PortOps.Repositories or {}; local R={}; R.__index=R
function R.new() return setmetatable({records={}},R) end
function R:append(v) self.records[#self.records+1]=v; return v end
function R:list(filter) local a={}; for _,v in ipairs(self.records) do if not filter or (not filter.entityId or v.entityId==filter.entityId) then a[#a+1]=v end end; return a end
PortOps.Repositories.Audit=R; return R
