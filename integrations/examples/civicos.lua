-- Example consumer; no framework or database objects cross this boundary.
local health = exports['gnsh-portops']:GetHealth()
if not health.ok or not health.data.ready then return end
local move = exports['gnsh-portops']:CreateMoveOrder({ idempotencyKey = 'civicos:MOVE-1' })
if not move.ok then print(('move unavailable: %s'):format(move.error.code)) end
