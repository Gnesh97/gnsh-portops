PortOps=PortOps or {}; PortOps.Repositories=PortOps.Repositories or {}
local R={}; R.__index=R
local function copy(v) local out={}; for k,x in pairs(v or {}) do if type(x)=='table' then local nested={}; for nk,nx in pairs(x) do nested[nk]=nx end; out[k]=nested else out[k]=x end end; return out end
function R.new() return setmetatable({records={}},R) end
function R:save(case) self.records[case.id]=copy(case); return copy(case) end
function R:get(id) local c=self.records[id]; return c and copy(c) or nil end
function R:list(status) local out={}; for _,c in pairs(self.records) do if not status or c.status==status then out[#out+1]=copy(c) end end; return out end
PortOps.Repositories.Customs=R; return R
