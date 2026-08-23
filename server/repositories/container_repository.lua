-- Container persistence boundary.  Memory mode is explicit for development;
-- oxmysql mode uses parameterized queries and optimistic version predicates.
PortOps = PortOps or {}
PortOps.Repositories = PortOps.Repositories or {}

local Result = PortOps.Core.Result
local Container = PortOps.Domain.Container
local Repository = {}
Repository.__index = Repository

local function copy(value)
    return Container.copy(value)
end

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function positiveInteger(value)
    return type(value) == 'number' and value >= 1 and value % 1 == 0
end

local function encode(value)
    if type(json) == 'table' and type(json.encode) == 'function' then
        local ok, result = pcall(json.encode, value or {})
        if ok then return result end
    end
    return nil
end

local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) == 'string' and type(json) == 'table' and type(json.decode) == 'function' then
        local ok, result = pcall(json.decode, value)
        if ok and type(result) == 'table' then return result end
    end
    return nil
end

local function failed(message, details)
    return Result.err('CONTAINER_REPOSITORY_FAILED', message, details)
end

local function notFound()
    return Result.err('CONTAINER_NOT_FOUND', 'container was not found')
end

local function normalize(record, requireId)
    local result = Container.validate(record, { requireId = requireId })
    if Result.isErr(result) then return result end
    return Result.ok(result.data)
end

function Repository.new(options)
    options = options or {}
    return setmetatable({
        database = options.database,
        records = {},
        numberIndex = {},
        sequence = 0,
        idGenerator = options.idGenerator,
        clock = options.clock
    }, Repository)
end

function Repository:_now()
    return self.clock and self.clock() or nowMs()
end

function Repository:_nextId()
    if type(self.idGenerator) == 'function' then return self.idGenerator() end
    self.sequence = self.sequence + 1
    return ('ctr-%d-%d'):format(self:_now(), self.sequence)
end

function Repository:_isMemory()
    return self.database and self.database.provider == 'memory'
end

function Repository:_jsonFields(record)
    local cargo = encode(record.cargo)
    local logistics = encode(record.logistics)
    local location = record.location and encode(record.location) or nil
    local customs = encode(record.customs)
    if not cargo or not logistics or not customs or (record.location and not location) then
        return nil, 'JSON serializer is unavailable'
    end
    return cargo, logistics, location, customs
end

