PortOps = PortOps or {}; PortOps.Client=PortOps.Client or {}; local Result=PortOps.Core and PortOps.Core.Result
local Snap={}
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
function Snap.metrics(physical, canonical)
    if type(physical)~='table' or type(canonical)~='table' then return Result.err('SNAP_INVALID','positions are required') end
    local p=physical.position or physical; local t=physical.heading or 0; local c=canonical.transform or canonical
    if not finite(p.x) or not finite(p.y) or not finite(p.z) or not finite(t) then return Result.err('SNAP_INVALID','physical transform is invalid') end
    local dx=p.x-c.x; local dy=p.y-c.y; local dz=p.z-c.z; local dh=math.abs(((t-(c.heading or 0)+180)%360)-180)
    return Result.ok({ distance=math.sqrt(dx*dx+dy*dy+dz*dz), vertical=math.abs(dz), heading=dh })
end
function Snap.accept(metrics, limits) limits=limits or {}; return metrics.distance <= (limits.distance or 1.5) and metrics.vertical <= (limits.vertical or .5) and metrics.heading <= (limits.heading or 5.0) end
function Snap.new(options) options=options or {}; return { limits=options.limits, request=options.request, place=function(self,slot,physical) local m=Snap.metrics(physical,slot); if Result.isErr(m) or not Snap.accept(m.data,self.limits) then return Result.err('SNAP_OUT_OF_TOLERANCE','physical placement is outside snap tolerances') end; return self.request and self.request(slot.id,m.data) or Result.ok(m.data) end } end
PortOps.Client.YardSnap=Snap; return Snap
