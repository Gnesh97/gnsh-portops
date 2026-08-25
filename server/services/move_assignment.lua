-- Assignment policy is deliberately framework-neutral. The caller supplies a
-- normalized employee/actor object; framework adapters remain outside domain.
PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}
local Result=PortOps.Core.Result; local Move=PortOps.Domain.Move
local Assignment={}; Assignment.__index=Assignment
function Assignment.new(options) options=options or {}; return setmetatable({repository=options.repository,moveService=options.moveService,stateMachine=options.stateMachine,framework=options.framework,authorizer=options.authorizer,clock=options.clock},Assignment) end
local function fail(c,m,d) return Result.err(c,m,d) end
function Assignment:_allowed(actor,role)
    if type(self.authorizer)=='function' then local ok,allow,reason=pcall(self.authorizer,actor,role); if not ok or allow~=true then return false,reason or 'assignment not authorized' end end
    if type(actor)~='table' or actor.id==nil then return false,'actor is required' end
    if actor.available==false or actor.onDuty==false then return false,'actor is unavailable' end
    if role and actor.role and actor.role~=role then return false,'actor role is incompatible' end
    return true
end
function Assignment:assign(ref,expectedVersion,actor,role,reason)
    local allowed,reason=self:_allowed(actor,role); if not allowed then return fail('ASSIGNMENT_NOT_AUTHORIZED',reason) end
    local current=self.repository:getById(ref); if Result.isErr(current) then current=self.repository:getByNumber(ref) end; if Result.isErr(current) then return current end
    if current.data.version~=expectedVersion then return fail('MOVE_VERSION_CONFLICT','move version conflict') end
    local next=Move.copy(current.data); next.assignments=Move.copy(next.assignments or {}); next.assignments[role or 'primary']={id=tostring(actor.id),role=role,assignedAt=(self.clock and self.clock()) or math.floor(os.time()*1000),reason=reason}
    if next.status=='READY' and self.stateMachine then
        local transitioned=self.stateMachine:transition(next,'CLAIMED',{timestamp=next.assignments[role or 'primary'].assignedAt})
        if Result.isErr(transitioned) then return transitioned end
        next=transitioned.data; next.assignments=Move.copy(current.data.assignments or {}); next.assignments[role or 'primary']={id=tostring(actor.id),role=role,assignedAt=next.updatedAt}
    else
        next.version=next.version+1; next.updatedAt=next.assignments[role or 'primary'].assignedAt
        if next.status=='READY' then next.status='CLAIMED' end
    end
    local saved=self.repository:update(next,expectedVersion); if Result.isErr(saved) then return saved end
    return Result.ok(Move.toDTO(saved.data))
end
function Assignment:claim(ref,expectedVersion,actor,role) return self:assign(ref,expectedVersion,actor,role) end
function Assignment:reassign(ref,expectedVersion,actor,role,reason)
    if type(reason)~='string' or reason=='' then return fail('ASSIGNMENT_REASON_REQUIRED','reassign reason is required') end
    return self:assign(ref,expectedVersion,actor,role,reason)
end
PortOps.Services.MoveAssignment=Assignment; return Assignment
