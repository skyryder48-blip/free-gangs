--[[
    FREE-GANGS: Server Exports Module
    
    Public exports for integration with other resources.
    Provides a clean API for gang membership, reputation, territory,
    heat/war, and archetype functions.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Exports = {}

-- ============================================================================
-- GANG MEMBERSHIP EXPORTS
-- ============================================================================

---Get player's gang data
---@param source number Player server ID
---@return table|nil gangData
local function GetPlayerGang(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local gangData = FreeGangs.Server.Gangs[membership.gang_name]
    if not gangData then return nil end
    
    return {
        name = gangData.name,
        label = gangData.label,
        archetype = gangData.archetype,
        color = gangData.color,
        master_level = gangData.master_level,
        rank = membership.rank,
        rankName = membership.rank_name,
        isBoss = membership.is_boss,
        isOfficer = membership.is_officer,
    }
end
exports('GetPlayerGang', GetPlayerGang)

---Check if player is in a specific gang
---@param source number Player server ID
---@param gangName string|nil Gang name (nil = check any gang)
---@return boolean
local function IsInGang(source, gangName)
    local playerGang = GetPlayerGang(source)
    if not playerGang then return false end
    
    if gangName then
        return playerGang.name == gangName
    end
    
    return true
end
exports('IsInGang', IsInGang)

---Get player's gang rank
---@param source number Player server ID
---@return number|nil rank, string|nil rankName
local function GetGangRank(source)
    local playerGang = GetPlayerGang(source)
    if not playerGang then return nil, nil end
    
    return playerGang.rank, playerGang.rankName
end
exports('GetGangRank', GetGangRank)

---Check if player has a gang permission
---@param source number Player server ID
---@param permission string Permission name
---@return boolean
local function HasGangPermission(source, permission)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    -- Boss has all permissions
    if membership.is_boss then return true end
    
    -- Check specific permission
    if membership.permissions and membership.permissions[permission] then
        return true
    end
    
    -- Check rank-based permissions
    local rankPermissions = FreeGangs.Utils.GetDefaultPermissions(membership.rank)
    return FreeGangs.Utils.HasPermission(rankPermissions, permission)
end
exports('HasGangPermission', HasGangPermission)

---Get gang data by name
---@param gangName string
---@return table|nil
local function GetGangData(gangName)
    if not gangName then return nil end
    return FreeGangs.Server.Gangs[gangName]
end
exports('GetGangData', GetGangData)

---Get all gang names
---@return table
local function GetAllGangs()
    local gangs = {}
    for gangName, _ in pairs(FreeGangs.Server.Gangs or {}) do
        table.insert(gangs, gangName)
    end
    return gangs
end
exports('GetAllGangs', GetAllGangs)

---Get gang members
---@param gangName string
---@return table
local function GetGangMembers(gangName)
    if not gangName then return {} end
    return FreeGangs.Server.DB.GetGangMembers(gangName) or {}
end
exports('GetGangMembers', GetGangMembers)

---Get online gang members
---@param gangName string
---@return table sourcesOnline
local function GetOnlineGangMembers(gangName)
    if not gangName then return {} end
    
    local onlineMembers = {}
    local players = FreeGangs.Bridge.GetPlayers()
    
    for source, player in pairs(players) do
        local gang = player.PlayerData.gang
        if gang and gang.name == gangName then
            table.insert(onlineMembers, source)
        end
    end
    
    return onlineMembers
end
exports('GetOnlineGangMembers', GetOnlineGangMembers)

-- ============================================================================
-- REPUTATION EXPORTS
-- ============================================================================

---Add master reputation to a gang
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
local function AddMasterRep(gangName, amount, reason)
    if not gangName or not amount then return false end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return false end
    
    -- Use the reputation module if available
    if FreeGangs.Server.Reputation and FreeGangs.Server.Reputation.Add then
        return FreeGangs.Server.Reputation.Add(gangName, amount, reason)
    end
    
    -- Fallback direct modification
    local currentRep = gangData.master_rep or 0
    local newRep = math.max(0, currentRep + amount)
    
    gangData.master_rep = newRep
    
    -- Check for level change
    local newLevel = FreeGangs.Utils.GetLevelFromRep(newRep)
    if newLevel ~= gangData.master_level then
        gangData.master_level = newLevel
    end
    
    -- Save to database
    FreeGangs.Server.DB.UpdateGang(gangName, { master_rep = newRep, master_level = newLevel })
    
    -- Sync to GlobalState
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    return true
end
exports('AddMasterRep', AddMasterRep)

---Remove master reputation from a gang
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
local function RemoveMasterRep(gangName, amount, reason)
    return AddMasterRep(gangName, -math.abs(amount), reason)
end
exports('RemoveMasterRep', RemoveMasterRep)

---Get master reputation for a gang
---@param gangName string
---@return number
local function GetMasterRep(gangName)
    if not gangName then return 0 end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return 0 end
    
    return gangData.master_rep or 0
end
exports('GetMasterRep', GetMasterRep)

---Get master level for a gang
---@param gangName string
---@return number
local function GetMasterLevel(gangName)
    if not gangName then return 1 end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return 1 end
    
    return gangData.master_level or 1
end
exports('GetMasterLevel', GetMasterLevel)

---Add individual reputation to a player
---@param source number
---@param amount number
---@param reason string|nil
---@return boolean success
local function AddIndividualRep(source, amount, reason)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local newRep = (membership.individual_rep or 0) + amount
    FreeGangs.Server.DB.UpdateMembership(citizenid, { individual_rep = newRep })
    
    return true
end
exports('AddIndividualRep', AddIndividualRep)

-- ============================================================================
-- TERRITORY EXPORTS
-- ============================================================================

---Get zone control percentage for a gang
---@param zoneName string
---@param gangName string
---@return number percentage (0-100)
local function GetZoneControl(zoneName, gangName)
    if not zoneName or not gangName then return 0 end
    
    local territory = FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName]
    if not territory or not territory.influence then return 0 end
    
    return territory.influence[gangName] or 0
end
exports('GetZoneControl', GetZoneControl)

---Add zone loyalty/influence for a gang
---@param zoneName string
---@param gangName string
---@param amount number
---@return boolean success
local function AddZoneLoyalty(zoneName, gangName, amount)
    if not zoneName or not gangName or not amount then return false end
    
    -- Use territory module if available
    if FreeGangs.Server.Territory and FreeGangs.Server.Territory.AddInfluence then
        return FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, amount)
    end
    
    -- Fallback
    local territory = FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName]
    if not territory then return false end
    
    territory.influence = territory.influence or {}
    local current = territory.influence[gangName] or 0
    territory.influence[gangName] = math.max(0, math.min(100, current + amount))
    
    -- Normalize all influences to 100%
    FreeGangs.Utils.NormalizeInfluence(territory.influence)
    
    -- Sync
    GlobalState['territory:' .. zoneName] = {
        influence = territory.influence,
        cooldown_until = territory.cooldown_until,
    }
    
    return true
