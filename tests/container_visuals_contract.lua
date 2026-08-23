-- Offline contract for logical-container to visual-prop separation.
PortOps = {}
dofile('client/containers/visuals.lua')

local Visuals = PortOps.Client.ContainerVisuals
local created, deleted, metadata = {}, {}, {}
local nextEntity = 100
local visuals = Visuals.new({
    createObject = function(model, transform)
        nextEntity = nextEntity + 1
        created[#created + 1] = { model = model, transform = transform }
        return nextEntity
    end,
    deleteEntity = function(entity) deleted[#deleted + 1] = entity end,
    setTransform = function(entity, transform) metadata['transform:' .. entity] = transform end,
    setMetadata = function(entity, value) metadata[entity] = value end
})

local descriptor = { id = 'ctr-001', isoType = '40GP', version = 4, transform = { x = 1, y = 2, z = 3, heading = 90 } }
local spawned = visuals:spawn(descriptor)
assert(spawned.ok and spawned.data.entity and created[1].model == 'container_40gp', 'container visual spawn failed')
assert(metadata[spawned.data.entity].containerId == 'ctr-001' and metadata[spawned.data.entity].version == 4, 'visual metadata was not bound')
assert(visuals:updateTransform('ctr-001', { x = 4, y = 5, z = 6, heading = 180 }).ok, 'visual transform update failed')

local reconciled = visuals:reconcile({ { id = 'ctr-002', isoType = '20GP', version = 1, transform = { x = 0, y = 0, z = 0 } } })
assert(reconciled.ok and reconciled.data.spawned == 1 and reconciled.data.despawned == 1, 'visual reconcile did not use nearby descriptors')
assert(#deleted == 1, 'visual despawn did not delete stale entity')
assert(visuals:despawn('ctr-002').ok, 'visual despawn was not idempotent')

print('container_visuals_contract: PASS')
