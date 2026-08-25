PortOps={}; dofile('shared/errors.lua'); dofile('server/core/result.lua'); dofile('config/yard.lua'); dofile('server/domain/yard.lua'); dofile('server/core/reservations.lua'); dofile('server/repositories/yard_repository.lua'); dofile('server/services/yard_service.lua')
local R=PortOps.Core.Result; local cfg=PortOps.Config.yard
assert(R.isOk(PortOps.Domain.Yard.validateConfig(cfg)),'yard config invalid')
local repo=PortOps.Repositories.Yard.new({config=cfg,clock=function() return 0 end})
local svc=PortOps.Services.Yard.new({repository=repo})
local c={id='ctr-1',isoType='40GP',cargo={reefer=false}}
local a=svc:reserve(c,'C-14-03-1','move-a',10000); assert(R.isOk(a),'first reservation failed')
local b=svc:reserve(c,'C-14-03-1','move-b',10000); assert(R.isErr(b) and b.error.code=='SLOT_RESERVED','two moves reserved one slot')
assert(R.isErr(svc:reserve({id='r',isoType='20RF',cargo={reefer=true}},'C-14-03-1','r','10000')),'reefer accepted in general zone')
assert(R.isOk(svc:occupy(c,'C-14-03-1','move-a')),'reservation owner could not occupy')
assert(R.isErr(svc:reserve(c,'C-14-03-1','move-c',10000)),'occupied slot was reservable')
print('yard_contract: PASS')
