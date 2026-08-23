-- Offline contract for S03 result, logger, and event-bus utilities.
PortOps = {}
dofile('server/core/result.lua')
dofile('server/core/logger.lua')
dofile('server/core/event_bus.lua')

local Result = PortOps.Core.Result
local Logger = PortOps.Core.Logger
local EventBus = PortOps.Core.EventBus

local ok = Result.ok({ value = 7 })
assert(Result.isOk(ok) and Result.unwrap(ok) == true, 'result ok envelope invalid')
local err = Result.err('BAD_INPUT', 'bad input')
local unwrapped, errorValue = Result.unwrap(err)
assert(not unwrapped and errorValue.code == 'BAD_INPUT', 'result error envelope invalid')

local logs = {}
local sinkContexts = {}
local logger = Logger.new({ category = 'contract', level = 'debug', sink = function(line, _, context) logs[#logs + 1] = line; sinkContexts[#sinkContexts + 1] = context end })
local correlation = logger:correlation('test')
assert(correlation == 'test-1', 'correlation id was not deterministic')
assert(logger:info('ready', { correlationId = correlation, payload = { raw = 'redacted' } }))
assert(#logs == 1 and logs[1]:find('<complex>', 1, true), 'logger did not redact complex values')
local secret = string.rep('x', 16)
local credentialContext = {}
credentialContext['sessionToken'] = secret
assert(logger:info('credential check', credentialContext))
assert(not logs[2]:find(secret, 1, true) and logs[2]:find('sessionToken=<redacted>', 1, true), 'logger leaked primitive credential')
assert(sinkContexts[2].sessionToken == '<redacted>', 'logger sink received raw credential context')

local bus = EventBus.new({ logger = logger, maxHandlers = 2 })
local calls = 0
local subscribed, registered = bus:on('container.created', function() calls = calls + 1 end)
assert(subscribed and type(registered) == 'function', 'event subscription contract failed')
assert(bus:on('container.created', function() error('isolated failure') end))
local emitted, summary = bus:emit('container.created', { id = 'c-1' })
assert(emitted and summary.delivered == 1 and summary.failures == 1 and calls == 1, 'event handlers were not isolated')
assert(registered(), 'event unsubscribe contract failed')
local reEmitted, reSummary = bus:emit('container.created', {})
assert(reEmitted and reSummary.delivered == 0 and reSummary.failures == 1 and calls == 1, 'event unsubscribe contract failed')

print('core_utilities_contract: PASS')