function Repository:create(record)
    local candidate = copy(record)
    if type(candidate) ~= 'table' then return failed('container record is invalid') end
    candidate.id = candidate.id or self:_nextId()
    local normalized = normalize(candidate, true)
    if Result.isErr(normalized) then return normalized end
    candidate = normalized.data

    if self:_isMemory() then
        if self.numberIndex[candidate.containerNumber] then return Result.err('CONTAINER_NUMBER_EXISTS', 'container number already exists') end
        if self.records[candidate.id] then return Result.err('CONTAINER_ID_EXISTS', 'container id already exists') end
        self.records[candidate.id] = copy(candidate)
        self.numberIndex[candidate.containerNumber] = candidate.id
        return Result.ok(copy(candidate))
    end

    local cargo, logistics, location, customs = self:_jsonFields(candidate)
    if not cargo then return failed(logistics) end
    local query = [[
        INSERT INTO portops_containers
            (id, container_number, iso_type, cargo_json, logistics_json, vessel_call_id, manifest_id,
             status, location_json, customs_json, condition_score, seal_status, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    local result = self.database:insert(query, {
        candidate.id, candidate.containerNumber, candidate.isoType, cargo, logistics,
        candidate.vesselCallId, candidate.manifestId, candidate.status, location, customs,
        candidate.condition, candidate.sealStatus, candidate.version, candidate.createdAt, candidate.updatedAt
    })
    if Result.isErr(result) then return failed('container insert failed', result.error) end
    return Result.ok(copy(candidate))
end

function Repository:_row(row)
    if type(row) ~= 'table' then return nil end
    local normalized = normalize({
        id = row.id,
        containerNumber = row.container_number or row.containerNumber,
        isoType = row.iso_type or row.isoType,
        cargo = decode(row.cargo_json or row.cargo),
        logistics = decode(row.logistics_json or row.logistics),
        vesselCallId = row.vessel_call_id or row.vesselCallId,
        manifestId = row.manifest_id or row.manifestId,
        status = row.status,
        location = decode(row.location_json or row.location),
        customs = decode(row.customs_json or row.customs),
        condition = tonumber(row.condition_score or row.condition),
        sealStatus = row.seal_status or row.sealStatus,
        version = tonumber(row.version),
        createdAt = tonumber(row.created_at or row.createdAt),
        updatedAt = tonumber(row.updated_at or row.updatedAt)
    }, true)
    return Result.isOk(normalized) and normalized.data or nil
end

function Repository:getById(id)
    if type(id) ~= 'string' or id == '' then return notFound() end
    if self:_isMemory() then
        local record = self.records[id]
        return record and Result.ok(copy(record)) or notFound()
    end
    local result = self.database:single('SELECT * FROM portops_containers WHERE id = ? LIMIT 1', { id })
    if Result.isErr(result) then return failed('container lookup failed', result.error) end
    local record = self:_row(result.data)
    return record and Result.ok(record) or notFound()
end

function Repository:getByNumber(number)
    if type(number) ~= 'string' or number == '' then return notFound() end
    if self:_isMemory() then
        local id = self.numberIndex[number:upper()]
        return id and self:getById(id) or notFound()
    end
    local result = self.database:single('SELECT * FROM portops_containers WHERE container_number = ? LIMIT 1', { number:upper() })
    if Result.isErr(result) then return failed('container number lookup failed', result.error) end
    local record = self:_row(result.data)
    return record and Result.ok(record) or notFound()
end

local function matches(record, filters)
    if type(filters) ~= 'table' then return true end
    if filters.status and record.status ~= filters.status then return false end
    if filters.isoType and record.isoType ~= filters.isoType then return false end
    if filters.locationType and (not record.location or record.location.type ~= filters.locationType) then return false end
    return true
end

function Repository:list(filters, options)
    filters, options = filters or {}, options or {}
    local limit = math.min(math.max(tonumber(options.limit) or 100, 1), 500)
    local offset = math.max(tonumber(options.offset) or 0, 0)
    if self:_isMemory() then
        local matching = {}
        for _, record in pairs(self.records) do
            if matches(record, filters) then
                matching[#matching + 1] = record
            end
        end
        table.sort(matching, function(left, right) return left.containerNumber < right.containerNumber end)
        local result = {}
        for index = offset + 1, math.min(#matching, offset + limit) do
            result[#result + 1] = copy(matching[index])
        end
        return Result.ok(result)
    end
    local clauses, parameters = {}, {}
    if filters.status then clauses[#clauses + 1] = 'status = ?'; parameters[#parameters + 1] = filters.status end
    if filters.isoType then clauses[#clauses + 1] = 'iso_type = ?'; parameters[#parameters + 1] = filters.isoType end
    local query = 'SELECT * FROM portops_containers'
    if #clauses > 0 then query = query .. ' WHERE ' .. table.concat(clauses, ' AND ') end
    query = query .. ' ORDER BY container_number LIMIT ? OFFSET ?'
    parameters[#parameters + 1] = limit
    parameters[#parameters + 1] = offset
    local result = self.database:query(query, parameters)
    if Result.isErr(result) then return failed('container list failed', result.error) end
    local rows = result.data and (result.data.rows or result.data) or {}
    local records = {}
    for _, row in ipairs(rows) do
        local record = self:_row(row)
        if record and (not filters.locationType or (record.location and record.location.type == filters.locationType)) then
            records[#records + 1] = record
        end
    end
    return Result.ok(records)
end

function Repository:update(record, expectedVersion)
    local normalized = normalize(record, true)
    if Result.isErr(normalized) then return normalized end
    local candidate = normalized.data
    if not positiveInteger(expectedVersion) then return Result.err('CONTAINER_VERSION_INVALID', 'expected version is required') end
    if candidate.version ~= expectedVersion + 1 then return Result.err('CONTAINER_VERSION_INVALID', 'record version must increment by one') end

    if self:_isMemory() then
        local existing = self.records[candidate.id]
        if not existing then return notFound() end
        if existing.version ~= expectedVersion then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
        local owner = self.numberIndex[candidate.containerNumber]
        if owner and owner ~= candidate.id then return Result.err('CONTAINER_NUMBER_EXISTS', 'container number already exists') end
        self.numberIndex[existing.containerNumber] = nil
        self.numberIndex[candidate.containerNumber] = candidate.id
        self.records[candidate.id] = copy(candidate)
        return Result.ok(copy(candidate))
    end

    local cargo, logistics, location, customs = self:_jsonFields(candidate)
    if not cargo then return failed(logistics) end
    local query = [[
        UPDATE portops_containers
           SET container_number = ?, iso_type = ?, cargo_json = ?, logistics_json = ?, vessel_call_id = ?,
               manifest_id = ?, status = ?, location_json = ?, customs_json = ?, condition_score = ?,
               seal_status = ?, version = ?, updated_at = ?
         WHERE id = ? AND version = ?
    ]]
    local result = self.database:update(query, {
        candidate.containerNumber, candidate.isoType, cargo, logistics, candidate.vesselCallId,
        candidate.manifestId, candidate.status, location, customs, candidate.condition,
        candidate.sealStatus, candidate.version, candidate.updatedAt, candidate.id, expectedVersion
    })
    if Result.isErr(result) then return failed('container update failed', result.error) end
    local affected = type(result.data) == 'number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows))
    if tonumber(affected) == 0 then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
    return Result.ok(copy(candidate))
end

function Repository:delete(id, expectedVersion)
    if type(id) ~= 'string' or not positiveInteger(expectedVersion) then return Result.err('CONTAINER_VERSION_INVALID', 'id and expected version are required') end
    if self:_isMemory() then
        local existing = self.records[id]
        if not existing then return notFound() end
        if existing.version ~= expectedVersion then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
        self.records[id] = nil
        self.numberIndex[existing.containerNumber] = nil
        return Result.ok({ deleted = true, id = id })
    end
    local result = self.database:update('DELETE FROM portops_containers WHERE id = ? AND version = ?', { id, expectedVersion })
    if Result.isErr(result) then return failed('container delete failed', result.error) end
    local affected = type(result.data) == 'number' and result.data or (result.data and (result.data.affectedRows or result.data.affected_rows))
    if tonumber(affected) == 0 then return Result.err('CONTAINER_VERSION_CONFLICT', 'container version conflict') end
    return Result.ok({ deleted = true, id = id })
end

PortOps.Repositories.Container = Repository
return Repository
