-- Offline contract for the development-only live smoke surface.
PortOps = {}
dofile('shared/enums.lua')
dofile('shared/errors.lua')
dofile('shared/crane/constants.lua')
dofile('shared/crane/schema.lua')
dofile('shared/crane/protocol.lua')
dofile('shared/crane/validation.lua')
dofile('config/config.lua')
dofile('config/features.lua')
dofile('client/crane/sync.lua')

local commands, events, outbound = {}, {}, {}
RegisterCommand = function(name, handler) commands[name] = handler end
RegisterNetEvent = function() end
AddEventHandler = function(name, handler) events[name] = handler end
TriggerServerEvent = function(name, ...) outbound[#outbound + 1] = { name = name, args = { ... } } end
CreateThread = function() end
Wait = function() end
GetGameTimer = function() return 1000 end
GetCurrentResourceName = function() return 'gnsh-portops' end

dofile('client/bootstrap.lua')

local function assertf(value, message) assert(value, message); return value end
assertf(commands.portops_reserve and commands.portops_release, 'session smoke commands were not registered')
assertf(commands.portops_snapshot and commands.portops_issue_attach and commands.portops_consume_attach, 'action smoke commands were not registered')
assertf(commands.portops_status == nil, 'server-only status command leaked to client')

commands.portops_observe(0, { 'qc-01' })
events['portops:crane:canonical']('qc-01', {
    version = PortOps.Crane.Protocol.VERSION,
    sequence = 1,
    timestamp = 2000,
    state = { gantry = 0.25, trolley = 0.5, spreader = 1.0, yaw = 0.0 }
})
local localized = PortOps.Client.sample('qc-01', 1000)
assertf(localized and localized.gantry == 0.25, 'server snapshot clock was not localized for interpolation')

commands.portops_reserve(0, { 'qc-01' })
assertf(outbound[#outbound].name == 'portops:crane:reserve' and outbound[#outbound].args[1] == 'qc-01', 'reserve command sent wrong event')
events['portops:crane:session']({ ok = true, data = {
    craneId = 'qc-01', sessionId = 'session-1', sessionToken = 'session-token', serverTime = 1000
} })
assertf(PortOps.Client.session.sessionId == 'session-1', 'session response was not stored')

commands.portops_snapshot(0, { 'qc-01' })
local snapshot = outbound[#outbound]
assertf(snapshot.name == 'portops:crane:snapshot', 'snapshot command sent wrong event')
assertf(snapshot.args[2].version == PortOps.Crane.Protocol.VERSION, 'snapshot protocol version missing')
assertf(snapshot.args[2].sessionToken == 'session-token' and snapshot.args[2].timestamp == 1000, 'snapshot session binding or clock offset missing')

commands.portops_issue_attach(0, { 'SMOKE-001' })
assertf(outbound[#outbound].name == 'portops:crane:action:issue', 'issue command sent wrong event')
local issueResult = { ok = true, data = {} }
issueResult.data['token'] = 'action-token'
events['portops:crane:action:result'](issueResult)
assertf(PortOps.Client.actionToken == 'action-token', 'issued action token was not stored')

commands.portops_consume_attach(0, { 'SMOKE-001' })
assertf(outbound[#outbound].name == 'portops:crane:action:consume' and outbound[#outbound].args[1] == 'action-token', 'consume command sent wrong token')
events['portops:crane:action:result']({ ok = true, data = { action = 'attach' } })
assertf(PortOps.Client.actionToken == nil, 'consumed action token was not cleared')

commands.portops_release(0, {})
assertf(outbound[#outbound].name == 'portops:crane:release', 'release command sent wrong event')
events['portops:crane:session']({ ok = true, data = { released = true } })
assertf(PortOps.Client.session == nil, 'release response did not clear client session')

print('client_bootstrap_contract: PASS')
