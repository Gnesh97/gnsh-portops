PortOps = PortOps or {}; PortOps.Services = PortOps.Services or {}
local Result=PortOps.Core.Result; local Service={}; Service.__index=Service
function Service.new(o) o=o or {}; return setmetatable({sessions=o.sessions, tokens=o.tokens, moves=o.moves, containers=o.containers, clock=o.clock or function() return math.floor(os.time()*1000) end},Service) end
function Service:bind(sessionId, moveId, containerId, craneId)
    if not self.sessions or not self.sessions:get(sessionId) then return Result.err('SESSION_INVALID','session is invalid') end
    if type(moveId)~='string' or type(containerId)~='string' or type(craneId)~='string' then return Result.err('CRANE_BINDING_INVALID','binding is invalid') end
    return Result.ok({sessionId=sessionId,moveId=moveId,containerId=containerId,craneId=craneId})
end
function Service:issueAction(binding, action)
    if type(binding)~='table' then return Result.err('CRANE_BINDING_INVALID','binding is required') end
    local token,reason=self.tokens:issue(binding.sessionId,binding.moveId,binding.containerId,action); if not token then return Result.err(reason,'action token rejected') end
    return Result.ok({token=token,expiresAt=self.clock()+self.tokens.ttlMs})
end
function Service:consumeAction(binding, token, action)
    local ok,record=self.tokens:consume(token,binding.sessionId,binding.moveId,binding.containerId,action); if not ok then return Result.err(record,'action token rejected') end
    return Result.ok(record)
end
PortOps.Services.Crane=Service; return Service
