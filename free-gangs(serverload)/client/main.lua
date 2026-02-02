--[[
    FREE-GANGS: Client Main
    
    Client-side initialization, event handlers, and core functionality.
    This is the entry point for all client-side operations.
]]

-- Ensure FreeGangs table exists
FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}

-- Client-side state
FreeGangs.Client.Ready = false
FreeGangs.Client.PlayerGang = nil
FreeGangs.Client.CurrentZone = nil
FreeGangs.Client.NearbyGraffiti = {}
FreeGangs.Client.Zones = {}

-- Cached player ped (updated periodically)
local cachedPed = nil
local lastPedUpdate = 0

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the client-side gang system
local function Initialize()
    FreeGangs.Utils.Log('Initializing client...')
    
    -- Wait for player to be loaded
    while not FreeGangs.Bridge.IsPlayerLoaded() do
        Wait(100)
    end
    
    -- Request initial data from server
    FreeGangs.Client.RequestInitialData()
    
    -- Initialize zones
    FreeGangs.Client.InitializeZones()
    
    -- Start background threads
    FreeGangs.Client.StartBackgroundTasks()
    
    -- Register keybinds
    FreeGangs.Client.RegisterKeybinds()
    
    FreeGangs.Client.Ready = true
    FreeGangs.Utils.Log('Client initialized')
end

---Request initial data from server
function FreeGangs.Client.RequestInitialData()
    -- Get player's gang data
    local gangData = lib.callback.await(FreeGangs.Callbacks.GET_PLAYER_GANG, false)
    if gangData then
        FreeGangs.Client.PlayerGang = gangData
        FreeGangs.Client.Cache.Set('playerGang', gangData)
    end
    
    -- Get territories
    local territories = lib.callback.await(FreeGangs.Callbacks.GET_TERRITORIES, false)
    if territories then
        FreeGangs.Client.Cache.Set('territories', territories)
    end
end

---Initialize territory zones
function FreeGangs.Client.InitializeZones()
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    
    for zoneName, territory in pairs(territories) do
        FreeGangs.Client.CreateZone(zoneName, territory)
    end
    
    FreeGangs.Utils.Debug('Initialized ' .. FreeGangs.Utils.TableLength(FreeGangs.Client.Zones) .. ' zones')
end

---Create a zone for a territory
---@param zoneName string
---@param territory table
function FreeGangs.Client.CreateZone(zoneName, territory)
    if FreeGangs.Client.Zones[zoneName] then
        FreeGangs.Client.Zones[zoneName]:remove()
    end
    
    local coords = territory.coords
    if not coords or not coords.x then return end
    
    local zone
    
    if territory.radius then
        -- Sphere zone
        zone = lib.zones.sphere({
            coords = vec3(coords.x, coords.y, coords.z),
            radius = territory.radius,
            debug = FreeGangs.Config.General.Debug,
            onEnter = function(self)
                FreeGangs.Client.OnEnterZone(zoneName, territory)
            end,
            onExit = function(self)
                FreeGangs.Client.OnExitZone(zoneName, territory)
            end,
            inside = function(self)
                FreeGangs.Client.OnInsideZone(zoneName, territory)
            end,
        })
    elseif territory.size then
        -- Box zone
        zone = lib.zones.box({
            coords = vec3(coords.x, coords.y, coords.z),
            size = vec3(territory.size.x, territory.size.y, territory.size.z),
            rotation = territory.rotation or 0,
            debug = FreeGangs.Config.General.Debug,
            onEnter = function(self)
                FreeGangs.Client.OnEnterZone(zoneName, territory)
            end,
            onExit = function(self)
                FreeGangs.Client.OnExitZone(zoneName, territory)
            end,
            inside = function(self)
                FreeGangs.Client.OnInsideZone(zoneName, territory)
            end,
        })
    end
    
    if zone then
        FreeGangs.Client.Zones[zoneName] = zone
    end
end

-- ============================================================================
-- ZONE HANDLERS
-- ============================================================================

---Called when player enters a zone
---@param zoneName string
---@param territory table
function FreeGangs.Client.OnEnterZone(zoneName, territory)
    FreeGangs.Client.CurrentZone = {
        name = zoneName,
        data = territory,
        enteredAt = GetGameTimer(),
    }
    
    -- Get latest influence data from GlobalState
    local stateData = GlobalState['territory:' .. zoneName]
    if stateData then
        territory.influence = stateData.influence
    end
    
    -- Notify server
    TriggerServerEvent(FreeGangs.Events.Server.ENTER_TERRITORY, zoneName)
    
    -- Show territory notification
    local ownerGang = FreeGangs.Client.GetZoneOwner(territory)
    local message
    
    if ownerGang then
        message = string.format(FreeGangs.Config.Messages.TerritoryEntered, ownerGang)
    else
        message = string.format(FreeGangs.Config.Messages.TerritoryEntered, 'Neutral')
    end
    
    if FreeGangs.Config.UI.ShowTerritoryHUD then
        FreeGangs.Bridge.Notify(message, 'inform', 3000)
    end
    
    -- Load nearby graffiti
    FreeGangs.Client.LoadNearbyGraffiti()
    
    FreeGangs.Utils.Debug('Entered zone:', zoneName)
