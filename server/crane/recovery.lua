-- Disconnect recovery freezes canonical state before invalidating authority.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Recovery = {}
Recovery.__index = Recovery

function Recovery.new(options)
    options = options or {}
    return setmetatable({
        registry = options.registry,
        sessions = options.sessions,
        tokens = options.tokens,
        notify = options.notify or function() end,
        inProgress = {}
    }, Recovery)
end

function Recovery:freeze(craneId, reason, timestamp)
    local state = self.registry and self.registry:get(craneId)
    if not state then return false, 'CRANE_NOT_FOUND' end
    if self.inProgress[craneId] then return true, self.registry:getState(craneId) end
    self.inProgress[craneId] = true
    local sessionId = state.sessionId
    local ok, frozen = self.registry:freeze(craneId, reason, timestamp)
    if not ok then self.inProgress[craneId] = nil; return false, frozen end
    if sessionId and self.sessions then self.sessions:release(sessionId, nil, timestamp) end
    if sessionId and self.tokens then self.tokens:invalidateSession(sessionId) end
    if sessionId then self.registry:release(craneId, sessionId) end
    self.inProgress[craneId] = nil
    self.notify(craneId, frozen, reason or 'recovery required')
    return true, frozen
end

function Recovery:handleDisconnect(source, timestamp)
    if not self.sessions then return 0 end
    local craneIds = {}
    for _, session in pairs(self.sessions.bySession or {}) do
        if session.source == tostring(source) then craneIds[#craneIds + 1] = session.craneId end
    end
    local recovered = 0
    for _, craneId in ipairs(craneIds) do
        local ok = self:freeze(craneId, 'operator disconnected', timestamp)
        if ok then recovered = recovered + 1 end
    end
    self.sessions:invalidateSource(source, timestamp)
    return recovered
end

function Recovery:invalidateSession(sessionId, reason, timestamp)
    local session = self.sessions and self.sessions:get(sessionId, timestamp)
    if not session then
        if self.tokens then self.tokens:invalidateSession(sessionId) end
        return true, reason
    end
    return self:freeze(session.craneId, reason or 'session invalidated', timestamp)
end

PortOps.Crane.Recovery = Recovery
return Recovery
