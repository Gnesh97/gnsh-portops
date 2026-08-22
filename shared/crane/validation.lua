PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Validation = {}

function Validation.requiredIdentifier(value, maxLength)
    if value == nil then return false end
    if type(value) ~= 'string' and type(value) ~= 'number' then return false end
    local text = tostring(value)
    return text ~= '' and (not maxLength or #text <= maxLength)
end

function Validation.binding(binding)
    return type(binding) == 'table'
        and Validation.requiredIdentifier(binding.craneId)
        and Validation.requiredIdentifier(binding.sessionId)
        and Validation.requiredIdentifier(binding.source)
end

function Validation.copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Validation.copy(child) end
    return result
end

PortOps.Crane.Validation = Validation
return Validation
