PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(o) return setmetatable(o or {},S) end
function S:record(event,entityId,payload) return self.repository:append({event=event,entityId=entityId,payload=payload or {},at=os.time()*1000}) end
function S:timeline(entityId) return self.repository:list({entityId=entityId}) end
PortOps.Services.Activity=S; return S
