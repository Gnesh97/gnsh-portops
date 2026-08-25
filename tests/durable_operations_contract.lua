local root = os.getenv('PORTOPS_ROOT') or '.'
local function load(path) dofile(root .. '/' .. path) end
PortOps = { Core = {} }
load('server/core/result.lua')
load('config/yard.lua')
load('server/core/reservations.lua')
load('server/repositories/yard_repository.lua')
load('server/domain/vessel.lua')
load('server/repositories/vessel_repository.lua')
load('server/repositories/vessel_call_repository.lua')
load('server/repositories/manifest_repository.lua')
load('server/domain/gate_appointment.lua')
load('server/repositories/gate_repository.lua')

local previousJson = json
local blobs, sequence = {}, 0
json = {
    encode = function(value)
        sequence = sequence + 1
        local key = 'blob:' .. sequence
        blobs[key] = value
        return key
    end,
    decode = function(value) return blobs[value] end
}

local database = { provider = 'oxmysql', statements = {} }
function database:query(sql, parameters)
    self.statements[#self.statements + 1] = { method = 'query', sql = sql, parameters = parameters }
    return PortOps.Core.Result.ok({ rows = {} })
end
function database:single(sql, parameters)
    self.statements[#self.statements + 1] = { method = 'single', sql = sql, parameters = parameters }
    return PortOps.Core.Result.ok(nil)
end
function database:insert(sql, parameters)
    self.statements[#self.statements + 1] = { method = 'insert', sql = sql, parameters = parameters }
    return PortOps.Core.Result.ok({ affectedRows = 1 })
end
function database:update(sql, parameters)
    self.statements[#self.statements + 1] = { method = 'update', sql = sql, parameters = parameters }
    return PortOps.Core.Result.ok({ affectedRows = 1 })
end

local yard = PortOps.Repositories.Yard.new({ config = PortOps.Config.yard, database = database, clock = function() return 1000 end })
assert(yard:reserve('C-14-03-1', 'operator-1', 5000).ok, 'durable yard reservation failed')
assert(yard:occupy('C-14-03-1', 'operator-1', 'container-1').ok, 'durable yard occupancy failed')
assert(yard:unoccupy('C-14-03-1', 'container-1').ok, 'durable yard release failed')

local vessels = PortOps.Repositories.Vessel.new({ database = database, clock = function() return 1000 end })
assert(vessels:create({ id = 'v-1', name = 'Test Vessel', metadata = {} }).ok, 'durable vessel insert failed')
local calls = PortOps.Repositories.VesselCall.new({ database = database, clock = function() return 1000 end })
assert(calls:create({ id = 'call-1', vesselId = 'v-1', metadata = {} }).ok, 'durable vessel call insert failed')
local manifests = PortOps.Repositories.Manifest.new({ database = database, clock = function() return 1000 end })
assert(manifests:create({ id = 'manifest-1', items = {} }).ok, 'durable manifest insert failed')
local gates = PortOps.Repositories.Gate.new({ database = database, clock = function() return 1000 end })
assert(gates:create({ id = 'appointment-1', containerId = 'container-1', windowStart = 1, windowEnd = 2 }).ok, 'durable gate insert failed')
assert(#database.statements >= #PortOps.Config.yard.slots + 8, 'durable repositories did not issue SQL writes')

json = previousJson
print('durable_operations_contract: PASS')
