local root = os.getenv('PORTOPS_ROOT') or '.'
local function load(path) dofile(root .. '/' .. path) end
PortOps = { Core = {} }
load('server/core/result.lua')
load('server/core/idempotency.lua')

local previousJson = json
local blobs, sequence, rows = {}, 0, {}
json = {
    encode = function(value)
        sequence = sequence + 1
        local key = 'blob:' .. sequence
        blobs[key] = value
        return key
    end,
    decode = function(value) return blobs[value] end
}

local database = { provider = 'oxmysql' }
function database:single(_, parameters)
    return PortOps.Core.Result.ok(rows[parameters[1] .. ':' .. parameters[2]])
end
function database:insert(_, parameters)
    local key = parameters[1] .. ':' .. parameters[2]
    if rows[key] then return PortOps.Core.Result.err('DUPLICATE', 'duplicate key') end
    rows[key] = { response_json = parameters[3], expires_at = parameters[4] }
    return PortOps.Core.Result.ok({ affectedRows = 1 })
end
function database:update(sql, parameters)
    if sql:find('DELETE', 1, true) then
        rows[parameters[1] .. ':' .. parameters[2]] = nil
    else
        local key = parameters[3] .. ':' .. parameters[4]
        rows[key] = { response_json = parameters[1], expires_at = parameters[2] }
    end
    return PortOps.Core.Result.ok({ affectedRows = 1 })
end

local firstCalls = 0
local first = PortOps.Core.Idempotency.new({ database = database, clock = function() return 1000 end })
local created = first:run('container.create', 'same-key', function()
    firstCalls = firstCalls + 1
    return PortOps.Core.Result.ok({ id = 'c1' })
end)
assert(created.ok and created.meta.persisted and firstCalls == 1, 'durable idempotency claim/store failed')

local secondCalls = 0
local second = PortOps.Core.Idempotency.new({ database = database, clock = function() return 1000 end })
local replay = second:run('container.create', 'same-key', function()
    secondCalls = secondCalls + 1
    return PortOps.Core.Result.ok({ id = 'c2' })
end)
assert(replay.ok and replay.meta.idempotent and replay.data.id == 'c1' and secondCalls == 0, 'durable idempotency replay was not returned')

local malformed = second:run('container.create', 'malformed', function() return { id = 'bad' } end)
assert(not malformed.ok and malformed.error.code == 'RESULT_INVALID', 'malformed operation result was accepted')

json = previousJson
print('idempotency_database_contract: PASS')
