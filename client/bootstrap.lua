-- Client production entrypoint.  Visual rig/controls are intentionally not
-- mixed into authority code; this client only consumes canonical snapshots.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}
PortOps.Client = PortOps.Client or {}
PortOps.Client.observers = PortOps.Client.observers or {}
PortOps.Client.ready = true
PortOps.Client.session = nil
PortOps.Client.actionToken = nil
PortOps.Client.clockOffsetMs = 0
PortOps.Client.clockOffsetKnown = false
PortOps.Client.sequences = PortOps.Client.sequences or {}

local ClientSync = PortOps.Crane.ClientSync

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.time() * 1000)
end

local function serverNowMs()
    return nowMs() + (PortOps.Client.clockOffsetMs or 0)
end

local function defaultCraneId()
    return (PortOps.Config and PortOps.Config.defaults and PortOps.Config.defaults.craneId) or 'qc-01'
end

local function printClient(message)
    if type(print) == 'function' then print('[PortOps] ' .. tostring(message)) end
end

local function localizeSnapshot(snapshot)
    if type(snapshot) ~= 'table' then return snapshot end
    local localized = {}
    for key, value in pairs(snapshot) do
        if key == 'state' and type(value) == 'table' then
            local state = {}
            for stateKey, stateValue in pairs(value) do state[stateKey] = stateValue end
            localized.state = state
        else
            localized[key] = value
        end
    end
    if type(localized.timestamp) == 'number' then
        localized.timestamp = localized.timestamp - (PortOps.Client.clockOffsetMs or 0)
    end
    return localized
end

local function observerCount()
    local count = 0
    for _ in pairs(PortOps.Client.observers) do count = count + 1 end
    return count
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

function PortOps.Client.reserve(craneId)
    if type(TriggerServerEvent) == 'function' then TriggerServerEvent('portops:crane:reserve', craneId or defaultCraneId()) end
end

function PortOps.Client.release()
    local session = PortOps.Client.session
    if session and type(TriggerServerEvent) == 'function' then
        TriggerServerEvent('portops:crane:release', session.sessionId, session.sessionToken)
    end
end

function PortOps.Client.sendSnapshot(craneId, state)
    local session = PortOps.Client.session
    craneId = craneId or (session and session.craneId) or defaultCraneId()
    if not session or session.craneId ~= craneId then
        printClient('reserve a crane session first')
        return false
    end
    PortOps.Client.sequences[craneId] = (PortOps.Client.sequences[craneId] or 0) + 1
    state = state or { gantry = 0.5, trolley = 0.5, spreader = 1.0, yaw = 0.0 }
    if type(TriggerServerEvent) == 'function' then
        TriggerServerEvent('portops:crane:snapshot', craneId, {
            version = PortOps.Crane.Protocol.VERSION,
            sessionId = session.sessionId,
            sessionToken = session.sessionToken,
            sequence = PortOps.Client.sequences[craneId],
            timestamp = serverNowMs(),
            state = state
        })
    end
    return true
end

function PortOps.Client.issueAttach(containerId)
    local session = PortOps.Client.session
    if not session or type(TriggerServerEvent) ~= 'function' then return false end
    TriggerServerEvent('portops:crane:action:issue', session.craneId, session.sessionId, containerId or 'SMOKE-001', 'attach', session.sessionToken, containerId or 'SMOKE-001')
    return true
end

function PortOps.Client.consumeAttach(containerId)
    local session, token = PortOps.Client.session, PortOps.Client.actionToken
    if not session or not token or type(TriggerServerEvent) ~= 'function' then return false end
    TriggerServerEvent('portops:crane:action:consume', token, session.craneId, session.sessionId, containerId or 'SMOKE-001', 'attach', session.sessionToken, containerId or 'SMOKE-001')
    return true
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
    RegisterNetEvent('portops:crane:session')
    AddEventHandler('portops:crane:session', function(result)
        if result and result.ok and result.data then
            if result.data.released then
                PortOps.Client.session = nil
                PortOps.Client.actionToken = nil
                printClient('session released')
            elseif result.data.sessionToken then
                PortOps.Client.session = result.data
                if type(result.data.serverTime) == 'number' then
                    PortOps.Client.clockOffsetMs = result.data.serverTime - nowMs()
                    PortOps.Client.clockOffsetKnown = true
                end
                printClient(('session ready crane=%s id=%s'):format(tostring(result.data.craneId), tostring(result.data.sessionId)))
            end
        elseif result and result.error then
            printClient(('session rejected: %s'):format(tostring(result.error.code)))
        end
    end)
    RegisterNetEvent('portops:crane:action:result')
    AddEventHandler('portops:crane:action:result', function(result)
        if result and result.ok and result.data and result.data.token then
            PortOps.Client.actionToken = result.data.token
            printClient('attach action token issued')
        elseif result and result.ok and result.data and result.data.action then
            PortOps.Client.actionToken = nil
            printClient(('action consumed: %s'):format(tostring(result.data.action)))
        elseif result and result.error then
            printClient(('action rejected: %s'):format(tostring(result.error.code)))
        end
    end)
    RegisterNetEvent('portops:crane:canonical')
    AddEventHandler('portops:crane:canonical', function(craneId, snapshot)
        local target = observer(craneId)
        if snapshot and not PortOps.Client.clockOffsetKnown and type(snapshot.timestamp) == 'number' then
            PortOps.Client.clockOffsetMs = snapshot.timestamp - nowMs()
            PortOps.Client.clockOffsetKnown = true
        end
        local localized = localizeSnapshot(snapshot)
        if localized and localized.resync then ClientSync.clear(target) end
        local accepted = ClientSync.push(target, localized)
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

if PortOps.Config and PortOps.Config.environment == 'development' and type(RegisterCommand) == 'function' then
    RegisterCommand('portops_reserve', function(_, args) PortOps.Client.reserve(args[1] or defaultCraneId()) end, false)
    RegisterCommand('portops_release', function() PortOps.Client.release() end, false)
    RegisterCommand('portops_observe', function(_, args) PortOps.Client.observe(args[1] or defaultCraneId()) end, false)
    RegisterCommand('portops_unobserve', function(_, args) PortOps.Client.unobserve(args[1] or defaultCraneId()) end, false)
    RegisterCommand('portops_snapshot', function(_, args) PortOps.Client.sendSnapshot(args[1] or (PortOps.Client.session and PortOps.Client.session.craneId)) end, false)
    RegisterCommand('portops_issue_attach', function(_, args) PortOps.Client.issueAttach(args[1] or 'SMOKE-001') end, false)
    RegisterCommand('portops_consume_attach', function(_, args) PortOps.Client.consumeAttach(args[1] or 'SMOKE-001') end, false)
    RegisterCommand('portops_client_status', function()
        local session = PortOps.Client.session
        printClient(('ready=%s crane=%s session=%s observerCount=%s'):format(tostring(PortOps.Client.ready), tostring(session and session.craneId), tostring(session and session.sessionId), tostring(observerCount())))
    end, false)
end

if type(CreateThread) == 'function' and type(Wait) == 'function' then
    CreateThread(function()
        while PortOps.Client.ready do
            Wait(50)
            for craneId, target in pairs(PortOps.Client.observers) do ClientSync.update(target, nowMs()) end
        end
    end)
end
