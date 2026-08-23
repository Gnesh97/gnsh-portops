-- Qbox adapter is intentionally separate from QBCore; shared data shapes do
-- not imply shared provider calls or lifecycle semantics.
PortOps = PortOps or {}
PortOps.Adapters = PortOps.Adapters or {}
PortOps.Adapters.Framework = PortOps.Adapters.Framework or {}

local Result = PortOps.Core.Result
local Qbox = {}
Qbox.__index = Qbox

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

function Qbox.new(options)
    options = options or {}
    return setmetatable({ provider = 'qbox', core = options.core, hooks = options }, Qbox)
end

function Qbox:_core()
    if self.core then return self.core end
    if exports ~= nil then
        local ok, core = pcall(function() return exports['qbx_core'] end)
        if ok then self.core = core; return core end
    end
    return nil
end

function Qbox:isAvailable()
    local core = self:_core()
    return core ~= nil and (type(core.GetPlayer) == 'function' or (core.Functions and type(core.Functions.GetPlayer) == 'function'))
end

function Qbox:getPlayer(source)
    local core = self:_core()
    if not core then return nil end
    local getter = core.GetPlayer or (core.Functions and core.Functions.GetPlayer)
    if type(getter) ~= 'function' then return nil end
    local ok, player = pcall(getter, source)
    return ok and player or nil
end

function Qbox:getIdentifier(source)
    local player = self:getPlayer(source)
    local data = player and player.PlayerData
    return data and (data.citizenid or data.license or data.identifier) or nil
end

function Qbox:getCharacter(source)
    local player = self:getPlayer(source)
    local data = player and player.PlayerData
    if not data then return nil end
    local info = data.charinfo or {}
    return { id = data.citizenid or data.license or data.identifier, name = info.firstname and ((info.firstname .. ' ' .. (info.lastname or '')):gsub('%s+$', '')) or data.name }
end

function Qbox:getJob(source)
    local player = self:getPlayer(source)
    local job = player and player.PlayerData and player.PlayerData.job
    if not job then return nil end
    local grade = job.grade or {}
    return { name = job.name, grade = grade.level or grade, gradeName = grade.name, onDuty = job.onduty == true }
end

function Qbox:isOnDuty(source)
    local job = self:getJob(source)
    return job and job.onDuty == true or false
end

function Qbox:getMoney(source, account)
    local player = self:getPlayer(source)
    local money = player and player.PlayerData and player.PlayerData.money
    return tonumber(money and money[account or 'cash']) or 0
end

function Qbox:addMoney(source, account, amount, reason)
    local player = self:getPlayer(source)
    local functionsAddMoney = player and player.Functions and player.Functions.AddMoney
    local playerAddMoney = player and player.AddMoney
    if type(functionsAddMoney) ~= 'function' and type(playerAddMoney) ~= 'function' then return Result.err('PLAYER_NOT_FOUND', 'Qbox player is unavailable') end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return Result.err('MONEY_AMOUNT_INVALID', 'money amount must be positive') end
    local ok, value
    if type(functionsAddMoney) == 'function' then
        ok, value = pcall(functionsAddMoney, account or 'cash', amount, reason or 'portops')
    else
        ok, value = pcall(playerAddMoney, player, account or 'cash', amount, reason or 'portops')
    end
    if not ok or value == false then return Result.err('MONEY_UPDATE_FAILED', 'Qbox money update failed') end
    return Result.ok({ amount = amount, account = account or 'cash' })
end

function Qbox:onPlayerLoaded(handler) return hook(self.hooks, 'QBX:Server:OnPlayerLoaded', handler) end
function Qbox:onPlayerUnload(handler) return hook(self.hooks, 'QBX:Server:OnPlayerUnload', handler) end
function Qbox:onJobChange(handler) return hook(self.hooks, 'QBX:Server:OnJobUpdate', handler) end

PortOps.Adapters.Framework.Qbox = Qbox
return Qbox
