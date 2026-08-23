-- Persistent logical container domain.  A container record is independent of
-- any GTA entity; visual clients only receive the safe DTO produced later.
PortOps = PortOps or {}
PortOps.Domain = PortOps.Domain or {}

local Result = PortOps.Core.Result
local Container = {}

Container.ISO_TYPES = {
    ['20GP'] = true,
    ['40GP'] = true,
    ['40HC'] = true,
    ['45HC'] = true,
    ['20RF'] = true,
    ['40RF'] = true
}

Container.STATUSES = {
    EXPECTED = true,
    ON_VESSEL = true,
    READY_FOR_DISCHARGE = true,
    CRANE_RESERVED = true,
    CRANE_ATTACHED = true,
    DISCHARGING = true,
    ON_TERMINAL_TRAILER = true,
    IN_TERMINAL_TRANSFER = true,
    YARD_RECEIVING = true,
    AT_YARD = true,
    CUSTOMS_PENDING = true,
    CUSTOMS_HOLD = true,
    INSPECTION = true,
    CUSTOMS_CLEARED = true,
    SEIZED = true,
    READY_FOR_PICKUP = true,
    PICKUP_IN_PROGRESS = true,
    GATE_OUT = true,
    LEFT_TERMINAL = true,
    DAMAGED = true,
    MISROUTED = true,
    BLOCKED = true,
    RECOVERY_REQUIRED = true,
    CANCELLED = true
}

