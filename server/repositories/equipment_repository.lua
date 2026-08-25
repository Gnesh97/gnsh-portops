PortOps=PortOps or {}; PortOps.Repositories=PortOps.Repositories or {}; local R={}; R.__index=R
function R.new() return setmetatable({records={}},R) end
function R:save(v) self.records[v.id]=v; return v end
function R:get(id) return self.records[id] end
function R:list() local a={}; for _,v in pairs(self.records) do a[#a+1]=v end; return a end
PortOps.Repositories.Equipment=R; return R