end
exports('AddZoneLoyalty', AddZoneLoyalty)

---Get zone owner (gang with majority control)
---@param zoneName string
---@return string|nil gangName
local function GetZoneOwner(zoneName)
    if not zoneName then return nil end
    
    local territory = FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName]
    if not territory or not territory.influence then return nil end
    
    local highestGang = nil
    local highestInfluence = 0
    
    for gang, influence in pairs(territory.influence) do
        if influence > highestInfluence then
            highestInfluence = influence
            highestGang = gang
        end
    end
    
    -- Must have majority to own
    if highestInfluence >= FreeGangs.Config.Territory.MajorityThreshold then
        return highestGang
    end
    
    return nil
end
exports('GetZoneOwner', GetZoneOwner)

---Check if player is in their gang's territory
---@param source number
---@param zoneName string|nil (nil = current zone)
---@return boolean
local function IsInGangTerritory(source, zoneName)
    local playerGang = GetPlayerGang(source)
    if not playerGang then return false end
    
    if zoneName then
        return GetZoneOwner(zoneName) == playerGang.name
    end
    
    -- Would need to track player's current zone
    return false
end
exports('IsInGangTerritory', IsInGangTerritory)

---Get all territories
---@return table
local function GetAllTerritories()
    return FreeGangs.Server.Territories or {}
end
exports('GetAllTerritories', GetAllTerritories)

---Get gang's controlled territories
---@param gangName string
---@return table zoneNames
local function GetGangTerritories(gangName)
    if not gangName then return {} end
    
    local territories = {}
    for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
        if GetZoneOwner(zoneName) == gangName then
            table.insert(territories, zoneName)
        end
    end
    
    return territories
end
exports('GetGangTerritories', GetGangTerritories)

-- ============================================================================
-- HEAT & WAR EXPORTS
-- ============================================================================

