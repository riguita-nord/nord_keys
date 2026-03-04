fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Nord Scripts'
description 'nord_keys - vehicle keys + lock/unlock'
version '1.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/bridge.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/owned_vehicles.lua',
  'server/main.lua',
  'server/exports.lua',
  'server/update.lua'
}

client_scripts {
  'client/main.lua',
  'client/exports.lua'
}

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/style.css',
  'web/audi.css',
  'web/bmw.css',
  'web/app.js',
  'web/assets/bmw_click.wav'
}

dependencies {
  'ox_lib',
  'ox_inventory',
  'oxmysql'
}

escrow_ignore {
    'config.lua',
    'shared/*',
    'install/*',
    'server/framework/secret.token'
}
