-- Offline contract for nearby-only container descriptors and client hysteresis.
PortOps = {}
dofile('shared/errors.lua')
dofile('server/core/result.lua')
dofile('server/adapters/database/memory.lua')
dofile('server/domain/container.lua')
dofile('server/repositories/container_repository.lua')
dofile('server/services/streaming_service.lua')
dofile('client/containers/streaming.lua')

local Result = PortOps.Core.Result
local Memory = PortOps.Adapters.Database.Memory
local Repository = PortOps.Repositories.Container
local StreamingService = PortOps.Services.Streaming
local database = Memory.new()
local repository = Repository.new({ database = database })
local function seed(id, number, x)
    local container = PortOps.Domain.Container.new({ id = id, containerNumber = number, isoType = '20GP', location = { type = 'YARD_SLOT', ref = id, transform = { x = x, y = 0, z = 0 } } })
    assert(Result.isOk(container) and Result.isOk(repository:create(container.data)))
end
dofile('server/domain/container.lua')
seed('ctr-near', 'MSCU1234567', 3)
seed('ctr-far', 'MSCU1234568', 100)
local serverStreaming = StreamingService.new({ repository = repository })
local descriptors = serverStreaming:descriptorsFor({ x = 0, y = 0, z = 0 }, { radius = 10 })
assert(Result.isOk(descriptors) and #descriptors.data == 1 and descriptors.data[1].id == 'ctr-near', 'nearby descriptor filtering failed')
assert(descriptors.data[1].cargo == nil and descriptors.data[1].customs == nil, 'streaming descriptor leaked private container data')
local serverClock = 0
local subscribed = StreamingService.new({ repository = repository, clock = function() return serverClock end })
assert(Result.isOk(subscribed:subscribe(7, { x = 0, y = 0, z = 0 }, { radius = 10 })), 'stream subscription failed')
local limited = subscribed:subscribe(7, { x = 0, y = 0, z = 0 }, { radius = 10 })
assert(Result.isErr(limited) and limited.error.code == 'STREAM_RATE_LIMITED', 'stream request rate limit was not enforced')
serverClock = 250
assert(Result.isOk(subscribed:subscribe(7, { x = 0, y = 0, z = 0 }, { radius = 10 })), 'stream subscription did not recover after rate limit window')

local requested, reconciled = 0, 0
local playerPosition = { x = 0, y = 0, z = 0 }
local fakeVisuals = { reconcile = function(_, values) reconciled = #values; return { ok = true, data = {} } end, despawn = function() end }
local streaming = PortOps.Client.ContainerStreaming.new({
    visuals = fakeVisuals,
    getPlayerPosition = function() return playerPosition end,
    requestDescriptors = function(position)
        requested = requested + 1
        return position.x == 0 and descriptors.data or {}
    end,
    enterRadius = 20,
    leaveRadius = 30,
    requestIntervalMs = 1000,
    refreshIntervalMs = 1000
})
assert(streaming:update(0).ok and requested == 1 and reconciled == 1, 'client streaming did not request initial interest zone')
assert(streaming:update(500).ok and requested == 1, 'client streaming ignored request hysteresis')
playerPosition = { x = 100, y = 0, z = 0 }
assert(streaming:update(1000).ok and requested == 2 and reconciled == 0, 'client streaming did not unload after leaving zone')
playerPosition = { x = 0, y = 0, z = 0 }
assert(streaming:update(2000).ok and requested == 3 and reconciled == 1, 'client streaming did not restore visuals on re-entry')
local stale = streaming:receive(descriptors.data, 1)
assert(Result.isErr(stale) and stale.error.code == 'STREAM_STALE_RESPONSE' and reconciled == 1, 'stale stream response overwrote current visuals')
assert(streaming:update(7000).ok and requested == 4 and reconciled == 1, 'stationary stream refresh did not reconcile current visuals')

print('container_streaming_contract: PASS')
