-- Stable service result envelope shared by future domain and adapter layers.
PortOps = PortOps or {}
PortOps.Core = PortOps.Core or {}

local Result = {}

function Result.ok(data, meta)
    return { ok = true, data = data, meta = meta }
end

function Result.err(code, message, details)
    return {
        ok = false,
        data = nil,
        error = {
            code = code or 'UNKNOWN_ERROR',
            message = message or code or 'unknown error',
            details = details
        }
    }
end

function Result.isOk(value)
    return type(value) == 'table' and value.ok == true and value.error == nil
end

function Result.isErr(value)
    return type(value) == 'table' and value.ok == false and type(value.error) == 'table'
end

function Result.unwrap(value)
    if Result.isOk(value) then return true, value.data end
    if Result.isErr(value) then return false, value.error end
    return false, { code = 'RESULT_INVALID', message = 'result envelope is invalid' }
end

PortOps.Core.Result = Result
return Result