end

---Called when player exits a zone
---@param zoneName string
---@param territory table
function FreeGangs.Client.OnExitZone(zoneName, territory)
    -- Notify server
    TriggerServerEvent(FreeGangs.Events.Server.EXIT_TERRITORY, zoneName)
    
    -- Clear current zone
    FreeGangs.Client.CurrentZone = nil
    
    -- Clear graffiti
    FreeGangs.Client.ClearNearbyGraffiti()
    
    FreeGangs.Utils.Debug('Exited zone:', zoneName)
end

---Called every frame while inside a zone (use sparingly)
---@param zoneName string
---@param territory table
function FreeGangs.Client.OnInsideZone(zoneName, territory)
    -- This runs every frame - only do essential rendering here
    -- Heavy logic should be in background threads
end

---Get zone owner (gang with majority control)
---@param territory table
---@return string|nil gangName
function FreeGangs.Client.GetZoneOwner(territory)
    if not territory.influence then return nil end
    
    local highestGang = nil
    local highestInfluence = 0
    
    for gangName, influence in pairs(territory.influence) do
        if influence > highestInfluence then
            highestInfluence = influence
            highestGang = gangName
        end
    end
    
    -- Only return if they have majority
    if highestInfluence >= FreeGangs.Config.Territory.MajorityThreshold then
        return highestGang
    end
    
    return nil
end

-- ============================================================================
-- BACKGROUND TASKS
-- ============================================================================

---Start background threads
function FreeGangs.Client.StartBackgroundTasks()
    -- Presence tick thread
    CreateThread(function()
        while true do
            Wait(FreeGangs.Config.Territory.PresenceTickMinutes * 60 * 1000)
            
            if FreeGangs.Client.CurrentZone and FreeGangs.Client.PlayerGang then
                TriggerServerEvent(FreeGangs.Events.Server.PRESENCE_TICK, FreeGangs.Client.CurrentZone.name)
            end
        end
    end)
    
    -- Ped cache update
    CreateThread(function()
        while true do
            cachedPed = PlayerPedId()
            lastPedUpdate = GetGameTimer()
            Wait(1000)
        end
    end)
    
    -- GlobalState listener for territory updates
    AddStateBagChangeHandler('', 'global', function(bagName, key, value)
        if key:find('territory:') then
            local zoneName = key:gsub('territory:', '')
            FreeGangs.Client.OnTerritoryStateChange(zoneName, value)
        elseif key:find('gang:') then
            local gangName = key:gsub('gang:', '')
            FreeGangs.Client.OnGangStateChange(gangName, value)
        end
    end)
end

---Handle territory state change from GlobalState
---@param zoneName string
---@param data table
function FreeGangs.Client.OnTerritoryStateChange(zoneName, data)
    if not data then return end
    
    -- Update cached territory
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    if territories[zoneName] then
        territories[zoneName].influence = data.influence
        territories[zoneName].cooldown_until = data.cooldown_until
        FreeGangs.Client.Cache.Set('territories', territories)
    end
    
    -- If we're in this zone, update current zone data
    if FreeGangs.Client.CurrentZone and FreeGangs.Client.CurrentZone.name == zoneName then
        FreeGangs.Client.CurrentZone.data.influence = data.influence
    end
    
    -- Trigger UI update event
    TriggerEvent(FreeGangs.Events.Client.UPDATE_TERRITORY, zoneName, data)
end

---Handle gang state change from GlobalState
---@param gangName string
---@param data table
function FreeGangs.Client.OnGangStateChange(gangName, data)
    if not data then return end
    
    -- If this is our gang, update local data
    if FreeGangs.Client.PlayerGang and FreeGangs.Client.PlayerGang.name == gangName then
        FreeGangs.Client.PlayerGang.master_level = data.master_level
        FreeGangs.Client.PlayerGang.label = data.label
        FreeGangs.Client.PlayerGang.color = data.color
        FreeGangs.Client.Cache.Set('playerGang', FreeGangs.Client.PlayerGang)
    end
end

-- ============================================================================
-- KEYBINDS
-- ============================================================================

