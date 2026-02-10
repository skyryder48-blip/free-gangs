--[[
    FREE-GANGS: Server Territory Module
    
    Handles all server-side territory logic including:
    - Zone management and influence tracking
    - Control tier calculations and benefits
    - Capture mechanics and notifications
    - Influence decay processing
    - GlobalState synchronization
]]

FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Territory = {}

-- Local caches for performance
local territoryCache = {}
local presenceTracking = {} -- Track player presence per zone
local cooldownTimers = {}   -- Zone capture cooldowns
local contestedAlerts = {}  -- Track contested territory alerts to prevent spam (keys: "zoneName:gangName")

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the territory system
function FreeGangs.Server.Territory.Initialize()
    FreeGangs.Utils.Log('Initializing Territory System...')
    
    -- Load territories from config
    local configTerritories = FreeGangs.Config.Territories or {}
    
    -- Sync with database
    FreeGangs.Server.Territory.SyncWithDatabase(configTerritories)
    
    -- Initialize GlobalState for all territories
    FreeGangs.Server.Territory.InitializeGlobalState()
    
    -- Start presence tracking thread
    FreeGangs.Server.Territory.StartPresenceThread()
    
    FreeGangs.Utils.Log('Territory System initialized with ' .. FreeGangs.Utils.TableLength(territoryCache) .. ' zones')
end

---Sync config territories with database
---@param configTerritories table
function FreeGangs.Server.Territory.SyncWithDatabase(configTerritories)
    -- Get existing territories from DB
    local dbTerritories = FreeGangs.Server.DB.GetAllTerritories()
    local dbLookup = {}
    
    for _, territory in pairs(dbTerritories) do
        dbLookup[territory.name] = territory
    end
    
    -- Create or update territories from config
    for zoneName, config in pairs(configTerritories) do
        local existing = dbLookup[zoneName]
        
        if not existing then
            -- Create new territory in database
            local data = {
                name = zoneName,
                label = config.label,
                zone_type = config.zoneType or 'residential',
                coords = config.coords,
                radius = config.radius,
                size = config.size,
                protection_value = config.protectionValue or 0,
                settings = config.settings or {},
            }
            
            FreeGangs.Server.DB.CreateTerritory(data)
            
            territoryCache[zoneName] = {
                name = zoneName,
                label = config.label,
                zoneType = config.zoneType or 'residential',
                coords = config.coords,
                radius = config.radius,
                size = config.size,
                rotation = config.rotation,
                blipSprite = config.blipSprite,
                blipColor = config.blipColor,
                protectionValue = config.protectionValue or 0,
                settings = config.settings or {},
                influence = {},
                cooldownUntil = nil,
                lastFlip = nil,
            }
        else
            -- Use database data but merge with config for visual settings
            territoryCache[zoneName] = {
                name = zoneName,
                label = config.label,
                zoneType = config.zoneType or existing.zone_type,
                coords = config.coords,
                radius = config.radius,
                size = config.size,
                rotation = config.rotation,
                blipSprite = config.blipSprite,
                blipColor = config.blipColor,
                protectionValue = config.protectionValue or existing.protection_value,
                settings = FreeGangs.Utils.MergeTables(existing.settings or {}, config.settings or {}),
                influence = existing.influence or {},
                cooldownUntil = existing.cooldown_until,
                lastFlip = existing.last_flip,
            }
        end
    end
    
    -- Update global cache reference
    FreeGangs.Server.Territories = territoryCache
end

---Initialize GlobalState for client synchronization
function FreeGangs.Server.Territory.InitializeGlobalState()
    for zoneName, territory in pairs(territoryCache) do
        GlobalState['territory:' .. zoneName] = {
            name = zoneName,
            label = territory.label,
            zoneType = territory.zoneType,
            influence = territory.influence,
            owner = FreeGangs.Server.Territory.GetOwner(zoneName),
            controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, nil),
        }
    end
end

-- ============================================================================
-- ZONE CREATION & MANAGEMENT
-- ============================================================================

