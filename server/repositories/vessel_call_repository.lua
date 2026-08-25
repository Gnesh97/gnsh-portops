PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Repository = {}; Repository.__index = Repository

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
local function nowMs() return type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.time() * 1000) end
local function encode(value)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then return nil end
    local ok, result = pcall(json.encode, value or {}); return ok and type(result) == 'string' and result or nil
end
local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or type(json) ~= 'table' or type(json.decode) ~= 'function' then return nil end
    local ok, result = pcall(json.decode, value); return ok and type(result) == 'table' and result or nil
end
local function affectedRows(result) return type(result.data) == 'number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows)) end

function Repository.new(options) options = options or {}; return setmetatable({ records = {}, database = options.database, clock = options.clock }, Repository) end
function Repository:_memory() return not self.database or self.database.provider == 'memory' end
function Repository:_now() return self.clock and self.clock() or nowMs() end
function Repository:_row(row)
    if type(row) ~= 'table' then return nil end
    return {
        id = row.id, vesselId = row.vessel_id or row.vesselId, voyage = row.voyage,
        status = row.status or 'PLANNED', berthId = row.berth_id or row.berthId,
        eta = tonumber(row.eta), etd = tonumber(row.etd), version = tonumber(row.version) or 1,
        metadata = decode(row.metadata_json or row.metadata) or {},
        createdAt = tonumber(row.created_at or row.createdAt) or self:_now(),
        updatedAt = tonumber(row.updated_at or row.updatedAt) or self:_now()
    }
end
function Repository:create(value)
    if type(value) ~= 'table' or type(value.id) ~= 'string' then return Result.err('VESSEL_CALL_INVALID', 'call id is required') end
    local candidate = copy(value); candidate.status = candidate.status or 'PLANNED'; candidate.version = candidate.version or 1
    candidate.createdAt = candidate.createdAt or self:_now(); candidate.updatedAt = candidate.updatedAt or candidate.createdAt
    if self:_memory() then
        if self.records[candidate.id] then return Result.err('VESSEL_CALL_EXISTS', 'call already exists') end
        self.records[candidate.id] = copy(candidate); return Result.ok(copy(candidate))
    end
    local metadata = encode(candidate.metadata)
    if not metadata then return Result.err('VESSEL_CALL_REPOSITORY_FAILED', 'JSON serializer is unavailable') end
    local result = self.database:insert([[
        INSERT INTO portops_vessel_calls (id, vessel_id, voyage, status, berth_id, eta, etd, version, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { candidate.id, candidate.vesselId, candidate.voyage, candidate.status, candidate.berthId, candidate.eta, candidate.etd, candidate.version, metadata })
    if Result.isErr(result) then return Result.err('VESSEL_CALL_REPOSITORY_FAILED', 'call insert failed', result.error) end
    return Result.ok(copy(candidate))
end
function Repository:get(id)
    if type(id) ~= 'string' or id == '' then return Result.err('VESSEL_CALL_NOT_FOUND', 'call not found') end
    if self:_memory() then local value=self.records[id]; return value and Result.ok(copy(value)) or Result.err('VESSEL_CALL_NOT_FOUND','call not found') end
    local result=self.database:single('SELECT * FROM portops_vessel_calls WHERE id = ? LIMIT 1',{id}); if Result.isErr(result) then return Result.err('VESSEL_CALL_REPOSITORY_FAILED','call lookup failed',result.error) end
    local value=self:_row(result.data); return value and Result.ok(value) or Result.err('VESSEL_CALL_NOT_FOUND','call not found')
end
function Repository:update(value, expectedVersion)
    if type(value) ~= 'table' or type(value.id) ~= 'string' then return Result.err('VESSEL_CALL_INVALID','call id is required') end
    if type(expectedVersion) ~= 'number' then return Result.err('VESSEL_CALL_VERSION_INVALID','expected version is required') end
    local candidate=copy(value); if candidate.version ~= expectedVersion + 1 then return Result.err('VESSEL_CALL_VERSION_INVALID','version must increment by one') end
    if self:_memory() then local old=self.records[candidate.id]; if not old then return Result.err('VESSEL_CALL_NOT_FOUND','call not found') end; if old.version~=expectedVersion then return Result.err('VESSEL_CALL_VERSION_CONFLICT','call version conflict') end; self.records[candidate.id]=copy(candidate); return Result.ok(copy(candidate)) end
    local metadata=encode(candidate.metadata); if not metadata then return Result.err('VESSEL_CALL_REPOSITORY_FAILED','JSON serializer is unavailable') end
    local result=self.database:update('UPDATE portops_vessel_calls SET status=?,berth_id=?,eta=?,etd=?,version=?,metadata_json=? WHERE id=? AND version=?',{candidate.status,candidate.berthId,candidate.eta,candidate.etd,candidate.version,metadata,candidate.id,expectedVersion}); if Result.isErr(result) then return Result.err('VESSEL_CALL_REPOSITORY_FAILED','call update failed',result.error) end
    if tonumber(affectedRows(result))==0 then return Result.err('VESSEL_CALL_VERSION_CONFLICT','call version conflict') end
    return Result.ok(copy(candidate))
end
function Repository:list(limit)
    local max=math.min(math.max(tonumber(limit) or 100,1),500)
    if self:_memory() then local out={}; for _,value in pairs(self.records) do if #out<max then out[#out+1]=copy(value) end end; return Result.ok(out) end
    local result=self.database:query('SELECT * FROM portops_vessel_calls ORDER BY id LIMIT ?',{max}); if Result.isErr(result) then return Result.err('VESSEL_CALL_REPOSITORY_FAILED','call list failed',result.error) end
    local out={}; for _,row in ipairs(result.data and (result.data.rows or result.data) or {}) do local value=self:_row(row); if value then out[#out+1]=value end end; return Result.ok(out)
end
PortOps.Repositories.VesselCall=Repository; return Repository
