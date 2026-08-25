PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:register(input) if type(input.id)~='string' or input.id=='' then return nil,'EQUIPMENT_ID_INVALID' end; input.state=input.state or 'AVAILABLE'; return self.repository:save(input) end
function S:assign(id,employeeId,kind)
    local e=self.repository:get(id); if not e then return nil,'EQUIPMENT_NOT_FOUND' end
    if e.state~='AVAILABLE' or (kind and e.type~=kind) then return nil,'EQUIPMENT_UNAVAILABLE' end
    if self.employeeService and kind and not self.employeeService:eligible(employeeId,kind) then return nil,'EMPLOYEE_NOT_CERTIFIED' end
    local next={}; for k,v in pairs(e) do next[k]=v end; next.operatorId=employeeId; next.state='ASSIGNED'; return self.repository:save(next)
end
function S:fault(id,reason) local e=self.repository:get(id); if not e then return nil,'EQUIPMENT_NOT_FOUND' end;e.state='FAULT';e.faultReason=reason;return self.repository:save(e) end
PortOps.Services.Equipment=S; return S
