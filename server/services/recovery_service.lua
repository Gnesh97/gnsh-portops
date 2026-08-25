PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result = PortOps.Core.Result
local Recovery = {}; Recovery.__index = Recovery

function Recovery.new(options)
    options = options or {}
    return setmetatable({ containers = options.containers, yard = options.yard, moves = options.moves, clock = options.clock }, Recovery)
end

local function appendRecords(records, result, mapper)
    if Result.isErr(result) then return result end
    for _, value in ipairs(result.data or {}) do records[#records + 1] = mapper(value) end
    return Result.ok(true)
end

function Recovery:restore(records)
    records = records or {}
    if type(records) ~= 'table' then return Result.err('RECOVERY_INVALID', 'records are required') end
    if #records == 0 then
        if self.containers and type(self.containers.list) == 'function' then
            local result = appendRecords(records, self.containers:list({}, { limit = 500 }), function(container)
                local location = container.location or {}
                return { id = 'container:' .. tostring(container.id), containerId = container.id, slotId = location.type == 'YARD_SLOT' and location.ref or nil, status = container.status }
            end)
            if Result.isErr(result) then return result end
        end
        if self.moves and type(self.moves.list) == 'function' then
            local result = appendRecords(records, self.moves:list({}, { limit = 500 }), function(move)
                return { id = 'move:' .. tostring(move.id), moveId = move.id, containerId = move.containerId, status = move.status, steps = move.steps, reservations = move.reservations }
            end)
            if Result.isErr(result) then return result end
        end
    end
    local restored, warnings = 0, {}
    for _, record in ipairs(records) do
        if type(record) ~= 'table' or type(record.id) ~= 'string' then
            warnings[#warnings + 1] = 'record-invalid'
        else
            restored = restored + 1
            if record.containerId and self.containers then
                local container = self.containers:get(record.containerId)
                if Result.isErr(container) then warnings[#warnings + 1] = 'container-missing:' .. record.containerId end
                if Result.isOk(container) and record.status == 'COMPLETED' and container.data.status == 'RECOVERY_REQUIRED' then
                    warnings[#warnings + 1] = 'completed-move-recovery-container:' .. record.containerId
                end
            end
            if record.slotId and self.yard then
                local slot = self.yard:get(record.slotId)
                if Result.isErr(slot) then
                    warnings[#warnings + 1] = 'slot-missing:' .. record.slotId
                elseif record.containerId and (record.status == 'AT_YARD' or record.status == 'YARD_RECEIVING') then
                    local occupied = self.yard:restoreOccupancy(record.slotId, record.containerId)
                    if Result.isErr(occupied) and occupied.error.code ~= 'SLOT_UNAVAILABLE' then warnings[#warnings + 1] = 'slot-restore:' .. record.slotId end
                end
            end
            if record.moveId then
                for _, step in ipairs(record.steps or {}) do
                    if step.status == 'CLAIMED' or step.status == 'IN_PROGRESS' then warnings[#warnings + 1] = 'active-step:' .. tostring(step.id) end
                end
                for slotId in pairs(record.reservations or {}) do
                    if self.yard and Result.isErr(self.yard:get(slotId)) then warnings[#warnings + 1] = 'move-reservation-slot-missing:' .. tostring(slotId) end
                end
                if record.status == 'IN_PROGRESS' or record.status == 'BLOCKED' or record.status == 'RECOVERY_REQUIRED' then
                    warnings[#warnings + 1] = 'move-requires-reconciliation:' .. tostring(record.moveId)
                end
            end
        end
    end
    return Result.ok({ restored = restored, coherent = #warnings == 0, requiresRecovery = #warnings > 0, warnings = warnings })
end

PortOps.Services.Recovery = Recovery
return Recovery
