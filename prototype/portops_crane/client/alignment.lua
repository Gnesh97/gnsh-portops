-- S01 / PORT-014. Client-only geometry helper.
-- This module measures presentation alignment; it does not grant gameplay authority.

PortOpsCrane = PortOpsCrane or {}
PortOpsCrane.Alignment = PortOpsCrane.Alignment or {}

local Alignment = PortOpsCrane.Alignment

local function validEntity(entity)
    return type(entity) == 'number' and entity ~= 0 and (not DoesEntityExist or DoesEntityExist(entity))
end

local function number(value, fallback)
    return type(value) == "number" and value or fallback
end

local function position(value)
    if type(value) == "vector3" then
        return value.x, value.y, value.z
    end
    if type(value) == "table" then
        return number(value.x or value[1], 0.0), number(value.y or value[2], 0.0), number(value.z or value[3], 0.0)
    end
    return 0.0, 0.0, 0.0
end

local function entityPosition(value)
    if type(value) == "number" and GetEntityCoords then
        local ok, coords = pcall(GetEntityCoords, value)
        if ok and coords then return position(coords) end
    end
    return position(value)
end

local function heading(value, isEntity)
    if isEntity and type(value) == "number" and GetEntityHeading then
        local ok, result = pcall(GetEntityHeading, value)
        if ok then return number(result, 0.0) end
    end
    if type(value) == "table" then
        return number(value.heading or value.yaw, 0.0)
    end
    return number(value, 0.0)
end

local function angleError(a, b)
    local delta = (a - b) % 360.0
    if delta > 180.0 then delta = delta - 360.0 end
    return math.abs(delta)
end

local function tolerances(profile, overrides)
    local alignment = (profile and profile.alignment) or {}
    overrides = overrides or {}
    return {
        horizontal = number(overrides.horizontalToleranceM or alignment.horizontalToleranceM, 0.25),
        vertical = number(overrides.verticalToleranceM or alignment.verticalToleranceM, 0.15),
        yaw = number(overrides.yawToleranceDegrees or alignment.yawToleranceDegrees, 3.0),
    }
end

function Alignment.GetMetrics(spreader, candidate)
    local spreaderSource = type(spreader) == 'number' and spreader
        or (spreader and (spreader.entity or spreader.position or spreader))
    local candidateSource = type(candidate) == 'number' and candidate
        or (candidate and (candidate.entity or candidate.position or candidate))
    local sx, sy, sz = entityPosition(spreaderSource)
    local cx, cy, cz = entityPosition(candidateSource)
    local spreaderEntity = type(spreader) == 'number' and spreader or (spreader and spreader.entity)
    local candidateEntity = type(candidate) == 'number' and candidate or (candidate and candidate.entity)
    local spreaderHeading = spreaderEntity or (spreader and (spreader.heading or spreader.yaw)) or spreader
    local candidateHeading = candidateEntity or (candidate and (candidate.heading or candidate.yaw)) or candidate
    local spreaderYaw = heading(spreaderHeading, spreaderEntity ~= nil)
    local candidateYaw = heading(candidateHeading, candidateEntity ~= nil)
    local dx, dy, dz = sx - cx, sy - cy, sz - cz
    return {
        horizontalDistanceM = math.sqrt((dx * dx) + (dy * dy)),
        verticalGapM = math.abs(dz),
        yawErrorDegrees = angleError(spreaderYaw, candidateYaw),
        delta = { x = dx, y = dy, z = dz },
        spreaderYaw = spreaderYaw,
        candidateYaw = candidateYaw,
    }
end

function Alignment.Evaluate(spreader, candidate, profile, overrides)
    profile = profile or (PortOpsCrane.Config and PortOpsCrane.Config.profile)
    if not candidate then
        return { aligned = false, reason = "NO_CANDIDATE", metrics = nil, tolerances = tolerances(profile, overrides) }
    end
    local metrics = Alignment.GetMetrics(spreader, candidate)
    local limit = tolerances(profile, overrides)
    local aligned = metrics.horizontalDistanceM <= limit.horizontal
        and metrics.verticalGapM <= limit.vertical
        and metrics.yawErrorDegrees <= limit.yaw
    local reason = aligned and "ALIGNED" or "OUT_OF_TOLERANCE"
    if metrics.horizontalDistanceM > limit.horizontal then reason = "HORIZONTAL_MISALIGNMENT"
    elseif metrics.verticalGapM > limit.vertical then reason = "VERTICAL_MISALIGNMENT"
    elseif metrics.yawErrorDegrees > limit.yaw then reason = "YAW_MISALIGNMENT" end
    return { aligned = aligned, reason = reason, candidate = candidate, metrics = metrics, tolerances = limit }
end

function Alignment.FindNearestCandidate(spreader, profile, options)
    options = options or {}
    profile = profile or (PortOpsCrane.Config and PortOpsCrane.Config.profile)
    local candidates = options.candidates
    if not candidates and GetGamePool then
        candidates = {}
        local spreaderEntity = type(spreader) == 'number' and spreader or (spreader and spreader.entity)
        local radius = number(options.radiusM, 8.0)
        local spreaderSource = type(spreader) == 'number' and spreader
            or (spreader and (spreader.entity or spreader.position or spreader))
        local sx, sy, sz = entityPosition(spreaderSource)
        local excluded = {}
        local activeRig = PortOpsCrane.ActiveRig
        for _, entity in pairs(activeRig and activeRig.entities or {}) do
            excluded[entity] = true
        end
        local modelHash = options.model
        if modelHash and type(modelHash) ~= 'number' then modelHash = joaat(modelHash) end
        for _, entity in ipairs(GetGamePool('CObject') or {}) do
            if entity ~= spreaderEntity and not excluded[entity] and validEntity(entity)
                and (not modelHash or GetEntityModel(entity) == modelHash) then
                local ex, ey, ez = entityPosition(entity)
                local dx, dy, dz = ex - sx, ey - sy, ez - sz
                if (dx * dx) + (dy * dy) + (dz * dz) <= radius * radius then
                    candidates[#candidates + 1] = {
                        entity = entity,
                        position = vector3(ex, ey, ez),
                        heading = heading(entity, true)
                    }
                end
            end
        end
    end
    return Alignment.NearestCandidate(spreader, candidates or {}, profile, options.tolerances)
end

function Alignment.NearestCandidate(spreader, candidates, profile, overrides)
    local nearest, nearestResult
    for _, candidate in pairs(candidates or {}) do
        local result = Alignment.Evaluate(spreader, candidate, profile, overrides)
        if not nearestResult or (result.metrics and result.metrics.horizontalDistanceM < nearestResult.metrics.horizontalDistanceM) then
            nearest, nearestResult = candidate, result
        end
    end
    return nearest, nearestResult
end

function Alignment.DebugOverlay(result, x, y)
    if not result or not DrawText or not SetTextFont then return end
    x, y = x or 0.02, y or 0.32
    local metrics, limit = result.metrics, result.tolerances
    SetTextFont(0); SetTextScale(0.30, 0.30); SetTextColour(255, 255, 255, 220)
    SetTextOutline(); BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(string.format(
        "ALIGN %s | XY %.2fm/%.2f | Z %.2fm/%.2f | YAW %.2f°/%.2f°",
        result.reason, metrics and metrics.horizontalDistanceM or 0.0, limit and limit.horizontal or 0.0,
        metrics and metrics.verticalGapM or 0.0, limit and limit.vertical or 0.0,
        metrics and metrics.yawErrorDegrees or 0.0, limit and limit.yaw or 0.0))
    EndTextCommandDisplayText(x, y)
end

return Alignment
