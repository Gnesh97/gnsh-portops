-- Example: integration code depends on the public API only.
local result = exports['gnsh-portops']:CreateContainer({
    id = 'EXT-001', isoType = '40HC', status = 'YARD'
}, 'shipment:EXT-001')
if not result.ok then print(('shipment rejected: %s'):format(result.error.code)) end
