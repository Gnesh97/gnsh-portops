-- Server-side manifest discharge planner. It reserves a compatible yard slot
-- before creating an ordered crane, transfer, and yard move.
PortOps = PortOps or {}
PortOps.Services = PortOps.Services or {}
local Result = PortOps.Core.Result
local Planner = {}; Planner.__index = Planner

function Planner.new(options)
    options = options or {}
    return setmetatable({ manifest = options.manifestService, yard = options.yardService, moves = options.moveService, clock = options.clock }, Planner)
end

function Planner:plan(manifestId, ownerId, options)
    options = options or {}
    if type(manifestId) ~= 'string' or type(ownerId) ~= 'string' then return Result.err('DISCHARGE_INPUT_INVALID', 'manifest and owner are required') end
    local manifest = self.manifest:get(manifestId)
    if Result.isErr(manifest) then return manifest end
    local created = {}
    for _, item in ipairs(manifest.data.items or {}) do
        local container = item.container or { id = item.containerId, isoType = item.isoType or '40GP', cargo = item.cargo or {} }
        local slots = self.yard:list({ block = options.block, zone = options.zone })
        if Result.isErr(slots) then return slots end
        local selected
        for _, slot in ipairs(slots.data) do
            local compatible = self.yard:compatible(container, slot)
            if Result.isOk(compatible) and slot.state == 'AVAILABLE' then selected = slot; break end
        end
        if not selected then return Result.err('YARD_CAPACITY_UNAVAILABLE', 'no compatible yard slot is available', { containerId = item.containerId }) end
        local reservation = self.yard:reserve(container, selected.id, ownerId, options.ttlMs)
        if Result.isErr(reservation) then return reservation end
        local move = self.moves:create({
            idempotencyKey = ('discharge:%s:%s'):format(manifestId, item.containerId),
            moveNumber = item.moveNumber,
            containerId = item.containerId,
            from = { type = 'VESSEL', ref = manifest.data.vesselCallId },
            to = { type = 'YARD_SLOT', ref = selected.id, transform = selected.transform },
            reservations = { yard = { slotId = selected.id, token = reservation.meta and reservation.meta.token } },
            steps = {
                { id = 'crane-' .. item.containerId, kind = 'CRANE' },
                { id = 'transfer-' .. item.containerId, kind = 'TRANSFER' },
                { id = 'yard-' .. item.containerId, kind = 'YARD' }
            }
        })
        if Result.isErr(move) then self.yard:release(selected.id, ownerId); return move end
        created[#created + 1] = move.data
    end
    return Result.ok(created)
end

PortOps.Services.DischargePlanning = Planner
return Planner
