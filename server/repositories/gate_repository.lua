PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Appointment = PortOps.Domain.GateAppointment
local Repository = {}; Repository.__index = Repository
local function copy(value) if type(value)~='table' then return value end; local out={}; for key,child in pairs(value) do out[key]=copy(child) end; return out end
local function nowMs() return type(GetGameTimer)=='function' and GetGameTimer() or math.floor(os.time()*1000) end
local function affectedRows(result) return type(result.data)=='number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows)) end
function Repository.new(options) options=options or {}; return setmetatable({records={},database=options.database,clock=options.clock},Repository) end
function Repository:_memory() return not self.database or self.database.provider=='memory' end
function Repository:_now() return self.clock and self.clock() or nowMs() end
function Repository:_row(row)
    if type(row)~='table' then return nil end
    local value={id=row.id,containerId=row.container_id or row.containerId,bookingRef=row.booking_ref or row.bookingRef,company=row.company,driverId=row.driver_id or row.driverId,windowStart=tonumber(row.window_start or row.windowStart),windowEnd=tonumber(row.window_end or row.windowEnd),status=row.status,version=tonumber(row.version) or 1,createdAt=tonumber(row.created_at or row.createdAt) or self:_now(),updatedAt=tonumber(row.updated_at or row.updatedAt) or self:_now()}
    local checked=Appointment.validate(value); return Result.isOk(checked) and checked.data or nil
end
function Repository:create(value)
    local checked=Appointment.validate(value); if Result.isErr(checked) then return checked end
    local candidate=copy(checked.data); candidate.createdAt=candidate.createdAt or self:_now(); candidate.updatedAt=candidate.updatedAt or candidate.createdAt
    if self:_memory() then if self.records[candidate.id] then return Result.err('APPOINTMENT_EXISTS','appointment already exists') end; self.records[candidate.id]=copy(candidate); return Result.ok(copy(candidate)) end
    local result=self.database:insert('INSERT INTO portops_gate_appointments (id,container_id,booking_ref,company,driver_id,window_start,window_end,status,version,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',{candidate.id,candidate.containerId,candidate.bookingRef,candidate.company,candidate.driverId,candidate.windowStart,candidate.windowEnd,candidate.status,candidate.version,candidate.createdAt,candidate.updatedAt}); if Result.isErr(result) then return Result.err('APPOINTMENT_REPOSITORY_FAILED','appointment insert failed',result.error) end
    return Result.ok(copy(candidate))
end
function Repository:get(id)
    if type(id)~='string' or id=='' then return Result.err('APPOINTMENT_NOT_FOUND','appointment was not found') end
    if self:_memory() then local value=self.records[id]; return value and Result.ok(copy(value)) or Result.err('APPOINTMENT_NOT_FOUND','appointment was not found') end
    local result=self.database:single('SELECT * FROM portops_gate_appointments WHERE id=? LIMIT 1',{id}); if Result.isErr(result) then return Result.err('APPOINTMENT_REPOSITORY_FAILED','appointment lookup failed',result.error) end
    local value=self:_row(result.data); return value and Result.ok(value) or Result.err('APPOINTMENT_NOT_FOUND','appointment was not found')
end
function Repository:update(value, expectedVersion)
    local checked=Appointment.validate(value); if Result.isErr(checked) then return checked end
    if type(expectedVersion)~='number' then return Result.err('APPOINTMENT_VERSION_INVALID','expected version is required') end
    local candidate=copy(checked.data); candidate.version=candidate.version or expectedVersion+1; candidate.updatedAt=candidate.updatedAt or self:_now()
    if candidate.version~=expectedVersion+1 then return Result.err('APPOINTMENT_VERSION_INVALID','version must increment by one') end
    if self:_memory() then local current=self.records[candidate.id]; if not current then return Result.err('APPOINTMENT_NOT_FOUND','appointment was not found') end; if current.version~=expectedVersion then return Result.err('APPOINTMENT_VERSION_CONFLICT','appointment version conflict') end; self.records[candidate.id]=copy(candidate); return Result.ok(copy(candidate)) end
    local result=self.database:update('UPDATE portops_gate_appointments SET container_id=?,booking_ref=?,company=?,driver_id=?,window_start=?,window_end=?,status=?,version=?,updated_at=? WHERE id=? AND version=?',{candidate.containerId,candidate.bookingRef,candidate.company,candidate.driverId,candidate.windowStart,candidate.windowEnd,candidate.status,candidate.version,candidate.updatedAt,candidate.id,expectedVersion}); if Result.isErr(result) then return Result.err('APPOINTMENT_REPOSITORY_FAILED','appointment update failed',result.error) end
    if tonumber(affectedRows(result))==0 then return Result.err('APPOINTMENT_VERSION_CONFLICT','appointment version conflict') end
    return Result.ok(copy(candidate))
end
function Repository:list(limit)
    local max=math.min(math.max(tonumber(limit) or 100,1),500)
    if self:_memory() then local out={}; for _,value in pairs(self.records) do if #out<max then out[#out+1]=copy(value) end end; return Result.ok(out) end
    local result=self.database:query('SELECT * FROM portops_gate_appointments ORDER BY window_start LIMIT ?',{max}); if Result.isErr(result) then return Result.err('APPOINTMENT_REPOSITORY_FAILED','appointment list failed',result.error) end
    local out={}; for _,row in ipairs(result.data and (result.data.rows or result.data) or {}) do local value=self:_row(row); if value then out[#out+1]=value end end; return Result.ok(out)
end
PortOps.Repositories.Gate=Repository; return Repository
