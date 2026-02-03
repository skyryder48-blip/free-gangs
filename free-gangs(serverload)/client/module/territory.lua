--[[
    FREE-GANGS: Client Territory Module
    
    Handles all client-side territory logic including:
    - Zone visualization (blips, markers)
    - Territory HUD display
    - Zone enter/exit handlers
    - Presence tracking and tick requests
    - Real-time influence updates via GlobalState
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Territory = {}

-- Local state
local territoryZones = {}       -- ox_lib zone objects
local territoryBlips = {}       -- Map blips
local currentZone = nil         -- Current zone player is in
local zoneHUD = {               -- HUD state
    active = false,
    zoneName = nil,
    zoneLabel = nil,
    owner = nil,
    playerInfluence = 0,
    controlTier = nil,
}
local lastPresenceTick = 0      -- Timestamp of last presence tick
local hudEnabled = true         -- HUD toggle

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the territory system
function FreeGangs.Client.Territory.Initialize()
    FreeGangs.Utils.Log('Initializing Client Territory System...')
    
    -- Wait for server data
    while not FreeGangs.Client.Ready do
        Wait(100)
    end
    
    -- Create zones from cached territories
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    
    for zoneName, territory in pairs(territories) do
        FreeGangs.Client.Territory.CreateZone(zoneName, territory)
    end
    
    -- Create map blips
    if FreeGangs.Config.TerritoryVisuals and FreeGangs.Config.TerritoryVisuals.Blips.Enabled then
        FreeGangs.Client.Territory.CreateBlips()
    end
    
    -- Start HUD render thread
    FreeGangs.Client.Territory.StartHUDThread()
    
    -- Start GlobalState listener
    FreeGangs.Client.Territory.StartStateListener()
    
    FreeGangs.Utils.Log('Client Territory System initialized with ' .. FreeGangs.Utils.TableLength(territoryZones) .. ' zones')
end

-- ============================================================================
-- ZONE CREATION & MANAGEMENT
-- ============================================================================

---Create a zone for a territory
---@param zoneName string
---@param config table
function FreeGangs.Client.Territory.CreateZone(zoneName, config)
    -- Remove existing zone if present
    if territoryZones[zoneName] then
        territoryZones[zoneName]:remove()
        territoryZones[zoneName] = nil
    end
    
    local coords = config.coords
    if not coords then return end
    
    -- Convert coords to vector if needed
    local centerVec
    if type(coords) == 'table' then
        centerVec = vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
    else
        centerVec = coords
    end
    
    local zone
    local debugMode = FreeGangs.Config.General.Debug
    
    if config.radius then
        -- Sphere zone
        zone = lib.zones.sphere({
            coords = centerVec,
            radius = config.radius,
            debug = debugMode,
            onEnter = function(self)
                FreeGangs.Client.Territory.OnEnterZone(zoneName, config)
            end,
            onExit = function(self)
                FreeGangs.Client.Territory.OnExitZone(zoneName, config)
            end,
        })
    elseif config.size then
        -- Box zone
        local sizeVec
        if type(config.size) == 'table' then
            sizeVec = vector3(config.size.x or config.size[1], config.size.y or config.size[2], config.size.z or config.size[3])
        else
            sizeVec = config.size
        end
        
        zone = lib.zones.box({
            coords = centerVec,
            size = sizeVec,
            rotation = config.rotation or 0,
            debug = debugMode,
            onEnter = function(self)
                FreeGangs.Client.Territory.OnEnterZone(zoneName, config)
            end,
            onExit = function(self)
                FreeGangs.Client.Territory.OnExitZone(zoneName, config)
            end,
        })
    end
    
    if zone then
        territoryZones[zoneName] = zone
        FreeGangs.Utils.Debug('Created zone:', zoneName)
    end
end

---Remove a territory zone
---@param zoneName string
function FreeGangs.Client.Territory.RemoveZone(zoneName)
    if territoryZones[zoneName] then
        territoryZones[zoneName]:remove()
        territoryZones[zoneName] = nil
    end
    
    if territoryBlips[zoneName] then
        RemoveBlip(territoryBlips[zoneName])
        territoryBlips[zoneName] = nil
    end
end

---Reload all zones
function FreeGangs.Client.Territory.ReloadZones()
    -- Clear existing
    for zoneName, _ in pairs(territoryZones) do
        FreeGangs.Client.Territory.RemoveZone(zoneName)
    end
    
    -- Recreate from cache
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    for zoneName, territory in pairs(territories) do
        FreeGangs.Client.Territory.CreateZone(zoneName, territory)
    end
    
    -- Recreate blips
    if FreeGangs.Config.TerritoryVisuals and FreeGangs.Config.TerritoryVisuals.Blips.Enabled then
        FreeGangs.Client.Territory.CreateBlips()
    end
end

-- ============================================================================
-- ZONE EVENT HANDLERS
-- ============================================================================

---Called when player enters a zone
---@param zoneName string
---@param config table
function FreeGangs.Client.Territory.OnEnterZone(zoneName, config)
    currentZone = {
        name = zoneName,
        config = config,
        enteredAt = GetGameTimer(),
    }
    
    -- Get real-time data from GlobalState
    local stateData = GlobalState['territory:' .. zoneName]
    if stateData then
        currentZone.influence = stateData.influence
        currentZone.owner = stateData.owner
    end
    
    -- Update HUD state
    FreeGangs.Client.Territory.UpdateHUDState(zoneName)
    
    -- Notify server
    TriggerServerEvent(FreeGangs.Events.Server.ENTER_TERRITORY, zoneName)

    -- Show entry notification only for territories controlled by a gang (>50%)
    local owner = currentZone.owner

    if owner then
        local gangData = FreeGangs.Client.Cache.Get('gangs') or {}
        local gangLabel = gangData[owner] and gangData[owner].label or owner
        FreeGangs.Bridge.Notify(string.format(FreeGangs.Config.Messages.TerritoryEntered, gangLabel .. ' territory'), 'inform', 3000)
    end

    -- Check if entering rival territory (gang members only)
    local playerGang = FreeGangs.Client.PlayerGang
    if playerGang and owner and owner ~= playerGang.name then
        -- Check heat stage with rival
        local heatInfo = FreeGangs.Client.Cache.GetHeat(owner)
        local heatStage = heatInfo and heatInfo.stage or 'neutral'
        
        if heatStage == 'cold_war' or heatStage == 'rivalry' or heatStage == 'war_ready' then
            FreeGangs.Bridge.Notify('Warning: You are in hostile territory!', 'warning', 5000)
        end
    end
    
    FreeGangs.Utils.Debug('Entered zone:', zoneName)
end

---Called when player exits a zone
---@param zoneName string
---@param config table
function FreeGangs.Client.Territory.OnExitZone(zoneName, config)
    -- Notify server
    TriggerServerEvent(FreeGangs.Events.Server.EXIT_TERRITORY, zoneName)
    
    -- Clear HUD
    zoneHUD.active = false
    currentZone = nil
    
    FreeGangs.Utils.Debug('Exited zone:', zoneName)
end

-- ============================================================================
-- HUD SYSTEM
-- ============================================================================

---Update HUD state for current zone
---@param zoneName string
function FreeGangs.Client.Territory.UpdateHUDState(zoneName)
    local stateData = GlobalState['territory:' .. zoneName]
    local config = FreeGangs.Config.Territories[zoneName]
    
    if not stateData or not config then
        zoneHUD.active = false
        return
    end
    
    local playerGang = FreeGangs.Client.PlayerGang
    local playerInfluence = 0
    
    if playerGang and stateData.influence then
        playerInfluence = stateData.influence[playerGang.name] or 0
    end
    
    -- Get control tier for player's gang
    local controlTier = FreeGangs.Client.Territory.GetControlTierForInfluence(playerInfluence)
    
    zoneHUD = {
        active = true,
        zoneName = zoneName,
        zoneLabel = config.label or zoneName,
        zoneType = stateData.zoneType or config.zoneType,
        owner = stateData.owner,
        playerInfluence = playerInfluence,
        controlTier = controlTier,
        totalInfluence = stateData.influence or {},
    }
end

---Get control tier data for an influence percentage
---@param influence number
---@return table
function FreeGangs.Client.Territory.GetControlTierForInfluence(influence)
    for tier = 6, 1, -1 do
        local tierData = FreeGangs.ZoneControlTiers[tier]
        if influence >= tierData.minControl then
            return {
                tier = tier,
                data = tierData,
            }
        end
    end
    return { tier = 1, data = FreeGangs.ZoneControlTiers[1] }
end

---Start the HUD render thread
function FreeGangs.Client.Territory.StartHUDThread()
    local hudConfig = FreeGangs.Config.TerritoryVisuals and FreeGangs.Config.TerritoryVisuals.HUD
    
    if not hudConfig or not hudConfig.Enabled then return end
    
    CreateThread(function()
        while true do
            Wait(0) -- Every frame for smooth rendering
            
            if hudEnabled and zoneHUD.active and FreeGangs.Config.UI.ShowTerritoryHUD then
                FreeGangs.Client.Territory.RenderHUD()
            else
                Wait(500) -- Sleep when not rendering
            end
        end
    end)
end

---Render the territory HUD
function FreeGangs.Client.Territory.RenderHUD()
    local hudConfig = FreeGangs.Config.TerritoryVisuals.HUD
    local x = hudConfig.Position.x
    local y = hudConfig.Position.y
    local width = hudConfig.Width
    
    local playerGang = FreeGangs.Client.PlayerGang
    local hasGang = playerGang ~= nil
    
    -- Background
    DrawRect(x, y, width, 0.08, 0, 0, 0, 150)
    
    -- Zone name
    SetTextFont(4)
    SetTextScale(0.35, 0.35)
    SetTextColour(255, 215, 0, 255) -- Gold
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(zoneHUD.zoneLabel)
    DrawText(x, y - 0.035)
    
    -- Zone type
    local zoneTypeInfo = FreeGangs.ZoneTypeInfo[zoneHUD.zoneType]
    if zoneTypeInfo then
        SetTextFont(0)
        SetTextScale(0.25, 0.25)
        SetTextColour(180, 180, 180, 255)
        SetTextCentre(true)
        SetTextEntry('STRING')
        AddTextComponentString(zoneTypeInfo.label)
        DrawText(x, y - 0.015)
    end
    
    -- Owner info
    local ownerText = zoneHUD.owner and ('Controlled by: ' .. zoneHUD.owner) or 'Contested/Neutral'
    SetTextFont(0)
    SetTextScale(0.25, 0.25)
    SetTextColour(255, 255, 255, 200)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(ownerText)
    DrawText(x, y + 0.005)
    
    -- Player influence bar (if in a gang)
    if hasGang and hudConfig.ShowInfluenceBar then
        local barY = y + 0.025
        local barWidth = width - 0.02
        local barHeight = 0.008
        
        -- Background bar
        DrawRect(x, barY, barWidth, barHeight, 50, 50, 50, 200)
        
        -- Influence fill
        local fillWidth = barWidth * (zoneHUD.playerInfluence / 100)
        local tierColors = FreeGangs.Config.TerritoryVisuals.TierColors[zoneHUD.controlTier.tier]
        DrawRect(x - (barWidth - fillWidth) / 2, barY, fillWidth, barHeight, 
            tierColors.r, tierColors.g, tierColors.b, 200)
        
        -- Influence percentage text
        SetTextFont(0)
        SetTextScale(0.22, 0.22)
        SetTextColour(255, 255, 255, 255)
        SetTextCentre(true)
        SetTextEntry('STRING')
        AddTextComponentString(string.format('%.1f%%', zoneHUD.playerInfluence))
        DrawText(x, barY + 0.005)
    end
    
    -- Control tier info
    if hasGang and hudConfig.ShowControlTier then
        local tierData = zoneHUD.controlTier.data
        local profitText
        
        if tierData.drugProfit > 0 then
            profitText = string.format('+%d%% profits', math.floor(tierData.drugProfit * 100))
        elseif tierData.drugProfit < 0 then
            profitText = string.format('%d%% profits', math.floor(tierData.drugProfit * 100))
        else
            profitText = 'Base profits'
        end
        
        SetTextFont(0)
        SetTextScale(0.2, 0.2)
        SetTextColour(200, 200, 200, 200)
        SetTextCentre(true)
        SetTextEntry('STRING')
        AddTextComponentString(profitText)
        DrawText(x, y + 0.045)
    end
end

---Toggle HUD visibility
function FreeGangs.Client.Territory.ToggleHUD()
    hudEnabled = not hudEnabled
    FreeGangs.Bridge.Notify(hudEnabled and 'Territory HUD enabled' or 'Territory HUD disabled', 'inform')
end

-- ============================================================================
-- MAP BLIPS
-- ============================================================================

---Create map blips for all territories
function FreeGangs.Client.Territory.CreateBlips()
    -- Clear existing blips
    for zoneName, blip in pairs(territoryBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    territoryBlips = {}
    
    local territories = FreeGangs.Config.Territories or {}
    local blipConfig = FreeGangs.Config.TerritoryVisuals.Blips
    
    for zoneName, config in pairs(territories) do
        local coords = config.coords
        if not coords then goto continue end
        
        local blipCoords = type(coords) == 'table' 
            and vector3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
            or coords
        
        local blip = AddBlipForCoord(blipCoords.x, blipCoords.y, blipCoords.z)
        
        SetBlipSprite(blip, config.blipSprite or blipConfig.DefaultSprite)
        SetBlipScale(blip, blipConfig.DefaultScale)
        SetBlipColour(blip, config.blipColor or 0)
        SetBlipAlpha(blip, blipConfig.DefaultAlpha)
        SetBlipAsShortRange(blip, true)
        
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(config.label or zoneName)
        EndTextCommandSetBlipName(blip)
        
        territoryBlips[zoneName] = blip
        
        ::continue::
    end
    
    FreeGangs.Utils.Debug('Created ' .. FreeGangs.Utils.TableLength(territoryBlips) .. ' territory blips')
end

---Update blip color based on ownership
---@param zoneName string
function FreeGangs.Client.Territory.UpdateBlipColor(zoneName)
    local blip = territoryBlips[zoneName]
    if not blip or not DoesBlipExist(blip) then return end
    
    local stateData = GlobalState['territory:' .. zoneName]
    local owner = stateData and stateData.owner
    
    if owner then
        -- Get gang color
        local gangs = FreeGangs.Client.Cache.Get('gangs') or {}
        local gangData = gangs[owner]
        
        if gangData and gangData.color then
            -- Convert hex to blip color (simplified)
            -- In production, you'd want a proper color mapping
            SetBlipColour(blip, 1) -- Default to red for now
        end
        
        -- Check if it's player's gang
        local playerGang = FreeGangs.Client.PlayerGang
        if playerGang and owner == playerGang.name then
            SetBlipColour(blip, 2) -- Green for own territory
        end
    else
        -- Neutral/contested
        SetBlipColour(blip, 0) -- White
    end
end

---Update all blip colors
function FreeGangs.Client.Territory.UpdateAllBlipColors()
    for zoneName, _ in pairs(territoryBlips) do
        FreeGangs.Client.Territory.UpdateBlipColor(zoneName)
    end
end

-- ============================================================================
-- GLOBALSTATE LISTENER
-- ============================================================================

---Start listening for GlobalState changes
function FreeGangs.Client.Territory.StartStateListener()
    AddStateBagChangeHandler('', 'global', function(bagName, key, value)
        -- Check if it's a territory update
        if key:find('^territory:') then
            local zoneName = key:gsub('territory:', '')
            
            -- Update cached territory data
            local territories = FreeGangs.Client.Cache.Get('territories') or {}
            if territories[zoneName] and value then
                territories[zoneName].influence = value.influence
                territories[zoneName].owner = value.owner
                FreeGangs.Client.Cache.Set('territories', territories)
            end
            
            -- Update current zone if applicable
            if currentZone and currentZone.name == zoneName then
                currentZone.influence = value.influence
                currentZone.owner = value.owner
                FreeGangs.Client.Territory.UpdateHUDState(zoneName)
            end
            
            -- Update blip color (only if blips are enabled)
            if FreeGangs.Config.TerritoryVisuals and FreeGangs.Config.TerritoryVisuals.Blips.Enabled then
                FreeGangs.Client.Territory.UpdateBlipColor(zoneName)
            end

            FreeGangs.Utils.Debug('Territory state updated:', zoneName)
        end
    end)
end

-- ============================================================================
-- PRESENCE TRACKING
-- ============================================================================

---Request presence tick from server
function FreeGangs.Client.Territory.RequestPresenceTick()
    if not currentZone then return end
    if not FreeGangs.Client.PlayerGang then return end
    
    local now = GetGameTimer()
    local tickInterval = FreeGangs.Config.Territory.PresenceTickMinutes * 60 * 1000
    
    -- Check if enough time has passed
    if now - lastPresenceTick < tickInterval then
        return
    end
    
    -- Request tick from server
    TriggerServerEvent(FreeGangs.Events.Server.PRESENCE_TICK, currentZone.name)
    lastPresenceTick = now
    
    FreeGangs.Utils.Debug('Requested presence tick for zone:', currentZone.name)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get current zone
---@return table|nil
function FreeGangs.Client.Territory.GetCurrentZone()
    return currentZone
end

---Get current zone name
---@return string|nil
function FreeGangs.Client.Territory.GetCurrentZoneName()
    return currentZone and currentZone.name or nil
end

---Check if player is in any territory
---@return boolean
function FreeGangs.Client.Territory.IsInTerritory()
    return currentZone ~= nil
end

---Check if player is in their gang's territory
---@return boolean
function FreeGangs.Client.Territory.IsInOwnTerritory()
    if not currentZone or not FreeGangs.Client.PlayerGang then
        return false
    end
    
    return currentZone.owner == FreeGangs.Client.PlayerGang.name
end

---Check if player is in rival territory
---@return boolean, string|nil rivalGang
function FreeGangs.Client.Territory.IsInRivalTerritory()
    if not currentZone or not FreeGangs.Client.PlayerGang then
        return false, nil
    end
    
    local owner = currentZone.owner
    if owner and owner ~= FreeGangs.Client.PlayerGang.name then
        return true, owner
    end
    
    return false, nil
end

---Get player's influence in current zone
---@return number
function FreeGangs.Client.Territory.GetPlayerInfluence()
    if not currentZone or not FreeGangs.Client.PlayerGang then
        return 0
    end
    
    local influence = currentZone.influence or {}
    return influence[FreeGangs.Client.PlayerGang.name] or 0
end

---Get drug profit modifier for current zone
---@return number
function FreeGangs.Client.Territory.GetDrugProfitModifier()
    if not currentZone or not FreeGangs.Client.PlayerGang then
        return 0
    end
    
    local influence = FreeGangs.Client.Territory.GetPlayerInfluence()
    local tier = FreeGangs.Client.Territory.GetControlTierForInfluence(influence)
    
    return tier.data.drugProfit or 0
end

---Get zone control tier
---@param zoneName string|nil If nil, uses current zone
---@return table|nil
function FreeGangs.Client.Territory.GetZoneControlTier(zoneName)
    local zone = zoneName and FreeGangs.Config.Territories[zoneName] or currentZone
    if not zone then return nil end
    
    if not FreeGangs.Client.PlayerGang then
        return FreeGangs.ZoneControlTiers[1]
    end
    
    local influence = FreeGangs.Client.Territory.GetPlayerInfluence()
    local tier = FreeGangs.Client.Territory.GetControlTierForInfluence(influence)
    
    return tier.data
end

---Check if gang can collect protection in current zone
---@return boolean
function FreeGangs.Client.Territory.CanCollectProtection()
    local tier = FreeGangs.Client.Territory.GetZoneControlTier(nil)
    return tier and tier.canCollectProtection == true or false
end

---Get all territories with their current state
---@return table
function FreeGangs.Client.Territory.GetAllTerritories()
    local result = {}
    local territories = FreeGangs.Config.Territories or {}
    
    for zoneName, config in pairs(territories) do
        local stateData = GlobalState['territory:' .. zoneName]
        
        result[zoneName] = {
            name = zoneName,
            label = config.label,
            zoneType = config.zoneType,
            coords = config.coords,
            influence = stateData and stateData.influence or {},
            owner = stateData and stateData.owner or nil,
        }
    end
    
    return result
end

-- ============================================================================
-- EXPORTS FOR OTHER MODULES
-- ============================================================================

-- These functions are called by other client modules (activities, etc.)

---Check if player can perform activity in current zone
---@param activityType string
---@return boolean allowed, string|nil reason
function FreeGangs.Client.Territory.CanPerformActivity(activityType)
    if not FreeGangs.Client.PlayerGang then
        return false, 'Not in a gang'
    end
    
    if not currentZone then
        return true, nil -- Not in a territory, allow anywhere
    end
    
    local influence = FreeGangs.Client.Territory.GetPlayerInfluence()
    local tier = FreeGangs.Client.Territory.GetControlTierForInfluence(influence)
    
    -- Check specific activity requirements
    if activityType == 'protection_collect' then
        if not tier.data.canCollectProtection then
            return false, 'Need 51%+ zone control to collect protection'
        end
    end
    
    return true, nil
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Handle territory alert from server
RegisterNetEvent(FreeGangs.Events.Client.TERRITORY_ALERT, function(zoneName, alertType, data)
    local config = FreeGangs.Config.Territories[zoneName]
    local label = config and config.label or zoneName
    
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

-- Handle update territory event
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_TERRITORY, function(zoneName, data)
    if not zoneName then
        -- Full refresh
        FreeGangs.Client.Territory.ReloadZones()
    else
        -- Single zone update
        local territories = FreeGangs.Client.Cache.Get('territories') or {}
        if territories[zoneName] then
            territories[zoneName] = FreeGangs.Utils.MergeTables(territories[zoneName], data)
            FreeGangs.Client.Cache.Set('territories', territories)
        end
        
        -- Update HUD if in this zone
        if currentZone and currentZone.name == zoneName then
            FreeGangs.Client.Territory.UpdateHUDState(zoneName)
        end
    end
end)

-- ============================================================================
-- KEYBINDS
-- ============================================================================

-- Toggle territory HUD
lib.addKeybind({
    name = 'freegangs_toggle_hud',
    description = 'Toggle Territory HUD',
    defaultKey = nil, -- No default, user must set
    onPressed = function()
        FreeGangs.Client.Territory.ToggleHUD()
    end,
})

-- ============================================================================
-- CLEANUP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    -- Remove all zones
    for zoneName, zone in pairs(territoryZones) do
        if zone then
            zone:remove()
        end
    end
    
    -- Remove all blips
    for zoneName, blip in pairs(territoryBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
end)

-- ============================================================================
-- INITIALIZATION TRIGGER
-- ============================================================================

-- Initialize when client is ready
CreateThread(function()
    Wait(2000) -- Wait for other systems to initialize
    FreeGangs.Client.Territory.Initialize()
end)

return FreeGangs.Client.Territory