---Add heat between two gangs
---@param gang1 string
---@param gang2 string
---@param amount number
---@param reason string|nil
---@return boolean success
local function AddGangHeat(gang1, gang2, amount, reason)
    if not gang1 or not gang2 or not amount then return false end
    if gang1 == gang2 then return false end
    
    -- Use heat module if available
    if FreeGangs.Server.Heat and FreeGangs.Server.Heat.Add then
        return FreeGangs.Server.Heat.Add(gang1, gang2, amount, reason)
    end
    
    -- Fallback
    local key = gang1 < gang2 and (gang1 .. ':' .. gang2) or (gang2 .. ':' .. gang1)
    FreeGangs.Server.Heat = FreeGangs.Server.Heat or {}
    
    local current = FreeGangs.Server.Heat[key] or 0
    local newHeat = math.max(0, math.min(FreeGangs.Config.Heat.MaxHeat, current + amount))
    FreeGangs.Server.Heat[key] = newHeat
    
    return true
end
exports('AddGangHeat', AddGangHeat)

---Get heat level between two gangs
---@param gang1 string
---@param gang2 string
---@return number heat (0-100)
local function GetGangHeat(gang1, gang2)
    if not gang1 or not gang2 then return 0 end
    
    local key = gang1 < gang2 and (gang1 .. ':' .. gang2) or (gang2 .. ':' .. gang1)
    return FreeGangs.Server.Heat and FreeGangs.Server.Heat[key] or 0
end
exports('GetGangHeat', GetGangHeat)

---Check if two gangs are at war
---@param gang1 string
---@param gang2 string
---@return boolean
local function AreGangsAtWar(gang1, gang2)
    if not gang1 or not gang2 then return false end
    
    for warId, war in pairs(FreeGangs.Server.ActiveWars or {}) do
        if war.status == 'active' then
            if (war.attacker_gang == gang1 and war.defender_gang == gang2) or
               (war.attacker_gang == gang2 and war.defender_gang == gang1) then
                return true
            end
        end
    end
    
    return false
end
exports('AreGangsAtWar', AreGangsAtWar)

---Get rivalry stage between two gangs
---@param gang1 string
---@param gang2 string
---@return string stage
local function GetRivalryStage(gang1, gang2)
    local heat = GetGangHeat(gang1, gang2)
    
    if heat >= 90 then return FreeGangs.HeatStages.WAR_READY
    elseif heat >= 75 then return FreeGangs.HeatStages.RIVALRY
    elseif heat >= 50 then return FreeGangs.HeatStages.COLD_WAR
    elseif heat >= 30 then return FreeGangs.HeatStages.TENSION
    else return FreeGangs.HeatStages.NEUTRAL
    end
end
exports('GetRivalryStage', GetRivalryStage)

---Get active wars for a gang
---@param gangName string
---@return table
local function GetActiveWars(gangName)
    if not gangName then return {} end
    
    local wars = {}
    for warId, war in pairs(FreeGangs.Server.ActiveWars or {}) do
        if war.attacker_gang == gangName or war.defender_gang == gangName then
            table.insert(wars, war)
        end
    end
    
    return wars
end
exports('GetActiveWars', GetActiveWars)

-- ============================================================================
-- ARCHETYPE EXPORTS
-- ============================================================================

---Get gang archetype
---@param gangName string
---@return string|nil archetype
local function GetArchetype(gangName)
    if not gangName then return nil end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return nil end
    
    return gangData.archetype
end
exports('GetArchetype', GetArchetype)

---Check if gang has archetype feature access
---@param gangName string
---@param feature string
---@return boolean
local function HasArchetypeAccess(gangName, feature)
    if not gangName or not feature then return false end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return false end
    
    local level = gangData.master_level or 1
    local archetype = gangData.archetype
    
    -- Tier access based on level
    if feature == 'tier1' then return level >= 4
    elseif feature == 'tier2' then return level >= 6
    elseif feature == 'tier3' then return level >= 8
    end
    
    -- Archetype-specific features
    local archetypeFeatures = {
        [FreeGangs.Archetypes.STREET] = { 'main_corner', 'block_party', 'driveby_contracts' },
        [FreeGangs.Archetypes.MC] = { 'prospect_runs', 'club_runs', 'territory_ride' },
        [FreeGangs.Archetypes.CARTEL] = { 'halcon_network', 'convoy_protection', 'exclusive_suppliers' },
        [FreeGangs.Archetypes.CRIME_FAMILY] = { 'tribute_network', 'high_value_contracts', 'political_immunity' },
    }
    
    local features = archetypeFeatures[archetype]
    if features then
        for _, f in ipairs(features) do
            if f == feature then
                return true
            end
        end
    end
    
    return false
