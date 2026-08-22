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
    'server/security/validation.lua',
    'server/crane/registry.lua',
    'server/crane/sessions.lua',
    'server/crane/action_tokens.lua',
    'server/crane/sync.lua',
    'server/crane/recovery.lua',
    'server/bootstrap.lua'
}

client_scripts {
    'client/crane/sync.lua',
    'client/bootstrap.lua'
}
