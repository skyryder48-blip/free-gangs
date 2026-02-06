fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'free-gangs'
description 'Comprehensive gang management system for QBox'
author 'Your Name'
version '1.0.0'

-- Dependencies (these resources must start before free-gangs)
dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'qbx_core',
}

-- Shared scripts (load first, available to both client and server)
shared_scripts {
    '@ox_lib/init.lua',
    'shared/enums.lua',
    'shared/utils.lua',
    'config/config.lua',
    'config/territories.lua',
    'config/bribes.lua',
    'config/archetypes.lua',
    'locales/en.lua',
}

-- Server scripts (load order matters!)
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    
    -- Bridge layer first
    'bridge/qbx.lua',
    
    -- Database layer
    'server/db/queries.lua',
    'server/db/cache.lua',
    
    -- Core modules (foundation)
    'server/modules/gang.lua',
    'server/modules/members.lua',
    'server/modules/reputation.lua',
    
    -- Feature modules (phases A-E)
    'server/modules/territory.lua',
    'server/modules/heat.lua',
    'server/modules/war.lua',
    'server/modules/activities.lua',
    'server/modules/graffiti.lua',
    'server/modules/bribes.lua',
    'server/modules/archetypes.lua',
    'server/modules/prison.lua',
    
    -- Callbacks (register after modules exist)
    'server/callbacks/territory.lua',
    'server/callbacks/heat.lua',
    'server/callbacks/war.lua',
    'server/callbacks/activities.lua',
    'server/callbacks/bribes.lua',
    'server/callbacks/archetypes.lua',
    
    -- Exports and initialization (last)
    'server/exports.lua',
    'server/main.lua',
}

-- Client scripts
client_scripts {
    '@qbx_core/modules/playerdata.lua',
    
    -- Bridge layer
    'bridge/qbx.lua',
    
    -- Cache first
    'client/cache.lua',
    
    -- Feature modules
    'client/module/territory.lua',
    'client/module/activities.lua',
    'client/module/graffiti.lua',
    'client/module/bribes.lua',
    'client/module/archetypes.lua',
    
    -- UI components
    'client/ui/menus.lua',
    'client/ui/inputs.lua',
    'client/ui/notifications.lua',
    
    -- Main initialization (last)
    'client/main.lua',
}

-- NUI configuration
ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/style.css',
    'nui/js/app.js',
    'locales/*.lua',
}

-- Server exports (callable by other resources)
server_exports {
    -- Membership
    'GetPlayerGang',
    'IsInGang',
    'GetGangRank',
    'GetGangMembers',
    'AddPlayerToGang',
    'RemovePlayerFromGang',
    
    -- Reputation
    'AddMasterRep',
    'RemoveMasterRep',
    'GetMasterRep',
    'GetMasterLevel',
    
    -- Territory
    'GetZoneControl',
    'GetZoneOwner',
    'AddZoneLoyalty',
    'IsInTerritory',
    'GetTerritoryInfo',
    
    -- Heat & War
    'AddGangHeat',
    'GetGangHeat',
    'GetHeatStage',
    'AreGangsAtWar',
    'GetActiveWars',
    
    -- Archetype
    'GetArchetype',
    'HasArchetypeAccess',
    'ApplyArchetypeBonus',
}