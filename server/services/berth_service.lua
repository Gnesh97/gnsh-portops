PortOps = PortOps or {}; PortOps.Services=PortOps.Services or {}; local Result=PortOps.Core.Result; local S={}; S.__index=S
function S.new(o) return setmetatable({slots=o and o.slots or {},assignments={}},S) end
local function overlaps(a,b) return a and b and tonumber(a.start or a.windowStart or a[1]) and tonumber(b.start or b.windowStart or b[1]) and (tonumber(a.start or a.windowStart or a[1]) < tonumber(b.finish or b.windowEnd or b[2])) and (tonumber(b.start or b.windowStart or b[1]) < tonumber(a.finish or a.windowEnd or a[2])) end
function S:reserve(berthId,callId,window,vesselType,craneId)
    local slot; for _,candidate in ipairs(self.slots or {}) do if candidate.id==berthId then slot=candidate end end
    if not slot and #(self.slots or {}) > 0 then return Result.err('BERTH_NOT_FOUND','berth is not configured') end
    if vesselType and slot.compatibleVesselTypes and not slot.compatibleVesselTypes[vesselType] then return Result.err('BERTH_INCOMPATIBLE','vessel type is not compatible') end
    if craneId and slot.craneIds and not slot.craneIds[craneId] then return Result.err('BERTH_CRANE_UNAVAILABLE','crane coverage is unavailable') end
    local current=self.assignments[berthId] or {}
    if current.callId then current={current} end
    for _, assignment in ipairs(current) do if not window or not assignment.window or overlaps(assignment.window,window) then return Result.err('BERTH_CONFLICT','berth window overlaps an existing assignment') end end
    local created={berthId=berthId,callId=callId,window=window}; current[#current+1]=created; self.assignments[berthId]=current; return Result.ok(created)
end
function S:release(berthId,callId) local list=self.assignments[berthId]; if not list then return Result.err('BERTH_NOT_FOUND','assignment not found') end; if list.callId then list={list} end; local kept={}; local released=false; for _,a in ipairs(list) do if not callId or a.callId==callId then released=true else kept[#kept+1]=a end end; if not released then return Result.err('BERTH_OWNER_INVALID','call does not own berth') end; self.assignments[berthId]=#kept>0 and kept or nil; return Result.ok({released=true,berthId=berthId}) end
PortOps.Services.Berth=S; return S
