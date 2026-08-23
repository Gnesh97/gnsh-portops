-- QBCore adapter. No QBCore calls leave this adapter boundary.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Framework = PortOps.Adapters.Framework or {}

local Result = PortOps.Core.Result
local QBCore = {}
QBCore.__index = QBCore

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

function QBCore.new(options)
    options = options or {}
    return setmetatable({ provider = 'qbcore', core = options.core, hooks = options }, QBCore)
end

function QBCore:_core()
    if self.core then return self.core end
    if exports ~= nil then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then self.core = core; return core end
    end
    return nil
end

function QBCore:isAvailable()
    local core = self:_core()
    return core ~= nil and core.Functions ~= nil and type(core.Functions.GetPlayer) == 'function'
end

function QBCore:getPlayer(source)
    local core = self:_core()
    if not core or not core.Functions or type(core.Functions.GetPlayer) ~= 'function' then return nil end
    local ok, player = pcall(core.Functions.GetPlayer, source)
    return ok and player or nil
end

function QBCore:getIdentifier(source)
    local player = self:getPlayer(source)
    local data = player and player.PlayerData
    return data and (data.citizenid or data.license) or nil
end

function QBCore:getCharacter(source)
    local player = self:getPlayer(source)
    local data = player and player.PlayerData
    local info = data and data.charinfo or {}
    if not data then return nil end
    return { id = data.citizenid or data.license, name = (info.firstname and ((info.firstname .. ' ' .. (info.lastname or '')):gsub('%s+$', ''))) or data.name }
end

function QBCore:getJob(source)
    local player = self:getPlayer(source)
    local job = player and player.PlayerData and player.PlayerData.job
    if not job then return nil end
    local grade = job.grade or {}
    return { name = job.name, grade = grade.level or grade, gradeName = grade.name, onDuty = job.onduty == true }
end

function QBCore:isOnDuty(source)
    local job = self:getJob(source)
    return job and job.onDuty == true or false
end

function QBCore:getMoney(source, account)
    local player = self:getPlayer(source)
    local money = player and player.PlayerData and player.PlayerData.money
    return tonumber(money and money[account or 'cash']) or 0
end

function QBCore:addMoney(source, account, amount, reason)
    local player = self:getPlayer(source)
    if not player or not player.Functions or type(player.Functions.AddMoney) ~= 'function' then return Result.err('PLAYER_NOT_FOUND', 'QBCore player is unavailable') end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return Result.err('MONEY_AMOUNT_INVALID', 'money amount must be positive') end
    local ok, value = pcall(player.Functions.AddMoney, account or 'cash', amount, reason or 'portops')
    if not ok or value == false then return Result.err('MONEY_UPDATE_FAILED', 'QBCore money update failed') end
    return Result.ok({ amount = amount, account = account or 'cash' })
end

function QBCore:onPlayerLoaded(handler) return hook(self.hooks, 'QBCore:Server:OnPlayerLoaded', handler) end
function QBCore:onPlayerUnload(handler) return hook(self.hooks, 'QBCore:Server:OnPlayerUnload', handler) end
function QBCore:onJobChange(handler) return hook(self.hooks, 'QBCore:Server:OnJobUpdate', handler) end

PortOps.Adapters.Framework.QBCore = QBCore
return QBCore
