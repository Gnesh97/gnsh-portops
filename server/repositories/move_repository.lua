-- Move persistence boundary. Memory mode is deterministic for tests; SQL mode
-- remains parameterized and uses version predicates for optimistic concurrency.
PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result=PortOps.Core.Result; local Move=PortOps.Domain.Move
local Repository={}; Repository.__index=Repository
local function copy(v) return Move.copy(v) end
local function encode(v) if type(json)=='table' and type(json.encode)=='function' then local ok,r=pcall(json.encode,v or {}); if ok then return r end end end
local function decode(v) if type(v)=='table' then return v end; if type(v)=='string' and type(json)=='table' and type(json.decode)=='function' then local ok,r=pcall(json.decode,v); if ok then return r end end end
local function err(code,msg,details) return Result.err(code,msg,details) end
function Repository.new(options) options=options or {}; return setmetatable({database=options.database,records={},numberIndex={},keyIndex={},sequence=0,clock=options.clock,idGenerator=options.idGenerator},Repository) end
function Repository:_memory() return self.database and self.database.provider=='memory' end
function Repository:_now() return self.clock and self.clock() or math.floor(os.time()*1000) end
function Repository:_id() self.sequence=self.sequence+1; return self.idGenerator and self.idGenerator() or ('move-'..self:_now()..'-'..self.sequence) end
local function normalize(v,requireId) return Move.validate(v,{requireId=requireId}) end
function Repository:create(move)
    local candidate=copy(move or {}); candidate.id=candidate.id or self:_id(); local checked=normalize(candidate,true); if Result.isErr(checked) then return checked end; candidate=checked.data
    if not self:_memory() then return self:createWithSteps(candidate) end
    if candidate.idempotencyKey and self.keyIndex[candidate.idempotencyKey] then return Result.ok(copy(self.records[self.keyIndex[candidate.idempotencyKey]]),{idempotent=true}) end
    if self.records[candidate.id] then return err('MOVE_ID_EXISTS','move id already exists') end
    if candidate.moveNumber and self.numberIndex[candidate.moveNumber] then return err('MOVE_NUMBER_EXISTS','move number already exists') end
    self.records[candidate.id]=copy(candidate); if candidate.moveNumber then self.numberIndex[candidate.moveNumber]=candidate.id end; if candidate.idempotencyKey then self.keyIndex[candidate.idempotencyKey]=candidate.id end
    return Result.ok(copy(candidate))
end
function Repository:createWithSteps(move)
    local candidate=copy(move or {}); candidate.id=candidate.id or self:_id(); local checked=normalize(candidate,true); if Result.isErr(checked) then return checked end; candidate=checked.data
    if self:_memory() then return self:create(candidate) end
    local steps=encode(candidate.steps); local assignments=encode(candidate.assignments); local reservations=encode(candidate.reservations)
    if not steps or not assignments or not reservations then return err('MOVE_REPOSITORY_FAILED','JSON serializer unavailable') end
    local statements={{query=[[INSERT INTO portops_moves (id,move_number,idempotency_key,container_id,from_location_json,to_location_json,status,steps_json,assignments_json,reservations_json,version,created_at,updated_at,blocked_reason) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],parameters={candidate.id,candidate.moveNumber,candidate.idempotencyKey,candidate.containerId,encode(candidate.fromLocation),encode(candidate.toLocation),candidate.status,steps,assignments,reservations,candidate.version,candidate.createdAt,candidate.updatedAt,candidate.blockedReason}}}
    for ordinal, step in ipairs(candidate.steps) do
        local stepAssignments = encode(step.assignee or {})
        local stepReservation = encode(step.reservation or {})
        local stepMetadata = encode(step.metadata or {})
        if not stepAssignments or not stepReservation or not stepMetadata then return err('MOVE_REPOSITORY_FAILED','JSON serializer unavailable') end
        statements[#statements + 1] = {
            query = 'INSERT INTO portops_move_steps (id,move_id,ordinal,kind,status,assignee_json,reservation_json,version,metadata_json) VALUES (?,?,?,?,?,?,?,?,?)',
            parameters = { step.id, candidate.id, ordinal, step.kind, step.status, stepAssignments, stepReservation, step.version or 1, stepMetadata }
        }
    end
    local tx=self.database:transaction(statements); if Result.isErr(tx) then return err('MOVE_REPOSITORY_FAILED','move transaction failed',tx.error) end
    return Result.ok(copy(candidate))
end
function Repository:_createSql(c)
    local steps=encode(c.steps); local assignments=encode(c.assignments); local reservations=encode(c.reservations); if not steps or not assignments or not reservations then return err('MOVE_REPOSITORY_FAILED','JSON serializer unavailable') end
    local q=[[INSERT INTO portops_moves (id,move_number,idempotency_key,container_id,from_location_json,to_location_json,status,steps_json,assignments_json,reservations_json,version,created_at,updated_at,blocked_reason) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)]]
    local r=self.database:insert(q,{c.id,c.moveNumber,c.idempotencyKey,c.containerId,encode(c.fromLocation),encode(c.toLocation),c.status,steps,assignments,reservations,c.version,c.createdAt,c.updatedAt,c.blockedReason}); if Result.isErr(r) then return err('MOVE_REPOSITORY_FAILED','move insert failed',r.error) end
    return Result.ok(copy(c))
