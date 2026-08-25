PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}
local Result = PortOps.Core.Result
local Vessel = PortOps.Domain.Vessel
local Repository = {}
Repository.__index = Repository

local function copy(value)
    return Vessel.copy(value)
end

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function encode(value)
    if type(json) ~= 'table' or type(json.encode) ~= 'function' then return nil end
    local ok, result = pcall(json.encode, value or {})
    return ok and type(result) == 'string' and result or nil
end

local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or type(json) ~= 'table' or type(json.decode) ~= 'function' then return nil end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or nil
end

local function affectedRows(result)
    return type(result.data) == 'number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows))
end

function Repository.new(options)
    options = options or {}
    return setmetatable({ records = {}, database = options.database, clock = options.clock }, Repository)
end

function Repository:_memory()
    return not self.database or self.database.provider == 'memory'
end

function Repository:_now()
    return self.clock and self.clock() or nowMs()
end

function Repository:_row(row)
    if type(row) ~= 'table' then return nil end
    local value = {
        id = row.id,
        name = row.name,
        imo = row.imo,
        vesselType = row.vessel_type or row.vesselType,
        metadata = decode(row.metadata_json or row.metadata) or {},
        version = tonumber(row.version) or 1,
        createdAt = tonumber(row.created_at or row.createdAt) or self:_now(),
        updatedAt = tonumber(row.updated_at or row.updatedAt) or self:_now()
    }
    local checked = Vessel.new(value)
    return Result.isOk(checked) and checked.data or nil
end

function Repository:create(value)
    local candidate = copy(value)
    if type(candidate) ~= 'table' then return Result.err('VESSEL_INVALID', 'vessel is invalid') end
    candidate.version = candidate.version or 1
    candidate.createdAt = candidate.createdAt or self:_now()
    candidate.updatedAt = candidate.updatedAt or candidate.createdAt
    local checked = Vessel.new(candidate)
    if Result.isErr(checked) then return checked end
    candidate = checked.data
    if self:_memory() then
        if self.records[candidate.id] then return Result.err('VESSEL_EXISTS', 'vessel already exists') end
        self.records[candidate.id] = copy(candidate)
        return Result.ok(copy(candidate))
    end
    local metadata = encode(candidate.metadata)
    if not metadata then return Result.err('VESSEL_REPOSITORY_FAILED', 'JSON serializer is unavailable') end
    local result = self.database:insert([[
        INSERT INTO portops_vessels (id, name, imo, vessel_type, metadata_json, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { candidate.id, candidate.name, candidate.imo, candidate.vesselType, metadata, candidate.version, candidate.createdAt, candidate.updatedAt })
    if Result.isErr(result) then return Result.err('VESSEL_REPOSITORY_FAILED', 'vessel insert failed', result.error) end
    return Result.ok(copy(candidate))
end

function Repository:get(id)
    if type(id) ~= 'string' or id == '' then return Result.err('VESSEL_NOT_FOUND', 'vessel was not found') end
    if self:_memory() then
        local value = self.records[id]
        return value and Result.ok(copy(value)) or Result.err('VESSEL_NOT_FOUND', 'vessel was not found')
    end
    local result = self.database:single('SELECT * FROM portops_vessels WHERE id = ? LIMIT 1', { id })
    if Result.isErr(result) then return Result.err('VESSEL_REPOSITORY_FAILED', 'vessel lookup failed', result.error) end
    local value = self:_row(result.data)
    return value and Result.ok(value) or Result.err('VESSEL_NOT_FOUND', 'vessel was not found')
end

function Repository:update(value, expectedVersion)
    if type(value) ~= 'table' or type(value.id) ~= 'string' then return Result.err('VESSEL_INVALID', 'vessel identity is required') end
    if type(expectedVersion) ~= 'number' then return Result.err('VESSEL_VERSION_INVALID', 'expected version is required') end
    local checked = Vessel.new(value)
    if Result.isErr(checked) then return checked end
    local candidate = checked.data
    if candidate.version ~= expectedVersion + 1 then return Result.err('VESSEL_VERSION_INVALID', 'version must increment by one') end
    if self:_memory() then
        local current = self.records[candidate.id]
        if not current then return Result.err('VESSEL_NOT_FOUND', 'vessel was not found') end
        if current.version ~= expectedVersion then return Result.err('VESSEL_VERSION_CONFLICT', 'vessel version conflict') end
        self.records[candidate.id] = copy(candidate)
        return Result.ok(copy(candidate))
    end
    local metadata = encode(candidate.metadata)
    if not metadata then return Result.err('VESSEL_REPOSITORY_FAILED', 'JSON serializer is unavailable') end
    local result = self.database:update([[
        UPDATE portops_vessels
           SET name = ?, imo = ?, vessel_type = ?, metadata_json = ?, version = ?, updated_at = ?
         WHERE id = ? AND version = ?
    ]], { candidate.name, candidate.imo, candidate.vesselType, metadata, candidate.version, candidate.updatedAt, candidate.id, expectedVersion })
    if Result.isErr(result) then return Result.err('VESSEL_REPOSITORY_FAILED', 'vessel update failed', result.error) end
    if tonumber(affectedRows(result)) == 0 then return Result.err('VESSEL_VERSION_CONFLICT', 'vessel version conflict') end
    return Result.ok(copy(candidate))
end

function Repository:list(limit)
    local max = math.min(math.max(tonumber(limit) or 100, 1), 500)
    if self:_memory() then
        local out = {}
        for _, value in pairs(self.records) do if #out < max then out[#out + 1] = copy(value) end end
        table.sort(out, function(a, b) return a.id < b.id end)
        return Result.ok(out)
    end
    local result = self.database:query('SELECT * FROM portops_vessels ORDER BY id LIMIT ?', { max })
    if Result.isErr(result) then return Result.err('VESSEL_REPOSITORY_FAILED', 'vessel list failed', result.error) end
    local rows = result.data and (result.data.rows or result.data) or {}
    local out = {}
    for _, row in ipairs(rows) do local value = self:_row(row); if value then out[#out + 1] = value end end
    return Result.ok(out)
end

PortOps.Repositories.Vessel = Repository
return Repository
