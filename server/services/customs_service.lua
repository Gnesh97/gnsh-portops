PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) o=o or {}; return setmetatable(o,S) end
function S:open(containerId,input) local c,err=self.caseDomain.new({containerId=containerId,riskScore=input and input.riskScore,reasons=input and input.reasons}); if not c then return nil,err end; return self.repository:save(c) end
function S:transition(id,status,actorId) local c=self.repository:get(id); if not c then return nil,'CUSTOMS_CASE_NOT_FOUND' end; if not self.caseDomain.STATUSES[status] then return nil,'CUSTOMS_STATUS_INVALID' end; c.status=status;c.officerId=actorId;c.version=c.version+1;c.updatedAt=os.time()*1000; return self.repository:save(c) end
function S:canGateOut(container) return container and container.customs and container.customs.status=='CLEARED' or false end
function S:inspect(id,officerId,result) local c,e=self:transition(id,'INSPECTION',officerId); if not c then return nil,e end; c.details=result or {}; return self.repository:save(c) end
PortOps.Services.Customs=S; return S
