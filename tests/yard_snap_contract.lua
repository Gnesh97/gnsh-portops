PortOps={}; dofile('shared/errors.lua'); dofile('server/core/result.lua'); dofile('client/yard/snap.lua')
local R=PortOps.Core.Result; local slot={id='C-1',transform={x=10,y=10,z=1,heading=90}}
local good=PortOps.Client.YardSnap.metrics({position={x=10.2,y=10,z=1.1},heading=92},slot); assert(R.isOk(good) and PortOps.Client.YardSnap.accept(good.data,{distance=1,vertical=.5,heading=5}),'valid snap rejected')
local bad=PortOps.Client.YardSnap.metrics({position={x=14,y=10,z=1},heading=120},slot); assert(not PortOps.Client.YardSnap.accept(bad.data,{distance=1,vertical=.5,heading=5}),'wrong distance accepted')
print('yard_snap_contract: PASS')
