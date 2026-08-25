PortOps=PortOps or {}; PortOps.Repositories=PortOps.Repositories or {}; local R={}; R.__index=R
function R.new() return setmetatable({events={}},R) end
function R:append(v) self.events[#self.events+1]=v end
function R:list(fromMs,toMs,limit) local a={}; local max=math.min(math.max(tonumber(limit) or 5000,1),5000); for _,v in ipairs(self.events) do if #a>=max then break end; if (not fromMs or v.at>=fromMs) and (not toMs or v.at<=toMs) then a[#a+1]=v end end; return a end
PortOps.Repositories.Analytics=R; return R
