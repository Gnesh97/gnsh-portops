-- Stable public DTO boundary. Never return database rows or framework objects.
PortOps = PortOps or {}; PortOps.Api = PortOps.Api or {}
local DTO = {}
local SENSITIVE = { database=true, framework=true, driver=true, password=true, secret=true, token=true, sessionToken=true }
local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do
        if not SENSITIVE[tostring(key)] and (type(key) ~= 'number' or key <= 128) then out[copy(key, seen)] = copy(child, seen) end
    end
    return out
end
function DTO.safe(value)
    if type(value) ~= 'table' then return value end
    local out = copy(value)
    return out
end
function DTO.result(result)
    if type(result) ~= 'table' then return result end
    local out = { ok = result.ok }
    if result.ok then out.data = DTO.safe(result.data); out.meta = DTO.safe(result.meta)
    else out.error = DTO.safe(result.error) end
    return out
end
PortOps.Api.DTO = DTO
return DTO