local CUSTOMS_STATUSES = { PENDING = true, HOLD = true, CLEARED = true, SEIZED = true }
local SEAL_STATUSES = { INTACT = true, BROKEN = true, MISSING = true, UNKNOWN = true }
local LOCATION_TYPES = { VESSEL = true, TERMINAL_TRAILER = true, YARD_SLOT = true, GATE = true, UNKNOWN = true }

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function text(value, maxLength)
    if type(value) ~= 'string' then return nil end
    if value == '' or (maxLength and #value > maxLength) then return nil end
    return value
end

local function optionalText(value, maxLength)
    if value == nil then return nil end
    return text(value, maxLength)
end

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function validIsoNumber(value)
    if type(value) ~= 'string' then return false end
    return value:match('^[A-Z][A-Z][A-Z][UJZ]%d%d%d%d%d%d%d$') ~= nil
end

local function normalizeIdentifier(value, maxLength)
    if value == nil then return nil end
    if type(value) == 'number' and finite(value) and value >= 0 and value % 1 == 0 then
        value = tostring(value)
    end
    return text(value, maxLength)
end

local function normalizeCargo(value)
    value = value or {}
    if type(value) ~= 'table' then return nil, 'cargo must be a table' end
    local weight = value.grossWeightKg
    if weight == nil then weight = 0 end
    if not finite(weight) or weight < 0 or weight > 100000 then return nil, 'cargo grossWeightKg is invalid' end
    if value.reefer ~= nil and type(value.reefer) ~= 'boolean' then return nil, 'cargo reefer is invalid' end
    local result = {
        category = optionalText(value.category, 96),
        description = optionalText(value.description, 256),
        grossWeightKg = weight,
        hazardousClass = optionalText(value.hazardousClass, 32),
        reefer = value.reefer == true
    }
    if value.category ~= nil and not result.category then return nil, 'cargo category is invalid' end
    if value.description ~= nil and not result.description then return nil, 'cargo description is invalid' end
    if value.hazardousClass ~= nil and not result.hazardousClass then return nil, 'cargo hazardousClass is invalid' end
    return result
end

local function normalizeLogistics(value)
    value = value or {}
    if type(value) ~= 'table' then return nil, 'logistics must be a table' end
    local result = {}
    for _, key in ipairs({ 'origin', 'destination', 'shipper', 'consignee', 'booking', 'voyage' }) do
        if value[key] ~= nil then
            result[key] = text(value[key], 128)
            if not result[key] then return nil, 'logistics.' .. key .. ' is invalid' end
        end
    end
    return result
end

local function normalizeTransform(value)
    if value == nil then return nil end
    if type(value) ~= 'table' then return nil, 'location transform must be a table' end
    for _, key in ipairs({ 'x', 'y', 'z' }) do
        if not finite(value[key]) then return nil, 'location transform is invalid' end
    end
    local heading = value.heading or 0.0
    if not finite(heading) then return nil, 'location heading is invalid' end
    return { x = value.x, y = value.y, z = value.z, heading = heading }
end

local function normalizeLocation(value)
    if value == nil then return nil end
    if type(value) ~= 'table' then return nil, 'location must be a table' end
    local locationType = value.type or 'UNKNOWN'
    if type(locationType) ~= 'string' or not LOCATION_TYPES[locationType] then return nil, 'location type is invalid' end
    local ref = value.ref
    if ref ~= nil and not text(ref, 128) then return nil, 'location ref is invalid' end
    local transform, transformReason = normalizeTransform(value.transform)
    if value.transform ~= nil and not transform then return nil, transformReason end
    return { type = locationType, ref = ref, transform = transform }
end

local function normalizeCustoms(value)
    value = value or {}
    if type(value) ~= 'table' then return nil, 'customs must be a table' end
    local status = value.status or 'PENDING'
    if type(status) ~= 'string' or not CUSTOMS_STATUSES[status] then return nil, 'customs status is invalid' end
    local riskScore = value.riskScore
    if riskScore == nil then riskScore = 0 end
    if not finite(riskScore) or riskScore < 0 or riskScore > 100 then return nil, 'customs riskScore is invalid' end
    return {
        status = status,
        riskScore = riskScore,
        caseId = optionalText(value.caseId, 64),
        holdReason = optionalText(value.holdReason, 256)
    }
end

local function invalid(reason, details)
    return Result.err('CONTAINER_INVALID', reason, details)
end

function Container.validate(input, options)
    options = options or {}
    if type(input) ~= 'table' then return invalid('container must be a table') end
    local number = input.containerNumber
    if type(number) == 'string' then number = number:upper() end
    if not validIsoNumber(number) then return invalid('containerNumber must be a valid ISO 6346 identifier') end
    local isoType = input.isoType
    if type(isoType) == 'string' then isoType = isoType:upper() end
    if not Container.ISO_TYPES[isoType] then return invalid('isoType is unsupported') end

    local id = normalizeIdentifier(input.id, 64)
    if input.id ~= nil and not id then return invalid('id is invalid') end
    local status = input.status or 'EXPECTED'
    if type(status) ~= 'string' or not Container.STATUSES[status] then return invalid('status is invalid') end
    local version = input.version or 1
    if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then return invalid('version is invalid') end
    local condition = input.condition
    if condition == nil then condition = 100 end
    if not finite(condition) or condition < 0 or condition > 100 then return invalid('condition is invalid') end

    local cargo, cargoReason = normalizeCargo(input.cargo)
    if not cargo then return invalid(cargoReason) end
    local logistics, logisticsReason = normalizeLogistics(input.logistics)
    if not logistics then return invalid(logisticsReason) end
    local vesselCallId = normalizeIdentifier(input.vesselCallId, 64)
    if input.vesselCallId ~= nil and not vesselCallId then return invalid('vesselCallId is invalid') end
    local manifestId = normalizeIdentifier(input.manifestId, 64)
    if input.manifestId ~= nil and not manifestId then return invalid('manifestId is invalid') end
    local location, locationReason = normalizeLocation(input.location)
    if input.location ~= nil and not location then return invalid(locationReason) end
    local customs, customsReason = normalizeCustoms(input.customs)
    if not customs then return invalid(customsReason) end
    local sealStatus = input.sealStatus or 'INTACT'
    if type(sealStatus) ~= 'string' or not SEAL_STATUSES[sealStatus] then return invalid('sealStatus is invalid') end

    local createdAt = input.createdAt or nowMs()
    local updatedAt = input.updatedAt or createdAt
    if not finite(createdAt) or not finite(updatedAt) then return invalid('timestamps are invalid') end
    if options.requireId and not id then return invalid('id is required') end

    return Result.ok({
        id = id,
        containerNumber = number,
        isoType = isoType,
        cargo = cargo,
        logistics = logistics,
        vesselCallId = vesselCallId,
        manifestId = manifestId,
        status = status,
        location = location,
        customs = customs,
        condition = condition,
        sealStatus = sealStatus,
        version = version,
        createdAt = createdAt,
        updatedAt = updatedAt
    })
end

function Container.new(input, options)
    return Container.validate(input, options)
end

function Container.copy(value)
    return copy(value)
end

function Container.toDTO(value)
    if type(value) ~= 'table' then return nil end
    return copy(value)
end

PortOps.Domain.Container = Container
return Container
