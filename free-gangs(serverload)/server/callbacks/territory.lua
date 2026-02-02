--[[
    FREE-GANGS: Server Territory Callbacks
    
    Provides callback endpoints for clients to retrieve territory data.
    Uses ox_lib callbacks for secure, validated data requests.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Callbacks = FreeGangs.Server.Callbacks or {}

-- ============================================================================
-- TERRITORY DATA CALLBACKS
-- ============================================================================

---Get all territories with current state
---@param source number
---@return table territories
lib.callback.register(FreeGangs.Callbacks.GET_TERRITORIES, function(source)
    local territories = FreeGangs.Server.Territory.GetAll()
    local result = {}
    
    for zoneName, territory in pairs(territories) do
        result[zoneName] = {
            name = zoneName,
            label = territory.label,
            zoneType = territory.zoneType,
            coords = territory.coords,
            radius = territory.radius,
            size = territory.size,
            rotation = territory.rotation,
            blipSprite = territory.blipSprite,
            blipColor = territory.blipColor,
            protectionValue = territory.protectionValue,
            influence = territory.influence,
            settings = territory.settings,
            owner = FreeGangs.Server.Territory.GetOwner(zoneName),
        }
    end
    
    return result
end)

---Get info for a specific territory
---@param source number
---@param zoneName string
---@return table|nil territoryInfo
lib.callback.register(FreeGangs.Callbacks.GET_TERRITORY_INFO, function(source, zoneName)
    if not zoneName then return nil end
    
    local territory = FreeGangs.Server.Territory.Get(zoneName)
    if not territory then return nil end
    
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    local playerInfluence = 0
    local playerTier = nil
    
    if playerGang then
        playerInfluence = territory.influence[playerGang] or 0
        playerTier = FreeGangs.Server.Territory.GetControlTier(zoneName, playerGang)
    end
    
    return {
        name = zoneName,
        label = territory.label,
        zoneType = territory.zoneType,
        coords = territory.coords,
        radius = territory.radius,
        size = territory.size,
        protectionValue = territory.protectionValue,
        influence = territory.influence,
        owner = FreeGangs.Server.Territory.GetOwner(zoneName),
        contestingGangs = FreeGangs.Server.Territory.GetContestingGangs(zoneName),
        playerInfluence = playerInfluence,
        playerControlTier = playerTier,
        cooldownUntil = territory.cooldownUntil,
        lastFlip = territory.lastFlip,
    }
end)

---Get zone control information for player's gang
---@param source number
---@param zoneName string
---@return table zoneControl
lib.callback.register(FreeGangs.Callbacks.GET_ZONE_CONTROL, function(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not zoneName then
        return {
            error = 'Zone name required',
            influence = 0,
            controlTier = FreeGangs.ZoneControlTiers[1],
            isOwner = false,
        }
    end
    
    local territory = FreeGangs.Server.Territory.Get(zoneName)
    if not territory then
        return {
            error = 'Zone not found',
            influence = 0,
            controlTier = FreeGangs.ZoneControlTiers[1],
            isOwner = false,
        }
    end
    
    local influence = 0
    local isOwner = false
    
    if playerGang then
        influence = territory.influence[playerGang] or 0
        isOwner = FreeGangs.Server.Territory.GetOwner(zoneName) == playerGang
    end
    
    local controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, playerGang)
    
    return {
        zoneName = zoneName,
        zoneLabel = territory.label,
        influence = influence,
        controlTier = controlTier,
        isOwner = isOwner,
        owner = FreeGangs.Server.Territory.GetOwner(zoneName),
        canCollectProtection = controlTier.canCollectProtection,
        drugProfitModifier = controlTier.drugProfit,
        protectionMultiplier = controlTier.protectionMultiplier,
        bribeAccess = controlTier.bribeAccess,
    }
end)

-- ============================================================================
-- GANG TERRITORY CALLBACKS
-- ============================================================================

---Get all territories for player's gang
---@param source number
---@return table gangTerritories
lib.callback.register('free-gangs:callback:getGangTerritories', function(source)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang then
        return { territories = {}, totalInfluence = 0, ownedCount = 0 }
    end
    
    local territories = FreeGangs.Server.Territory.GetGangTerritories(playerGang)
    local totalInfluence = FreeGangs.Server.Territory.GetTotalInfluence(playerGang)
    local ownedCount = FreeGangs.Server.Territory.CountOwnedTerritories(playerGang)
    
    return {
        territories = territories,
        totalInfluence = totalInfluence,
        ownedCount = ownedCount,
        canClaimNew = FreeGangs.Server.Territory.CanClaimNewTerritory(playerGang),
    }
end)

---Get territory leaderboard (top gangs by territory count)
---@param source number
---@return table leaderboard
lib.callback.register('free-gangs:callback:getTerritoryLeaderboard', function(source)
    local gangs = FreeGangs.Server.GetAllGangs()
    local leaderboard = {}
    
    for gangName, gang in pairs(gangs) do
        local ownedCount = FreeGangs.Server.Territory.CountOwnedTerritories(gangName)
        local totalInfluence = FreeGangs.Server.Territory.GetTotalInfluence(gangName)
        
        if ownedCount > 0 or totalInfluence > 0 then
            leaderboard[#leaderboard + 1] = {
                gangName = gangName,
                gangLabel = gang.label,
                gangColor = gang.color,
                ownedTerritories = ownedCount,
                totalInfluence = totalInfluence,
            }
        end
    end
    
    -- Sort by owned territories, then by total influence
    table.sort(leaderboard, function(a, b)
        if a.ownedTerritories == b.ownedTerritories then
            return a.totalInfluence > b.totalInfluence
        end
        return a.ownedTerritories > b.ownedTerritories
    end)
    
    return leaderboard
end)

-- ============================================================================
-- ZONE BENEFIT CALLBACKS
-- ============================================================================

---Get drug profit modifier for a zone
---@param source number
---@param zoneName string
---@return number modifier
lib.callback.register('free-gangs:callback:getDrugProfitModifier', function(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang or not zoneName then
        return 0
    end
    
    return FreeGangs.Server.Territory.GetDrugProfitModifier(zoneName, playerGang)
end)

---Check if player can collect protection in a zone
---@param source number
---@param zoneName string
---@return boolean
lib.callback.register('free-gangs:callback:canCollectProtection', function(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang or not zoneName then
        return false
    end
    
    return FreeGangs.Server.Territory.CanCollectProtection(zoneName, playerGang)
end)

---Get protection multiplier for a zone
---@param source number
---@param zoneName string
---@return number multiplier
lib.callback.register('free-gangs:callback:getProtectionMultiplier', function(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang or not zoneName then
        return 0
    end
    
    return FreeGangs.Server.Territory.GetProtectionMultiplier(zoneName, playerGang)
end)

---Check if player has bribe access in a zone
---@param source number
---@param zoneName string
---@return boolean
lib.callback.register('free-gangs:callback:hasBribeAccess', function(source, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang or not zoneName then
        return false
    end
    
    return FreeGangs.Server.Territory.HasBribeAccess(zoneName, playerGang)
end)

-- ============================================================================
-- TERRITORY STATUS CALLBACKS
-- ============================================================================

---Check if player is in their own territory
---@param source number
---@param zoneName string
---@return boolean
lib.callback.register('free-gangs:callback:isInOwnTerritory', function(source, zoneName)
    if not zoneName then return false end
    return FreeGangs.Server.Territory.IsInOwnTerritory(source, zoneName)
end)

---Get contesting gangs for a zone
---@param source number
---@param zoneName string
---@return table gangNames
lib.callback.register('free-gangs:callback:getContestingGangs', function(source, zoneName)
    if not zoneName then return {} end
    return FreeGangs.Server.Territory.GetContestingGangs(zoneName)
end)

---Get zone owner
---@param source number
---@param zoneName string
---@return string|nil gangName
lib.callback.register('free-gangs:callback:getZoneOwner', function(source, zoneName)
    if not zoneName then return nil end
    return FreeGangs.Server.Territory.GetOwner(zoneName)
end)

-- ============================================================================
-- PERMISSION CALLBACKS
-- ============================================================================

---Check if player can perform a territory action
---@param source number
---@param action string
---@param zoneName string
---@return boolean allowed, string|nil reason
lib.callback.register('free-gangs:callback:canPerformTerritoryAction', function(source, action, zoneName)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    if not playerGang then
        return false, 'Not in a gang'
    end
    
    if not zoneName then
        return false, 'Zone name required'
    end
    
    local territory = FreeGangs.Server.Territory.Get(zoneName)
    if not territory then
        return false, 'Zone not found'
    end
    
    local influence = territory.influence[playerGang] or 0
    local controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, playerGang)
    
    -- Check specific actions
    if action == 'collect_protection' then
        if not controlTier.canCollectProtection then
            return false, 'Need 51%+ zone control'
        end
    elseif action == 'spray_graffiti' then
        -- Always allowed in any territory
        return true, nil
    elseif action == 'remove_graffiti' then
        -- Always allowed in any territory
        return true, nil
    elseif action == 'register_business' then
        local owner = FreeGangs.Server.Territory.GetOwner(zoneName)
        if owner ~= playerGang then
            return false, 'Must own the zone to register businesses'
        end
    elseif action == 'access_bribe' then
        if not controlTier.bribeAccess then
            return false, 'Need 25%+ zone control for bribes'
        end
    end
    
    return true, nil
end)

-- ============================================================================
-- MAP DATA CALLBACKS
-- ============================================================================

---Get territory map data (for UI rendering)
---@param source number
---@return table mapData
lib.callback.register('free-gangs:callback:getTerritoryMapData', function(source)
    local territories = FreeGangs.Server.Territory.GetAll()
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    local mapData = {}
    
    for zoneName, territory in pairs(territories) do
        local owner = FreeGangs.Server.Territory.GetOwner(zoneName)
        local playerInfluence = playerGang and (territory.influence[playerGang] or 0) or 0
        
        mapData[zoneName] = {
            name = zoneName,
            label = territory.label,
            zoneType = territory.zoneType,
            coords = {
                x = territory.coords.x or territory.coords[1],
                y = territory.coords.y or territory.coords[2],
            },
            owner = owner,
            ownerLabel = owner and (FreeGangs.Server.GetGang(owner) or {}).label or nil,
            influence = territory.influence,
            playerInfluence = playerInfluence,
            isOwned = owner == playerGang,
            isContested = FreeGangs.Utils.TableLength(territory.influence) > 1,
        }
    end
    
    return mapData
end)

-- ============================================================================
-- ACTIVITY MODIFIER CALLBACKS (for other phases)
-- ============================================================================

---Get activity modifiers based on zone control
---Used by Activities phase for calculating rewards
---@param source number
---@param zoneName string
---@param activityType string
---@return table modifiers
lib.callback.register('free-gangs:callback:getActivityModifiers', function(source, zoneName, activityType)
    local playerGang = FreeGangs.Bridge.GetPlayerGang(source)
    
    local modifiers = {
        drugProfit = 0,
        repMultiplier = 1.0,
        influenceMultiplier = 1.0,
        heatMultiplier = 1.0,
        allowed = true,
        reason = nil,
    }
    
    if not playerGang then
        modifiers.allowed = false
        modifiers.reason = 'Not in a gang'
        return modifiers
    end
    
    if not zoneName then
        -- Not in a zone, use base values
        return modifiers
    end
    
    local territory = FreeGangs.Server.Territory.Get(zoneName)
    if not territory then
        return modifiers
    end
    
    local influence = territory.influence[playerGang] or 0
    local controlTier = FreeGangs.Server.Territory.GetControlTier(zoneName, playerGang)
    local owner = FreeGangs.Server.Territory.GetOwner(zoneName)
    
    -- Apply drug profit modifier
    modifiers.drugProfit = controlTier.drugProfit
    
    -- Check if in rival territory
    if owner and owner ~= playerGang then
        -- STUB: Check rivalry stage
        -- local heatStage = FreeGangs.Server.Heat.GetStage(playerGang, owner)
        -- TODO: STUB - Replace with FreeGangs.Server.Heat.GetStage()
        local heatStage = 'neutral'
        
        if heatStage == 'rivalry' then
            modifiers.drugProfit = -0.70 -- -70% in rival territory during rivalry
            modifiers.heatMultiplier = 1.5 -- More heat generated
        end
    end
    
    -- Own territory bonus
    if owner == playerGang then
        modifiers.repMultiplier = 1.1 -- +10% rep in own territory
        modifiers.heatMultiplier = 0.8 -- Less heat in own territory
    end
    
    -- Zone type specific modifiers
    local zoneSettings = FreeGangs.Config.ZoneTypeSettings[territory.zoneType]
    if zoneSettings then
        modifiers.influenceMultiplier = zoneSettings.activityBonus or 1.0
    end
    
    return modifiers
end)

-- ============================================================================
-- EXPORTS FOR EXTERNAL RESOURCES
-- ============================================================================

-- These are registered as exports for other resources to use

---Get zone control tier (export)
---@param zoneName string
---@param gangName string
---@return table tierData
exports('GetZoneControlTier', function(zoneName, gangName)
    return FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
end)

---Get zone owner (export)
---@param zoneName string
---@return string|nil gangName
exports('GetZoneOwner', function(zoneName)
    return FreeGangs.Server.Territory.GetOwner(zoneName)
end)

---Add zone influence (export)
---@param zoneName string
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
exports('AddZoneInfluence', function(zoneName, gangName, amount, reason)
    return FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, amount, reason)
end)

---Remove zone influence (export)
---@param zoneName string
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
exports('RemoveZoneInfluence', function(zoneName, gangName, amount, reason)
    return FreeGangs.Server.Territory.RemoveInfluence(zoneName, gangName, amount, reason)
end)

---Get drug profit modifier (export)
---@param zoneName string
---@param gangName string
---@return number modifier
exports('GetDrugProfitModifier', function(zoneName, gangName)
    return FreeGangs.Server.Territory.GetDrugProfitModifier(zoneName, gangName)
end)

---Check if in own territory (export)
---@param source number
---@param zoneName string
---@return boolean
exports('IsInOwnTerritory', function(source, zoneName)
    return FreeGangs.Server.Territory.IsInOwnTerritory(source, zoneName)
end)

---Get gang territories (export)
---@param gangName string
---@return table territories
exports('GetGangTerritories', function(gangName)
    return FreeGangs.Server.Territory.GetGangTerritories(gangName)
end)

---Get contesting gangs (export)
---@param zoneName string
---@return table gangNames
exports('GetContestingGangs', function(zoneName)
    return FreeGangs.Server.Territory.GetContestingGangs(zoneName)
end)

---Can collect protection (export)
---@param zoneName string
---@param gangName string
---@return boolean
exports('CanCollectProtection', function(zoneName, gangName)
    return FreeGangs.Server.Territory.CanCollectProtection(zoneName, gangName)
end)

---Get protection multiplier (export)
---@param zoneName string
---@param gangName string
---@return number
exports('GetProtectionMultiplier', function(zoneName, gangName)
    return FreeGangs.Server.Territory.GetProtectionMultiplier(zoneName, gangName)
end)

FreeGangs.Utils.Log('Territory callbacks registered')

return FreeGangs.Server.Callbacks
