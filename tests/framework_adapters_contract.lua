-- Offline contract for standalone, QBCore, Qbox, and ESX adapter parity.
PortOps = {}
dofile('server/core/result.lua')
dofile('server/adapters/framework/standalone.lua')
dofile('server/adapters/framework/qbcore.lua')
dofile('server/adapters/framework/qbox.lua')
dofile('server/adapters/framework/esx.lua')
dofile('server/adapters/framework/interface.lua')

local Framework = PortOps.Adapters.Framework.Interface
assert(Framework.validate(Framework.Standalone.new()), 'standalone adapter contract invalid')
local standalone = Framework.create({ provider = 'standalone' })
assert(standalone:isAvailable() and standalone:getIdentifier(12) == 'standalone:12' and standalone:isOnDuty(12), 'standalone identity contract failed')

local qbPlayer = {
    PlayerData = {
        citizenid = 'citizen-1',
        charinfo = { firstname = 'Ada', lastname = 'Lovelace' },
        job = { name = 'crane', grade = { level = 2, name = 'senior' }, onduty = true },
        money = { cash = 125 }
    },
    Functions = { AddMoney = function(_, amount) return amount > 0 end }
}
local qb = Framework.create({ provider = 'qbcore', core = { Functions = { GetPlayer = function() return qbPlayer end } } })
assert(qb:isAvailable() and qb:getIdentifier(1) == 'citizen-1' and qb:getCharacter(1).name == 'Ada Lovelace', 'QBCore identity contract failed')
assert(qb:getJob(1).grade == 2 and qb:isOnDuty(1) and qb:getMoney(1, 'cash') == 125, 'QBCore job/money contract failed')
assert(PortOps.Core.Result.isOk(qb:addMoney(1, 'cash', 10)), 'QBCore money contract failed')

local qbox = Framework.create({ provider = 'qbox', core = { GetPlayer = function() return qbPlayer end } })
assert(qbox:isAvailable() and qbox:getIdentifier(1) == 'citizen-1' and qbox:getJob(1).name == 'crane', 'Qbox adapter must remain independently callable')

local esxPlayer = {
    identifier = 'license-1',
    getName = function() return 'Grace Hopper' end,
    getJob = function() return { name = 'customs', grade = 3, grade_name = 'officer' } end,
    getAccount = function() return { money = 90 } end,
    addAccountMoney = function() return true end
}
local esx = Framework.create({ provider = 'esx', core = { GetPlayerFromId = function() return esxPlayer end } })
assert(esx:isAvailable() and esx:getIdentifier(1) == 'license-1' and esx:getCharacter(1).name == 'Grace Hopper', 'ESX identity contract failed')
assert(esx:getJob(1).grade == 3 and esx:getMoney(1, 'money') == 90, 'ESX job/money contract failed')
assert(PortOps.Core.Result.isOk(esx:addMoney(1, 'money', 5)), 'ESX money contract failed')

local removedHandler
local hookAdapter = Framework.QBCore.new({
    core = { Functions = { GetPlayer = function() return qbPlayer end } },
    registerNetEvent = function() end,
    addEventHandler = function() return 41 end,
    removeEventHandler = function(handlerId) removedHandler = handlerId end
})
local subscribed, unsubscribe = hookAdapter:onPlayerLoaded(function() end)
assert(subscribed and unsubscribe() and removedHandler == 41, 'framework hook unsubscribe did not remove handler')

local unknown, reason = Framework.create({ provider = 'unknown' })
assert(not unknown and reason.error.code == 'FRAMEWORK_PROVIDER_UNSUPPORTED', 'unsupported framework provider did not fail')

print('framework_adapters_contract: PASS')
