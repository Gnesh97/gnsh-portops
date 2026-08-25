PortOps={}; dofile('shared/errors.lua'); dofile('server/core/result.lua'); dofile('client/yard/streaming.lua')
local R=PortOps.Core.Result; local p={x=0,y=0,z=0}; local requests=0; local visuals={count=0,reconcile=function(self,v) self.count=#v; return R.ok(true) end}
local stream=PortOps.Client.YardStreaming.new({visuals=visuals,getPlayerPosition=function() return p end,requestIntervalMs=1000,request=function() requests=requests+1; return R.ok({{id='C-1'}}) end})
assert(R.isOk(stream:update(0)) and requests==1 and visuals.count==1,'yard stream did not enter block')
p={x=1000,y=0,z=0}; assert(R.isOk(stream:update(100)) and visuals.count==0,'yard stream did not unload block')
p={x=0,y=0,z=0}; assert(R.isOk(stream:update(1000)) and requests==2,'yard stream did not re-enter block')
assert(R.isErr(stream:receive({{id='stale'}},1)),'stale yard response accepted')
print('yard_streaming_contract: PASS')
