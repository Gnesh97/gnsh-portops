PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:upsert(id,identity) if type(id)~='string' or id=='' then return nil,'EMPLOYEE_ID_INVALID' end; local e=self.repository:get(id) or {id=id,certifications={}}; for k,v in pairs(identity or {}) do e[k]=v end; e.available=e.available~=false; return self.repository:save(e) end
function S:certify(id,kind,expiresAt) local e=self.repository:get(id); if not e then return nil,'EMPLOYEE_NOT_FOUND' end; e.certifications[kind]={expiresAt=expiresAt}; return self.repository:save(e) end
function S:eligible(id,kind,now) local e=self.repository:get(id); local c=e and e.certifications[kind]; return e and e.available and c and (not c.expiresAt or c.expiresAt>(now or os.time()*1000)) or false end
PortOps.Services.Employee=S; return S
