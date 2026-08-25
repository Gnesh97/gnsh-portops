-- Canonical yard slots. Gameplay code consumes this table; no world transform is
-- hard-coded in a service or client script.
PortOps = PortOps or {}
PortOps.Config = PortOps.Config or {}

local function transform(x, y, z, heading)
    return { x = x, y = y, z = z, heading = heading or 0.0 }
end

PortOps.Config.yard = {
    id = 'yard-c',
    version = 1,
    zones = { GENERAL = true, REEFER = true, HAZMAT = true },
    slots = {
        { id = 'C-14-03-1', block = 'C', bay = 14, row = 3, tier = 1, zone = 'GENERAL', isoTypes = { ['20GP'] = true, ['40GP'] = true, ['40HC'] = true }, transform = transform(10.0, 10.0, 1.0) },
        { id = 'C-14-03-2', block = 'C', bay = 14, row = 3, tier = 2, zone = 'GENERAL', isoTypes = { ['20GP'] = true, ['40GP'] = true, ['40HC'] = true }, transform = transform(10.0, 10.0, 3.8) },
        { id = 'C-14-04-1', block = 'C', bay = 14, row = 4, tier = 1, zone = 'REEFER', isoTypes = { ['20RF'] = true, ['40RF'] = true }, transform = transform(10.0, 14.0, 1.0) },
        { id = 'C-14-05-1', block = 'C', bay = 14, row = 5, tier = 1, zone = 'HAZMAT', isoTypes = { ['20GP'] = true, ['40GP'] = true }, transform = transform(10.0, 18.0, 1.0) }
    },
    reservationTtlMs = 30000,
    interestRadius = 90.0,
    interestLeaveRadius = 110.0
}

return PortOps.Config.yard
