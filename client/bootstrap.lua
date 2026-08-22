-- Client production entrypoint.  Visual rig/controls are intentionally not
-- mixed into authority code; this client only consumes canonical snapshots.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Client = PortOps.Client or {}
PortOps.Client.observers = PortOps.Client.observers or {}
PortOps.Client.ready = true

local ClientSync = PortOps.Crane.ClientSync

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function observer(craneId)
    if not PortOps.Client.observers[craneId] then
        PortOps.Client.observers[craneId] = ClientSync.new({
            interpolationDelayMs = (PortOps.Config and PortOps.Config.crane.interpolationDelayMs) or 100,
            bufferSize = (PortOps.Config and PortOps.Config.crane.observerBufferSize) or 12
        })
    end
    return PortOps.Client.observers[craneId]
end

function PortOps.Client.observe(craneId)
    observer(craneId)
    if type(TriggerServerEvent) == 'function' then TriggerServerEvent('portops:crane:observe', craneId) end
end

function PortOps.Client.unobserve(craneId)
    PortOps.Client.observers[craneId] = nil
    if type(TriggerServerEvent) == 'function' then TriggerServerEvent('portops:crane:unobserve', craneId) end
end

function PortOps.Client.sample(craneId, timestamp)
    local target = PortOps.Client.observers[craneId]
    if not target then return nil end
    return ClientSync.update(target, timestamp or nowMs())
end

if type(RegisterNetEvent) == 'function' and type(AddEventHandler) == 'function' then
    RegisterNetEvent('portops:crane:canonical')
    AddEventHandler('portops:crane:canonical', function(craneId, snapshot)
        local target = observer(craneId)
        if snapshot and snapshot.resync then ClientSync.clear(target) end
        local accepted = ClientSync.push(target, snapshot)
        if accepted then target.recovery = false
        elseif type(TriggerServerEvent) == 'function' then TriggerServerEvent('portops:crane:observe', craneId) end
    end)
    RegisterNetEvent('portops:crane:recovery_required')
    AddEventHandler('portops:crane:recovery_required', function(craneId, marker)
        local target = PortOps.Client.observers[craneId]
        if target then ClientSync.clear(target); target.recovery = marker or true end
    end)
    RegisterNetEvent('portops:resource:state')
    AddEventHandler('portops:resource:state', function(state) PortOps.Client.resourceState = state end)
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then
            for craneId in pairs(PortOps.Client.observers) do PortOps.Client.unobserve(craneId) end
        end
    end)
end

if type(CreateThread) == 'function' and type(Wait) == 'function' then
    CreateThread(function()
        while PortOps.Client.ready do
            Wait(50)
            for craneId, target in pairs(PortOps.Client.observers) do ClientSync.update(target, nowMs()) end
        end
    end)
end