---Create a new territory zone
---@param zoneName string
---@param config table
---@return boolean success
function FreeGangs.Server.Territory.Create(zoneName, config)
    if territoryCache[zoneName] then
        FreeGangs.Utils.Debug('Territory already exists:', zoneName)
        return false
    end
    
    local data = {
        name = zoneName,
        label = config.label or zoneName,
        zone_type = config.zoneType or 'residential',
        coords = config.coords,
        radius = config.radius,
        size = config.size,
        protection_value = config.protectionValue or 0,
        settings = config.settings or {},
    }
    
    local insertId = FreeGangs.Server.DB.CreateTerritory(data)
    
    if insertId then
        territoryCache[zoneName] = {
            name = zoneName,
            label = config.label or zoneName,
            zoneType = config.zoneType or 'residential',
            coords = config.coords,
            radius = config.radius,
            size = config.size,
            rotation = config.rotation,
            blipSprite = config.blipSprite,
            blipColor = config.blipColor,
            protectionValue = config.protectionValue or 0,
            settings = config.settings or {},
            influence = {},
            cooldownUntil = nil,
            lastFlip = nil,
        }
        
        FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
        FreeGangs.Utils.Log('Created territory:', zoneName)
        return true
    end
    
    return false
end

---Get a territory by name
---@param zoneName string
---@return table|nil
function FreeGangs.Server.Territory.Get(zoneName)
    return territoryCache[zoneName]
end

---Get all territories
---@return table
function FreeGangs.Server.Territory.GetAll()
    return territoryCache
end

-- ============================================================================
-- INFLUENCE MANAGEMENT
-- ============================================================================

---Add influence to a gang in a zone
---@param zoneName string
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
function FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, amount, reason)
    local territory = territoryCache[zoneName]
    if not territory then
        FreeGangs.Utils.Debug('Territory not found:', zoneName)
        return false
    end
    
    local gang = FreeGangs.Server.GetGang(gangName)
    if not gang then
        FreeGangs.Utils.Debug('Gang not found:', gangName)
        return false
    end
    
    -- Apply zone type modifier
    local zoneSettings = FreeGangs.Config.ZoneTypeSettings[territory.zoneType] or {}
    local modifier = zoneSettings.activityBonus or 1.0
    amount = amount * modifier
    
    -- Get current influence
    local currentInfluence = territory.influence[gangName] or 0
    local newInfluence = currentInfluence + amount
    
    -- Normalize all influence to ensure total doesn't exceed 100%
    territory.influence[gangName] = math.max(0, newInfluence)
    FreeGangs.Server.Territory.NormalizeInfluence(zoneName)

    -- Check for contested territory alerts
    local ownerGang = FreeGangs.Server.Territory.GetOwner(zoneName)
    if ownerGang then
        -- Check if a rival gang's influence crossed the 25% threshold
        if gangName ~= ownerGang then
            local rivalInfluence = territory.influence[gangName] or 0
            local alertKey = zoneName .. ':' .. gangName

            if rivalInfluence >= 25 and not contestedAlerts[alertKey] then
                contestedAlerts[alertKey] = true
                local ownerMembers = FreeGangs.Server.Member.GetOnlineMembers(ownerGang)
                for _, memberSource in pairs(ownerMembers) do
                    TriggerClientEvent(FreeGangs.Events.Client.TERRITORY_ALERT, memberSource, zoneName, 'contested', {
                        rivalGang = gangName,
                        rivalInfluence = rivalInfluence,
                    })
                end
                FreeGangs.Utils.Debug(string.format('Contested alert: %s at %.1f%% in %s (owned by %s)',
                    gangName, rivalInfluence, zoneName, ownerGang))
            elseif rivalInfluence < 20 and contestedAlerts[alertKey] then
                -- Reset alert when rival drops below 20% (hysteresis to prevent spam)
                contestedAlerts[alertKey] = nil
            end
        end

        -- Also reset alerts for other gangs whose influence dropped due to normalization
        for otherGang, influence in pairs(territory.influence) do
            if otherGang ~= ownerGang and otherGang ~= gangName then
                local alertKey = zoneName .. ':' .. otherGang
                if influence < 20 and contestedAlerts[alertKey] then
                    contestedAlerts[alertKey] = nil
                end
            end
        end
    end

    -- Mark for database update
    FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
    
    -- Check for capture
    FreeGangs.Server.Territory.CheckCapture(zoneName, gangName)
    
    -- Update GlobalState
    FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
    
    -- Log the change
    FreeGangs.Server.DB.Log(gangName, nil, 'influence_add', FreeGangs.LogCategories.TERRITORY, {
        zone = zoneName,
        amount = amount,
        newInfluence = territory.influence[gangName],
        reason = reason,
    })
    
    FreeGangs.Utils.Debug(string.format('Added %.2f influence to %s in %s (reason: %s)', 
        amount, gangName, zoneName, reason or 'unknown'))
    
    return true
