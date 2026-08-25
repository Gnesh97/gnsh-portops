PortOps = PortOps or {}; PortOps.Services=PortOps.Services or {}; local Result=PortOps.Core.Result
local Placement={}; Placement.__index=Placement
local function metrics(physical, canonical)
    local p=physical and (physical.position or physical); local c=canonical.transform or canonical
    if type(p)~='table' or type(c)~='table' or type(p.x)~='number' or type(p.y)~='number' or type(p.z)~='number' then return nil end
    local dx=p.x-c.x; local dy=p.y-c.y; local dz=p.z-c.z; local heading=physical.heading or 0
    return {distance=math.sqrt(dx*dx+dy*dy+dz*dz),vertical=math.abs(dz),heading=math.abs(((heading-(c.heading or 0)+180)%360)-180)}
end
function Placement.new(options) options=options or {}; return setmetatable({yard=options.yardService, containers=options.containerRepository, containerService=options.containerService, clock=options.clock, limits=options.limits},Placement) end
function Placement:place(containerId,slotId,physical,ownerId,expectedVersion,expectedSlotVersion)
    if type(expectedVersion)~='number' or expectedVersion<1 or expectedVersion%1~=0 then return Result.err('CONTAINER_VERSION_INVALID','container version is required') end
    local c=self.containers:getById(containerId); if Result.isErr(c) then return c end
    local slot=self.yard:get(slotId); if Result.isErr(slot) then return slot end
    local measured=metrics(physical,slot.data)
    if not measured then return Result.err('SNAP_INVALID','physical transform is invalid') end
    local limits=self.limits or {}; if measured.distance>(limits.distance or 1.5) or measured.vertical>(limits.vertical or .5) or measured.heading>(limits.heading or 5.0) then return Result.err('SNAP_OUT_OF_TOLERANCE','physical placement is outside snap tolerances') end
    local occupied=self.yard:occupy(c.data,slotId,ownerId,expectedSlotVersion); if Result.isErr(occupied) then return occupied end
    local location={type='YARD_SLOT',ref=slotId,transform=slot.data.transform}
    local result
    if self.containerService then
        result=self.containerService:transition(containerId,'AT_YARD',expectedVersion,{location=location})
    else
        local candidate=self.containers and self.containers.getById and self.containers:getById(containerId)
        if not candidate or Result.isErr(candidate) then self.yard:unoccupy(slotId,c.data.id); return candidate or Result.err('CONTAINER_NOT_FOUND','container was not found') end
        candidate=candidate.data; candidate.location=location; candidate.status='AT_YARD'; candidate.version=expectedVersion+1
        result=self.containers:update(candidate,expectedVersion)
    end
    if Result.isErr(result) then self.yard:unoccupy(slotId,c.data.id); return result end
    return Result.ok({container=result.data,slot=occupied.data})
end
PortOps.Services.Placement=Placement; return Placement