---Register keybinds
function FreeGangs.Client.RegisterKeybinds()
    local menuKey = FreeGangs.Config.UI.MenuKeybind
    if not menuKey then return end
    
    -- Register gang menu keybind
    lib.addKeybind({
        name = 'freegangs_menu',
        description = 'Open Gang Menu',
        defaultKey = menuKey,
        onPressed = function()
            if FreeGangs.Client.PlayerGang then
                TriggerEvent(FreeGangs.Events.Client.OPEN_GANG_UI)
            else
                FreeGangs.Bridge.Notify('You are not in a gang', 'error')
            end
        end,
    })
end

-- ============================================================================
-- GRAFFITI MANAGEMENT
-- ============================================================================

---Load nearby graffiti
function FreeGangs.Client.LoadNearbyGraffiti()
    if not FreeGangs.Client.CurrentZone then return end
    
    local graffiti = lib.callback.await(FreeGangs.Callbacks.GET_NEARBY_GRAFFITI, false, 
        FreeGangs.Bridge.GetPlayerCoords(),
        FreeGangs.Config.Activities.Graffiti.RenderDistance
    )
    
    if graffiti then
        for _, tag in pairs(graffiti) do
            FreeGangs.Client.SpawnGraffiti(tag)
        end
    end
end

---Clear nearby graffiti
function FreeGangs.Client.ClearNearbyGraffiti()
    for id, data in pairs(FreeGangs.Client.NearbyGraffiti) do
        FreeGangs.Client.RemoveGraffitiVisual(id)
    end
    FreeGangs.Client.NearbyGraffiti = {}
end

---Spawn a graffiti tag in the world
---@param tag table
function FreeGangs.Client.SpawnGraffiti(tag)
    -- Store reference for cleanup
    FreeGangs.Client.NearbyGraffiti[tag.id] = tag
    
    -- Visual implementation depends on method chosen
    -- Using runtime texture replacement (most performant)
    -- This would be implemented with actual texture loading
    FreeGangs.Utils.Debug('Spawned graffiti:', tag.id)
end

---Remove a graffiti visual
---@param tagId number
function FreeGangs.Client.RemoveGraffitiVisual(tagId)
    local tag = FreeGangs.Client.NearbyGraffiti[tagId]
    if not tag then return end
    
    -- Cleanup visual resources
    FreeGangs.Client.NearbyGraffiti[tagId] = nil
    FreeGangs.Utils.Debug('Removed graffiti:', tagId)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get cached player ped
---@return number
function FreeGangs.Client.GetPlayerPed()
    local now = GetGameTimer()
    if now - lastPedUpdate > 1000 then
        cachedPed = PlayerPedId()
        lastPedUpdate = now
    end
    return cachedPed or PlayerPedId()
end

---Check if player is in their gang's territory
---@return boolean
function FreeGangs.Client.IsInOwnTerritory()
    if not FreeGangs.Client.CurrentZone or not FreeGangs.Client.PlayerGang then
        return false
    end
    
    local owner = FreeGangs.Client.GetZoneOwner(FreeGangs.Client.CurrentZone.data)
    return owner == FreeGangs.Client.PlayerGang.name
end

---Check if player is in rival territory
---@return boolean, string|nil rivalGang
function FreeGangs.Client.IsInRivalTerritory()
    if not FreeGangs.Client.CurrentZone or not FreeGangs.Client.PlayerGang then
        return false, nil
    end
    
    local owner = FreeGangs.Client.GetZoneOwner(FreeGangs.Client.CurrentZone.data)
    if owner and owner ~= FreeGangs.Client.PlayerGang.name then
        return true, owner
    end
    
    return false, nil
end

---Get player's zone influence percentage
---@return number
function FreeGangs.Client.GetPlayerZoneInfluence()
    if not FreeGangs.Client.CurrentZone or not FreeGangs.Client.PlayerGang then
        return 0
    end
    
    local influence = FreeGangs.Client.CurrentZone.data.influence or {}
    return influence[FreeGangs.Client.PlayerGang.name] or 0
end

---Check if player has permission
---@param permission string
---@return boolean
function FreeGangs.Client.HasPermission(permission)
    if not FreeGangs.Client.PlayerGang then
        return false
    end
    
    local membership = FreeGangs.Client.PlayerGang.membership
    if not membership then return false end
    
    -- Boss has all permissions
    if membership.isBoss then
        return true
    end
    
    -- Check personal permissions
    if membership.permissions and membership.permissions[permission] then
        return true
    end
    
    -- Check rank-based permissions
    local rankPermissions = FreeGangs.Utils.GetDefaultPermissions(membership.rank)
    return FreeGangs.Utils.HasPermission(rankPermissions, permission)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

