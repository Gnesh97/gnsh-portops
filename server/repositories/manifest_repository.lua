PortOps = PortOps or {}; PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Repository = {}; Repository.__index = Repository
local function copy(value) if type(value) ~= 'table' then return value end; local out={}; for key,child in pairs(value) do out[key]=copy(child) end; return out end
local function nowMs() return type(GetGameTimer)=='function' and GetGameTimer() or math.floor(os.time()*1000) end
local function encode(value) if type(json)~='table' or type(json.encode)~='function' then return nil end; local ok,result=pcall(json.encode,value or {}); return ok and type(result)=='string' and result or nil end
local function decode(value) if type(value)=='table' then return value end; if type(value)~='string' or type(json)~='table' or type(json.decode)~='function' then return nil end; local ok,result=pcall(json.decode,value); return ok and type(result)=='table' and result or nil end
local function affectedRows(result) return type(result.data)=='number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows)) end
function Repository.new(options) options=options or {}; return setmetatable({records={},database=options.database,clock=options.clock},Repository) end
function Repository:_memory() return not self.database or self.database.provider=='memory' end
function Repository:_now() return self.clock and self.clock() or nowMs() end
function Repository:_row(row)
    if type(row)~='table' then return nil end
    return { id=row.id, vesselCallId=row.vessel_call_id or row.vesselCallId, direction=row.direction, status=row.status, items=decode(row.items_json or row.items) or {}, version=tonumber(row.version) or 1, createdAt=tonumber(row.created_at or row.createdAt) or self:_now(), updatedAt=tonumber(row.updated_at or row.updatedAt) or self:_now() }
end
function Repository:create(manifest)
    if type(manifest)~='table' or type(manifest.id)~='string' or type(manifest.items)~='table' then return Result.err('MANIFEST_INVALID','manifest is invalid') end
    local candidate=copy(manifest); candidate.direction=candidate.direction or 'IMPORT'; candidate.status=candidate.status or 'RECEIVED'; candidate.version=candidate.version or 1; candidate.createdAt=candidate.createdAt or self:_now(); candidate.updatedAt=candidate.updatedAt or candidate.createdAt
    if self:_memory() then if self.records[candidate.id] then return Result.err('MANIFEST_EXISTS','manifest already exists') end; self.records[candidate.id]=copy(candidate); return Result.ok(copy(candidate)) end
    local items=encode(candidate.items); if not items then return Result.err('MANIFEST_REPOSITORY_FAILED','JSON serializer is unavailable') end
    local result=self.database:insert('INSERT INTO portops_manifests (id,vessel_call_id,direction,status,items_json,version,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',{candidate.id,candidate.vesselCallId,candidate.direction,candidate.status,items,candidate.version,candidate.createdAt,candidate.updatedAt}); if Result.isErr(result) then return Result.err('MANIFEST_REPOSITORY_FAILED','manifest insert failed',result.error) end
    return Result.ok(copy(candidate))
end
function Repository:get(id)
    if type(id)~='string' or id=='' then return Result.err('MANIFEST_NOT_FOUND','manifest was not found') end
    if self:_memory() then local value=self.records[id]; return value and Result.ok(copy(value)) or Result.err('MANIFEST_NOT_FOUND','manifest was not found') end
    local result=self.database:single('SELECT * FROM portops_manifests WHERE id=? LIMIT 1',{id}); if Result.isErr(result) then return Result.err('MANIFEST_REPOSITORY_FAILED','manifest lookup failed',result.error) end
    local value=self:_row(result.data); return value and Result.ok(value) or Result.err('MANIFEST_NOT_FOUND','manifest was not found')
end
function Repository:update(manifest, expectedVersion)
    if type(manifest)~='table' or type(manifest.id)~='string' then return Result.err('MANIFEST_INVALID','manifest is invalid') end
    local current=self:get(manifest.id); if Result.isErr(current) then return current end
    expectedVersion=expectedVersion or current.data.version
    if manifest.version ~= expectedVersion + 1 then return Result.err('MANIFEST_VERSION_INVALID','version must increment by one') end
    local candidate=copy(manifest)
    if self:_memory() then if current.data.version~=expectedVersion then return Result.err('MANIFEST_VERSION_CONFLICT','manifest version conflict') end; self.records[candidate.id]=copy(candidate); return Result.ok(copy(candidate)) end
    local items=encode(candidate.items); if not items then return Result.err('MANIFEST_REPOSITORY_FAILED','JSON serializer is unavailable') end
    local result=self.database:update('UPDATE portops_manifests SET vessel_call_id=?,direction=?,status=?,items_json=?,version=?,updated_at=? WHERE id=? AND version=?',{candidate.vesselCallId,candidate.direction,candidate.status,items,candidate.version,candidate.updatedAt,candidate.id,expectedVersion}); if Result.isErr(result) then return Result.err('MANIFEST_REPOSITORY_FAILED','manifest update failed',result.error) end
    if tonumber(affectedRows(result))==0 then return Result.err('MANIFEST_VERSION_CONFLICT','manifest version conflict') end
    return Result.ok(copy(candidate))
end
function Repository:list(limit)
    local max=math.min(math.max(tonumber(limit) or 100,1),500)
    if self:_memory() then local out={}; for _,value in pairs(self.records) do if #out<max then out[#out+1]=copy(value) end end; return Result.ok(out) end
    local result=self.database:query('SELECT * FROM portops_manifests ORDER BY id LIMIT ?',{max}); if Result.isErr(result) then return Result.err('MANIFEST_REPOSITORY_FAILED','manifest list failed',result.error) end
    local out={}; for _,row in ipairs(result.data and (result.data.rows or result.data) or {}) do local value=self:_row(row); if value then out[#out+1]=value end end; return Result.ok(out)
end
PortOps.Repositories.Manifest=Repository; return Repository
