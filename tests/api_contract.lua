local root = os.getenv('PORTOPS_ROOT') or '.'
local function load(path) dofile(root .. '/' .. path) end
PortOps = { Core = {} }
load('server/core/result.lua')
load('server/core/idempotency.lua')
load('server/api/dto.lua')
load('server/api/events.lua')
load('server/api/exports.lua')
local clock = 1000
local idem = PortOps.Core.Idempotency.new({ clock = function() return clock end })
local calls = 0
local first = idem:run('container', 'same-key', function()
    calls = calls + 1
    return PortOps.Core.Result.ok({ id = 'C-1', token = 'secret' })
end)
local second = idem:run('container', 'same-key', function() calls = calls + 1; return PortOps.Core.Result.ok({ id = 'C-2' }) end)
assert(first.ok and second.ok and second.meta.idempotent and calls == 1, 'idempotency did not deduplicate')
local dto = PortOps.Api.DTO.result(PortOps.Core.Result.ok({ id = 'C-1', token = 'secret', database = {} }))
assert(dto.ok and dto.data.id == 'C-1' and dto.data.token == nil and dto.data.database == nil, 'DTO leaked protected fields')
print('api contract: ok')
