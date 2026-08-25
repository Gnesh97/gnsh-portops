PortOps = PortOps or {}; PortOps.Client=PortOps.Client or {}; local N={}
function N.request(name,payload) if type(name)~='string' or name=='' then return false end; if type(SendNUIMessage)=='function' then SendNUIMessage({type=name,payload=payload}) end; return true end
PortOps.Client.NUI=N; return N
