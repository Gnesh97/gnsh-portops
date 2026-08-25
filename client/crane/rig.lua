-- Production clean-room rig model. It contains no prototype imports and only
-- applies profile-defined transforms to a canonical normalized state.
PortOps = PortOps or {}
PortOps.Client = PortOps.Client or {}
local Rig = {}; Rig.__index = Rig
local function clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
function Rig.new(profile)
    return setmetatable({ profile = profile, state = { gantry = 0, trolley = 0, spreader = 0, yaw = 0 } }, Rig)
end
function Rig:setState(nextState)
    local p = self.profile; if type(p) ~= 'table' then return false end
    self.state = {
        gantry = clamp(tonumber(nextState.gantry) or self.state.gantry, 0, 1),
        trolley = clamp(tonumber(nextState.trolley) or self.state.trolley, 0, 1),
        spreader = clamp(tonumber(nextState.spreader) or self.state.spreader, 0, 1),
        yaw = clamp(tonumber(nextState.yaw) or self.state.yaw, -1, 1)
    }
    return true
end
function Rig:getState() local out={}; for k,v in pairs(self.state) do out[k]=v end; return out end
function Rig:worldTransform()
    local p=self.profile; local s=self.state; local origin=p.origin or {x=0,y=0,z=0}
    local function axisValue(axis, minimum, maximum, value) local span=(maximum or 0)-(minimum or 0); return (axis or 0)*((minimum or 0)+span*value) end
    return { x=origin.x+axisValue(p.gantry.axis.x,p.gantry.min,p.gantry.max,s.gantry)+axisValue(p.trolley.axis.x,p.trolley.min,p.trolley.max,s.trolley), y=origin.y+axisValue(p.gantry.axis.y,p.gantry.min,p.gantry.max,s.gantry)+axisValue(p.trolley.axis.y,p.trolley.min,p.trolley.max,s.trolley), z=origin.z+axisValue(p.spreader.axis.z,p.spreader.min,p.spreader.max,s.spreader), heading=(p.heading or 0)+(p.yaw.min or -180)+(p.yaw.max-(p.yaw.min or -180))*((s.yaw+1)/2) }
end
PortOps.Client.CraneRig = Rig
return Rig
