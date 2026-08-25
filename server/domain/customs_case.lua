PortOps = PortOps or {}; PortOps.Domain = PortOps.Domain or {}
local Case = {}; Case.__index = Case
Case.STATUSES = { OPEN=true, HOLD=true, INSPECTION=true, CLEARED=true, SEIZED=true, CLOSED=true }
function Case.new(input)
    input = input or {}; local id = input.id or ('case-' .. tostring(os.time()))
    if type(id) ~= 'string' or id == '' or #id > 64 then return nil, 'CUSTOMS_CASE_ID_INVALID' end
    local status = input.status or 'OPEN'; if not Case.STATUSES[status] then return nil, 'CUSTOMS_CASE_STATUS_INVALID' end
    if type(input.containerId) ~= 'string' or input.containerId == '' then return nil, 'CUSTOMS_CASE_CONTAINER_REQUIRED' end
    return setmetatable({ id=id, containerId=input.containerId, status=status, riskScore=tonumber(input.riskScore) or 0,
        reasons=input.reasons or {}, officerId=input.officerId, version=tonumber(input.version) or 1,
        createdAt=input.createdAt or os.time()*1000, updatedAt=input.updatedAt or os.time()*1000 }, Case)
end
function Case:copy() local c={}; for k,v in pairs(self) do c[k]=v end; return c end
PortOps.Domain.CustomsCase = Case; return Case
