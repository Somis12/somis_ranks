fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Somis'
description 'Rank leaderboard system'
version '1.0.0'

client_script 'client/client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
}

ui_page 'ui/index.html'

files {
  'ui/config.js',
    'ui/index.html',
    'ui/img/*.png'
}
