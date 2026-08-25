PortOps = PortOps or {}; PortOps.Services=PortOps.Services or {}; local Result=PortOps.Core.Result; local S={}; S.__index=S
function S.new(o) o=o or {}; return setmetatable({containers=o.containers or {}, manifests={}, repository=o.repository, containerService=o.containerService},S) end
function S:import(manifest)
    if type(manifest)~='table' or type(manifest.id)~='string' or type(manifest.items)~='table' then return Result.err('MANIFEST_INVALID','manifest is invalid') end
    local seen={}; local copy={}; for key,value in pairs(manifest) do copy[key]=value end; copy.items={}
    for _,item in ipairs(manifest.items) do
        if type(item)~='table' or type(item.containerId)~='string' or seen[item.containerId] then return Result.err('MANIFEST_DUPLICATE','container ids must be unique') end
        seen[item.containerId]=true; copy.items[#copy.items+1]=item
    end
    local saved=self.repository and self.repository:create(copy) or Result.ok(copy)
    if Result.isErr(saved) then return saved end
    self.manifests[copy.id]=copy
    if self.containerService then
        for _,item in ipairs(copy.items) do if type(item.container) == 'table' then local created=self.containerService:create(item.container, {manifestId=copy.id}); if Result.isErr(created) then return created end end end
    end
    return Result.ok(copy)
end
function S:get(id) if self.repository then return self.repository:get(id) end; local m=self.manifests[id]; return m and Result.ok(m) or Result.err('MANIFEST_NOT_FOUND','manifest not found') end
function S:materialize(id) local result=self:get(id); if Result.isErr(result) then return result end; local out={}; for _,item in ipairs(result.data.items) do out[#out+1]=item.containerId end; return Result.ok(out) end
PortOps.Services.Manifest=S; return S
