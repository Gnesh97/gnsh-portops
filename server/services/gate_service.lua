PortOps = PortOps or {}; PortOps.Services=PortOps.Services or {}; local Result=PortOps.Core.Result; local S={}; S.__index=S
function S.new(o) o=o or {}; return setmetatable({appointments=o.appointments or {},repository=o.repository,clock=o.clock or function() return math.floor(os.time()*1000) end,containerService=o.containerService,customsService=o.customsService},S) end
function S:_get(id) if self.repository then return self.repository:get(id) end; local value=self.appointments[id]; return value and Result.ok(value) or Result.err('APPOINTMENT_NOT_FOUND','appointment not found') end
function S:book(a) local r=PortOps.Domain.GateAppointment.validate(a); if Result.isErr(r) then return r end; local current=self:_get(a.id); if Result.isOk(current) then return Result.ok(current.data,{idempotent=true}) end; local saved=self.repository and self.repository:create(r.data) or Result.ok(r.data); if Result.isOk(saved) then self.appointments[a.id]=saved.data end; return saved end
function S:transition(id,target)
    local current=self:_get(id); if Result.isErr(current) then return current end; local a={}; for k,v in pairs(current.data) do a[k]=v end
    local allowed={BOOKED={ARRIVED=true,CANCELLED=true,EXPIRED=true},ARRIVED={PICKUP_CLAIMED=true,CANCELLED=true},PICKUP_CLAIMED={GATE_IN=true},GATE_IN={SERVICED=true},SERVICED={GATE_OUT=true},GATE_OUT={},CANCELLED={},EXPIRED={}}
    if not allowed[a.status] or not allowed[a.status][target] then return Result.err('APPOINTMENT_TRANSITION_INVALID','transition is not allowed') end
    a.status=target; a.version=(a.version or 1)+1; a.updatedAt=self.clock(); local saved=self.repository and self.repository:update(a,current.data.version) or Result.ok(a); if Result.isOk(saved) then self.appointments[id]=saved.data end; return saved
end
function S:gateOut(id,container)
    local current=self:_get(id); if Result.isErr(current) then return current end
    if current.data.status=='GATE_OUT' then return Result.ok(current.data,{idempotent=true}) end
    if self.customsService and container and not self.customsService:canGateOut(container) then return Result.err('CUSTOMS_HOLD','container is not cleared') end
    if container and container.status and container.status~='READY_FOR_PICKUP' and container.status~='PICKUP_IN_PROGRESS' then return Result.err('CONTAINER_NOT_READY','container is not ready for gate-out') end
    local result=self:transition(id,'GATE_OUT'); if Result.isErr(result) then return result end; return result
end
PortOps.Services.Gate=S; return S
