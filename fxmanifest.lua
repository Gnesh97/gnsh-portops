fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Gnesh97'
description 'PortOps production-first port operations resource'
version '0.1.0'

shared_scripts {
    'shared/enums.lua',
    'shared/errors.lua',
    'shared/crane/constants.lua',
    'shared/crane/schema.lua',
    'shared/crane/protocol.lua',
    'shared/crane/validation.lua',
    'config/config.lua',
    'config/features.lua'
}
server_scripts {
    'server/core/result.lua',
    'server/core/logger.lua',
    'server/core/event_bus.lua',
    'server/core/migrations.lua',
    'server/adapters/database/memory.lua',
    'server/adapters/database/oxmysql.lua',
    'server/adapters/database/interface.lua',
    'server/adapters/framework/standalone.lua',
    'server/adapters/framework/qbcore.lua',
    'server/adapters/framework/qbox.lua',
    'server/adapters/framework/esx.lua',
    'server/adapters/framework/interface.lua',
    'server/security/validation.lua',
    'server/crane/registry.lua',
    'server/crane/sessions.lua',
    'server/crane/action_tokens.lua',
    'server/crane/sync.lua',
    'server/crane/recovery.lua',
    'server/bootstrap.lua'
}

files {
    'sql/001_initial.sql',
    'sql/002_indexes.sql'
}

client_scripts {
    'client/crane/sync.lua',
    'client/bootstrap.lua'
}
