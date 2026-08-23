-- Offline contract for container repository CRUD and optimistic versioning.
PortOps = {}
dofile('shared/errors.lua')
dofile('server/core/result.lua')
dofile('server/adapters/database/memory.lua')
dofile('server/domain/container.lua')
dofile('server/repositories/container_repository.lua')

local Result = PortOps.Core.Result
local Container = PortOps.Domain.Container
local Memory = PortOps.Adapters.Database.Memory
local Repository = PortOps.Repositories.Container

local database = Memory.new()
assert(Result.isOk(database:connect()), 'memory database did not connect')
local repository = Repository.new({ database = database })
local first = Container.new({ id = 'ctr-001', containerNumber = 'MSCU1234567', isoType = '40GP' })
assert(Result.isOk(first), 'test container could not be created')
assert(Result.isOk(repository:create(first.data)), 'container repository create failed')
assert(Result.isErr(repository:create(first.data)) and repository:create(first.data).error.code == 'CONTAINER_NUMBER_EXISTS', 'duplicate container number was accepted')

local byId = repository:getById('ctr-001')
assert(Result.isOk(byId) and byId.data.containerNumber == 'MSCU1234567', 'repository get by id failed')
local byNumber = repository:getByNumber('MSCU1234567')
assert(Result.isOk(byNumber) and byNumber.data.id == 'ctr-001', 'repository get by number failed')

local updated = first.data
updated.status = 'ON_VESSEL'
updated.version = 2
assert(Result.isOk(repository:update(updated, 1)), 'optimistic repository update failed')
local conflict = repository:update(updated, 1)
assert(Result.isErr(conflict) and conflict.error.code == 'CONTAINER_VERSION_CONFLICT', 'stale repository update was accepted')

local list = repository:list({ status = 'ON_VESSEL' })
assert(Result.isOk(list) and #list.data == 1, 'repository list filter failed')
local missing = repository:getById('missing')
assert(Result.isErr(missing) and missing.error.code == 'CONTAINER_NOT_FOUND', 'missing container did not return stable error')

print('container_repository_contract: PASS')
