PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:record(actorId,action,entityId,details) if type(actorId)~='string' or type(action)~='string' then return nil,'AUDIT_INPUT_INVALID' end; return self.repository:append({actorId=actorId,action=action,entityId=entityId,details=details or {},at=os.time()*1000}) end
function S:list(filter) return self.repository:list(filter) end
PortOps.Services.Audit=S; return S
