-- S01 / PORT-013: local camera modes.
-- Camera state is presentation-only and never mutates the rig state.

PortOpsCrane = PortOpsCrane or {}
PortOpsCrane.Cameras = PortOpsCrane.Cameras or {}

local Cameras = PortOpsCrane.Cameras
local active = false
local currentMode = 'default'
local camera = nil
local modes = { 'default', 'cabin', 'top', 'spreader', 'side' }

local function cameraControl()
    local shared = PortOpsCrane.Config or {}
    return (shared.Controls and shared.Controls.cameraNext) or 244
end

local function activeRig()
    return PortOpsCrane.ActiveRig
end

local function transform()
    local rig = activeRig()
    if not rig or not PortOpsCrane.Rig.GetWorldTransform then return nil end
    return PortOpsCrane.Rig.GetWorldTransform(rig)
end

local function isMode(mode)
    for _, candidate in ipairs(modes) do
        if candidate == mode then return true end
    end
    return false
end

local function offsetFor(mode)
    local shared = PortOpsCrane.Config or {}
    local configured = shared.Cameras and shared.Cameras[mode]
    if configured then return configured end
    return { x = 0.0, y = -8.0, z = 4.0, fov = 55.0 }
end

local function destroy()
    if camera and DoesCamExist(camera) then DestroyCam(camera, false) end
    camera = nil
end

local function update()
    if not active or not camera then return end
    local position, target, axes = transform()
    if not position or not target then return end
    local offset = offsetFor(currentMode)
    local xAxis = axes and axes.gantry or vector3(1.0, 0.0, 0.0)
    local yAxis = axes and axes.trolley or vector3(0.0, 1.0, 0.0)
    local zAxis = axes and axes.spreader or vector3(0.0, 0.0, 1.0)
    local cameraPosition = position
        + xAxis * (offset.x or 0.0)
        + yAxis * (offset.y or 0.0)
        + zAxis * (offset.z or 0.0)
    SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(camera, target.x, target.y, target.z)
    SetCamFov(camera, offset.fov or 55.0)
end

function Cameras.SetMode(mode)
    if not isMode(mode) then return false end
    currentMode = mode
    if active then update() end
    return true
end

function Cameras.NextMode()
    local index = 1
    for i, mode in ipairs(modes) do
        if mode == currentMode then index = i; break end
    end
    index = (index % #modes) + 1
    Cameras.SetMode(modes[index])
    return currentMode
end

function Cameras.Start(mode)
    if active then
        if mode then return Cameras.SetMode(mode) end
        return true
    end
    if mode and not isMode(mode) then return false end
    if not transform() or not CreateCam then return false end
    currentMode = mode or 'default'
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not camera then return false end
    active = true
    RenderScriptCams(true, true, 250, true, true)
    update()
    return true
end

function Cameras.Stop()
    if not active and not camera then return end
    active = false
    RenderScriptCams(false, true, 250, true, true)
    destroy()
    currentMode = 'default'
end

function Cameras.IsActive() return active end
function Cameras.GetMode() return currentMode end

if RegisterCommand then
    local prefix = (PortOpsCrane.Config and PortOpsCrane.Config.commandPrefix) or 'portops_crane'
    RegisterCommand(('%s_camera'):format(prefix), function(_, args)
        if args and args[1] then
            Cameras.SetMode(args[1])
        else
            Cameras.NextMode()
        end
    end, false)
end

if AddEventHandler then
    AddEventHandler('onClientResourceStop', function(resourceName)
        if resourceName == GetCurrentResourceName() then Cameras.Stop() end
    end)
end

if CreateThread then
    CreateThread(function()
        while true do
            if active then
                update()
                if IsControlJustPressed(0, cameraControl()) then Cameras.NextMode() end
            end
            Wait(0)
        end
    end)
end
