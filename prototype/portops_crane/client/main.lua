-- S01 / PORT-010: standalone prototype bootstrap and debug commands.
-- No QBCore, Qbox, ESX, server event, or production resource is loaded here.

PortOpsCrane = PortOpsCrane or {}

local Config = PortOpsCrane.Config
local Rig = PortOpsCrane.Rig
local crane = Rig.New(Config.profile)
PortOpsCrane.ActiveRig = crane
local lastAlignmentResult
local lastAlignmentAt = 0

local function notify(message)
    print(('[PortOpsCrane] %s'):format(message))
end

local function spreaderDescriptor()
    return {
        entity = Rig.GetSpreaderEntity(crane),
        position = Rig.GetSpreaderPosition(crane),
        heading = Rig.GetSpreaderHeading(crane)
    }
end

local function command(name, handler)
    RegisterCommand(('%s_%s'):format(Config.commandPrefix, name), function(_, args)
        local ok, result = handler(args or {})
        if ok == false then
            notify(result or 'command failed')
        elseif result then
            notify(result)
        end
    end, false)
end

command('spawn', function()
    local ok, errorMessage = Rig.Spawn(crane)
    return ok, ok and 'rig spawned' or errorMessage
end)

command('despawn', function()
    PortOpsCrane.Attachment.DetachAll()
    PortOpsCrane.Cameras.Stop()
    PortOpsCrane.Controller.Stop()
    Rig.Destroy(crane)
    return true, 'rig despawned'
end)

command('reset', function()
    PortOpsCrane.Controller.ResetMotion()
    Rig.SetState(crane, { gantry = 0.5, trolley = 0.5, spreader = 0.5, yaw = 0.5 })
    return true, 'rig state reset'
end)

command('state', function()
    local state = Rig.GetState(crane)
    return true, ('state gantry=%.3f trolley=%.3f spreader=%.3f yaw=%.3f attached=%d'):format(
        state.gantry, state.trolley, state.spreader, state.yaw or 0.0, PortOpsCrane.Attachment.Count()
    )
end)

command('attach', function(args)
    local descriptor = spreaderDescriptor()
    if not descriptor.entity then return false, 'spreader is not spawned' end
    local attached, reason = PortOpsCrane.Attachment.AttachNearest(descriptor, Config.profile, {
        radiusM = tonumber(args[1]) or 8.0,
        model = Config.profile.models and Config.profile.models.container,
        target = args[2] or 'top'
    })
    return attached, attached and 'nearest candidate attached' or reason
end)

command('detach', function(args)
    local entity = PortOpsCrane.Attachment.GetFirst()
    if not entity then return false, 'no attached container' end
    local target = args[1]
    local detached, reason
    if target and target ~= '' then
        detached, reason = PortOpsCrane.Attachment.DetachTarget(entity, target)
    else
        detached, reason = PortOpsCrane.Attachment.Detach(entity)
    end
    return detached, reason
end)

command('cycles', function(args)
    local descriptor = spreaderDescriptor()
    if not descriptor.entity then return false, 'spreader is not spawned' end
    local candidate = PortOpsCrane.Alignment.FindNearestCandidate(descriptor, Config.profile, {
        radiusM = tonumber(args[1]) or 8.0,
        model = Config.profile.models and Config.profile.models.container
    })
    if not candidate then return false, 'no candidate in cycle radius' end
    local report = PortOpsCrane.Attachment.RunCycleHarness(descriptor, candidate, Config.profile, tonumber(args[2]) or 10)
    return report.pass, ('cycles %d/%d'):format(report.passed, report.requested)
end)

command('camera', function(args)
    local mode = args[1]
    if mode then
        return PortOpsCrane.Cameras.Start(mode), mode
    end
    return PortOpsCrane.Cameras.Start(), 'camera started'
end)

if Config.profile.spawn and Config.profile.spawn.enabled then
    local ok, errorMessage = Rig.Spawn(crane)
    if not ok then notify(errorMessage) end
end

PortOpsCrane.Controller.Start()

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    PortOpsCrane.Attachment.DetachAll()
    PortOpsCrane.Cameras.Stop()
    PortOpsCrane.Controller.Stop()
    Rig.Destroy(crane)
end)

CreateThread(function()
    while true do
        if PortOpsCrane.Controller.IsDebugEnabled() then
            local now = GetGameTimer()
            if now - lastAlignmentAt >= 100 then
                local descriptor = spreaderDescriptor()
                lastAlignmentResult = PortOpsCrane.Alignment.FindNearestCandidate(descriptor, Config.profile, {
                    radiusM = 8.0,
                    model = Config.profile.models and Config.profile.models.container
                })
                lastAlignmentAt = now
            end
            PortOpsCrane.Alignment.DebugOverlay(lastAlignmentResult)
        end
        Wait(0)
    end
end)

CreateThread(function()
    if Config.debug then
        notify(('standalone prototype ready (%s); use /%s_spawn'):format(
            Config.profile.id, Config.commandPrefix
        ))
    end
end)
