PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:open(input) local e,err=self.domain.new(input); if not e then return nil,err end; return self.repository:save(e) end
function S:resolve(id,actorId) local e=self.repository:get(id); if not e then return nil,'EXCEPTION_NOT_FOUND' end;e.status='RESOLVED';e.resolvedBy=actorId;return self.repository:save(e) end
function S:misroute(containerId,details) return self:open({type='MISROUTED',entityId=containerId,details=details}) end
PortOps.Services.Exceptions=S; return S
