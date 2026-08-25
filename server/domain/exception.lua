PortOps = PortOps or {}; PortOps.Domain = PortOps.Domain or {}
local Exception = {}; Exception.TYPES={SLOT_BLOCKED=true,CRANE_FAULT=true,TRAILER_UNAVAILABLE=true,MISROUTED=true,SEAL_BROKEN=true,DRIVER_NO_SHOW=true}
function Exception.new(input)
    input=input or {}; if not Exception.TYPES[input.type] then return nil,'EXCEPTION_TYPE_INVALID' end
    if type(input.entityId)~='string' or input.entityId=='' then return nil,'EXCEPTION_ENTITY_REQUIRED' end
    return {id=input.id or ('exc-'..tostring(os.time())..'-'..math.random(9999)), type=input.type, entityId=input.entityId, status=input.status or 'OPEN', details=input.details or {}, actorId=input.actorId, createdAt=input.createdAt or os.time()*1000}
end
PortOps.Domain.Exception=Exception; return Exception
