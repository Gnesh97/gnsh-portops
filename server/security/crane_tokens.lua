PortOps = PortOps or {}; PortOps.Security = PortOps.Security or {}
local Tokens = {}; Tokens.__index = Tokens
function Tokens.new(options) options=options or {}; return setmetatable({clock=options.clock or function() return math.floor(os.time()*1000) end, ttlMs=options.ttlMs or 5000, records={},sequence=0},Tokens) end
function Tokens:issue(sessionId, moveId, containerId, action)
    if type(sessionId)~='string' or type(moveId)~='string' or type(containerId)~='string' or type(action)~='string' then return nil,'TOKEN_INPUT_INVALID' end
    self.sequence=self.sequence+1
    local entropy=type(GetRandomIntInRange)=='function' and ('%08x'):format(GetRandomIntInRange(0,0x7fffffff)) or ('%08x'):format(math.random(0,0x7fffffff))
    local token=('ct-%s-%d-%d'):format(entropy,self.clock(),self.sequence); self.records[token]={sessionId=sessionId,moveId=moveId,containerId=containerId,action=action,expiresAt=self.clock()+self.ttlMs}; return token
end
function Tokens:consume(token, sessionId, moveId, containerId, action)
    local r=self.records[token]; if not r then return false,'TOKEN_INVALID' end
    if r.expiresAt<self.clock() then self.records[token]=nil; return false,'TOKEN_EXPIRED' end
    if r.sessionId~=sessionId or r.moveId~=moveId or r.containerId~=containerId or r.action~=action then return false,'TOKEN_BINDING_INVALID' end
    self.records[token]=nil
    return true,r
end
PortOps.Security.CraneTokens=Tokens; return Tokens
