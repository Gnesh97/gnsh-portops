-- Move workflow service. All lifecycle writes pass through state machines and
-- optimistic repository updates; clients never choose a resulting status.
PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}
local Result=PortOps.Core.Result; local Move=PortOps.Domain.Move
local Service={}; Service.__index=Service
function Service.new(options) options=options or {}; return setmetatable({repository=options.repository,stateMachine=options.stateMachine,stepStateMachine=options.stepStateMachine,containerService=options.containerService,yardService=options.yardService,assignmentService=options.assignmentService,events=options.events,logger=options.logger,clock=options.clock},Service) end
local function fail(code,msg,d) return Result.err(code,msg,d) end
function Service:_emit(name,payload)
    if not self.events then return end
    if self.events.emit then self.events:emit(name,payload) elseif self.events.publish then self.events:publish(name,payload) end
end
function Service:_find(ref) if type(ref)=='string' then local r=self.repository:getById(ref); if Result.isOk(r) then return r end; return self.repository:getByNumber(ref) end; return fail('MOVE_NOT_FOUND','move reference is invalid') end
function Service:create(input)
    local checked=Move.new(input); if Result.isErr(checked) then return checked end
    local result=self.repository:create(checked.data); if Result.isErr(result) then return result end
    self:_emit('portops:moveCreated',Move.toDTO(result.data))
    return Result.ok(Move.toDTO(result.data))
end
function Service:get(ref) local r=self:_find(ref); return Result.isOk(r) and Result.ok(Move.toDTO(r.data)) or r end
function Service:list(filters,options) local r=self.repository:list(filters,options); if Result.isErr(r) then return r end; local out={}; for _,m in ipairs(r.data) do out[#out+1]=Move.toDTO(m) end; return Result.ok(out) end
function Service:_save(next,current,expected) local r=self.repository:update(next,expected); if Result.isErr(r) then return r end; self:_emit('portops:moveTransitioned',{id=next.id,from=current.status,to=next.status,version=next.version}); return Result.ok(Move.toDTO(r.data)) end
function Service:transition(ref,target,expectedVersion,context,guard)
    if type(expectedVersion)~='number' then return fail('MOVE_VERSION_INVALID','expected version is required') end
    local current=self:_find(ref); if Result.isErr(current) then return current end
    if current.data.version~=expectedVersion then return fail('MOVE_VERSION_CONFLICT','move version conflict') end
    local next=self.stateMachine:transition(current.data,target,context,guard); if Result.isErr(next) then return next end
    return self:_save(next.data,current.data,expectedVersion)
end
function Service:reserve(ref,expected,ctx)
    local context=Move.copy(ctx or {}); local reservation
    if self.yardService and context.slotId and context.ownerId and context.container then
        reservation=self.yardService:reserve(context.container,context.slotId,context.ownerId,context.ttlMs)
        if Result.isErr(reservation) then return reservation end
        context.reservation=reservation.data
    end
    local transitioned=self:transition(ref,'RESERVED',expected,context)
    if Result.isErr(transitioned) and reservation then self.yardService:release(context.slotId,context.ownerId) end
    return transitioned
end
function Service:ready(ref,expected,ctx) return self:transition(ref,'READY',expected,ctx) end
function Service:claim(ref,expected,actor,ctx) local context=Move.copy(ctx or {}); context.actor=Move.copy(actor); return self:transition(ref,'CLAIMED',expected,context) end
function Service:start(ref,expected,ctx) return self:transition(ref,'IN_PROGRESS',expected,ctx) end
function Service:block(ref,expected,reason) return self:transition(ref,'BLOCKED',expected,{blockedReason=reason}) end
function Service:recover(ref,expected) return self:transition(ref,'RECOVERY_REQUIRED',expected) end
function Service:complete(ref,expected)
    local current=self:_find(ref); if Result.isErr(current) then return current end
    if current.data.status=='COMPLETED' then return Result.ok(Move.toDTO(current.data),{idempotent=true}) end
    return self:transition(ref,'COMPLETED',expected)
end
function Service:completeStep(ref,stepId,expectedVersion,context)
    local current=self:_find(ref); if Result.isErr(current) then return current end; if current.data.version~=expectedVersion then return fail('MOVE_VERSION_CONFLICT','move version conflict') end
    local steps=Move.copy(current.data.steps); local index
    for i,s in ipairs(steps) do if s.id==stepId then index=i; break end end
    if not index then return fail('MOVE_STEP_NOT_FOUND','move step was not found') end
    if steps[index].status=='COMPLETED' then return Result.ok(Move.toDTO(current.data),{idempotent=true}) end
    for i=1,index-1 do if steps[i].status~='COMPLETED' then return fail('MOVE_PREREQUISITE_REQUIRED','previous move step is not complete',{step=steps[i].id}) end end
    local timestamp=(context and context.timestamp) or (self.clock and self.clock()) or math.floor(os.time()*1000)
    local step=steps[index]
    if self.stepStateMachine then
        local statusPath={}
        if step.status=='PENDING' then return fail('MOVE_PREREQUISITE_REQUIRED','step is not ready',{step=step.id}) end
        if step.status=='READY' then statusPath[#statusPath+1]='CLAIMED' end
        if step.status=='READY' or step.status=='CLAIMED' then statusPath[#statusPath+1]='IN_PROGRESS' end
        if step.status=='IN_PROGRESS' or step.status=='CLAIMED' or step.status=='READY' then statusPath[#statusPath+1]='COMPLETED' end
        for _,target in ipairs(statusPath) do
            local advanced=self.stepStateMachine:transition(step,target,{timestamp=timestamp})
            if Result.isErr(advanced) then return advanced end
            step=advanced.data
        end
        steps[index]=step
    else
        step.status='COMPLETED'; step.version=(step.version or 1)+1
        steps[index]=step
    end
    steps[index].completedAt=timestamp
    local next=Move.copy(current.data); next.steps=steps; next.version=next.version+1; next.updatedAt=steps[index].completedAt
    local all=true; for _,s in ipairs(steps) do if s.status~='COMPLETED' then all=false end end
    if all then next.status='COMPLETED' elseif next.status=='PLANNED' then next.status='IN_PROGRESS' end
    if context and context.containerStatus and self.containerService then
        local containerResult=self.containerService:transition(current.data.containerId,context.containerStatus,context.containerVersion,context.containerContext or {})
        if Result.isErr(containerResult) then return fail('MOVE_CONTAINER_SYNC_FAILED','container transition failed',containerResult.error) end
    end
    return self:_save(next,current.data,expectedVersion)
end
function Service:reassign(ref,expectedVersion,actor,role,reason)
    if not self.assignmentService then return fail('ASSIGNMENT_UNAVAILABLE','assignment service is unavailable') end
    return self.assignmentService:reassign(ref,expectedVersion,actor,role,reason)
end
PortOps.Services.Move=Service; return Service