end
function Repository:_row(row)
    if type(row)~='table' then return nil end
    local steps=decode(row.steps_json or row.steps) or {}; local normalized=normalize({id=row.id,moveNumber=row.move_number or row.moveNumber,idempotencyKey=row.idempotency_key or row.idempotencyKey,containerId=row.container_id or row.containerId,fromLocation=decode(row.from_location_json or row.fromLocation),toLocation=decode(row.to_location_json or row.toLocation),status=row.status,steps=steps,assignments=decode(row.assignments_json or row.assignments) or {},reservations=decode(row.reservations_json or row.reservations) or {},version=tonumber(row.version),createdAt=tonumber(row.created_at or row.createdAt),updatedAt=tonumber(row.updated_at or row.updatedAt),blockedReason=row.blocked_reason or row.blockedReason},{requireId=true})
    return Result.isOk(normalized) and normalized.data or nil
end
function Repository:getById(id)
    if type(id)~='string' or id=='' then return err('MOVE_NOT_FOUND','move was not found') end
    if self:_memory() then return self.records[id] and Result.ok(copy(self.records[id])) or err('MOVE_NOT_FOUND','move was not found') end
    local r=self.database:single('SELECT * FROM portops_moves WHERE id = ? LIMIT 1',{id}); if Result.isErr(r) then return err('MOVE_REPOSITORY_FAILED','move lookup failed',r.error) end; local row=self:_row(r.data); return row and Result.ok(row) or err('MOVE_NOT_FOUND','move was not found')
end
function Repository:getByNumber(number) if type(number)~='string' then return err('MOVE_NOT_FOUND','move was not found') end; if self:_memory() then local id=self.numberIndex[number]; return id and self:getById(id) or err('MOVE_NOT_FOUND','move was not found') end; local r=self.database:single('SELECT * FROM portops_moves WHERE move_number = ? LIMIT 1',{number}); if Result.isErr(r) then return err('MOVE_REPOSITORY_FAILED','move lookup failed',r.error) end; local row=self:_row(r.data); return row and Result.ok(row) or err('MOVE_NOT_FOUND','move was not found') end
function Repository:list(filters,options)
    filters=filters or {}; options=options or {}; local limit=math.min(math.max(tonumber(options.limit) or 100,1),500); local offset=math.max(tonumber(options.offset) or 0,0)
    if self:_memory() then local a={}; for _,m in pairs(self.records) do if (not filters.status or m.status==filters.status) and (not filters.containerId or m.containerId==filters.containerId) then a[#a+1]=copy(m) end end; table.sort(a,function(x,y)return x.createdAt<y.createdAt end); local out={}; for i=offset+1,math.min(#a,offset+limit) do out[#out+1]=a[i] end; return Result.ok(out) end
    local r=self.database:query('SELECT * FROM portops_moves ORDER BY created_at LIMIT ? OFFSET ?',{limit,offset}); if Result.isErr(r) then return err('MOVE_REPOSITORY_FAILED','move list failed',r.error) end; local out={}; for _,row in ipairs(r.data and (r.data.rows or r.data) or {}) do local m=self:_row(row); if m then out[#out+1]=m end end; return Result.ok(out)
end
function Repository:update(move,expectedVersion)
    if type(expectedVersion)~='number' or expectedVersion<1 or expectedVersion%1~=0 then return err('MOVE_VERSION_INVALID','expected version is required') end
    local checked=normalize(move,true); if Result.isErr(checked) then return checked end; local c=checked.data; if c.version~=expectedVersion+1 then return err('MOVE_VERSION_INVALID','record version must increment by one') end
    if self:_memory() then local old=self.records[c.id]; if not old then return err('MOVE_NOT_FOUND','move was not found') end; if old.version~=expectedVersion then return err('MOVE_VERSION_CONFLICT','move version conflict') end; self.records[c.id]=copy(c); return Result.ok(copy(c)) end
    local r=self.database:update('UPDATE portops_moves SET status=?,steps_json=?,assignments_json=?,reservations_json=?,version=?,updated_at=?,blocked_reason=? WHERE id=? AND version=?',{c.status,encode(c.steps),encode(c.assignments),encode(c.reservations),c.version,c.updatedAt,c.blockedReason,c.id,expectedVersion}); if Result.isErr(r) then return err('MOVE_REPOSITORY_FAILED','move update failed',r.error) end; local n=type(r.data)=='number' and r.data or (r.data and (r.data.affectedRows or r.data.affected_rows)); if tonumber(n)==0 then return err('MOVE_VERSION_CONFLICT','move version conflict') end; return Result.ok(copy(c))
end
return (function() PortOps.Repositories.Move=Repository; return Repository end)()
