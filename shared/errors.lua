-- Stable, serializable error envelopes used by server and client contracts.
PortOps = PortOps or {}
PortOps.Errors = PortOps.Errors or {}

local Errors = PortOps.Errors

Errors.codes = {
    CONFIG_INVALID = 'CONFIG_INVALID',
    RESOURCE_NOT_READY = 'RESOURCE_NOT_READY',
    CRANE_NOT_FOUND = 'CRANE_NOT_FOUND',
    CRANE_OCCUPIED = 'CRANE_OCCUPIED',
    CRANE_UNAVAILABLE = 'CRANE_UNAVAILABLE',
    SESSION_INVALID = 'SESSION_INVALID',
    SESSION_OWNER_MISMATCH = 'SESSION_OWNER_MISMATCH',
    SNAPSHOT_INVALID = 'SNAPSHOT_INVALID',
    SNAPSHOT_STALE = 'SNAPSHOT_STALE',
    SNAPSHOT_RATE_LIMITED = 'SNAPSHOT_RATE_LIMITED',
    SNAPSHOT_OUT_OF_BOUNDS = 'SNAPSHOT_OUT_OF_BOUNDS',
    SNAPSHOT_DELTA_TOO_LARGE = 'SNAPSHOT_DELTA_TOO_LARGE',
    SNAPSHOT_TIMESTAMP_INVALID = 'SNAPSHOT_TIMESTAMP_INVALID',
    TOKEN_INVALID = 'TOKEN_INVALID',
    TOKEN_RATE_LIMITED = 'TOKEN_RATE_LIMITED',
    TOKEN_EXPIRED = 'TOKEN_EXPIRED',
    TOKEN_REPLAY = 'TOKEN_REPLAY',
    TOKEN_BINDING_MISMATCH = 'TOKEN_BINDING_MISMATCH',
    RECOVERY_REQUIRED = 'RECOVERY_REQUIRED',
    INPUT_INVALID = 'INPUT_INVALID',
    NOT_AUTHORIZED = 'NOT_AUTHORIZED'
}

local function envelope(ok, data, code, message, details)
    return {
        ok = ok,
        data = data,
        error = ok and nil or {
            code = code,
            message = message,
            details = details
        }
    }
end
function Errors.ok(data, meta)
    local result = envelope(true, data)
    result.meta = meta
    return result
end

function Errors.err(code, message, details)
    return envelope(false, nil, code, message or code, details)
end

function Errors.isOk(result)
    return type(result) == 'table' and result.ok == true
end

function Errors.code(reason, fallback)
    if type(reason) == 'table' and reason.error then return reason.error.code end
    if type(reason) == 'string' and Errors.codes[reason] then return reason end
    return fallback or Errors.codes.INPUT_INVALID
end