end

---Remove influence from a gang in a zone
---@param zoneName string
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
function FreeGangs.Server.Territory.RemoveInfluence(zoneName, gangName, amount, reason)
    local territory = territoryCache[zoneName]
    if not territory then return false end
    
    local currentInfluence = territory.influence[gangName] or 0
    if currentInfluence <= 0 then return false end
    
    local newInfluence = math.max(0, currentInfluence - amount)
    
    if newInfluence <= 0 then
        territory.influence[gangName] = nil
    else
        territory.influence[gangName] = newInfluence
    end
    
    -- Mark for database update
    FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
    
    -- Check if this caused a capture change
    FreeGangs.Server.Territory.CheckCapture(zoneName, nil)
    
    -- Update GlobalState
    FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
    
    -- Log the change
    FreeGangs.Server.DB.Log(gangName, nil, 'influence_remove', FreeGangs.LogCategories.TERRITORY, {
        zone = zoneName,
        amount = amount,
        newInfluence = territory.influence[gangName] or 0,
        reason = reason,
    })
    
    return true
end

---Set influence directly for a gang
---@param zoneName string
---@param gangName string
---@param amount number
function FreeGangs.Server.Territory.SetInfluence(zoneName, gangName, amount)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    amount = FreeGangs.Utils.Clamp(amount, 0, 100)
    
    if amount <= 0 then
        territory.influence[gangName] = nil
    else
        territory.influence[gangName] = amount
    end
    
    FreeGangs.Server.Territory.NormalizeInfluence(zoneName)
    FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
    FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
end

---Get gang influence in a zone
---@param zoneName string
---@param gangName string
---@return number
function FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)
    local territory = territoryCache[zoneName]
    if not territory then return 0 end
    
    return territory.influence[gangName] or 0
end

