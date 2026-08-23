-- Offline contract for production crane session and action-token authority.
local root = 'server/crane/'
dofile(root .. 'sessions.lua')
dofile(root .. 'action_tokens.lua')

local time = 1000
local sessions = PortOpsCrane.Sessions.new({ ttlMs = 100, clock = function() return time end })
local originalTostring = tostring
tostring = function(value)
    if type(value) == 'table' then return 'table: 0000029FD80A0F00' end
    return originalTostring(value)
end
local first = assert(sessions:reserve('qc-01', 11, 'employee-11'))
tostring = originalTostring
assert(not first.id:find('table:', 1, true), 'session id leaked table allocation format')
assert(not first.token:find('table:', 1, true), 'session token leaked table allocation format')
assert(not first.token:match('^st_%d+_%d+$'), 'session token must not be timestamp predictable')
local second, occupiedReason = sessions:reserve('qc-01', 12, 'employee-12')
assert(not second and occupiedReason == 'CRANE_OCCUPIED', 'reserve must be atomic per crane')
assert(sessions:validate(first.id, 'qc-01', 11, 'employee-11'))
local wrongSessionToken, wrongSessionTokenReason = sessions:validate(first.id, 'qc-01', 11, 'employee-11', time, 'invalid-token')
assert(not wrongSessionToken and wrongSessionTokenReason == 'WRONG_SESSION_TOKEN', 'session credential must be enforced when supplied')
local wrong, wrongReason = sessions:validate(first.id, 'qc-01', 12, 'employee-11')
assert(not wrong and wrongReason == 'WRONG_SOURCE', 'source binding must be enforced')
assert(sessions:release(first.id, 11), 'owner must release session')
local repeatedRelease, repeatedReason = sessions:release(first.id, 11)
assert(repeatedRelease and repeatedReason == 'ALREADY_RELEASED', 'owner release must be idempotent')
local wrongRepeated, wrongRepeatedReason = sessions:release(first.id, 99)
assert(not wrongRepeated and wrongRepeatedReason == 'WRONG_SOURCE', 'wrong source must not release tombstone')
assert(not sessions:get(first.id), 'released session must be invalid')

local recovered = assert(sessions:reserve('qc-01', 12, 'employee-12', time))
assert(recovered.token ~= first.token, 'session credentials must not collide')
assert(sessions:invalidateSource(12, time) == 1, 'disconnect must invalidate source sessions')
assert(not sessions:get(recovered.id), 'disconnect cleanup must remove session')

local expiring = assert(sessions:reserve('qc-02', 13, 'employee-13', time))
time = time + 101
assert(not sessions:get(expiring.id), 'expired session must be rejected')