---Handle gang data update from server
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, function(data)
    if data then
        FreeGangs.Client.PlayerGang = data.gang
        FreeGangs.Client.PlayerGang.membership = data.membership
        FreeGangs.Client.Cache.Set('playerGang', FreeGangs.Client.PlayerGang)
        
        if data.territories then
            FreeGangs.Client.Cache.Set('territories', data.territories)
        end
    else
        FreeGangs.Client.PlayerGang = nil
        FreeGangs.Client.Cache.Remove('playerGang')
    end
end)

---Handle notification from server
RegisterNetEvent(FreeGangs.Events.Client.NOTIFY, function(message, notifyType, duration)
    FreeGangs.Bridge.Notify(message, notifyType, duration)
end)

---Handle territory alert
RegisterNetEvent(FreeGangs.Events.Client.TERRITORY_ALERT, function(zoneName, alertType, data)
    local territory = (FreeGangs.Client.Cache.Get('territories') or {})[zoneName]
    local label = territory and territory.label or zoneName
    
    if alertType == 'contested' then
        lib.notify({
            id = 'territory_alert_' .. zoneName,
            title = 'Territory Alert',
            description = string.format('%s is being contested!', label),
            type = 'warning',
            duration = 10000,
            icon = 'skull-crossbones',
            iconColor = '#FF0000',
        })
    elseif alertType == 'captured' then
        lib.notify({
            id = 'territory_alert_' .. zoneName,
            title = 'Territory Captured',
            description = string.format('Your gang now controls %s!', label),
            type = 'success',
            duration = 10000,
            icon = 'flag',
            iconColor = '#00FF00',
        })
    elseif alertType == 'lost' then
        lib.notify({
            id = 'territory_alert_' .. zoneName,
            title = 'Territory Lost',
            description = string.format('%s has been lost to %s!', label, data.newOwner or 'rivals'),
            type = 'error',
            duration = 10000,
            icon = 'flag',
            iconColor = '#FF0000',
        })
    end
end)

---Handle war alert
RegisterNetEvent(FreeGangs.Events.Client.WAR_ALERT, function(alertType, data)
    if alertType == 'declared' then
        lib.notify({
            id = 'war_alert',
            title = 'WAR DECLARED',
            description = string.format('%s has declared war on your gang!', data.enemyGang),
            type = 'error',
            duration = 15000,
            icon = 'crosshairs',
            iconColor = '#FF0000',
        })
    elseif alertType == 'started' then
        lib.notify({
            id = 'war_alert',
            title = 'WAR BEGUN',
            description = string.format('War with %s is now active!', data.enemyGang),
            type = 'warning',
            duration = 15000,
            icon = 'crosshairs',
        })
    elseif alertType == 'ended' then
        local result = data.won and 'Victory!' or 'Defeat...'
        lib.notify({
            id = 'war_alert',
            title = 'WAR ENDED - ' .. result,
            description = string.format('War with %s has concluded.', data.enemyGang),
            type = data.won and 'success' or 'error',
            duration = 15000,
            icon = 'flag-checkered',
        })
    end
end)

---Handle bribe payment reminder
RegisterNetEvent(FreeGangs.Events.Client.BRIBE_DUE, function(contactType, hoursRemaining)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return end
    
    lib.notify({
        id = 'bribe_due_' .. contactType,
        title = 'Payment Due',
        description = string.format('%s payment due in %d hours', contactInfo.label, hoursRemaining),
        type = 'warning',
        duration = 10000,
        icon = contactInfo.icon,
    })
end)

---Handle graffiti load from server
RegisterNetEvent(FreeGangs.Events.Client.LOAD_GRAFFITI, function(graffiti)
    for _, tag in pairs(graffiti) do
        FreeGangs.Client.SpawnGraffiti(tag)
    end
end)

---Handle single graffiti add
RegisterNetEvent(FreeGangs.Events.Client.ADD_GRAFFITI, function(tag)
    FreeGangs.Client.SpawnGraffiti(tag)
end)

---Handle graffiti removal
RegisterNetEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, function(tagId)
    FreeGangs.Client.RemoveGraffitiVisual(tagId)
end)

-- ============================================================================
-- RESOURCE CLEANUP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    -- Remove all zones
    for zoneName, zone in pairs(FreeGangs.Client.Zones) do
        zone:remove()
    end
    FreeGangs.Client.Zones = {}
    
    -- Clear graffiti
    FreeGangs.Client.ClearNearbyGraffiti()
end)

-- ============================================================================
-- STARTUP
-- ============================================================================

CreateThread(function()
    Wait(1000)
    Initialize()
end)

return FreeGangs.Client