---Normalize influence so total doesn't exceed 100%
---@param zoneName string
function FreeGangs.Server.Territory.NormalizeInfluence(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    local total = 0
    for _, influence in pairs(territory.influence) do
        total = total + influence
    end
    
    if total > 100 then
        local scale = 100 / total
        for gangName, influence in pairs(territory.influence) do
            territory.influence[gangName] = FreeGangs.Utils.Round(influence * scale, 2)
        end
    end
end

-- ============================================================================
-- ZONE OWNERSHIP & CONTROL TIERS
-- ============================================================================

---Get the gang that owns a zone (>51% control)
---@param zoneName string
---@return string|nil gangName
function FreeGangs.Server.Territory.GetOwner(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return nil end
    
    local majority = FreeGangs.Config.Territory.MajorityThreshold
    
    for gangName, influence in pairs(territory.influence) do
        if influence >= majority then
            return gangName
        end
    end
    
    return nil
end

---Get the gang with highest influence (not necessarily owner)
---@param zoneName string
---@return string|nil gangName, number influence
function FreeGangs.Server.Territory.GetDominant(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return nil, 0 end
    
    local highestGang = nil
    local highestInfluence = 0
    
    for gangName, influence in pairs(territory.influence) do
        if influence > highestInfluence then
            highestInfluence = influence
            highestGang = gangName
        end
    end
    
    return highestGang, highestInfluence
end

---Get control tier for a gang in a zone
---@param zoneName string
---@param gangName string|nil If nil, returns tier for dominant gang
---@return table tierData
function FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    local territory = territoryCache[zoneName]
    if not territory then
        return FreeGangs.ZoneControlTiers[1] -- Worst tier
    end
    
    local influence = 0
    
    if gangName then
        influence = territory.influence[gangName] or 0
    else
        local dominant, dominantInfluence = FreeGangs.Server.Territory.GetDominant(zoneName)
        influence = dominantInfluence
    end
    
    -- Find matching tier
    for tier = 6, 1, -1 do
        local tierData = FreeGangs.ZoneControlTiers[tier]
        if influence >= tierData.minControl then
            return tierData
        end
    end
    
    return FreeGangs.ZoneControlTiers[1]
end

---Get drug profit modifier for a gang in a zone
---@param zoneName string
---@param gangName string
---@return number modifier (-0.20 to +0.15)
function FreeGangs.Server.Territory.GetDrugProfitModifier(zoneName, gangName)
    local tier = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    return tier.drugProfit or 0
end

---Check if gang can collect protection in a zone
---@param zoneName string
---@param gangName string
---@return boolean
function FreeGangs.Server.Territory.CanCollectProtection(zoneName, gangName)
    local tier = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    return tier.canCollectProtection == true
end

---Check if gang has bribe access in a zone
---@param zoneName string
---@param gangName string
---@return boolean
function FreeGangs.Server.Territory.HasBribeAccess(zoneName, gangName)
    local tier = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    return tier.bribeAccess == true
end

---Get protection multiplier for a gang in a zone
---@param zoneName string
---@param gangName string
---@return number multiplier (0 to 2.0)
function FreeGangs.Server.Territory.GetProtectionMultiplier(zoneName, gangName)
    local tier = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    return tier.protectionMultiplier or 0
end

---Check if a player's gang is in their own territory
---@param source number
---@param zoneName string
---@return boolean
function FreeGangs.Server.Territory.IsInOwnTerritory(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    if not playerGang then return false end
    
    local owner = FreeGangs.Server.Territory.GetOwner(zoneName)
    return owner == playerGang
end

---Get all gangs contesting a zone (>10% influence)
---@param zoneName string
---@return table gangNames
function FreeGangs.Server.Territory.GetContestingGangs(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return {} end
    
    local contesting = {}
    local minInfluence = FreeGangs.Config.Territory.MinInfluenceForBenefits
    
    for gangName, influence in pairs(territory.influence) do
        if influence >= minInfluence then
            contesting[#contesting + 1] = gangName
        end
    end
    
    return contesting
end

-- ============================================================================
-- CAPTURE MECHANICS
-- ============================================================================

---Check if a zone capture should occur
---@param zoneName string
---@param triggeringGang string|nil
function FreeGangs.Server.Territory.CheckCapture(zoneName, triggeringGang)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    -- Check if on cooldown
    if territory.cooldownUntil then
        local now = FreeGangs.Utils.GetTimestamp()
        if now < territory.cooldownUntil then
            FreeGangs.Utils.Debug('Zone on cooldown:', zoneName)
            return
        end
    end
    
    local currentOwner = FreeGangs.Server.Territory.GetOwner(zoneName)
    local dominant, dominantInfluence = FreeGangs.Server.Territory.GetDominant(zoneName)
    
    local majority = FreeGangs.Config.Territory.MajorityThreshold
    
    -- Case 1: Zone becomes owned by a new gang
    if dominant and dominantInfluence >= majority then
        if currentOwner ~= dominant then
            -- Enforce territory cap: only allow capture if the gang hasn't reached their max
            if FreeGangs.Server.Territory.CanClaimNewTerritory(dominant) then
                FreeGangs.Server.Territory.ProcessCapture(zoneName, currentOwner, dominant)
            else
                FreeGangs.Utils.Debug(string.format(
                    'Gang %s reached territory limit, capture blocked for zone %s',
                    dominant, zoneName))
            end
        end
    end
    
    -- Case 2: Owner loses majority (zone becomes contested)
    if currentOwner and dominantInfluence < majority then
        FreeGangs.Server.Territory.ProcessLostControl(zoneName, currentOwner)
    end
end

---Process a zone capture
---@param zoneName string
---@param oldOwner string|nil
---@param newOwner string
function FreeGangs.Server.Territory.ProcessCapture(zoneName, oldOwner, newOwner)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    local areAtWar = oldOwner and FreeGangs.Server.War.IsAtWarWith(oldOwner, newOwner) or false
    
    -- Set cooldown
    local cooldownSeconds = FreeGangs.Config.Territory.CaptureCooldownSeconds
    territory.cooldownUntil = FreeGangs.Utils.GetTimestamp() + cooldownSeconds
    territory.lastFlip = FreeGangs.Utils.GetTimestamp()
    
    -- Update database
    FreeGangs.Server.DB.SetTerritoryCooldown(zoneName, territory.cooldownUntil)
    
    -- Award capture bonus to new owner
    local capturePoints = FreeGangs.ActivityPoints[FreeGangs.Activities.ZONE_CAPTURE]
    if capturePoints then
        FreeGangs.Server.Reputation.Add(newOwner, capturePoints.masterRep, 'zone_capture')
    end
    
    -- Penalize old owner
    if oldOwner then
        local lossPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.ZONE_LOST]
        if lossPoints then
            FreeGangs.Server.Reputation.Remove(oldOwner, math.abs(lossPoints.masterRep), 'zone_lost')
        end
        
        -- Notify old owner's gang
        FreeGangs.Bridge.NotifyGang(oldOwner, 
            string.format(FreeGangs.Config.Messages.ZoneLost, territory.label), 
            'error')
        
        -- Trigger territory alert for old owner
        local oldOwnerMembers = FreeGangs.Server.Member.GetOnlineMembers(oldOwner)
        for _, source in pairs(oldOwnerMembers) do
            TriggerClientEvent(FreeGangs.Events.Client.TERRITORY_ALERT, source, zoneName, 'lost', {
                newOwner = newOwner,
            })
        end
    end
    
    -- Notify new owner's gang
    FreeGangs.Bridge.NotifyGang(newOwner, 
        string.format(FreeGangs.Config.Messages.ZoneCaptured, territory.label), 
        'success')
    
    -- Trigger territory alert for new owner
    local newOwnerMembers = FreeGangs.Server.Member.GetOnlineMembers(newOwner)
    for _, source in pairs(newOwnerMembers) do
        TriggerClientEvent(FreeGangs.Events.Client.TERRITORY_ALERT, source, zoneName, 'captured', {})
    end
    
    -- Update GlobalState
    FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
    
    -- Log the capture
    FreeGangs.Server.DB.Log(newOwner, nil, 'zone_captured', FreeGangs.LogCategories.TERRITORY, {
        zone = zoneName,
        previousOwner = oldOwner,
        influence = territory.influence[newOwner],
    })
    
    -- Send Discord webhook
    FreeGangs.Server.SendDiscordWebhook('Territory Captured', 
        string.format('**%s** has captured **%s** from %s', 
            newOwner, 
            territory.label, 
            oldOwner or 'neutral control'
        ),
        5763719 -- Green color
    )
    
    FreeGangs.Utils.Log(string.format('Zone %s captured by %s (from %s)', 
        zoneName, newOwner, oldOwner or 'neutral'))
end

---Process loss of control (below majority)
---@param zoneName string
---@param formerOwner string
function FreeGangs.Server.Territory.ProcessLostControl(zoneName, formerOwner)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    -- Notify the gang that they've lost majority
    FreeGangs.Bridge.NotifyGang(formerOwner, 
        string.format(FreeGangs.Config.Messages.ZoneContested, territory.label), 
        'warning')
    
    -- Update GlobalState
    FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
    
    FreeGangs.Utils.Log(string.format('Zone %s control lost by %s (now contested)', 
        zoneName, formerOwner))
end

-- ============================================================================
-- DECAY PROCESSING
-- ============================================================================

---Process influence decay for all territories
function FreeGangs.Server.Territory.ProcessDecay()
    local decayPercent = FreeGangs.Config.Territory.DecayPercentage
    local zonesDecayed = 0
    
    for zoneName, territory in pairs(territoryCache) do
        local zoneSettings = FreeGangs.Config.ZoneTypeSettings[territory.zoneType] or {}
        local decayModifier = zoneSettings.decayModifier or 1.0
        local actualDecay = decayPercent * decayModifier
        
        local changed = false
        
        for gangName, influence in pairs(territory.influence) do
            -- Check for neighboring zone bonus
            local neighbors = FreeGangs.Config.NeighboringZones[zoneName] or {}
            local neighborBonus = 0
            
            for _, neighborZone in pairs(neighbors) do
                local neighborOwner = FreeGangs.Server.Territory.GetOwner(neighborZone)
                if neighborOwner == gangName then
                    neighborBonus = neighborBonus + 0.5 -- 0.5% decay resistance per friendly neighbor
                end
            end
            
            local finalDecay = math.max(0, actualDecay - neighborBonus)
            local newInfluence = math.max(0, influence - finalDecay)
            
            if newInfluence ~= influence then
                if newInfluence <= 0 then
                    territory.influence[gangName] = nil
                else
                    territory.influence[gangName] = FreeGangs.Utils.Round(newInfluence, 2)
                end
                changed = true
            end
        end
        
        if changed then
            FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
            FreeGangs.Server.Territory.CheckCapture(zoneName, nil)
            FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
            zonesDecayed = zonesDecayed + 1
        end
    end
    
    FreeGangs.Utils.Debug('Processed decay for ' .. zonesDecayed .. ' zones')
end

-- ============================================================================
-- PRESENCE TRACKING
-- ============================================================================

---Track player entering a zone
---@param source number
---@param zoneName string
function FreeGangs.Server.Territory.OnPlayerEnter(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not presenceTracking[source] then
        presenceTracking[source] = {}
    end
    
    presenceTracking[source] = {
        zone = zoneName,
        enteredAt = FreeGangs.Utils.GetTimestamp(),
        lastTick = FreeGangs.Utils.GetTimestamp(),
        gang = playerGang,
    }
    
    FreeGangs.Utils.Debug(string.format('Player %d entered zone %s', source, zoneName))
end

---Track player exiting a zone
---@param source number
---@param zoneName string
function FreeGangs.Server.Territory.OnPlayerExit(source, zoneName)
    presenceTracking[source] = nil
    FreeGangs.Utils.Debug(string.format('Player %d exited zone %s', source, zoneName))
end

---Process presence tick for a player
---@param source number
---@param zoneName string
function FreeGangs.Server.Territory.ProcessPresenceTick(source, zoneName)
    local tracking = presenceTracking[source]
    if not tracking or tracking.zone ~= zoneName then return end
    
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    if not playerGang then return end
    
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    -- Check minimum influence requirement for presence bonus
    local currentInfluence = territory.influence[playerGang] or 0
    local minInfluence = 15 -- Must have 15% from activities first
    
    if currentInfluence < minInfluence then
        FreeGangs.Bridge.Notify(source, 'Need at least 15% zone influence from activities before presence bonus applies', 'inform')
        return
    end
    
    -- Calculate presence points with modifiers
    local basePoints = FreeGangs.Config.InfluencePoints.PresenceTick
    local zoneSettings = FreeGangs.Config.ZoneTypeSettings[territory.zoneType] or {}
    local presenceBonus = zoneSettings.presenceBonus or 1.0
    
    local points = basePoints * presenceBonus
    
    -- Add influence
    FreeGangs.Server.Territory.AddInfluence(zoneName, playerGang, points, 'presence_tick')
    
    -- Update last tick time
    tracking.lastTick = FreeGangs.Utils.GetTimestamp()
    
    -- Notify player
    FreeGangs.Bridge.Notify(source, 
        string.format('+%.1f zone influence (presence)', points), 
        'success')
end

---Start the presence tracking background thread
function FreeGangs.Server.Territory.StartPresenceThread()
    local tickInterval = FreeGangs.Config.Territory.PresenceTickMinutes * 60 * 1000
    
    CreateThread(function()
        while true do
            Wait(tickInterval)
            
            -- Process all tracked players
            for source, tracking in pairs(presenceTracking) do
                if tracking.zone and tracking.gang then
                    -- Verify player is still valid
                    if GetPlayerName(source) then
                        FreeGangs.Server.Territory.ProcessPresenceTick(source, tracking.zone)
                    else
                        presenceTracking[source] = nil
                    end
                end
            end
        end
    end)
end

-- ============================================================================
-- GLOBALSTATE SYNCHRONIZATION
-- ============================================================================

---Update GlobalState for a zone
---@param zoneName string
function FreeGangs.Server.Territory.UpdateGlobalState(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return end
    
    GlobalState['territory:' .. zoneName] = {
        name = zoneName,
        label = territory.label,
        zoneType = territory.zoneType,
        influence = territory.influence,
        owner = FreeGangs.Server.Territory.GetOwner(zoneName),
        controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, nil),
        cooldownUntil = territory.cooldownUntil,
    }
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get all territories owned by a gang
---@param gangName string
---@return table territories
function FreeGangs.Server.Territory.GetGangTerritories(gangName)
    local territories = {}
    local majority = FreeGangs.Config.Territory.MajorityThreshold
    
    for zoneName, territory in pairs(territoryCache) do
        local influence = territory.influence[gangName] or 0
        if influence > 0 then
            territories[zoneName] = {
                name = zoneName,
                label = territory.label,
                zoneType = territory.zoneType,
                influence = influence,
                isOwner = influence >= majority,
                controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName),
            }
        end
    end
    
    return territories
end

---Count territories owned by a gang
---@param gangName string
---@return number
function FreeGangs.Server.Territory.CountOwnedTerritories(gangName)
    local count = 0
    
    for zoneName, _ in pairs(territoryCache) do
        if FreeGangs.Server.Territory.GetOwner(zoneName) == gangName then
            count = count + 1
        end
    end
    
    return count
end

---Check if gang has reached max territories for their level
---@param gangName string
---@return boolean
function FreeGangs.Server.Territory.CanClaimNewTerritory(gangName)
    local gang = FreeGangs.Server.GetGang(gangName)
    if not gang then return false end

    local maxTerritories = FreeGangs.GetMaxTerritories(gang.master_level)
    if maxTerritories == -1 then return true end -- Unlimited

    local currentCount = FreeGangs.Server.Territory.CountOwnedTerritories(gangName)
    return currentCount < maxTerritories
end

---Get total influence points for a gang across all zones
---@param gangName string
---@return number
function FreeGangs.Server.Territory.GetTotalInfluence(gangName)
    local total = 0
    
    for _, territory in pairs(territoryCache) do
        total = total + (territory.influence[gangName] or 0)
    end
    
    return total
end

-- ============================================================================
-- ADMIN/DEBUG FUNCTIONS
-- ============================================================================

---Force set influence (admin command)
---@param zoneName string
---@param gangName string
---@param amount number
function FreeGangs.Server.Territory.AdminSetInfluence(zoneName, gangName, amount)
    FreeGangs.Server.Territory.SetInfluence(zoneName, gangName, amount)
    FreeGangs.Server.Territory.CheckCapture(zoneName, gangName)
    FreeGangs.Utils.Log(string.format('[ADMIN] Set %s influence in %s to %.2f', gangName, zoneName, amount))
end

---Force trigger decay (admin/debug)
function FreeGangs.Server.Territory.AdminTriggerDecay()
    FreeGangs.Server.Territory.ProcessDecay()
    FreeGangs.Utils.Log('[ADMIN] Manually triggered territory decay')
end

---Get debug info for a territory
---@param zoneName string
---@return table
function FreeGangs.Server.Territory.GetDebugInfo(zoneName)
    local territory = territoryCache[zoneName]
    if not territory then return { error = 'Territory not found' } end
    
    return {
        name = zoneName,
        label = territory.label,
        zoneType = territory.zoneType,
        influence = territory.influence,
        owner = FreeGangs.Server.Territory.GetOwner(zoneName),
        dominant = FreeGangs.Server.Territory.GetDominant(zoneName),
        controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, nil),
        cooldownUntil = territory.cooldownUntil,
        lastFlip = territory.lastFlip,
        contesting = FreeGangs.Server.Territory.GetContestingGangs(zoneName),
    }
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

RegisterNetEvent(FreeGangs.Events.Server.ENTER_TERRITORY, function(zoneName)
    local source = source
    FreeGangs.Server.Territory.OnPlayerEnter(source, zoneName)
end)

RegisterNetEvent(FreeGangs.Events.Server.EXIT_TERRITORY, function(zoneName)
    local source = source
    FreeGangs.Server.Territory.OnPlayerExit(source, zoneName)
end)

RegisterNetEvent(FreeGangs.Events.Server.PRESENCE_TICK, function(zoneName)
    local source = source
    FreeGangs.Server.Territory.ProcessPresenceTick(source, zoneName)
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config and FreeGangs.Config.General and FreeGangs.Config.General.Debug then
    RegisterCommand('fg_territory', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local zoneName = args[1]
        if zoneName then
            local info = FreeGangs.Server.Territory.GetDebugInfo(zoneName)
            print('[free-gangs:debug] Territory Info:')
            FreeGangs.Utils.PrintTable(info)
        else
            print('[free-gangs:debug] All Territories:')
            for name, _ in pairs(territoryCache) do
                local owner = FreeGangs.Server.Territory.GetOwner(name) or 'none'
                print(string.format('  %s: owner=%s', name, owner))
            end
        end
    end, false)
    
    RegisterCommand('fg_setinfluence', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local zoneName = args[1]
        local gangName = args[2]
        local amount = tonumber(args[3])
        
        if zoneName and gangName and amount then
            FreeGangs.Server.Territory.AdminSetInfluence(zoneName, gangName, amount)
            print(string.format('[free-gangs:debug] Set %s influence in %s to %d%%', gangName, zoneName, amount))
        else
            print('Usage: fg_setinfluence [zone] [gang] [percentage]')
        end
    end, false)
    
    RegisterCommand('fg_decaytest', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        FreeGangs.Server.Territory.AdminTriggerDecay()
        print('[free-gangs:debug] Manually triggered territory decay')
    end, false)
end

return FreeGangs.Server.Territory
