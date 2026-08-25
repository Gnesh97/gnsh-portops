PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result=PortOps.Core.Result; local Recovery={}; Recovery.__index=Recovery
function Recovery.new(o) o=o or {}; return setmetatable({containers=o.containers,yard=o.yard,moves=o.moves,clock=o.clock},Recovery) end
function Recovery:restore(records)
    if type(records)~='table' then return Result.err('RECOVERY_INVALID','records are required') end
    local restored=0; local warnings={}
    for _,record in ipairs(records) do
        if type(record)~='table' or type(record.id)~='string' then warnings[#warnings+1]='record-invalid'
        else
            restored=restored+1
            if record.containerId and self.containers and not self.containers:get(record.containerId).ok then warnings[#warnings+1]='container-missing:'..record.containerId end
            if record.slotId and self.yard and not self.yard:get(record.slotId).ok then warnings[#warnings+1]='slot-missing:'..record.slotId end
        end
    end
    return Result.ok({restored=restored,coherent=#warnings==0,warnings=warnings})
end
PortOps.Services.Recovery=Recovery; return Recovery
