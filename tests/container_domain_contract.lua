-- Offline contract for the persistent container domain model.
PortOps = {}
dofile('shared/errors.lua')
dofile('server/core/result.lua')
dofile('server/domain/container.lua')

local Result = PortOps.Core.Result
local Container = PortOps.Domain.Container

local created = Container.new({
    id = 'ctr-001',
    containerNumber = 'MSCU1234567',
    isoType = '40GP',
    cargo = { category = 'consumer_electronics', grossWeightKg = 18420, reefer = false },
    logistics = { origin = 'Shanghai', destination = 'Los Santos', shipper = 'Exporter', consignee = 'Importer' },
    vesselCallId = 518,
    manifestId = 930,
    location = { type = 'YARD_SLOT', ref = 'C-14-03-2', transform = { x = 10.0, y = 5.0, z = 1.0, heading = 90.0 } },
    customs = { status = 'PENDING', riskScore = 42 },
    condition = 100,
    sealStatus = 'INTACT'
})
assert(Result.isOk(created), 'valid container was rejected')
assert(created.data.status == 'EXPECTED' and created.data.version == 1, 'container defaults are invalid')
assert(created.data.cargo.reefer == false and created.data.customs.riskScore == 42, 'container metadata was not normalized')
assert(created.data.vesselCallId == '518' and created.data.manifestId == '930', 'container references were not normalized')

local invalidNumber = Container.new({ containerNumber = 'bad', isoType = '40GP' })
assert(Result.isErr(invalidNumber) and invalidNumber.error.code == 'CONTAINER_INVALID', 'invalid ISO number was accepted')
local invalidType = Container.new({ containerNumber = 'MSCU1234567', isoType = '10GP' })
assert(Result.isErr(invalidType) and invalidType.error.code == 'CONTAINER_INVALID', 'unsupported ISO type was accepted')

local dto = Container.toDTO(created.data)
dto.cargo.category = 'mutated'
assert(created.data.cargo.category == 'consumer_electronics', 'container DTO leaked mutable domain state')
assert(dto.id == 'ctr-001' and dto.containerNumber == 'MSCU1234567', 'safe container DTO is incomplete')

print('container_domain_contract: PASS')
