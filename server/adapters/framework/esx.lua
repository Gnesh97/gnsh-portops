-- ESX Legacy adapter boundary.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Framework = PortOps.Adapters.Framework or {}

local Result = PortOps.Core.Result
local ESXAdapter = {}
ESXAdapter.__index = ESXAdapter

local function hook(options, name, handler)
    local register = type(options.registerNetEvent) == 'function' and options.registerNetEvent or RegisterNetEvent
    local add = type(options.addEventHandler) == 'function' and options.addEventHandler or AddEventHandler
    local remove = type(options.removeEventHandler) == 'function' and options.removeEventHandler or RemoveEventHandler
    if type(register) == 'function' and type(add) == 'function' then
        register(name)
        local handlerId = add(name, handler)
        local removed = false
        return true, function()
            if removed then return true end
            removed = true
            if handlerId ~= nil and type(remove) == 'function' then remove(handlerId); return true end
            return false, 'FRAMEWORK_EVENTS_UNAVAILABLE'
        end
    end
    return false, 'FRAMEWORK_EVENTS_UNAVAILABLE'
end

function ESXAdapter.new(options)
    options = options or {}
    return setmetatable({ provider = 'esx', core = options.core, hooks = options }, ESXAdapter)
end

function ESXAdapter:_core()
    if self.core then return self.core end
    if type(ESX) == 'table' then self.core = ESX; return ESX end
    if exports ~= nil then
        local ok, core = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then self.core = core; return core end
    end
    return nil
end

function ESXAdapter:isAvailable()
    local core = self:_core()
    return core ~= nil and type(core.GetPlayerFromId) == 'function'
end

function ESXAdapter:getPlayer(source)
    local core = self:_core()
    if not core or type(core.GetPlayerFromId) ~= 'function' then return nil end
    local ok, player = pcall(core.GetPlayerFromId, source)
    return ok and player or nil
end

function ESXAdapter:getIdentifier(source)
    local player = self:getPlayer(source)
    return player and (player.identifier or (player.getIdentifier and player.getIdentifier())) or nil
end

function ESXAdapter:getCharacter(source)
    local player = self:getPlayer(source)
    if not player then return nil end
    local name = player.getName and player.getName() or player.name
    return { id = self:getIdentifier(source), name = name }
end

function ESXAdapter:getJob(source)
    local player = self:getPlayer(source)
    local job = player and (player.getJob and player.getJob() or player.job)
    if not job then return nil end
    local grade = job.grade or 0
    return { name = job.name, grade = grade, gradeName = job.grade_name, onDuty = job.onDuty ~= false }
end

function ESXAdapter:isOnDuty(source)
    local job = self:getJob(source)
    return job and job.onDuty == true or false
end

function ESXAdapter:getMoney(source, account)
    local player = self:getPlayer(source)
    if not player then return 0 end
    if player.getAccount then
        local value = player.getAccount(account or 'money')
        return tonumber(value and value.money) or 0
    end
    return tonumber(player.getMoney and player.getMoney() or 0) or 0
end

function ESXAdapter:addMoney(source, account, amount, reason)
    local player = self:getPlayer(source)
    if not player then return Result.err('PLAYER_NOT_FOUND', 'ESX player is unavailable') end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return Result.err('MONEY_AMOUNT_INVALID', 'money amount must be positive') end
    local ok
    if player.addAccountMoney then ok = pcall(player.addAccountMoney, account or 'money', amount, reason or 'portops')
    elseif player.addMoney then ok = pcall(player.addMoney, amount, reason or 'portops') end
    if not ok then return Result.err('MONEY_UPDATE_FAILED', 'ESX money update failed') end
    return Result.ok({ amount = amount, account = account or 'money' })
end

function ESXAdapter:onPlayerLoaded(handler) return hook(self.hooks, 'esx:playerLoaded', handler) end
function ESXAdapter:onPlayerUnload(handler) return hook(self.hooks, 'playerDropped', handler) end
function ESXAdapter:onJobChange(handler) return hook(self.hooks, 'esx:setJob', handler) end

PortOps.Adapters.Framework.ESX = ESXAdapter
return ESXAdapter
