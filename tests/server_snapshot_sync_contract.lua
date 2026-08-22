-- Offline contract checks for production crane snapshot authority and observers.
PortOps = {}
dofile('shared/crane/protocol.lua')
dofile('server/crane/sync.lua')
dofile('client/crane/sync.lua')

local Server = PortOps.Crane.ServerSync
local Client = PortOps.Crane.ClientSync
local Protocol = PortOps.Crane.Protocol
local function assertf(value, message) assert(value, message) end

local sync = Server.new({ craneId = 'crane-01', sessionId = 'session-01', snapshotHz = 10, maxTimestampSkewMs = 5000 })
Server.setOperator(sync, 17)
local first = { craneId = 'crane-01', sessionId = 'session-01', sequence = 1, timestamp = 1000, gantry = .5, trolley = .5, spreader = 1, yaw = 0 }
assertf(Server.accept(sync, 17, first, 1000), 'valid operator snapshot rejected')
assertf(not Protocol.validate({ version = 99, sequence = 2, timestamp = 1000, gantry = .5, trolley = .5, spreader = 1, yaw = 0 }, nil, 1000), 'protocol version mismatch accepted')
assertf(not Protocol.validate({ sequence = 1, timestamp = 1000, state = { gantry = .5, trolley = .5, spreader = 1, yaw = 0, extra = true } }, nil, 1000, { maxPayloadKeys = 4 }), 'configured payload limit ignored')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-01', sequence = 2, timestamp = 1000, gantry = .5, trolley = .5, spreader = 1 }, 1000), 'missing yaw accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-01', sequence = 2, timestamp = 1300, gantry = .5, trolley = .5, spreader = 1, yaw = 0 }, 1000), 'future timestamp accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-01', sequence = 2, timestamp = -1101, gantry = .5, trolley = .5, spreader = 1, yaw = 0 }, 1000), 'stale timestamp accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-99', sessionId = 'session-01', sequence = 2, timestamp = 1200, gantry = .5, trolley = .5, spreader = 1 }, 1200), 'wrong crane accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-99', sequence = 2, timestamp = 1200, gantry = .5, trolley = .5, spreader = 1 }, 1200), 'wrong session accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-01', sequence = 1, timestamp = 1100, gantry = .5, trolley = .5, spreader = 1 }, 1100), 'late sequence accepted')
assertf(not Server.accept(sync, 17, { craneId = 'crane-01', sessionId = 'session-01', sequence = 2, timestamp = 1100, gantry = 1, trolley = .5, spreader = 1 }, 1100), 'teleport snapshot accepted')
assertf(not Server.accept(sync, 99, first, 1200), 'non-operator snapshot accepted')

local observer = Client.new({ interpolationDelayMs = 0, bufferSize = 4 })
assertf(Client.push(observer, { sequence = 1, timestamp = 1000, gantry = 0, trolley = 0, spreader = 0, yaw = 0 }))
assertf(Client.push(observer, { sequence = 2, timestamp = 1100, gantry = 1, trolley = 1, spreader = 1, yaw = 90 }))
assertf(not Client.push(observer, { sequence = 1, timestamp = 1200, gantry = 0, trolley = 0, spreader = 0 }), 'late observer snapshot accepted')
local sampled = Client.sample(observer, 1050)
assertf(sampled and sampled.gantry > 0 and sampled.gantry < 1, 'observer interpolation failed')
Client.clear(observer)
assertf(observer.hardResync and Client.push(observer, { sequence = 8, timestamp = 2000, gantry = .25, trolley = .5, spreader = 1, yaw = 0 }))
assertf(Client.sample(observer, 2000).gantry == .25, 'observer hard resync failed')

print('server_snapshot_sync_contract: PASS')
