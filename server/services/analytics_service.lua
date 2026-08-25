PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:record(metric,value,entityId,at) return self.repository:append({metric=metric,value=value,entityId=entityId,at=at or os.time()*1000}) end
function S:kpi(fromMs,toMs)
    if fromMs and toMs and (type(fromMs)~='number' or type(toMs)~='number' or toMs<fromMs or toMs-fromMs>31*24*60*60*1000) then return nil,'ANALYTICS_RANGE_INVALID' end
    local rows=self.repository:list(fromMs,toMs,5000); local out={moves=0,misroutes=0,craneUtilization=0,yardOccupancy=0,cycleTime=0,truckTurnaround=0,dwell=0}
    for _,r in ipairs(rows) do if r.metric=='move' then out.moves=out.moves+(tonumber(r.value) or 0) elseif r.metric=='misroute' then out.misroutes=out.misroutes+(tonumber(r.value) or 0) elseif out[r.metric]~=nil then out[r.metric]=out[r.metric]+(tonumber(r.value) or 0) end end
    return out
end
PortOps.Services.Analytics=S; return S
