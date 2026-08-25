PortOps = PortOps or {}; PortOps.Client = PortOps.Client or {}
local Cameras={}; Cameras.__index=Cameras
function Cameras.new(options) return setmetatable({modes=(options and options.modes) or {'default','cabin','top','spreader','side'},active='default'},Cameras) end
function Cameras:set(mode) for _,candidate in ipairs(self.modes) do if candidate==mode then self.active=mode; return true end end; return false end
function Cameras:get() return self.active end
function Cameras:stop() self.active='default'; return true end
PortOps.Client.CraneCameras=Cameras; return Cameras