end
exports('HasArchetypeAccess', HasArchetypeAccess)

---Get archetype passive bonus value
---@param gangName string
---@param bonusType string
---@return number multiplier (e.g., 1.2 for 20% bonus)
local function GetArchetypeBonus(gangName, bonusType)
    if not gangName or not bonusType then return 1.0 end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return 1.0 end
    
    local bonuses = FreeGangs.ArchetypePassiveBonuses[gangData.archetype]
    if not bonuses then return 1.0 end
    
    return bonuses[bonusType] or 1.0
end
exports('GetArchetypeBonus', GetArchetypeBonus)

-- ============================================================================
-- TREASURY EXPORTS
-- ============================================================================

---Get gang treasury balance
---@param gangName string
---@return number
local function GetTreasuryBalance(gangName)
    if not gangName then return 0 end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return 0 end
    
    return gangData.treasury or 0
end
exports('GetTreasuryBalance', GetTreasuryBalance)

---Get gang war chest balance
---@param gangName string
---@return number
local function GetWarChestBalance(gangName)
    if not gangName then return 0 end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return 0 end
    
    return gangData.war_chest or 0
end
exports('GetWarChestBalance', GetWarChestBalance)

---Deposit to gang treasury
---@param gangName string
---@param amount number
---@return boolean success
local function DepositTreasury(gangName, amount)
    if not gangName or not amount or amount <= 0 then return false end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return false end
    
    gangData.treasury = (gangData.treasury or 0) + amount
    FreeGangs.Server.DB.UpdateGang(gangName, { treasury = gangData.treasury })
    
    return true
end
exports('DepositTreasury', DepositTreasury)

---Withdraw from gang treasury
---@param gangName string
---@param amount number
---@return boolean success
local function WithdrawTreasury(gangName, amount)
    if not gangName or not amount or amount <= 0 then return false end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return false end
    
    if (gangData.treasury or 0) < amount then return false end
    
    gangData.treasury = (gangData.treasury or 0) - amount
    FreeGangs.Server.DB.UpdateGang(gangName, { treasury = gangData.treasury })
    
    return true
end
exports('WithdrawTreasury', WithdrawTreasury)

-- ============================================================================
-- BRIBE EXPORTS
-- ============================================================================

---Check if gang has active bribe
---@param gangName string
---@param contactType string
---@return boolean
local function HasActiveBribe(gangName, contactType)
    if not gangName or not contactType then return false end
    
    local gangBribes = FreeGangs.Server.Bribes and FreeGangs.Server.Bribes[gangName]
    if not gangBribes then return false end
    
    local bribe = gangBribes[contactType]
    return bribe and not bribe.is_paused
end
exports('HasActiveBribe', HasActiveBribe)

---Get all active bribes for a gang
---@param gangName string
---@return table
local function GetActiveBribes(gangName)
    if not gangName then return {} end
    return FreeGangs.Server.Bribes and FreeGangs.Server.Bribes[gangName] or {}
end
exports('GetActiveBribes', GetActiveBribes)

-- ============================================================================
-- EVENT TRIGGER EXPORTS
-- ============================================================================

---Notify a gang (all online members)
---@param gangName string
---@param message string
---@param notifyType string|nil
local function NotifyGang(gangName, message, notifyType)
    if not gangName or not message then return end
    FreeGangs.Bridge.NotifyGang(gangName, message, notifyType)
end
exports('NotifyGang', NotifyGang)

---Trigger event for all gang members
---@param gangName string
---@param eventName string
---@param ... any
local function TriggerGangEvent(gangName, eventName, ...)
    if not gangName or not eventName then return end
    
    local onlineMembers = GetOnlineGangMembers(gangName)
    for _, source in ipairs(onlineMembers) do
        TriggerClientEvent(eventName, source, ...)
    end
end
exports('TriggerGangEvent', TriggerGangEvent)

-- ============================================================================
-- UTILITY EXPORTS
-- ============================================================================

---Check if gang exists
---@param gangName string
---@return boolean
local function GangExists(gangName)
    if not gangName then return false end
    return FreeGangs.Server.Gangs[gangName] ~= nil
end
exports('GangExists', GangExists)

---Get player's citizenid from source
---@param source number
---@return string|nil
local function GetCitizenId(source)
    return FreeGangs.Bridge.GetCitizenId(source)
end
exports('GetCitizenId', GetCitizenId)

-- Log export registration
FreeGangs.Utils.Log('Server exports registered')

return FreeGangs.Server.Exports
