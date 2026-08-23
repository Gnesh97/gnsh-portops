-- Small structured logger.  It keeps correlation metadata server-side and
-- never serializes raw credentials into log lines.
PortOps = PortOps or {}
PortOps.Core = PortOps.Core or {}

local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }

local function sensitiveKey(key)
    if type(key) ~= 'string' then return false end
    local normalized = key:lower():gsub('[^%w]', '')
    for _, marker in ipairs({ 'token', 'password', 'secret', 'credential', 'authorization', 'privatekey', 'apikey' }) do
        if normalized:find(marker, 1, true) then return true end
    end
    return false
end

local function scalar(key, value)
    if sensitiveKey(key) then return '<redacted>' end
    if value == nil then return 'nil' end
    if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
    return '<complex>'
end

local function formatContext(context)
    if type(context) ~= 'table' then return '' end
    local fields = {}
    for key, value in pairs(context) do
        if type(key) == 'string' and #key <= 64 then fields[#fields + 1] = ('%s=%s'):format(key, scalar(key, value)) end
    end
    table.sort(fields)
    return #fields > 0 and (' {' .. table.concat(fields, ' ') .. '}') or ''
end

local function sanitizeContext(context)
    if type(context) ~= 'table' then return context end
    local sanitized = {}
    for key, value in pairs(context) do
        if type(key) == 'string' and #key <= 64 then
            if sensitiveKey(key) then
                sanitized[key] = '<redacted>'
            elseif type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' or value == nil then
                sanitized[key] = value
            else
                sanitized[key] = '<complex>'
            end
        end
    end
    return sanitized
end

function Logger.new(options)
    options = options or {}
    local minimum = options.level or 'info'
    if not LEVELS[minimum] then minimum = 'info' end
    return setmetatable({
        category = options.category or 'portops',
        level = minimum,
        sink = options.sink,
        sequence = 0
    }, Logger)
end

function Logger:correlation(prefix)
    self.sequence = self.sequence + 1
    return ('%s-%d'):format(prefix or 'corr', self.sequence)
end

function Logger:write(level, message, context)
    if not LEVELS[level] or LEVELS[level] < LEVELS[self.level] then return false end
    local safeContext = sanitizeContext(context)
    local line = ('[%s] %s: %s%s'):format(self.category, level:upper(), tostring(message), formatContext(safeContext))
    if type(self.sink) == 'function' then self.sink(line, level, safeContext); return true end
    if type(print) == 'function' then print(line); return true end
    return false
end

function Logger:debug(message, context) return self:write('debug', message, context) end
function Logger:info(message, context) return self:write('info', message, context) end
function Logger:warn(message, context) return self:write('warn', message, context) end
function Logger:error(message, context) return self:write('error', message, context) end

PortOps.Core.Logger = Logger
return Logger
