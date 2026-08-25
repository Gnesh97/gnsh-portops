PortOps=PortOps or {}; PortOps.Client=PortOps.Client or {}; local Result=PortOps.Core and PortOps.Core.Result
local Streaming={}; Streaming.__index=Streaming
function Streaming.new(options) options=options or {}; return setmetatable({visuals=options.visuals, getPlayerPosition=options.getPlayerPosition or function() return nil end, request=options.request, enterRadius=options.enterRadius or 90, leaveRadius=options.leaveRadius or 110, active=false, requestId=0, lastRequest=0, interval=options.requestIntervalMs or 1000},Streaming) end
local function dist(a,b) local x=a.x-b.x; local y=a.y-b.y; return math.sqrt(x*x+y*y) end
function Streaming:update(now)
    local p=self.getPlayerPosition(); if type(p)~='table' then return Result.err('STREAM_POSITION_INVALID','player position is unavailable') end
    local d=self.active and dist(p,self.center or p) or 0
    if self.active and d>self.leaveRadius then self.active=false; self.center=nil; if self.visuals then self.visuals:reconcile({}) end end
    if not self.active and (self.requestId == 0 or now-self.lastRequest>=self.interval) then self.active=true; self.center={x=p.x,y=p.y}; self.requestId=self.requestId+1; self.lastRequest=now; if self.request then local result=self.request(p,{radius=self.enterRadius,requestId=self.requestId}); if result and result.ok then self:receive(result.data,result.meta and result.meta.requestId or self.requestId) end end end
    return Result.ok({active=self.active,requestId=self.requestId})
end
function Streaming:receive(descriptors,requestId) if requestId and requestId~=self.requestId then return Result.err('STREAM_STALE_RESPONSE','stale yard stream response') end; if self.visuals then return self.visuals:reconcile(descriptors or {}) end; return Result.ok({}) end
function Streaming:stop() self.active=false; self.center=nil; if self.visuals then self.visuals:reconcile({}) end; return Result.ok(true) end
PortOps.Client.YardStreaming=Streaming; return Streaming
