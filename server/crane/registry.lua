-- In-memory crane registry for the production authority boundary.  Database
-- persistence is intentionally deferred to PORT-032; this registry is the
-- canonical state holder for the direct development path.
PortOps = PortOps or {}
PortOps.Crane = PortOps.Crane or {}

local Schema = PortOps.Crane.Schema
local Enums = PortOps.Enums

local Registry = {}
Registry.__index = Registry

function Registry.new(config)
    local registry = setmetatable({ profiles = {}, states = {}, sequence = 0 }, Registry)
    for id, profile in pairs((config and config.craneProfiles) or {}) do
        local profileCopy = Schema.copyProfile(profile)
        profileCopy.id = profileCopy.id or id
        local ok, reason = registry:register(profileCopy)
        if not ok then return nil, reason end
    end
    return registry
end

function Registry:register(profile)
    local ok, reason = Schema.validateProfile(profile)
    if not ok then return false, reason end
    if self.profiles[profile.id] then return false, 'duplicate crane profile: ' .. profile.id end
    self.profiles[profile.id] = Schema.copyProfile(profile)
    self.states[profile.id] = {
        craneId = profile.id,
        mode = Enums.CraneState.AVAILABLE,
        canonical = Schema.defaultState(),
        version = 0,
        updatedAt = 0,
        sessionId = nil,
        source = nil,
        operatorId = nil,
        attachedContainerId = nil,
        frozen = false,
        recoveryRequired = false,
        recoveryReason = nil
    }
    return true
end

function Registry:getProfile(craneId)
    local profile = self.profiles[craneId]
    return profile and Schema.copyProfile(profile) or nil
end

function Registry:get(craneId)
    return self.states[craneId]
end

function Registry:getState(craneId)
    local state = self.states[craneId]
    if not state then return nil end
    local copy = {}
    for key, value in pairs(state) do
        if key == 'canonical' then copy[key] = Schema.copyState(value) else copy[key] = value end
    end
    return copy
end

function Registry:reserve(craneId, session)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    if state.recoveryRequired or state.frozen then return false, 'RECOVERY_REQUIRED' end
    if state.sessionId and state.sessionId ~= session.id then return false, 'CRANE_OCCUPIED' end
    state.sessionId = session.id
    state.source = session.source
    state.operatorId = session.operatorId
    state.mode = Enums.CraneState.RESERVED
    return true, self:getState(craneId)
end

function Registry:release(craneId, sessionId)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    if state.sessionId and state.sessionId ~= sessionId then return false, 'SESSION_OWNER_MISMATCH' end
    state.sessionId = nil
    state.source = nil
    state.operatorId = nil
    if not state.recoveryRequired then state.mode = Enums.CraneState.AVAILABLE end
    return true, self:getState(craneId)
end

function Registry:updateCanonical(craneId, stateValue, sessionId, timestamp)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    if state.recoveryRequired or state.frozen then return false, 'RECOVERY_REQUIRED' end
    if state.sessionId ~= sessionId then return false, 'SESSION_OWNER_MISMATCH' end
    local ok, normalized = Schema.validateState(stateValue)
    if not ok then return false, normalized end
    state.canonical = normalized
    state.version = state.version + 1
    state.updatedAt = tonumber(timestamp) or state.updatedAt
    state.mode = Enums.CraneState.OPERATING
    return true, self:getState(craneId)
end

-- Domain services may attach an opaque container reference without handing
-- visual/entity authority to the client.  The actual container transition is
-- intentionally implemented in a later phase.
function Registry:setAttachment(craneId, containerId, sessionId)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    if state.recoveryRequired or state.frozen then return false, 'RECOVERY_REQUIRED' end
    if state.sessionId ~= sessionId then return false, 'SESSION_OWNER_MISMATCH' end
    if type(containerId) ~= 'string' or containerId == '' or #containerId > 64 then return false, 'INVALID_CONTAINER' end
    state.attachedContainerId = containerId
    state.mode = Enums.CraneState.ATTACHED
    state.version = state.version + 1
    return true, self:getState(craneId)
end

function Registry:clearAttachment(craneId, sessionId)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    if state.sessionId and state.sessionId ~= sessionId then return false, 'SESSION_OWNER_MISMATCH' end
    state.attachedContainerId = nil
    if not state.recoveryRequired then state.mode = state.sessionId and Enums.CraneState.RESERVED or Enums.CraneState.AVAILABLE end
    state.version = state.version + 1
    return true, self:getState(craneId)
end

function Registry:freeze(craneId, reason, timestamp)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    state.frozen = true
    state.recoveryRequired = true
    state.recoveryReason = reason or 'recovery required'
    state.mode = Enums.CraneState.RECOVERY_REQUIRED
    state.updatedAt = tonumber(timestamp) or state.updatedAt
    return true, self:getState(craneId)
end

function Registry:markRecovered(craneId, timestamp)
    local state = self.states[craneId]
    if not state then return false, 'CRANE_NOT_FOUND' end
    state.frozen = false
    state.recoveryRequired = false
    state.recoveryReason = nil
    state.mode = state.sessionId and Enums.CraneState.RESERVED or Enums.CraneState.AVAILABLE
    state.version = state.version + 1
    state.updatedAt = tonumber(timestamp) or state.updatedAt
    return true, self:getState(craneId)
end

PortOps.Crane.Registry = Registry
return Registry