time = 2000
local active = assert(sessions:reserve('qc-03', 14, 'employee-14', time))
local replayReasons = {}
local tokens = PortOpsCrane.ActionTokens.new({
    ttlMs = 50,
    clock = function() return time end,
    replayLog = function(event) replayReasons[#replayReasons + 1] = event end
})
originalTostring = tostring
tostring = function(value)
    if type(value) == 'table' then return 'table: 0000029FD80A0F00' end
    return originalTostring(value)
end
local token = assert(tokens:issue(sessions, active.id, 'qc-03', 'MSCU-001', 'attach', 14, 'employee-14'))
tostring = originalTostring
assert(not token:find('table:', 1, true), 'action token leaked table allocation format')
local secureToken = assert(tokens:issue(sessions, active.id, 'qc-03', 'MSCU-SECURE', 'attach', 14, 'employee-14', time, active.token))
local invalidCredential, invalidCredentialReason = tokens:consume(secureToken, sessions, active.id, 'qc-03', 'MSCU-SECURE', 'attach', 14, 'employee-14', time, 'invalid-token')
assert(not invalidCredential and invalidCredentialReason == 'WRONG_SESSION_TOKEN', 'token consume must enforce supplied session credential')
local secureConsumed = tokens:consume(secureToken, sessions, active.id, 'qc-03', 'MSCU-SECURE', 'attach', 14, 'employee-14', time, active.token)
assert(secureConsumed, 'valid session credential must authorize token consume')
local scopedToken = assert(tokens:issue(sessions, active.id, 'qc-03', 'MSCU-SCOPED', 'attach', 14, 'employee-14', time, active.token, 'target-A', 'v1'))
local wrongTarget, wrongTargetReason = tokens:consume(scopedToken, sessions, active.id, 'qc-03', 'MSCU-SCOPED', 'attach', 14, 'employee-14', time, active.token, 'target-B', 'v1')
assert(not wrongTarget and wrongTargetReason == 'TOKEN_BINDING_MISMATCH', 'wrong target must reject token')
local wrongProfile, wrongProfileReason = tokens:consume(scopedToken, sessions, active.id, 'qc-03', 'MSCU-SCOPED', 'attach', 14, 'employee-14', time, active.token, 'target-A', 'v2')
assert(not wrongProfile and wrongProfileReason == 'TOKEN_BINDING_MISMATCH', 'wrong profile version must reject token')
assert(tokens:consume(scopedToken, sessions, active.id, 'qc-03', 'MSCU-SCOPED', 'attach', 14, 'employee-14', time, active.token, 'target-A', 'v1'))
local malformed, malformedReason = tokens:issue(sessions, active.id, 'qc-03', {}, 'attach', 14, 'employee-14')
assert(not malformed and malformedReason == 'INVALID_TOKEN_BINDING', 'non-string container must reject')
local unsupported, unsupportedReason = tokens:issue(sessions, active.id, 'qc-03', 'MSCU-001', 'teleport', 14, 'employee-14')
assert(not unsupported and unsupportedReason == 'INVALID_TOKEN_BINDING', 'unsupported action must reject')
local malformedConsume, malformedConsumeReason = tokens:consume(token, sessions, active.id, 'qc-03', '', 'attach', 14, 'employee-14')
assert(not malformedConsume and malformedConsumeReason == 'INVALID_TOKEN_BINDING', 'malformed consume binding must reject')
local wrongSession, wrongSessionReason = tokens:consume(token, sessions, active.id, 'qc-03', 'MSCU-001', 'attach', 99, 'employee-14')
assert(not wrongSession and wrongSessionReason == 'WRONG_SOURCE', 'wrong session source must reject token')
local wrongContainer, wrongContainerReason = tokens:consume(token, sessions, active.id, 'qc-03', 'MSCU-999', 'attach', 14, 'employee-14')
assert(not wrongContainer and wrongContainerReason == 'TOKEN_BINDING_MISMATCH', 'wrong container must reject token')
local consumed, consumedRecord = tokens:consume(token, sessions, active.id, 'qc-03', 'MSCU-001', 'attach', 14, 'employee-14')
assert(consumed, 'valid token must consume')
assert(consumedRecord.containerId == 'MSCU-001', 'consume must return validated binding')
local replay, replayReason = tokens:consume(token, sessions, active.id, 'qc-03', 'MSCU-001', 'attach', 14, 'employee-14')
assert(not replay and replayReason == 'TOKEN_REPLAY', 'token must be one-time')

local expiringToken = assert(tokens:issue(sessions, active.id, 'qc-03', 'MSCU-002', 'detach', 14, 'employee-14', time))
time = time + 51
local expired, expiredReason = tokens:consume(expiringToken, sessions, active.id, 'qc-03', 'MSCU-002', 'detach', 14, 'employee-14')
assert(not expired and expiredReason == 'TOKEN_EXPIRED', 'expired token must reject')
assert(#replayReasons >= 3, 'rejection events must be observable through replay log')
for _, event in ipairs(replayReasons) do
    assert(event ~= token and event ~= expiringToken, 'replay log must not contain raw token')
end

local limited = PortOpsCrane.ActionTokens.new({
    ttlMs = 100,
    maxActivePerSession = 2,
    maxIssuesPerWindow = 2,
    issueWindowMs = 1000,
    clock = function() return time end
})
assert(limited:issue(sessions, active.id, 'qc-03', 'MSCU-L1', 'attach', 14, 'employee-14', time, active.token))
assert(limited:issue(sessions, active.id, 'qc-03', 'MSCU-L2', 'attach', 14, 'employee-14', time, active.token))
local limitedToken, limitedReason = limited:issue(sessions, active.id, 'qc-03', 'MSCU-L3', 'attach', 14, 'employee-14', time, active.token)
assert(not limitedToken and limitedReason == 'TOKEN_RATE_LIMITED', 'active token limit was not enforced')

print('Production crane sessions/action tokens contract: PASS')
