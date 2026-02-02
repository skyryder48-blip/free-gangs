--[[
    FREE-GANGS: Server Archetypes Module
    
    Handles all archetype-specific mechanics including:
    - Passive bonus calculations
    - Tier activity management
    - Archetype-specific features (Main Corner, Halcon Network, etc.)
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Archetypes = {}

-- Sub-modules for each archetype
FreeGangs.Server.Archetypes.Street = {}
FreeGangs.Server.Archetypes.MC = {}
FreeGangs.Server.Archetypes.Cartel = {}
FreeGangs.Server.Archetypes.CrimeFamily = {}

-- Runtime state
local ActiveBlockParties = {}    -- gangName -> { startTime, zoneName, endTime }
local ActiveClubRuns = {}        -- gangName -> { members, checkpoints, startTime }
local ActiveTerritoryRides = {}  -- gangName -> { members, visitedZones, startTime }
local ActiveConvoys = {}         -- gangName -> { vehicle, escort, route, startTime }
local ActiveDriveByContracts = {} -- gangName -> { contracts[] }
local HalconNetworkEnabled = {}  -- gangName -> boolean
local MainCorners = {}           -- gangName -> zoneName
local TributeCollections = {}    -- gangName -> lastCollectionTime

-- ============================================================================
-- PASSIVE BONUS SYSTEM
-- ============================================================================

---Get the passive bonus value for a specific bonus type
---@param gangName string
---@param bonusType string
---@return number bonusMultiplier (e.g., 0.20 for +20%)
function FreeGangs.Server.Archetypes.GetPassiveBonus(gangName, bonusType)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return 0 end
    
    local archetype = gang.archetype
    local passives = FreeGangs.ArchetypePassiveBonuses[archetype]
    
    if not passives then return 0 end
    
    return passives[bonusType] or 0
end

---Apply a passive bonus to a base value
---@param gangName string
---@param baseValue number
---@param bonusType string
---@return number modifiedValue
function FreeGangs.Server.Archetypes.ApplyBonus(gangName, baseValue, bonusType)
    local bonus = FreeGangs.Server.Archetypes.GetPassiveBonus(gangName, bonusType)
    return math.floor(baseValue * (1 + bonus))
end

---Get all active passive bonuses for a gang
---@param gangName string
---@return table bonuses
function FreeGangs.Server.Archetypes.GetAllPassiveBonuses(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return {} end
    
    local archetype = gang.archetype
    local passives = FreeGangs.ArchetypePassiveBonuses[archetype]
    
    if not passives then return {} end
    
    -- Filter to only non-zero bonuses
    local active = {}
    for bonusType, value in pairs(passives) do
        if value ~= 0 then
            active[bonusType] = value
        end
    end
    
    return active
end

-- ============================================================================
-- TIER ACCESS SYSTEM
-- ============================================================================

---Check if a gang has unlocked a specific tier
---@param gangName string
---@param tier number (1, 2, or 3)
---@return boolean
function FreeGangs.Server.Archetypes.HasTierAccess(gangName, tier)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    local requiredLevel = FreeGangs.Config.ArchetypeTiers[tier]
    if not requiredLevel then return false end
    
    return gang.master_level >= requiredLevel
end

---Get all unlocked tiers for a gang
---@param gangName string
---@return table unlockedTiers
function FreeGangs.Server.Archetypes.GetUnlockedTiers(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return {} end
    
    local unlocked = {}
    for tier, requiredLevel in pairs(FreeGangs.Config.ArchetypeTiers) do
        if gang.master_level >= requiredLevel then
            unlocked[tier] = true
        end
    end
    
    return unlocked
end

---Get tier activity info for a gang's archetype
---@param gangName string
---@param tier number
---@return table|nil activityInfo
function FreeGangs.Server.Archetypes.GetTierActivity(gangName, tier)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return nil end
    
    local archetype = gang.archetype
    local activities = FreeGangs.ArchetypeTierActivities[archetype]
    
    if not activities then return nil end
    
    return activities[tier]
end

---Check if a gang can execute a tier activity
---@param gangName string
---@param tier number
---@return boolean canExecute
---@return string|nil reason
function FreeGangs.Server.Archetypes.CanExecuteTierActivity(gangName, tier)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, tier) then
        local requiredLevel = FreeGangs.Config.ArchetypeTiers[tier]
        return false, 'Requires Master Level ' .. requiredLevel
    end
    
    local activity = FreeGangs.Server.Archetypes.GetTierActivity(gangName, tier)
    if not activity then
        return false, 'No activity available for this tier'
    end
    
    return true
end

-- ============================================================================
-- ACTIVITY EXECUTION ROUTER
-- ============================================================================

---Execute a tier activity
---@param source number Player source
---@param activityName string
---@param params table|nil Optional parameters
---@return boolean success
---@return string|nil message
function FreeGangs.Server.Archetypes.ExecuteTierActivity(source, activityName, params)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Unable to identify player' end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false, 'You are not in a gang' end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    -- Route to appropriate handler based on archetype and activity
    local archetype = gang.archetype
    
    -- Street Gang activities
    if archetype == FreeGangs.Archetypes.STREET then
        if activityName == 'main_corner' then
            return FreeGangs.Server.Archetypes.Street.SetMainCorner(source, gangName, params)
        elseif activityName == 'block_party' then
            return FreeGangs.Server.Archetypes.Street.StartBlockParty(source, gangName, params)
        elseif activityName == 'driveby_contract' then
            return FreeGangs.Server.Archetypes.Street.AcceptDriveByContract(source, gangName, params)
        end
    
    -- MC activities
    elseif archetype == FreeGangs.Archetypes.MC then
        if activityName == 'prospect_run' then
            return FreeGangs.Server.Archetypes.MC.StartProspectRun(source, gangName, params)
        elseif activityName == 'club_run' then
            return FreeGangs.Server.Archetypes.MC.StartClubRun(source, gangName, params)
        elseif activityName == 'territory_ride' then
            return FreeGangs.Server.Archetypes.MC.StartTerritoryRide(source, gangName, params)
        end
    
    -- Cartel activities
    elseif archetype == FreeGangs.Archetypes.CARTEL then
        if activityName == 'halcon_network' then
            return FreeGangs.Server.Archetypes.Cartel.ToggleHalconNetwork(source, gangName, params)
        elseif activityName == 'convoy_protection' then
            return FreeGangs.Server.Archetypes.Cartel.StartConvoyProtection(source, gangName, params)
        elseif activityName == 'exclusive_supplier' then
            return FreeGangs.Server.Archetypes.Cartel.AccessExclusiveSupplier(source, gangName, params)
        end
    
    -- Crime Family activities
    elseif archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        if activityName == 'tribute_network' then
            return FreeGangs.Server.Archetypes.CrimeFamily.CollectTribute(source, gangName, params)
        elseif activityName == 'high_value_contract' then
            return FreeGangs.Server.Archetypes.CrimeFamily.StartHighValueContract(source, gangName, params)
        elseif activityName == 'political_immunity' then
            return FreeGangs.Server.Archetypes.CrimeFamily.CheckPoliticalImmunity(source, gangName, params)
        end
    end
    
    return false, 'Unknown activity: ' .. activityName
end

-- ============================================================================
-- STREET GANG: MAIN CORNER (TIER 1)
-- ============================================================================

---Set a zone as the gang's main corner
---@param source number
---@param gangName string
---@param params table { zoneName: string }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.SetMainCorner(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.STREET then
        return false, 'Only Street Gangs can set a main corner'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return false, 'Requires Master Level 4'
    end
    
    local zoneName = params and params.zoneName
    if not zoneName then
        return false, 'No zone specified'
    end
    
    -- Check zone control
    local control = FreeGangs.Server.GetZoneControl and 
                    FreeGangs.Server.GetZoneControl(zoneName, gangName) or 0
    local config = FreeGangs.Config.StreetGang.MainCorner
    
    if control < config.MinZoneControl then
        return false, 'Requires at least ' .. config.MinZoneControl .. '% zone control'
    end
    
    -- Check cooldown
    local cooldownKey = 'main_corner_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Main corner change on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Set main corner
    local oldCorner = MainCorners[gangName]
    MainCorners[gangName] = zoneName
    
    -- Update database
    FreeGangs.Server.DB.SetGangMetadata(gangName, 'main_corner', zoneName)
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.MinZoneControl and 3600 or FreeGangs.Config.ActivityCooldowns.main_corner_set)
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'main_corner_set', FreeGangs.LogCategories.ACTIVITY, {
        zoneName = zoneName,
        previousCorner = oldCorner,
    })
    
    -- Notify gang members
    FreeGangs.Server.NotifyGangMembers(gangName, 'Main corner set to ' .. zoneName, 'success')
    
    return true, 'Main corner set successfully'
end

---Get the main corner for a gang
---@param gangName string
---@return string|nil zoneName
function FreeGangs.Server.Archetypes.Street.GetMainCorner(gangName)
    return MainCorners[gangName]
end

---Check if a zone is a gang's main corner
---@param gangName string
---@param zoneName string
---@return boolean
function FreeGangs.Server.Archetypes.Street.IsMainCorner(gangName, zoneName)
    return MainCorners[gangName] == zoneName
end

---Get bonus rep for drug sale in main corner
---@param gangName string
---@param zoneName string
---@return number bonusRep
function FreeGangs.Server.Archetypes.Street.GetMainCornerBonus(gangName, zoneName)
    if not FreeGangs.Server.Archetypes.Street.IsMainCorner(gangName, zoneName) then
        return 0
    end
    
    return FreeGangs.Config.StreetGang.MainCorner.BonusRepPerSale
end

-- ============================================================================
-- STREET GANG: BLOCK PARTY (TIER 2)
-- ============================================================================

---Start a block party event
---@param source number
---@param gangName string
---@param params table { zoneName: string }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.StartBlockParty(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.STREET then
        return false, 'Only Street Gangs can host block parties'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 2) then
        return false, 'Requires Master Level 6'
    end
    
    local zoneName = params and params.zoneName
    if not zoneName then
        return false, 'No zone specified'
    end
    
    -- Check if party already active
    if ActiveBlockParties[gangName] then
        local remaining = ActiveBlockParties[gangName].endTime - os.time()
        if remaining > 0 then
            return false, 'Block party already active. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
        end
    end
    
    -- Check cooldown
    local cooldownKey = 'block_party_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Block party on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    local config = FreeGangs.Config.StreetGang.BlockParty
    
    -- Check zone control
    local control = FreeGangs.Server.GetZoneControl and 
                    FreeGangs.Server.GetZoneControl(zoneName, gangName) or 0
    if control < config.MinZoneControl then
        return false, 'Requires at least ' .. config.MinZoneControl .. '% zone control'
    end
    
    -- Check minimum members online
    local onlineMembers = FreeGangs.Server.GetOnlineGangMembers(gangName)
    if #onlineMembers < config.MinMembersOnline then
        return false, 'Requires at least ' .. config.MinMembersOnline .. ' members online'
    end
    
    -- Start block party
    local startTime = os.time()
    local endTime = startTime + config.Duration
    
    ActiveBlockParties[gangName] = {
        zoneName = zoneName,
        startTime = startTime,
        endTime = endTime,
        startedBy = FreeGangs.Bridge.GetCitizenId(source),
    }
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.Cooldown)
    
    -- Notify all gang members
    FreeGangs.Server.NotifyGangMembers(gangName, 'Block party started in ' .. zoneName .. '! 2x loyalty for 1 hour!', 'success')
    
    -- Notify nearby players (not in gang)
    TriggerClientEvent(FreeGangs.Events.Client.TERRITORY_ALERT, -1, {
        type = 'block_party',
        zoneName = zoneName,
        gangName = gangName,
        gangLabel = gang.label,
    })
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'block_party_started', FreeGangs.LogCategories.ACTIVITY, {
        zoneName = zoneName,
        duration = config.Duration,
    })
    
    -- Schedule end
    SetTimeout(config.Duration * 1000, function()
        FreeGangs.Server.Archetypes.Street.EndBlockParty(gangName)
    end)
    
    return true, 'Block party started!'
end

---End a block party
---@param gangName string
function FreeGangs.Server.Archetypes.Street.EndBlockParty(gangName)
    if not ActiveBlockParties[gangName] then return end
    
    local party = ActiveBlockParties[gangName]
    ActiveBlockParties[gangName] = nil
    
    -- Notify gang
    FreeGangs.Server.NotifyGangMembers(gangName, 'Block party has ended', 'inform')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, nil, 'block_party_ended', FreeGangs.LogCategories.ACTIVITY, {
        zoneName = party.zoneName,
        duration = os.time() - party.startTime,
    })
end

---Check if a block party is active for a gang
---@param gangName string
---@return boolean, table|nil partyInfo
function FreeGangs.Server.Archetypes.Street.IsBlockPartyActive(gangName)
    local party = ActiveBlockParties[gangName]
    if not party then return false, nil end
    
    if os.time() > party.endTime then
        ActiveBlockParties[gangName] = nil
        return false, nil
    end
    
    return true, party
end

---Get the loyalty multiplier (for block party bonus)
---@param gangName string
---@param zoneName string
---@return number multiplier
function FreeGangs.Server.Archetypes.Street.GetLoyaltyMultiplier(gangName, zoneName)
    local active, party = FreeGangs.Server.Archetypes.Street.IsBlockPartyActive(gangName)
    if active and party.zoneName == zoneName then
        return FreeGangs.Config.StreetGang.BlockParty.LoyaltyMultiplier
    end
    return 1.0
end

-- ============================================================================
-- STREET GANG: DRIVE-BY CONTRACTS (TIER 3)
-- Target NPCs in opposing gang territories via ox_target
-- Rewards: Payout, rep increase, territory influence gain, heat escalation
-- Failure: Rep loss, territory influence loss
-- ============================================================================

-- Active drive-by missions (one per gang at a time)
local ActiveDriveByMissions = {} -- gangName -> missionData

---Start a drive-by contract targeting NPCs in rival territory
---@param source number
---@param gangName string
---@param params table|nil { targetZone?: string, targetGang?: string }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.AcceptDriveByContract(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.STREET then
        return false, 'Only Street Gangs can accept drive-by contracts'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 3) then
        return false, 'Requires Master Level 8'
    end
    
    local config = FreeGangs.Config.StreetGang.DriveByContracts
    
    -- Check if mission already active
    if ActiveDriveByMissions[gangName] and ActiveDriveByMissions[gangName].status == 'active' then
        local remaining = ActiveDriveByMissions[gangName].expiresAt - os.time()
        if remaining > 0 then
            return false, 'Drive-by mission already active. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
        end
    end
    
    -- Check cooldown
    local cooldownKey = 'driveby_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Contracts on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Find valid target zone (must be opposing gang territory)
    local targetZone = params and params.targetZone
    local targetGang = params and params.targetGang
    
    if not targetZone or not targetGang then
        -- Auto-select a rival territory
        local rivalTerritories = FreeGangs.Server.Archetypes.Street.FindRivalTerritories(gangName)
        if #rivalTerritories == 0 then
            return false, 'No rival gang territories available for contracts'
        end
        
        local selected = rivalTerritories[math.random(1, #rivalTerritories)]
        targetZone = selected.zoneName
        targetGang = selected.gangName
    end
    
    -- Validate target zone is owned by rival
    local zoneControl = 0
    if FreeGangs.Server.Territory and FreeGangs.Server.Territory.GetInfluence then
        zoneControl = FreeGangs.Server.Territory.GetInfluence(targetZone, targetGang) or 0
    elseif FreeGangs.Server.Territories[targetZone] then
        local inf = FreeGangs.Server.Territories[targetZone].influence or {}
        zoneControl = inf[targetGang] or 0
    end
    
    if zoneControl < 25 then
        return false, 'Target zone must have at least 25% rival gang control'
    end
    
    -- Get territory data
    local territory = FreeGangs.Server.Territories[targetZone]
    if not territory or not territory.coords then
        return false, 'Invalid target zone'
    end
    
    -- Generate mission parameters
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local payout = math.random(config.MinPayout, config.MaxPayout)
    local timeLimit = config.TimeLimitSeconds or 900 -- 15 minutes default
    
    local mission = {
        id = FreeGangs.Utils.GenerateId('dbc'),
        gangName = gangName,
        startedBy = citizenid,
        startedBySource = source,
        targetZone = targetZone,
        targetGang = targetGang,
        targetCoords = territory.coords,
        payout = payout,
        repGain = config.RepBonus or 50,
        influenceGain = config.InfluenceGain or 5,
        heatGain = config.HeatGenerated or 25,
        status = 'active',
        startedAt = os.time(),
        expiresAt = os.time() + timeLimit,
        timeLimit = timeLimit,
        targetsKilled = 0,
        requiredKills = config.RequiredKills or 1,
    }
    
    ActiveDriveByMissions[gangName] = mission
    
    -- Send mission data to client
    local targetGangData = FreeGangs.Server.Gangs[targetGang]
    TriggerClientEvent('free-gangs:client:startDriveByMission', source, {
        missionId = mission.id,
        targetZone = targetZone,
        targetZoneLabel = territory.label or targetZone,
        targetGang = targetGang,
        targetGangLabel = targetGangData and targetGangData.label or targetGang,
        targetCoords = mission.targetCoords,
        payout = payout,
        repGain = mission.repGain,
        influenceGain = mission.influenceGain,
        timeLimit = timeLimit,
        requiredKills = mission.requiredKills,
    })
    
    -- Schedule expiry check
    SetTimeout(timeLimit * 1000 + 1000, function()
        FreeGangs.Server.Archetypes.Street.CheckDriveByExpiry(gangName)
    end)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'driveby_mission_started', FreeGangs.LogCategories.ACTIVITY, {
        missionId = mission.id,
        targetZone = targetZone,
        targetGang = targetGang,
    })
    
    return true, 'Drive-by contract accepted! Target zone: ' .. (territory.label or targetZone)
end

---Find rival gang territories for targeting
---@param gangName string
---@return table[] territories
function FreeGangs.Server.Archetypes.Street.FindRivalTerritories(gangName)
    local rivalTerritories = {}
    
    for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
        local influence = territory.influence or {}
        for ownerGang, control in pairs(influence) do
            if ownerGang ~= gangName and control >= 25 and FreeGangs.Server.Gangs[ownerGang] then
                table.insert(rivalTerritories, {
                    zoneName = zoneName,
                    gangName = ownerGang,
                    control = control,
                })
            end
        end
    end
    
    return rivalTerritories
end

---Record a kill during drive-by mission (called from client via ox_target)
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.RecordDriveByKill(source, gangName)
    local mission = ActiveDriveByMissions[gangName]
    if not mission or mission.status ~= 'active' then
        return false, 'No active drive-by mission'
    end
    
    -- Check if mission expired
    if os.time() >= mission.expiresAt then
        FreeGangs.Server.Archetypes.Street.FailDriveByMission(gangName, 'Time expired')
        return false, 'Mission time expired'
    end
    
    mission.targetsKilled = mission.targetsKilled + 1
    
    -- Check if mission complete
    if mission.targetsKilled >= mission.requiredKills then
        return FreeGangs.Server.Archetypes.Street.CompleteDriveByMission(source, gangName)
    end
    
    local remaining = mission.requiredKills - mission.targetsKilled
    FreeGangs.Bridge.Notify(source, 'Target eliminated! ' .. remaining .. ' remaining.', 'success')
    
    return true, 'Kill recorded'
end

---Complete drive-by mission successfully
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.CompleteDriveByMission(source, gangName)
    local mission = ActiveDriveByMissions[gangName]
    if not mission then return false, 'No active mission' end
    
    mission.status = 'completed'
    mission.completedAt = os.time()
    
    local config = FreeGangs.Config.StreetGang.DriveByContracts
    
    -- === SUCCESS REWARDS ===
    
    -- 1. Cash payout
    FreeGangs.Bridge.AddMoney(source, mission.payout, 'cash', 'Drive-by contract completion')
    
    -- 2. Reputation increase
    FreeGangs.Server.Reputation.Add(gangName, mission.repGain, 'Drive-by contract completed')
    
    -- 3. Territory influence gain in target zone
    if FreeGangs.Server.Territory and FreeGangs.Server.Territory.AddInfluence then
        FreeGangs.Server.Territory.AddInfluence(mission.targetZone, gangName, mission.influenceGain)
    end
    
    -- 4. Heat escalation with target gang
    if FreeGangs.Server.Heat and FreeGangs.Server.Heat.Add then
        FreeGangs.Server.Heat.Add(gangName, mission.targetGang, mission.heatGain, 'Drive-by attack')
    end
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, 'driveby_' .. gangName, config.Cooldown or 7200)
    
    -- Notify completing gang
    local targetGangLabel = FreeGangs.Server.Gangs[mission.targetGang] and FreeGangs.Server.Gangs[mission.targetGang].label or mission.targetGang
    FreeGangs.Server.NotifyGangMembers(gangName, 
        'Drive-by completed in ' .. mission.targetZone .. '! +$' .. FreeGangs.Utils.FormatMoney(mission.payout) .. ', +' .. mission.repGain .. ' rep, +' .. mission.influenceGain .. ' influence',
        'success')
    
    -- Notify target gang they were hit
    local attackerLabel = FreeGangs.Server.Gangs[gangName] and FreeGangs.Server.Gangs[gangName].label or gangName
    FreeGangs.Server.NotifyGangMembers(mission.targetGang,
        'Your territory ' .. mission.targetZone .. ' was attacked by ' .. attackerLabel .. '!',
        'error')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, mission.startedBy, 'driveby_mission_completed', FreeGangs.LogCategories.ACTIVITY, {
        missionId = mission.id,
        targetZone = mission.targetZone,
        targetGang = mission.targetGang,
        payout = mission.payout,
        repGain = mission.repGain,
        influenceGain = mission.influenceGain,
        heatGain = mission.heatGain,
    })
    
    ActiveDriveByMissions[gangName] = nil
    
    return true, 'Mission completed!'
end

---Fail drive-by mission with penalties
---@param gangName string
---@param reason string
function FreeGangs.Server.Archetypes.Street.FailDriveByMission(gangName, reason)
    local mission = ActiveDriveByMissions[gangName]
    if not mission or mission.status ~= 'active' then return end
    
    mission.status = 'failed'
    mission.failedAt = os.time()
    mission.failReason = reason
    
    local config = FreeGangs.Config.StreetGang.DriveByContracts.FailurePenalty or {}
    local repLoss = config.repLoss or 25
    local influenceLoss = config.influenceLoss or 3
    
    -- === FAILURE PENALTIES ===
    
    -- 1. Reputation loss
    FreeGangs.Server.Reputation.Remove(gangName, repLoss, 'Failed drive-by contract: ' .. reason)
    
    -- 2. Territory influence loss in target zone (lost ground)
    if FreeGangs.Server.Territory and FreeGangs.Server.Territory.RemoveInfluence then
        FreeGangs.Server.Territory.RemoveInfluence(mission.targetZone, gangName, influenceLoss)
    end
    
    -- Notify
    local startedByPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(mission.startedBy)
    if startedByPlayer then
        FreeGangs.Bridge.Notify(startedByPlayer.PlayerData.source, 
            'Drive-by mission failed! -' .. repLoss .. ' rep, -' .. influenceLoss .. ' influence. Reason: ' .. reason, 
            'error')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, mission.startedBy, 'driveby_mission_failed', FreeGangs.LogCategories.ACTIVITY, {
        missionId = mission.id,
        reason = reason,
        repLoss = repLoss,
        influenceLoss = influenceLoss,
    })
    
    ActiveDriveByMissions[gangName] = nil
end

---Cancel/abandon drive-by mission
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Street.CancelDriveByMission(source, gangName)
    local mission = ActiveDriveByMissions[gangName]
    if not mission or mission.status ~= 'active' then
        return false, 'No active mission to cancel'
    end
    
    FreeGangs.Server.Archetypes.Street.FailDriveByMission(gangName, 'Mission abandoned')
    return true, 'Mission cancelled'
end

---Check and expire timed-out drive-by missions
---@param gangName string|nil Check specific gang or all if nil
function FreeGangs.Server.Archetypes.Street.CheckDriveByExpiry(gangName)
    if gangName then
        local mission = ActiveDriveByMissions[gangName]
        if mission and mission.status == 'active' and os.time() >= mission.expiresAt then
            FreeGangs.Server.Archetypes.Street.FailDriveByMission(gangName, 'Time expired')
        end
    else
        for gName, mission in pairs(ActiveDriveByMissions) do
            if mission.status == 'active' and os.time() >= mission.expiresAt then
                FreeGangs.Server.Archetypes.Street.FailDriveByMission(gName, 'Time expired')
            end
        end
    end
end

---Get active drive-by mission status
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.Street.GetDriveByMissionStatus(gangName)
    local mission = ActiveDriveByMissions[gangName]
    if not mission or mission.status ~= 'active' then return nil end
    
    return {
        id = mission.id,
        targetZone = mission.targetZone,
        targetGang = mission.targetGang,
        targetsKilled = mission.targetsKilled,
        requiredKills = mission.requiredKills,
        timeRemaining = math.max(0, mission.expiresAt - os.time()),
        payout = mission.payout,
        repGain = mission.repGain,
        influenceGain = mission.influenceGain,
    }
end

-- ============================================================================
-- MC: PROSPECT RUNS (TIER 1)
-- Item delivery missions with ambush risks
-- Required items must be delivered to destination territory
-- Ambush risk at destination (lower with higher gang rep)
-- NPC biker ambush along route (more NPCs with higher gang rep - increased difficulty)
-- Success: Territory rep in trap spot + destination, loot table rewards
-- ============================================================================

-- Active prospect runs (per player)
local ActiveProspectRuns = {} -- citizenid -> runData

---Start a prospect run - generates required items and destination
---@param source number
---@param gangName string
---@param params table|nil
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.StartProspectRun(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.MC then
        return false, 'Only MCs can start prospect runs'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return false, 'Requires Master Level 4'
    end
    
    local config = FreeGangs.Config.MC.ProspectRuns
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    -- Check if player already has active run
    if ActiveProspectRuns[citizenid] then
        return false, 'You already have an active prospect run'
    end
    
    -- Check player rank (must be prospect - rank 0)
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if membership and membership.rank > 0 then
        return false, 'Only prospects can perform prospect runs'
    end
    
    -- Check if on motorcycle
    if config.RequiresBike then
        local ped = GetPlayerPed(source)
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then
            return false, 'You must be on a motorcycle'
        end
        
        local vehicleModel = GetEntityModel(vehicle)
        local isValidBike = false
        for _, model in ipairs(config.ValidBikeModels or {}) do
            if GetHashKey(model) == vehicleModel then
                isValidBike = true
                break
            end
        end
        
        if not isValidBike then
            return false, 'You must be on an approved motorcycle'
        end
    end
    
    -- Check cooldown
    local cooldownKey = 'prospect_run_' .. citizenid
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Prospect run on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Generate required items to deliver
    local requiredItems = FreeGangs.Server.Archetypes.MC.GenerateDeliveryItems(config)
    
    -- Get trap spot and destination territory
    local trapSpot = gang.trap_spot and json.decode(gang.trap_spot) or nil
    local destination = FreeGangs.Server.Archetypes.MC.GetDeliveryDestination(gangName)
    
    if not destination then
        return false, 'No valid delivery destination found'
    end
    
    -- Calculate ambush chances based on gang reputation
    local gangRep = gang.reputation or 0
    
    -- Destination ambush/doublecross chance (DECREASES with rep - you're more trusted)
    local baseAmbushChance = config.DestinationAmbushChance or 0.25
    local ambushReduction = math.min(0.20, gangRep / 5000) -- Max 20% reduction at 5000 rep
    local destinationAmbushChance = math.max(0.05, baseAmbushChance - ambushReduction)
    
    -- Route ambush NPC count (INCREASES with rep - more enemies target you)
    local baseAmbushNPCs = config.RouteAmbush.BaseNPCCount or 2
    local additionalNPCs = math.floor(gangRep / 1000) -- +1 NPC per 1000 rep
    local maxAmbushNPCs = math.min(config.RouteAmbush.MaxNPCCount or 6, baseAmbushNPCs + additionalNPCs)
    
    -- Route ambush spawn chance
    local routeAmbushChance = config.RouteAmbush.SpawnChance or 0.40
    
    -- Create run data
    local runId = FreeGangs.Utils.GenerateId('pr')
    local timeLimitSeconds = config.TimeLimitMinutes * 60
    
    local runData = {
        id = runId,
        gangName = gangName,
        citizenid = citizenid,
        source = source,
        requiredItems = requiredItems,
        trapSpot = trapSpot,
        destination = destination,
        destinationTerritory = destination.territory,
        status = 'active',
        startedAt = os.time(),
        expiresAt = os.time() + timeLimitSeconds,
        timeLimit = timeLimitSeconds,
        destinationAmbushChance = destinationAmbushChance,
        routeAmbushChance = routeAmbushChance,
        routeAmbushNPCCount = maxAmbushNPCs,
        itemsDelivered = false,
    }
    
    ActiveProspectRuns[citizenid] = runData
    
    -- Send to client with item list and destination
    TriggerClientEvent('free-gangs:client:startProspectRun', source, {
        runId = runId,
        requiredItems = requiredItems,
        destination = destination,
        trapSpot = trapSpot,
        timeLimit = timeLimitSeconds,
        destinationAmbushChance = destinationAmbushChance,
        routeAmbushChance = routeAmbushChance,
        routeAmbushNPCCount = maxAmbushNPCs,
        npcAmbushModels = config.RouteAmbush.NPCModels or { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03' },
        npcAmbushVehicles = config.RouteAmbush.Vehicles or { 'daemon', 'hexer', 'zombieb' },
    })
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.Cooldown or 3600)
    
    -- Schedule expiry check
    SetTimeout(timeLimitSeconds * 1000 + 1000, function()
        FreeGangs.Server.Archetypes.MC.CheckProspectRunExpiry(citizenid, runId)
    end)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'prospect_run_started', FreeGangs.LogCategories.ACTIVITY, {
        runId = runId,
        requiredItems = requiredItems,
        destination = destination.territory,
        timeLimit = timeLimitSeconds,
    })
    
    -- Build item list string for notification
    local itemListStr = ''
    for _, item in ipairs(requiredItems) do
        itemListStr = itemListStr .. item.label .. ' x' .. item.count .. ', '
    end
    itemListStr = itemListStr:sub(1, -3) -- Remove trailing comma
    
    return true, 'Prospect run started! Deliver: ' .. itemListStr .. ' | Time: ' .. config.TimeLimitMinutes .. ' minutes'
end

---Generate random items required for delivery
---@param config table
---@return table items
function FreeGangs.Server.Archetypes.MC.GenerateDeliveryItems(config)
    local items = {}
    local itemPool = config.DeliveryItems or {
        { name = 'weed_bag', label = 'Weed Bag', minCount = 5, maxCount = 15, weight = 1 },
        { name = 'coke_brick', label = 'Cocaine Brick', minCount = 2, maxCount = 5, weight = 0.7 },
        { name = 'meth_bag', label = 'Meth Bag', minCount = 3, maxCount = 8, weight = 0.6 },
        { name = 'pistol_ammo', label = 'Pistol Ammo', minCount = 50, maxCount = 100, weight = 0.5 },
        { name = 'weapon_pistol', label = 'Pistol', minCount = 1, maxCount = 2, weight = 0.3 },
    }
    
    local numItems = math.random(config.MinDeliveryItems or 1, config.MaxDeliveryItems or 3)
    local selectedItems = {}
    
    -- Weighted random selection
    for i = 1, numItems do
        local totalWeight = 0
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                totalWeight = totalWeight + item.weight
            end
        end
        
        local roll = math.random() * totalWeight
        local cumulative = 0
        
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                cumulative = cumulative + item.weight
                if roll <= cumulative then
                    local count = math.random(item.minCount, item.maxCount)
                    table.insert(items, {
                        name = item.name,
                        label = item.label,
                        count = count,
                    })
                    selectedItems[item.name] = true
                    break
                end
            end
        end
    end
    
    return items
end

---Get delivery destination territory
---@param gangName string
---@return table|nil destination
function FreeGangs.Server.Archetypes.MC.GetDeliveryDestination(gangName)
    local config = FreeGangs.Config.MC.ProspectRuns
    
    -- Try to get a controlled or neutral territory
    local territories = {}
    
    if FreeGangs.Server.Territories then
        for zoneName, zoneData in pairs(FreeGangs.Server.Territories) do
            local ourControl = 0
            if zoneData.influence then
                ourControl = zoneData.influence[gangName] or 0
            end
            
            -- Prefer territories we have some control over
            if ourControl >= 10 then
                table.insert(territories, {
                    territory = zoneName,
                    label = zoneData.label or zoneName,
                    coords = zoneData.coords,
                    control = ourControl,
                })
            end
        end
    end
    
    -- If no territories, use configured drop locations
    if #territories == 0 and config.DefaultDestinations then
        for _, dest in ipairs(config.DefaultDestinations) do
            table.insert(territories, {
                territory = dest.name,
                label = dest.label,
                coords = dest.coords,
                control = 0,
            })
        end
    end
    
    if #territories == 0 then
        return nil
    end
    
    return territories[math.random(#territories)]
end

---Verify player has required items for delivery
---@param source number
---@param requiredItems table
---@return boolean hasAll, table missing
function FreeGangs.Server.Archetypes.MC.VerifyDeliveryItems(source, requiredItems)
    local missing = {}
    local hasAll = true
    
    for _, item in ipairs(requiredItems) do
        local playerCount = FreeGangs.Bridge.GetItemCount(source, item.name)
        if playerCount < item.count then
            hasAll = false
            table.insert(missing, {
                name = item.name,
                label = item.label,
                required = item.count,
                have = playerCount,
                need = item.count - playerCount,
            })
        end
    end
    
    return hasAll, missing
end

---Attempt to complete prospect run at destination
---@param source number
---@param runId string
---@param wasAmbushed boolean - Did destination ambush occur?
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.CompleteProspectRun(source, runId, wasAmbushed)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local runData = ActiveProspectRuns[citizenid]
    
    if not runData or runData.id ~= runId then
        return false, 'Invalid or expired prospect run'
    end
    
    if runData.status ~= 'active' then
        return false, 'Run already completed or failed'
    end
    
    -- Check if time expired
    if os.time() >= runData.expiresAt then
        return FreeGangs.Server.Archetypes.MC.FailProspectRun(citizenid, runId, 'Time expired')
    end
    
    -- Verify player has required items
    local hasItems, missing = FreeGangs.Server.Archetypes.MC.VerifyDeliveryItems(source, runData.requiredItems)
    
    if not hasItems then
        local missingStr = ''
        for _, m in ipairs(missing) do
            missingStr = missingStr .. m.label .. ' (need ' .. m.need .. ' more), '
        end
        return false, 'Missing items: ' .. missingStr:sub(1, -3)
    end
    
    -- If ambushed and player died/failed, this would be called with wasAmbushed = true and handled by FailProspectRun
    if wasAmbushed then
        return FreeGangs.Server.Archetypes.MC.FailProspectRun(citizenid, runId, 'Ambushed at destination')
    end
    
    -- Remove items from player inventory
    for _, item in ipairs(runData.requiredItems) do
        FreeGangs.Bridge.RemoveItem(source, item.name, item.count)
    end
    
    -- Mark as complete
    runData.status = 'completed'
    runData.completedAt = os.time()
    
    local config = FreeGangs.Config.MC.ProspectRuns
    local gangName = runData.gangName
    
    -- === SUCCESS REWARDS ===
    
    -- 1. Territory rep in trap spot territory (if exists)
    if runData.trapSpot then
        local trapTerritory = FreeGangs.Server.Archetypes.MC.FindTerritoryByCoords(runData.trapSpot)
        if trapTerritory and FreeGangs.Server.Territory then
            FreeGangs.Server.Territory.AddInfluence(trapTerritory, gangName, config.TrapSpotInfluenceGain or 3)
        end
    end
    
    -- 2. Territory rep in destination territory
    if runData.destinationTerritory and FreeGangs.Server.Territory then
        FreeGangs.Server.Territory.AddInfluence(runData.destinationTerritory, gangName, config.DestinationInfluenceGain or 5)
    end
    
    -- 3. Gang reputation
    FreeGangs.Server.Reputation.Add(gangName, config.RepGain or 15, 'Prospect run completed')
    
    -- 4. Loot table rewards
    local rewards = FreeGangs.Server.Archetypes.MC.RollLootTable(config.LootTable)
    for _, reward in ipairs(rewards) do
        if reward.type == 'item' then
            FreeGangs.Bridge.AddItem(source, reward.name, reward.count)
        elseif reward.type == 'money' then
            FreeGangs.Bridge.AddMoney(source, reward.amount, 'cash', 'Prospect run reward')
        end
    end
    
    -- Build reward notification
    local rewardStr = ''
    for _, r in ipairs(rewards) do
        if r.type == 'item' then
            rewardStr = rewardStr .. r.label .. ' x' .. r.count .. ', '
        elseif r.type == 'money' then
            rewardStr = rewardStr .. '$' .. FreeGangs.Utils.FormatMoney(r.amount) .. ', '
        end
    end
    rewardStr = rewardStr:sub(1, -3)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'prospect_run_completed', FreeGangs.LogCategories.ACTIVITY, {
        runId = runId,
        destination = runData.destinationTerritory,
        rewards = rewards,
    })
    
    -- Clear run data
    ActiveProspectRuns[citizenid] = nil
    
    FreeGangs.Bridge.Notify(source, 'Prospect run complete! Rewards: ' .. rewardStr, 'success')
    
    return true, 'Run completed successfully'
end

---Fail a prospect run
---@param citizenid string
---@param runId string
---@param reason string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.FailProspectRun(citizenid, runId, reason)
    local runData = ActiveProspectRuns[citizenid]
    if not runData or runData.id ~= runId then
        return false, 'Invalid run'
    end
    
    runData.status = 'failed'
    runData.failedAt = os.time()
    runData.failReason = reason
    
    local config = FreeGangs.Config.MC.ProspectRuns
    
    -- Reputation loss on failure
    FreeGangs.Server.Reputation.Remove(runData.gangName, config.FailureRepLoss or 10, 'Prospect run failed: ' .. reason)
    
    -- Notify player
    local player = FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
    if player then
        FreeGangs.Bridge.Notify(player.PlayerData.source, 
            'Prospect run failed: ' .. reason .. '! -' .. (config.FailureRepLoss or 10) .. ' rep', 
            'error')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(runData.gangName, citizenid, 'prospect_run_failed', FreeGangs.LogCategories.ACTIVITY, {
        runId = runId,
        reason = reason,
    })
    
    -- Clear run data
    ActiveProspectRuns[citizenid] = nil
    
    return true, 'Run failed'
end

---Check and expire timed-out prospect runs
---@param citizenid string
---@param runId string
function FreeGangs.Server.Archetypes.MC.CheckProspectRunExpiry(citizenid, runId)
    local runData = ActiveProspectRuns[citizenid]
    if runData and runData.id == runId and runData.status == 'active' then
        if os.time() >= runData.expiresAt then
            FreeGangs.Server.Archetypes.MC.FailProspectRun(citizenid, runId, 'Time expired')
        end
    end
end

---Roll loot table for rewards
---@param lootTable table
---@return table rewards
function FreeGangs.Server.Archetypes.MC.RollLootTable(lootTable)
    local rewards = {}
    lootTable = lootTable or {
        { type = 'money', amount = { min = 500, max = 2000 }, chance = 1.0 },
        { type = 'item', name = 'lockpick', label = 'Lockpick', count = { min = 1, max = 3 }, chance = 0.3 },
        { type = 'item', name = 'radio', label = 'Radio', count = { min = 1, max = 1 }, chance = 0.2 },
    }
    
    for _, loot in ipairs(lootTable) do
        if math.random() <= loot.chance then
            if loot.type == 'money' then
                table.insert(rewards, {
                    type = 'money',
                    amount = math.random(loot.amount.min, loot.amount.max),
                })
            elseif loot.type == 'item' then
                table.insert(rewards, {
                    type = 'item',
                    name = loot.name,
                    label = loot.label,
                    count = math.random(loot.count.min, loot.count.max),
                })
            end
        end
    end
    
    return rewards
end

---Find territory name by coordinates
---@param coords vector3
---@return string|nil
function FreeGangs.Server.Archetypes.MC.FindTerritoryByCoords(coords)
    if not FreeGangs.Server.Territories then return nil end
    
    for zoneName, zoneData in pairs(FreeGangs.Server.Territories) do
        if zoneData.coords then
            local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(zoneData.coords.x, zoneData.coords.y, zoneData.coords.z))
            if dist < (zoneData.radius or 100) then
                return zoneName
            end
        end
    end
    
    return nil
end

---Get active prospect run for player
---@param citizenid string
---@return table|nil
function FreeGangs.Server.Archetypes.MC.GetActiveProspectRun(citizenid)
    return ActiveProspectRuns[citizenid]
end

-- ============================================================================
-- MC: CLUB RUNS (TIER 2)
-- Scaled-up version of prospect runs requiring 4+ members
-- Larger item requirements, higher rewards, more risk
-- Same mechanics: required items, destination, ambush at destination
-- NPC biker ambush along route with INCREASED intensity
-- ============================================================================

---Start a club run - requires 4+ members, larger delivery
---@param source number
---@param gangName string
---@param params table|nil
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.StartClubRun(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.MC then
        return false, 'Only MCs can start club runs'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 2) then
        return false, 'Requires Master Level 6'
    end
    
    local config = FreeGangs.Config.MC.ClubRuns
    
    -- Check if club run already active
    if ActiveClubRuns[gangName] and ActiveClubRuns[gangName].status == 'active' then
        return false, 'A club run is already in progress'
    end
    
    -- Check cooldown
    local cooldownKey = 'club_run_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Club runs on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Get online members - need 4+ for club run
    local onlineMembers = FreeGangs.Server.GetOnlineGangMembers(gangName)
    local minMembers = config.MinMembers or 4
    if #onlineMembers < minMembers then
        return false, 'Need at least ' .. minMembers .. ' members online for a club run'
    end
    
    -- Generate LARGER required items (scaled up from prospect runs)
    local requiredItems = FreeGangs.Server.Archetypes.MC.GenerateClubDeliveryItems(config)
    
    -- Get destination territory
    local destination = FreeGangs.Server.Archetypes.MC.GetDeliveryDestination(gangName)
    if not destination then
        return false, 'No valid delivery destination found'
    end
    
    -- Calculate ambush chances - club runs are MORE dangerous
    local gangRep = gang.reputation or 0
    
    -- Destination ambush chance (decreases with rep but starts higher)
    local baseAmbushChance = config.DestinationAmbushChance or 0.40 -- Higher base than prospect
    local ambushReduction = math.min(0.25, gangRep / 4000)
    local destinationAmbushChance = math.max(0.10, baseAmbushChance - ambushReduction)
    
    -- Route ambush - MORE NPCs (scaled up)
    local baseAmbushNPCs = config.RouteAmbush.BaseNPCCount or 4
    local additionalNPCs = math.floor(gangRep / 800) -- +1 NPC per 800 rep (faster scaling)
    local maxAmbushNPCs = math.min(config.RouteAmbush.MaxNPCCount or 10, baseAmbushNPCs + additionalNPCs)
    
    -- Multiple ambush waves possible
    local ambushWaves = math.min(3, 1 + math.floor(gangRep / 2000)) -- Up to 3 waves
    
    local routeAmbushChance = config.RouteAmbush.SpawnChance or 0.60 -- Higher than prospect
    
    -- Create run data
    local runId = FreeGangs.Utils.GenerateId('cr')
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local timeLimitSeconds = (config.TimeLimitMinutes or 20) * 60
    
    local runData = {
        id = runId,
        gangName = gangName,
        startedBy = citizenid,
        startedBySource = source,
        requiredItems = requiredItems,
        destination = destination,
        destinationTerritory = destination.territory,
        status = 'active',
        startedAt = os.time(),
        expiresAt = os.time() + timeLimitSeconds,
        timeLimit = timeLimitSeconds,
        destinationAmbushChance = destinationAmbushChance,
        routeAmbushChance = routeAmbushChance,
        routeAmbushNPCCount = maxAmbushNPCs,
        ambushWaves = ambushWaves,
        members = { source }, -- Track participating members
        memberCitizenIds = { citizenid },
        itemsDelivered = false,
    }
    
    ActiveClubRuns[gangName] = runData
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.Cooldown or 14400)
    
    -- Build item list for notification
    local itemListStr = ''
    for _, item in ipairs(requiredItems) do
        itemListStr = itemListStr .. item.label .. ' x' .. item.count .. ', '
    end
    itemListStr = itemListStr:sub(1, -3)
    
    -- Notify ALL online gang members immediately
    for _, member in ipairs(onlineMembers) do
        TriggerClientEvent('free-gangs:client:clubRunStarted', member.source, {
            runId = runId,
            startedBy = FreeGangs.Bridge.GetPlayerName(source),
            requiredItems = requiredItems,
            destination = destination,
            timeLimit = timeLimitSeconds,
            destinationAmbushChance = destinationAmbushChance,
            routeAmbushChance = routeAmbushChance,
            routeAmbushNPCCount = maxAmbushNPCs,
            ambushWaves = ambushWaves,
            npcAmbushModels = config.RouteAmbush.NPCModels or { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03' },
            npcAmbushVehicles = config.RouteAmbush.Vehicles or { 'daemon', 'hexer', 'zombieb' },
        })
    end
    
    -- Schedule timeout
    SetTimeout(timeLimitSeconds * 1000 + 1000, function()
        FreeGangs.Server.Archetypes.MC.CheckClubRunTimeout(gangName, runId)
    end)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'club_run_started', FreeGangs.LogCategories.ACTIVITY, {
        runId = runId,
        requiredItems = requiredItems,
        destination = destination.territory,
        timeLimit = timeLimitSeconds,
        memberCount = #onlineMembers,
    })
    
    return true, 'Club run started! All members notified. Deliver: ' .. itemListStr
end

---Generate delivery items for club run (scaled up from prospect)
---@param config table
---@return table items
function FreeGangs.Server.Archetypes.MC.GenerateClubDeliveryItems(config)
    local items = {}
    local itemPool = config.DeliveryItems or {
        { name = 'weed_bag', label = 'Weed Bag', minCount = 20, maxCount = 50, weight = 1 },
        { name = 'coke_brick', label = 'Cocaine Brick', minCount = 5, maxCount = 15, weight = 0.8 },
        { name = 'meth_bag', label = 'Meth Bag', minCount = 10, maxCount = 25, weight = 0.7 },
        { name = 'pistol_ammo', label = 'Pistol Ammo', minCount = 200, maxCount = 500, weight = 0.6 },
        { name = 'weapon_pistol', label = 'Pistol', minCount = 3, maxCount = 8, weight = 0.4 },
        { name = 'weapon_smg', label = 'SMG', minCount = 1, maxCount = 3, weight = 0.2 },
    }
    
    -- More items required for club runs
    local numItems = math.random(config.MinDeliveryItems or 3, config.MaxDeliveryItems or 5)
    local selectedItems = {}
    
    for i = 1, numItems do
        local totalWeight = 0
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                totalWeight = totalWeight + item.weight
            end
        end
        
        if totalWeight <= 0 then break end
        
        local roll = math.random() * totalWeight
        local cumulative = 0
        
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                cumulative = cumulative + item.weight
                if roll <= cumulative then
                    local count = math.random(item.minCount, item.maxCount)
                    table.insert(items, {
                        name = item.name,
                        label = item.label,
                        count = count,
                    })
                    selectedItems[item.name] = true
                    break
                end
            end
        end
    end
    
    return items
end

---Join an active club run
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.JoinClubRun(source, gangName)
    local run = ActiveClubRuns[gangName]
    if not run or run.status ~= 'active' then 
        return false, 'No active club run' 
    end
    
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    -- Check if already joined
    for _, cid in ipairs(run.memberCitizenIds) do
        if cid == citizenid then
            return false, 'Already participating in this club run'
        end
    end
    
    -- Add to participants
    table.insert(run.members, source)
    table.insert(run.memberCitizenIds, citizenid)
    
    -- Notify other members
    for _, memberSource in ipairs(run.members) do
        if memberSource ~= source then
            FreeGangs.Bridge.Notify(memberSource, FreeGangs.Bridge.GetPlayerName(source) .. ' joined the club run!', 'inform')
        end
    end
    
    return true, 'Joined club run! ' .. #run.members .. ' members participating.'
end

---Verify all club run required items across participating members
---@param gangName string
---@return boolean hasAll, table contributors
function FreeGangs.Server.Archetypes.MC.VerifyClubRunItems(gangName)
    local run = ActiveClubRuns[gangName]
    if not run then return false, {} end
    
    local contributors = {} -- Track who contributed what
    local itemsNeeded = {}
    
    -- Build needed items list
    for _, item in ipairs(run.requiredItems) do
        itemsNeeded[item.name] = {
            required = item.count,
            collected = 0,
            label = item.label,
        }
    end
    
    -- Check each member's inventory
    for i, memberSource in ipairs(run.members) do
        local citizenid = run.memberCitizenIds[i]
        contributors[citizenid] = {}
        
        for itemName, data in pairs(itemsNeeded) do
            if data.collected < data.required then
                local playerCount = FreeGangs.Bridge.GetItemCount(memberSource, itemName)
                if playerCount > 0 then
                    local toTake = math.min(playerCount, data.required - data.collected)
                    data.collected = data.collected + toTake
                    contributors[citizenid][itemName] = toTake
                end
            end
        end
    end
    
    -- Check if we have everything
    local hasAll = true
    for itemName, data in pairs(itemsNeeded) do
        if data.collected < data.required then
            hasAll = false
            break
        end
    end
    
    return hasAll, contributors
end

---Complete club run at destination
---@param source number
---@param gangName string
---@param wasAmbushed boolean
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.CompleteClubRun(source, gangName, wasAmbushed)
    local run = ActiveClubRuns[gangName]
    if not run or run.status ~= 'active' then
        return false, 'No active club run'
    end
    
    -- Check time
    if os.time() >= run.expiresAt then
        return FreeGangs.Server.Archetypes.MC.FailClubRun(gangName, 'Time expired')
    end
    
    -- Check minimum members still participating
    local config = FreeGangs.Config.MC.ClubRuns
    if #run.members < (config.MinMembers or 4) then
        return false, 'Need at least ' .. (config.MinMembers or 4) .. ' members at destination'
    end
    
    -- Verify items
    local hasItems, contributors = FreeGangs.Server.Archetypes.MC.VerifyClubRunItems(gangName)
    if not hasItems then
        return false, 'Members do not have all required items'
    end
    
    -- If ambushed and failed
    if wasAmbushed then
        return FreeGangs.Server.Archetypes.MC.FailClubRun(gangName, 'Ambushed at destination')
    end
    
    -- Remove items from contributors
    for citizenid, items in pairs(contributors) do
        local player = FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
        if player then
            for itemName, count in pairs(items) do
                if count > 0 then
                    FreeGangs.Bridge.RemoveItem(player.PlayerData.source, itemName, count)
                end
            end
        end
    end
    
    -- Mark complete
    run.status = 'completed'
    run.completedAt = os.time()
    
    -- === SUCCESS REWARDS (scaled up from prospect) ===
    
    local memberCount = #run.members
    
    -- 1. Territory influence in destination
    if run.destinationTerritory and FreeGangs.Server.Territory then
        local influenceGain = (config.DestinationInfluenceGain or 10) + (memberCount * 2)
        FreeGangs.Server.Territory.AddInfluence(run.destinationTerritory, gangName, influenceGain)
    end
    
    -- 2. Gang reputation (bonus for more members)
    local repGain = (config.RepGain or 50) + (memberCount * 5)
    FreeGangs.Server.Reputation.Add(gangName, repGain, 'Club run completed')
    
    -- 3. Loot table rewards for each member
    local lootTable = config.LootTable or {
        { type = 'money', amount = { min = 2000, max = 8000 }, chance = 1.0 },
        { type = 'item', name = 'lockpick', label = 'Lockpick', count = { min = 2, max = 5 }, chance = 0.5 },
        { type = 'item', name = 'radio', label = 'Radio', count = { min = 1, max = 2 }, chance = 0.4 },
        { type = 'item', name = 'weapon_pistol', label = 'Pistol', count = { min = 1, max = 1 }, chance = 0.2 },
    }
    
    for _, memberSource in ipairs(run.members) do
        local rewards = FreeGangs.Server.Archetypes.MC.RollLootTable(lootTable)
        
        local rewardStr = ''
        for _, r in ipairs(rewards) do
            if r.type == 'item' then
                FreeGangs.Bridge.AddItem(memberSource, r.name, r.count)
                rewardStr = rewardStr .. r.label .. ' x' .. r.count .. ', '
            elseif r.type == 'money' then
                FreeGangs.Bridge.AddMoney(memberSource, r.amount, 'cash', 'Club run reward')
                rewardStr = rewardStr .. '$' .. FreeGangs.Utils.FormatMoney(r.amount) .. ', '
            end
        end
        rewardStr = rewardStr:sub(1, -3)
        
        FreeGangs.Bridge.Notify(memberSource, 'Club run complete! Rewards: ' .. rewardStr, 'success')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, run.startedBy, 'club_run_completed', FreeGangs.LogCategories.ACTIVITY, {
        runId = run.id,
        destination = run.destinationTerritory,
        memberCount = memberCount,
        repGain = repGain,
    })
    
    -- Clear run
    ActiveClubRuns[gangName] = nil
    
    return true, 'Club run completed!'
end

---Fail a club run
---@param gangName string
---@param reason string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.FailClubRun(gangName, reason)
    local run = ActiveClubRuns[gangName]
    if not run then return false, 'No active run' end
    
    run.status = 'failed'
    run.failedAt = os.time()
    run.failReason = reason
    
    local config = FreeGangs.Config.MC.ClubRuns
    local repLoss = config.FailureRepLoss or 30
    
    -- Reputation loss
    FreeGangs.Server.Reputation.Remove(gangName, repLoss, 'Club run failed: ' .. reason)
    
    -- Notify all members
    for _, memberSource in ipairs(run.members) do
        FreeGangs.Bridge.Notify(memberSource, 
            'Club run failed: ' .. reason .. '! -' .. repLoss .. ' rep', 
            'error')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, run.startedBy, 'club_run_failed', FreeGangs.LogCategories.ACTIVITY, {
        runId = run.id,
        reason = reason,
        memberCount = #run.members,
    })
    
    ActiveClubRuns[gangName] = nil
    
    return true, 'Club run failed'
end

---Check club run timeout
---@param gangName string
---@param runId string
function FreeGangs.Server.Archetypes.MC.CheckClubRunTimeout(gangName, runId)
    local run = ActiveClubRuns[gangName]
    if run and run.id == runId and run.status == 'active' then
        if os.time() >= run.expiresAt then
            FreeGangs.Server.Archetypes.MC.FailClubRun(gangName, 'Time expired')
        end
    end
end

---Get active club run status
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.MC.GetActiveClubRun(gangName)
    local run = ActiveClubRuns[gangName]
    if not run or run.status ~= 'active' then return nil end
    
    return {
        id = run.id,
        destination = run.destination,
        requiredItems = run.requiredItems,
        memberCount = #run.members,
        timeRemaining = math.max(0, run.expiresAt - os.time()),
    }
end

-- ============================================================================
-- MC: TERRITORY RIDE (TIER 3)
-- Patrol-style activity affecting ALL territories (owned AND opposition)
-- Requires 3+ members in proximity, all on motorcycles
-- More members = increased loyalty/influence effect
-- ============================================================================

---Start a territory ride
---@param source number
---@param gangName string
---@param params table|nil { memberSources: table }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.StartTerritoryRide(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.MC then
        return false, 'Only MCs can start territory rides'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 3) then
        return false, 'Requires Master Level 8'
    end
    
    local config = FreeGangs.Config.MC.TerritoryRide
    
    -- Check if ride already active
    if ActiveTerritoryRides[gangName] and ActiveTerritoryRides[gangName].status == 'active' then
        return false, 'A territory ride is already in progress'
    end
    
    -- Check cooldown
    local cooldownKey = 'territory_ride_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Territory ride on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Get online members
    local onlineMembers = FreeGangs.Server.GetOnlineGangMembers(gangName)
    local minMembers = config.MinMembers or 3
    
    if #onlineMembers < minMembers then
        return false, 'Need at least ' .. minMembers .. ' members online to start a territory ride'
    end
    
    -- Check if starter is on motorcycle
    local starterOnBike, bikeError = FreeGangs.Server.Archetypes.MC.IsOnValidMotorcycle(source)
    if not starterOnBike then
        return false, bikeError or 'You must be on a motorcycle to start a territory ride'
    end
    
    -- Start ride
    local rideId = FreeGangs.Utils.GenerateId('tr')
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    ActiveTerritoryRides[gangName] = {
        id = rideId,
        gangName = gangName,
        startedBy = citizenid,
        leaderSource = source,
        status = 'active',
        startTime = os.time(),
        -- Track participating members (validated each tick)
        activeMembers = { source },
        activeMemberCitizenIds = { citizenid },
        -- Track zones visited and influence gained
        visitedZones = {},
        zoneInfluenceGained = {},
        totalInfluenceGained = 0,
        -- Track opposition zones affected
        oppositionZonesAffected = {},
    }
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.Cooldown or 21600)
    
    -- Notify all gang members
    for _, member in ipairs(onlineMembers) do
        TriggerClientEvent('free-gangs:client:territoryRideStarted', member.source, {
            rideId = rideId,
            startedBy = FreeGangs.Bridge.GetPlayerName(source),
            leaderSource = source,
            minMembers = minMembers,
            proximityRadius = config.ProximityRadius or 50.0,
        })
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'territory_ride_started', FreeGangs.LogCategories.ACTIVITY, {
        rideId = rideId,
    })
    
    return true, 'Territory ride started! ' .. minMembers .. '+ members must stay in proximity on motorcycles.'
end

---Check if player is on a valid motorcycle
---@param source number
---@return boolean isValid, string|nil error
function FreeGangs.Server.Archetypes.MC.IsOnValidMotorcycle(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return false, 'Invalid player'
    end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return false, 'You must be on a motorcycle'
    end
    
    local config = FreeGangs.Config.MC.ProspectRuns -- Reuse bike list
    local vehicleModel = GetEntityModel(vehicle)
    
    for _, model in ipairs(config.ValidBikeModels or {}) do
        if GetHashKey(model) == vehicleModel then
            return true, nil
        end
    end
    
    return false, 'You must be on an approved motorcycle'
end

---Join an active territory ride
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.JoinTerritoryRide(source, gangName)
    local ride = ActiveTerritoryRides[gangName]
    if not ride or ride.status ~= 'active' then
        return false, 'No active territory ride'
    end
    
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    -- Check if already joined
    for _, cid in ipairs(ride.activeMemberCitizenIds) do
        if cid == citizenid then
            return false, 'Already participating in this ride'
        end
    end
    
    -- Check if on motorcycle
    local onBike, bikeError = FreeGangs.Server.Archetypes.MC.IsOnValidMotorcycle(source)
    if not onBike then
        return false, bikeError or 'You must be on a motorcycle'
    end
    
    table.insert(ride.activeMembers, source)
    table.insert(ride.activeMemberCitizenIds, citizenid)
    
    -- Notify other riders
    for _, memberSource in ipairs(ride.activeMembers) do
        if memberSource ~= source then
            FreeGangs.Bridge.Notify(memberSource, FreeGangs.Bridge.GetPlayerName(source) .. ' joined the ride!', 'inform')
        end
    end
    
    return true, 'Joined territory ride! Stay on your bike and in proximity.'
end

---Validate territory ride members (called periodically from client)
---Checks proximity and motorcycle status
---@param gangName string
---@param leaderCoords vector3
---@param memberData table { [source] = { onBike: boolean, coords: vector3 } }
---@return table validMembers, number count
function FreeGangs.Server.Archetypes.MC.ValidateRideMembers(gangName, leaderCoords, memberData)
    local ride = ActiveTerritoryRides[gangName]
    if not ride or ride.status ~= 'active' then
        return {}, 0
    end
    
    local config = FreeGangs.Config.MC.TerritoryRide
    local proximityRadius = config.ProximityRadius or 50.0
    local validMembers = {}
    
    for i, memberSource in ipairs(ride.activeMembers) do
        local data = memberData[memberSource]
        
        if data then
            -- Check if on motorcycle
            if not data.onBike then
                goto continue
            end
            
            -- Check proximity to leader
            if data.coords then
                local dist = #(vector3(data.coords.x, data.coords.y, data.coords.z) - leaderCoords)
                if dist > proximityRadius then
                    goto continue
                end
            end
            
            -- Member is valid
            table.insert(validMembers, memberSource)
        end
        
        ::continue::
    end
    
    return validMembers, #validMembers
end

---Record zone presence during territory ride
---Called when ride group is in a zone with minimum valid members
---@param gangName string
---@param zoneName string
---@param validMemberCount number
---@param isOwnedZone boolean
---@param isOppositionZone boolean
---@param oppositionGang string|nil
---@return boolean success, number|nil influenceGained
function FreeGangs.Server.Archetypes.MC.RecordTerritoryRideZone(gangName, zoneName, validMemberCount, isOwnedZone, isOppositionZone, oppositionGang)
    local ride = ActiveTerritoryRides[gangName]
    if not ride or ride.status ~= 'active' then
        return false, nil
    end
    
    local config = FreeGangs.Config.MC.TerritoryRide
    local minMembers = config.MinMembers or 3
    
    -- Must have minimum members in proximity on bikes
    if validMemberCount < minMembers then
        return false, nil
    end
    
    local now = os.time()
    
    -- Check zone visit cooldown
    local lastVisit = ride.visitedZones[zoneName]
    if lastVisit and (now - lastVisit) < (config.ZoneEntryGap or 60) then
        return false, nil
    end
    
    -- Record visit time
    ride.visitedZones[zoneName] = now
    
    -- Calculate influence gain based on member count
    local baseInfluence = config.BaseInfluencePerZone or 3
    local memberBonus = 1.0
    
    -- Apply member count bonus (more members = more influence)
    for threshold, multiplier in pairs(config.MemberBonus or {}) do
        if validMemberCount >= tonumber(threshold) then
            memberBonus = math.max(memberBonus, multiplier)
        end
    end
    
    local influenceGain = math.floor(baseInfluence * memberBonus)
    
    -- Apply zone type modifier
    if isOppositionZone then
        -- Opposition zones give bonus influence (intimidation factor)
        influenceGain = math.floor(influenceGain * (config.OppositionZoneMultiplier or 1.5))
        
        -- Track opposition zones affected
        if not ride.oppositionZonesAffected[zoneName] then
            ride.oppositionZonesAffected[zoneName] = {
                gang = oppositionGang,
                influenceGained = 0,
            }
        end
        ride.oppositionZonesAffected[zoneName].influenceGained = 
            ride.oppositionZonesAffected[zoneName].influenceGained + influenceGain
    end
    
    -- Track total influence
    ride.zoneInfluenceGained[zoneName] = (ride.zoneInfluenceGained[zoneName] or 0) + influenceGain
    ride.totalInfluenceGained = ride.totalInfluenceGained + influenceGain
    
    -- Apply influence to territory
    if FreeGangs.Server.Territory and FreeGangs.Server.Territory.AddInfluence then
        FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, influenceGain)
    end
    
    -- Notify riders
    local zoneTypeStr = isOppositionZone and ' (opposition)' or (isOwnedZone and ' (owned)' or '')
    for _, memberSource in ipairs(ride.activeMembers) do
        FreeGangs.Bridge.Notify(memberSource, 
            '+' .. influenceGain .. ' influence in ' .. zoneName .. zoneTypeStr,
            'success')
    end
    
    -- If opposition zone, notify that gang
    if isOppositionZone and oppositionGang then
        local gangLabel = FreeGangs.Server.Gangs[gangName] and FreeGangs.Server.Gangs[gangName].label or gangName
        FreeGangs.Server.NotifyGangMembers(oppositionGang,
            gangLabel .. ' MC is riding through ' .. zoneName .. '!',
            'error')
    end
    
    return true, influenceGain
end

---End territory ride
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.MC.EndTerritoryRide(source, gangName)
    local ride = ActiveTerritoryRides[gangName]
    if not ride or ride.status ~= 'active' then
        return false, 'No active territory ride'
    end
    
    -- Only leader can end, or if no leader online
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if ride.startedBy ~= citizenid then
        -- Check if leader is still online
        local leaderOnline = false
        for _, memberSource in ipairs(ride.activeMembers) do
            local memberCid = FreeGangs.Bridge.GetCitizenId(memberSource)
            if memberCid == ride.startedBy then
                leaderOnline = true
                break
            end
        end
        
        if leaderOnline then
            return false, 'Only the ride leader can end the territory ride'
        end
    end
    
    ride.status = 'completed'
    ride.endTime = os.time()
    
    local config = FreeGangs.Config.MC.TerritoryRide
    
    -- Count zones visited
    local ownedZonesVisited = 0
    local oppositionZonesVisited = 0
    
    for zoneName, _ in pairs(ride.visitedZones) do
        if ride.oppositionZonesAffected[zoneName] then
            oppositionZonesVisited = oppositionZonesVisited + 1
        else
            ownedZonesVisited = ownedZonesVisited + 1
        end
    end
    
    local totalZones = ownedZonesVisited + oppositionZonesVisited
    
    -- Bonus rep for visiting many zones
    local bonusRep = 0
    if totalZones >= (config.MinZonesForBonus or 5) then
        bonusRep = config.CompletionRepBonus or 50
        FreeGangs.Server.Reputation.Add(gangName, bonusRep, 'Territory ride completion')
    end
    
    -- Notify all members
    for _, memberSource in ipairs(ride.activeMembers) do
        local msg = 'Territory ride complete! ' .. totalZones .. ' zones visited (' .. 
                    ownedZonesVisited .. ' owned, ' .. oppositionZonesVisited .. ' opposition). ' ..
                    'Total influence: +' .. ride.totalInfluenceGained
        if bonusRep > 0 then
            msg = msg .. ' +' .. bonusRep .. ' bonus rep!'
        end
        FreeGangs.Bridge.Notify(memberSource, msg, 'success')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, ride.startedBy, 'territory_ride_completed', FreeGangs.LogCategories.ACTIVITY, {
        rideId = ride.id,
        duration = ride.endTime - ride.startTime,
        ownedZonesVisited = ownedZonesVisited,
        oppositionZonesVisited = oppositionZonesVisited,
        totalInfluenceGained = ride.totalInfluenceGained,
        oppositionZonesAffected = ride.oppositionZonesAffected,
        bonusRep = bonusRep,
    })
    
    ActiveTerritoryRides[gangName] = nil
    
    return true, 'Territory ride complete!'
end

---Get active territory ride status
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.MC.GetActiveTerritoryRide(gangName)
    local ride = ActiveTerritoryRides[gangName]
    if not ride or ride.status ~= 'active' then
        return nil
    end
    
    local ownedZones = 0
    local oppositionZones = 0
    for zoneName, _ in pairs(ride.visitedZones) do
        if ride.oppositionZonesAffected[zoneName] then
            oppositionZones = oppositionZones + 1
        else
            ownedZones = ownedZones + 1
        end
    end
    
    return {
        id = ride.id,
        leaderSource = ride.leaderSource,
        memberCount = #ride.activeMembers,
        duration = os.time() - ride.startTime,
        ownedZonesVisited = ownedZones,
        oppositionZonesVisited = oppositionZones,
        totalInfluenceGained = ride.totalInfluenceGained,
    }
end

---Remove a member from active ride (disconnected or left)
---@param gangName string
---@param source number
function FreeGangs.Server.Archetypes.MC.RemoveRideMember(gangName, source)
    local ride = ActiveTerritoryRides[gangName]
    if not ride then return end
    
    for i, memberSource in ipairs(ride.activeMembers) do
        if memberSource == source then
            table.remove(ride.activeMembers, i)
            table.remove(ride.activeMemberCitizenIds, i)
            break
        end
    end
    
    -- If leader left and no members remain, end ride
    if #ride.activeMembers == 0 then
        ride.status = 'abandoned'
        ActiveTerritoryRides[gangName] = nil
    -- If leader left, assign new leader
    elseif source == ride.leaderSource and #ride.activeMembers > 0 then
        ride.leaderSource = ride.activeMembers[1]
        FreeGangs.Bridge.Notify(ride.leaderSource, 'You are now the ride leader!', 'inform')
    end
end

-- ============================================================================
-- CARTEL: HALCON NETWORK (TIER 1)
-- ============================================================================

---Toggle Halcon Network
---@param source number
---@param gangName string
---@param params table { enabled: boolean }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.ToggleHalconNetwork(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.CARTEL then
        return false, 'Only Cartels can use the Halcon Network'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return false, 'Requires Master Level 4'
    end
    
    local enabled = params and params.enabled
    if enabled == nil then
        enabled = not HalconNetworkEnabled[gangName]
    end
    
    HalconNetworkEnabled[gangName] = enabled
    
    FreeGangs.Server.NotifyGangMembers(gangName, 
        enabled and 'Halcon Network activated - You will receive alerts' or 'Halcon Network deactivated',
        enabled and 'success' or 'inform')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, FreeGangs.Bridge.GetCitizenId(source), 'halcon_network_toggle', FreeGangs.LogCategories.ACTIVITY, {
        enabled = enabled,
    })
    
    return true, enabled and 'Halcon Network activated' or 'Halcon Network deactivated'
end

---Check if Halcon Network is enabled
---@param gangName string
---@return boolean
function FreeGangs.Server.Archetypes.Cartel.IsHalconNetworkEnabled(gangName)
    return HalconNetworkEnabled[gangName] == true
end

---Send Halcon alert when someone enters territory
---@param gangName string
---@param zoneName string
---@param enteringPlayer number Source
---@param alertType string 'rival'|'police'|'unknown'
function FreeGangs.Server.Archetypes.Cartel.SendHalconAlert(gangName, zoneName, enteringPlayer, alertType)
    if not FreeGangs.Server.Archetypes.Cartel.IsHalconNetworkEnabled(gangName) then
        return
    end
    
    local config = FreeGangs.Config.Cartel.HalconNetwork
    
    -- Check zone control
    local control = FreeGangs.Server.GetZoneControl and 
                    FreeGangs.Server.GetZoneControl(zoneName, gangName) or 0
    if control < config.MinZoneControl then
        return
    end
    
    -- Check alert type enabled
    if not config.AlertTypes[alertType] then
        return
    end
    
    -- Check cooldown for this player
    local cooldownKey = 'halcon_' .. gangName .. '_' .. enteringPlayer
    local onCooldown = FreeGangs.Server.IsOnCooldown(enteringPlayer, cooldownKey)
    if onCooldown then
        return
    end
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(enteringPlayer, cooldownKey, config.AlertCooldown)
    
    -- Determine intel quality based on control
    local intelQuality = 'basic'
    for threshold, quality in pairs(config.IntelQuality) do
        if control >= threshold then
            intelQuality = quality
        end
    end
    
    -- Build alert data
    local alertData = {
        zoneName = zoneName,
        alertType = alertType,
        intelQuality = intelQuality,
        timestamp = os.time(),
    }
    
    if intelQuality == 'detailed' or intelQuality == 'full' then
        alertData.playerCount = 1 -- Would count nearby same-type players
    end
    
    if intelQuality == 'full' then
        alertData.playerName = FreeGangs.Bridge.GetPlayerName(enteringPlayer)
        -- Get their gang if any
        local citizenid = FreeGangs.Bridge.GetCitizenId(enteringPlayer)
        local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
        if membership then
            alertData.gangName = membership.gang_name
            alertData.gangLabel = FreeGangs.Server.Gangs[membership.gang_name] and 
                                  FreeGangs.Server.Gangs[membership.gang_name].label or membership.gang_name
        end
    end
    
    -- Send to all online gang members
    local onlineMembers = FreeGangs.Server.GetOnlineGangMembers(gangName)
    for _, member in ipairs(onlineMembers) do
        TriggerClientEvent('free-gangs:client:halconAlert', member.source, alertData)
    end
end

-- ============================================================================
-- CARTEL: CONVOY PROTECTION (TIER 2)
-- Item delivery mission similar to MC prospect runs
-- Players must deliver required items to a territory
-- NO route ambush - only ambush/doublecross at destination
-- Mission syncs to all online gang members when activated
-- Timer starts when activated
-- ============================================================================

---Start a convoy protection mission (item delivery)
---@param source number
---@param gangName string
---@param params table|nil
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.StartConvoyProtection(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.CARTEL then
        return false, 'Only Cartels can start convoy protection'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 2) then
        return false, 'Requires Master Level 6'
    end
    
    local config = FreeGangs.Config.Cartel.ConvoyProtection
    
    -- Check if already active
    if ActiveConvoys[gangName] and ActiveConvoys[gangName].status == 'active' then
        return false, 'A convoy is already in progress'
    end
    
    -- Check cooldown
    local cooldownKey = 'convoy_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Convoy protection on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Generate required items for delivery
    local requiredItems = FreeGangs.Server.Archetypes.Cartel.GenerateConvoyItems(config)
    
    -- Get destination territory
    local destination = FreeGangs.Server.Archetypes.Cartel.GetConvoyDestination(gangName)
    if not destination then
        return false, 'No valid delivery destination found'
    end
    
    -- Calculate destination ambush/doublecross chance (decreases with rep)
    local gangRep = gang.reputation or 0
    local baseAmbushChance = config.DestinationAmbushChance or 0.30
    local ambushReduction = math.min(0.20, gangRep / 5000) -- Max 20% reduction
    local destinationAmbushChance = math.max(0.05, baseAmbushChance - ambushReduction)
    
    -- Create convoy data
    local convoyId = FreeGangs.Utils.GenerateId('cv')
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local timeLimitSeconds = (config.TimeLimitMinutes or 20) * 60
    
    local convoyData = {
        id = convoyId,
        gangName = gangName,
        startedBy = citizenid,
        startedBySource = source,
        requiredItems = requiredItems,
        destination = destination,
        destinationTerritory = destination.territory,
        status = 'active',
        startedAt = os.time(),
        expiresAt = os.time() + timeLimitSeconds,
        timeLimit = timeLimitSeconds,
        destinationAmbushChance = destinationAmbushChance,
        -- NO route ambush for Cartel convoys
        hasRouteAmbush = false,
        participants = { source },
        participantCitizenIds = { citizenid },
        itemsDelivered = false,
    }
    
    ActiveConvoys[gangName] = convoyData
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.Cooldown or 10800) -- 3 hours
    
    -- Build item list string
    local itemListStr = ''
    for _, item in ipairs(requiredItems) do
        itemListStr = itemListStr .. item.label .. ' x' .. item.count .. ', '
    end
    itemListStr = itemListStr:sub(1, -3)
    
    -- SYNC TO ALL ONLINE GANG MEMBERS IMMEDIATELY
    local onlineMembers = FreeGangs.Server.GetOnlineGangMembers(gangName)
    for _, member in ipairs(onlineMembers) do
        TriggerClientEvent('free-gangs:client:convoyStarted', member.source, {
            convoyId = convoyId,
            startedBy = FreeGangs.Bridge.GetPlayerName(source),
            requiredItems = requiredItems,
            destination = destination,
            timeLimit = timeLimitSeconds,
            destinationAmbushChance = destinationAmbushChance,
            hasRouteAmbush = false, -- Cartel convoys have NO route ambush
        })
    end
    
    -- Schedule expiry check
    SetTimeout(timeLimitSeconds * 1000 + 1000, function()
        FreeGangs.Server.Archetypes.Cartel.CheckConvoyExpiry(gangName, convoyId)
    end)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'convoy_started', FreeGangs.LogCategories.ACTIVITY, {
        convoyId = convoyId,
        requiredItems = requiredItems,
        destination = destination.territory,
        timeLimit = timeLimitSeconds,
    })
    
    return true, 'Convoy protection started! All members notified. Deliver: ' .. itemListStr .. ' | Time: ' .. config.TimeLimitMinutes .. ' minutes'
end

---Generate required items for convoy delivery
---@param config table
---@return table items
function FreeGangs.Server.Archetypes.Cartel.GenerateConvoyItems(config)
    local items = {}
    local itemPool = config.DeliveryItems or {
        { name = 'coke_brick', label = 'Cocaine Brick', minCount = 10, maxCount = 30, weight = 1 },
        { name = 'heroin_pack', label = 'Heroin Package', minCount = 5, maxCount = 20, weight = 0.8 },
        { name = 'meth_bag', label = 'Meth Bag', minCount = 10, maxCount = 25, weight = 0.7 },
        { name = 'dirty_money', label = 'Dirty Money', minCount = 50000, maxCount = 150000, weight = 0.6 },
        { name = 'weapon_carbinerifle', label = 'Carbine Rifle', minCount = 2, maxCount = 5, weight = 0.4 },
        { name = 'weapon_smg', label = 'SMG', minCount = 3, maxCount = 8, weight = 0.5 },
    }
    
    local numItems = math.random(config.MinDeliveryItems or 2, config.MaxDeliveryItems or 4)
    local selectedItems = {}
    
    for i = 1, numItems do
        local totalWeight = 0
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                totalWeight = totalWeight + item.weight
            end
        end
        
        if totalWeight <= 0 then break end
        
        local roll = math.random() * totalWeight
        local cumulative = 0
        
        for _, item in ipairs(itemPool) do
            if not selectedItems[item.name] then
                cumulative = cumulative + item.weight
                if roll <= cumulative then
                    local count = math.random(item.minCount, item.maxCount)
                    table.insert(items, {
                        name = item.name,
                        label = item.label,
                        count = count,
                    })
                    selectedItems[item.name] = true
                    break
                end
            end
        end
    end
    
    return items
end

---Get destination territory for convoy
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.Cartel.GetConvoyDestination(gangName)
    local config = FreeGangs.Config.Cartel.ConvoyProtection
    local destinations = {}
    
    -- Prefer territories the cartel has some control over
    if FreeGangs.Server.Territories then
        for zoneName, zoneData in pairs(FreeGangs.Server.Territories) do
            local ourControl = 0
            if zoneData.influence then
                ourControl = zoneData.influence[gangName] or 0
            end
            
            if ourControl >= 15 then
                table.insert(destinations, {
                    territory = zoneName,
                    label = zoneData.label or zoneName,
                    coords = zoneData.coords,
                    control = ourControl,
                })
            end
        end
    end
    
    -- Fallback to default destinations
    if #destinations == 0 and config.DefaultDestinations then
        for _, dest in ipairs(config.DefaultDestinations) do
            table.insert(destinations, {
                territory = dest.name,
                label = dest.label,
                coords = dest.coords,
                control = 0,
            })
        end
    end
    
    if #destinations == 0 then
        return nil
    end
    
    return destinations[math.random(#destinations)]
end

---Join convoy protection mission
---@param source number
---@param gangName string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.JoinConvoy(source, gangName)
    local convoy = ActiveConvoys[gangName]
    if not convoy or convoy.status ~= 'active' then
        return false, 'No active convoy'
    end
    
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    -- Check if already joined
    for _, cid in ipairs(convoy.participantCitizenIds) do
        if cid == citizenid then
            return false, 'Already participating in this convoy'
        end
    end
    
    table.insert(convoy.participants, source)
    table.insert(convoy.participantCitizenIds, citizenid)
    
    -- Notify other participants
    for _, pSource in ipairs(convoy.participants) do
        if pSource ~= source then
            FreeGangs.Bridge.Notify(pSource, FreeGangs.Bridge.GetPlayerName(source) .. ' joined the convoy!', 'inform')
        end
    end
    
    return true, 'Joined convoy! ' .. #convoy.participants .. ' participants.'
end

---Verify convoy items across participants
---@param gangName string
---@return boolean hasAll, table contributors
function FreeGangs.Server.Archetypes.Cartel.VerifyConvoyItems(gangName)
    local convoy = ActiveConvoys[gangName]
    if not convoy then return false, {} end
    
    local contributors = {}
    local itemsNeeded = {}
    
    for _, item in ipairs(convoy.requiredItems) do
        itemsNeeded[item.name] = {
            required = item.count,
            collected = 0,
            label = item.label,
        }
    end
    
    for i, pSource in ipairs(convoy.participants) do
        local citizenid = convoy.participantCitizenIds[i]
        contributors[citizenid] = {}
        
        for itemName, data in pairs(itemsNeeded) do
            if data.collected < data.required then
                local playerCount = FreeGangs.Bridge.GetItemCount(pSource, itemName)
                if playerCount > 0 then
                    local toTake = math.min(playerCount, data.required - data.collected)
                    data.collected = data.collected + toTake
                    contributors[citizenid][itemName] = toTake
                end
            end
        end
    end
    
    local hasAll = true
    for _, data in pairs(itemsNeeded) do
        if data.collected < data.required then
            hasAll = false
            break
        end
    end
    
    return hasAll, contributors
end

---Complete convoy protection at destination
---@param source number
---@param gangName string
---@param wasAmbushed boolean
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.CompleteConvoy(source, gangName, wasAmbushed)
    local convoy = ActiveConvoys[gangName]
    if not convoy or convoy.status ~= 'active' then
        return false, 'No active convoy'
    end
    
    -- Check time
    if os.time() >= convoy.expiresAt then
        return FreeGangs.Server.Archetypes.Cartel.FailConvoy(gangName, 'Time expired')
    end
    
    -- Verify items
    local hasItems, contributors = FreeGangs.Server.Archetypes.Cartel.VerifyConvoyItems(gangName)
    if not hasItems then
        return false, 'Participants do not have all required items'
    end
    
    -- If ambushed/doublecrossed
    if wasAmbushed then
        return FreeGangs.Server.Archetypes.Cartel.FailConvoy(gangName, 'Double-crossed at destination')
    end
    
    -- Remove items from contributors
    for citizenid, items in pairs(contributors) do
        local player = FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
        if player then
            for itemName, count in pairs(items) do
                if count > 0 then
                    FreeGangs.Bridge.RemoveItem(player.PlayerData.source, itemName, count)
                end
            end
        end
    end
    
    convoy.status = 'completed'
    convoy.completedAt = os.time()
    
    local config = FreeGangs.Config.Cartel.ConvoyProtection
    local participantCount = #convoy.participants
    
    -- === SUCCESS REWARDS ===
    
    -- 1. Territory influence at destination
    if convoy.destinationTerritory and FreeGangs.Server.Territory then
        local influenceGain = config.DestinationInfluenceGain or 8
        FreeGangs.Server.Territory.AddInfluence(convoy.destinationTerritory, gangName, influenceGain)
    end
    
    -- 2. Gang reputation
    local repGain = (config.RepGain or 40) + (participantCount * 3)
    FreeGangs.Server.Reputation.Add(gangName, repGain, 'Convoy protection completed')
    
    -- 3. Rewards for each participant
    local lootTable = config.LootTable or {
        { type = 'money', amount = { min = 5000, max = 15000 }, chance = 1.0 },
        { type = 'item', name = 'coke_brick', label = 'Cocaine Brick', count = { min = 1, max = 3 }, chance = 0.4 },
        { type = 'item', name = 'weapon_pistol', label = 'Pistol', count = { min = 1, max = 1 }, chance = 0.3 },
    }
    
    for _, pSource in ipairs(convoy.participants) do
        local rewards = FreeGangs.Server.Archetypes.MC.RollLootTable(lootTable) -- Reuse MC's loot table function
        
        local rewardStr = ''
        for _, r in ipairs(rewards) do
            if r.type == 'item' then
                FreeGangs.Bridge.AddItem(pSource, r.name, r.count)
                rewardStr = rewardStr .. r.label .. ' x' .. r.count .. ', '
            elseif r.type == 'money' then
                FreeGangs.Bridge.AddMoney(pSource, r.amount, 'cash', 'Convoy protection reward')
                rewardStr = rewardStr .. '$' .. FreeGangs.Utils.FormatMoney(r.amount) .. ', '
            end
        end
        rewardStr = rewardStr:sub(1, -3)
        
        FreeGangs.Bridge.Notify(pSource, 'Convoy delivered! Rewards: ' .. rewardStr, 'success')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, convoy.startedBy, 'convoy_completed', FreeGangs.LogCategories.ACTIVITY, {
        convoyId = convoy.id,
        destination = convoy.destinationTerritory,
        participantCount = participantCount,
        repGain = repGain,
    })
    
    ActiveConvoys[gangName] = nil
    
    return true, 'Convoy delivered successfully!'
end

---Fail convoy protection
---@param gangName string
---@param reason string
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.FailConvoy(gangName, reason)
    local convoy = ActiveConvoys[gangName]
    if not convoy then return false, 'No active convoy' end
    
    convoy.status = 'failed'
    convoy.failedAt = os.time()
    convoy.failReason = reason
    
    local config = FreeGangs.Config.Cartel.ConvoyProtection
    local repLoss = config.FailureRepLoss or 25
    
    FreeGangs.Server.Reputation.Remove(gangName, repLoss, 'Convoy protection failed: ' .. reason)
    
    for _, pSource in ipairs(convoy.participants) do
        FreeGangs.Bridge.Notify(pSource, 
            'Convoy failed: ' .. reason .. '! -' .. repLoss .. ' rep', 
            'error')
    end
    
    FreeGangs.Server.DB.Log(gangName, convoy.startedBy, 'convoy_failed', FreeGangs.LogCategories.ACTIVITY, {
        convoyId = convoy.id,
        reason = reason,
    })
    
    ActiveConvoys[gangName] = nil
    
    return true, 'Convoy failed'
end

---Check convoy expiry
---@param gangName string
---@param convoyId string
function FreeGangs.Server.Archetypes.Cartel.CheckConvoyExpiry(gangName, convoyId)
    local convoy = ActiveConvoys[gangName]
    if convoy and convoy.id == convoyId and convoy.status == 'active' then
        if os.time() >= convoy.expiresAt then
            FreeGangs.Server.Archetypes.Cartel.FailConvoy(gangName, 'Time expired')
        end
    end
end

---Get active convoy status
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.Cartel.GetActiveConvoy(gangName)
    local convoy = ActiveConvoys[gangName]
    if not convoy or convoy.status ~= 'active' then return nil end
    
    return {
        id = convoy.id,
        destination = convoy.destination,
        requiredItems = convoy.requiredItems,
        participantCount = #convoy.participants,
        timeRemaining = math.max(0, convoy.expiresAt - os.time()),
    }
end

-- ============================================================================
-- CARTEL: EXCLUSIVE SUPPLIERS (TIER 3)
-- ============================================================================

---Access exclusive supplier
---@param source number
---@param gangName string
---@param params table { supplierType: string }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.Cartel.AccessExclusiveSupplier(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    local config = FreeGangs.Config.Cartel.ExclusiveSuppliers
    
    -- Check archetype access
    local hasAccess = false
    for _, archetype in ipairs(config.AccessibleArchetypes) do
        if gang.archetype == archetype then
            hasAccess = true
            break
        end
    end
    
    if not hasAccess then
        return false, 'Only Cartels and Crime Families can access exclusive suppliers'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 3) then
        return false, 'Requires Master Level 8'
    end
    
    local supplierType = params and params.supplierType or 'drugs'
    local supplierConfig = config.SupplierTypes[supplierType]
    
    if not supplierConfig or not supplierConfig.enabled then
        return false, 'Supplier type not available'
    end
    
    -- Return supplier access info
    TriggerClientEvent('free-gangs:client:openExclusiveSupplier', source, {
        supplierType = supplierType,
        discount = supplierConfig.discountPercent,
        exclusiveItems = supplierConfig.exclusiveItems,
        gangLevel = gang.master_level,
    })
    
    return true, 'Accessing exclusive supplier'
end

-- ============================================================================
-- CRIME FAMILY: BUSINESS EXTORTION BONUS (TIER 1) - PASSIVE BONUS
-- Crime families get increased reputation and payout from business extortions
-- This is a PASSIVE BONUS that applies automatically to extortion activities
-- ============================================================================

---Check if Crime Family has extortion bonus active
---@param gangName string
---@return boolean
function FreeGangs.Server.Archetypes.CrimeFamily.HasExtortionBonus(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang or gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return false
    end
    
    return FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1)
end

---Get extortion bonus multipliers for Crime Family
---@param gangName string
---@return table bonuses { repMultiplier: number, payoutMultiplier: number }
function FreeGangs.Server.Archetypes.CrimeFamily.GetExtortionBonus(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Default - no bonus
    local bonuses = {
        repMultiplier = 1.0,
        payoutMultiplier = 1.0,
    }
    
    if not gang or gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return bonuses
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return bonuses
    end
    
    local config = FreeGangs.Config.CrimeFamily.BusinessExtortion or {
        RepMultiplier = 1.50,     -- 50% more rep from extortions
        PayoutMultiplier = 1.25, -- 25% more payout from extortions
    }
    
    return {
        repMultiplier = config.RepMultiplier or 1.50,
        payoutMultiplier = config.PayoutMultiplier or 1.25,
    }
end

---Apply extortion bonus to reputation gain
---Called by extortion activities to get boosted rep for Crime Families
---@param gangName string
---@param baseRep number
---@return number boostedRep
function FreeGangs.Server.Archetypes.CrimeFamily.ApplyExtortionRepBonus(gangName, baseRep)
    local bonuses = FreeGangs.Server.Archetypes.CrimeFamily.GetExtortionBonus(gangName)
    return math.floor(baseRep * bonuses.repMultiplier)
end

---Apply extortion bonus to payout
---Called by extortion activities to get boosted payout for Crime Families
---@param gangName string
---@param basePayout number
---@return number boostedPayout
function FreeGangs.Server.Archetypes.CrimeFamily.ApplyExtortionPayoutBonus(gangName, basePayout)
    local bonuses = FreeGangs.Server.Archetypes.CrimeFamily.GetExtortionBonus(gangName)
    return math.floor(basePayout * bonuses.payoutMultiplier)
end

---Process a business extortion (called when Crime Family extorts a business)
---This function should be called by the business/extortion system
---@param source number
---@param gangName string
---@param businessData table { businessName: string, basePayout: number, baseRep: number }
---@return table result { payout: number, rep: number, wasEnhanced: boolean }
function FreeGangs.Server.Archetypes.CrimeFamily.ProcessBusinessExtortion(source, gangName, businessData)
    local gang = FreeGangs.Server.Gangs[gangName]
    local basePayout = businessData.basePayout or 1000
    local baseRep = businessData.baseRep or 5
    
    local result = {
        payout = basePayout,
        rep = baseRep,
        wasEnhanced = false,
    }
    
    -- Apply Crime Family bonus if applicable
    if gang and gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        if FreeGangs.Server.Archetypes.CrimeFamily.HasExtortionBonus(gangName) then
            result.payout = FreeGangs.Server.Archetypes.CrimeFamily.ApplyExtortionPayoutBonus(gangName, basePayout)
            result.rep = FreeGangs.Server.Archetypes.CrimeFamily.ApplyExtortionRepBonus(gangName, baseRep)
            result.wasEnhanced = true
            
            -- Log the enhanced extortion
            local citizenid = FreeGangs.Bridge.GetCitizenId(source)
            FreeGangs.Server.DB.Log(gangName, citizenid, 'enhanced_extortion', FreeGangs.LogCategories.ACTIVITY, {
                businessName = businessData.businessName or 'Unknown',
                basePayout = basePayout,
                enhancedPayout = result.payout,
                baseRep = baseRep,
                enhancedRep = result.rep,
            })
        end
    end
    
    return result
end

---Get info about Crime Family extortion bonuses (for UI display)
---@param gangName string
---@return table info
function FreeGangs.Server.Archetypes.CrimeFamily.GetExtortionBonusInfo(gangName)
    local hasBonus = FreeGangs.Server.Archetypes.CrimeFamily.HasExtortionBonus(gangName)
    local bonuses = FreeGangs.Server.Archetypes.CrimeFamily.GetExtortionBonus(gangName)
    
    return {
        active = hasBonus,
        repBonus = hasBonus and string.format('+%.0f%%', (bonuses.repMultiplier - 1) * 100) or '0%',
        payoutBonus = hasBonus and string.format('+%.0f%%', (bonuses.payoutMultiplier - 1) * 100) or '0%',
        description = hasBonus 
            and 'Business extortions grant enhanced reputation and payouts'
            or 'Requires Master Level 4 to unlock'
    }
end

-- ============================================================================
-- CRIME FAMILY: TRIBUTE NETWORK (TIER 1) - ACTIVE ABILITY
-- Crime families collect a cut from NPC sales in controlled zones
-- ============================================================================

---Get tribute cut percentage for a zone based on gang influence
---@param gangName string
---@param zoneName string
---@return number cutPercent (0.0 to 0.05)
function FreeGangs.Server.Archetypes.CrimeFamily.GetTributeCut(gangName, zoneName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang or gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return 0
    end

    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return 0
    end

    local influence = FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)
    if influence < 25 then
        return 0
    end

    -- Base 5% cut, scaled by influence above 25%
    local baseCut = 0.05
    local influenceScale = math.min(1.0, (influence - 25) / 75)
    return baseCut * (0.5 + 0.5 * influenceScale)
end

---Collect tribute from controlled zones
---@param source number
---@param gangName string
---@param params table
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.CrimeFamily.CollectTribute(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang or gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return false, 'Only Crime Families can collect tribute'
    end

    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 1) then
        return false, 'Requires Master Level 4'
    end

    -- Check cooldown
    local cooldownKey = gangName .. '_tribute_collection'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'Tribute collection on cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end

    -- Calculate tribute from all controlled zones
    local totalTribute = 0
    local zoneCount = 0
    local territories = FreeGangs.Server.Territory.GetAll()

    for zoneName, territory in pairs(territories) do
        local cut = FreeGangs.Server.Archetypes.CrimeFamily.GetTributeCut(gangName, zoneName)
        if cut > 0 then
            local zoneValue = territory.protectionValue or 500
            local tribute = math.floor(zoneValue * cut)
            totalTribute = totalTribute + tribute
            zoneCount = zoneCount + 1
        end
    end

    if totalTribute <= 0 then
        return false, 'No controlled zones to collect tribute from (need 25%+ influence)'
    end

    -- Apply extortion bonus if available
    if FreeGangs.Server.Archetypes.CrimeFamily.HasExtortionBonus(gangName) then
        totalTribute = FreeGangs.Server.Archetypes.CrimeFamily.ApplyExtortionPayoutBonus(gangName, totalTribute)
    end

    -- Deposit into treasury
    gang.treasury = (gang.treasury or 0) + totalTribute
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)

    -- Set cooldown
    local cooldownSeconds = FreeGangs.Config.Cooldowns.tribute_collection or 3600
    FreeGangs.Server.SetCooldown(source, cooldownKey, cooldownSeconds)

    -- Add reputation
    local repGain = math.floor(5 * zoneCount)
    FreeGangs.Server.Reputation.Add(gangName, repGain, 'Tribute collection')

    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'tribute_collected', FreeGangs.LogCategories.ACTIVITY, {
        zones = zoneCount,
        amount = totalTribute,
        repGain = repGain,
    })

    return true, 'Collected $' .. FreeGangs.Utils.FormatMoney(totalTribute) .. ' tribute from ' .. zoneCount .. ' zone(s)'
end

-- ============================================================================
-- CRIME FAMILY: HIGH-VALUE CONTRACTS (TIER 2)
-- ============================================================================

---Link a heist for reputation bonus
---@param source number
---@param gangName string
---@param params table { heistName: string, payout: number }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.CrimeFamily.LinkHeist(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return false, 'Only Crime Families can link high-value contracts'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 2) then
        return false, 'Requires Master Level 6'
    end
    
    local config = FreeGangs.Config.CrimeFamily.HighValueContracts
    local heistName = params and params.heistName
    local payout = params and params.payout or 0
    
    if not heistName then
        return false, 'No heist specified'
    end
    
    -- Calculate boosted rep
    local baseRep = 50
    local contractType = config.ContractTypes[heistName]
    if contractType then
        baseRep = contractType.rep
    end
    
    local boostedRep = math.floor(baseRep * config.HeistRepMultiplier)
    
    FreeGangs.Server.Reputation.Add(gangName, boostedRep, 'High-value contract: ' .. heistName)
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'heist_linked', FreeGangs.LogCategories.ACTIVITY, {
        heistName = heistName,
        payout = payout,
        repEarned = boostedRep,
    })
    
    return true, 'Heist linked! +' .. boostedRep .. ' reputation'
end

---Start a high-value contract (internal system)
---@param source number
---@param gangName string
---@param params table { contractType: string }
---@return boolean, string|nil
function FreeGangs.Server.Archetypes.CrimeFamily.StartHighValueContract(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return false, 'Only Crime Families can start high-value contracts'
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 2) then
        return false, 'Requires Master Level 6'
    end
    
    local config = FreeGangs.Config.CrimeFamily.HighValueContracts
    
    -- Check cooldown
    local cooldownKey = 'hv_contract_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Contracts on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    local contractType = params and params.contractType
    local contract = config.ContractTypes[contractType]
    
    if not contract then
        -- Return available contract types
        TriggerClientEvent('free-gangs:client:showContractTypes', source, config.ContractTypes)
        return true, 'Select a contract type'
    end
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.ContractCooldown)
    
    -- Generate contract details
    local payout = math.random(contract.payout.min, contract.payout.max)
    
    TriggerClientEvent('free-gangs:client:startContract', source, {
        type = contractType,
        payout = payout,
        rep = contract.rep,
    })
    
    return true, 'Contract started'
end

-- ============================================================================
-- CRIME FAMILY: POLITICAL IMMUNITY (TIER 3)
-- ============================================================================

---Check political immunity benefits
---@param source number
---@param gangName string
---@param params table|nil
---@return boolean, table|nil benefits
function FreeGangs.Server.Archetypes.CrimeFamily.CheckPoliticalImmunity(source, gangName, params)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return false, nil
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 3) then
        return false, nil
    end
    
    local config = FreeGangs.Config.CrimeFamily.PoliticalImmunity
    
    return true, {
        bribeCostReduction = config.BribeCostReduction,
        bribeEffectBonus = config.BribeEffectBonus,
        ignoreZoneRequirements = config.IgnoreZoneRequirements,
        heatReduction = config.HeatReduction,
        benefits = config.Benefits,
    }
end

---Get bribe discount for Crime Family with Political Immunity
---@param gangName string
---@return number discount (0-1)
function FreeGangs.Server.Archetypes.CrimeFamily.GetBribeDiscount(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang or gang.archetype ~= FreeGangs.Archetypes.CRIME_FAMILY then
        return 0
    end
    
    if not FreeGangs.Server.Archetypes.HasTierAccess(gangName, 3) then
        -- Use base bribe effectiveness bonus
        return FreeGangs.Server.Archetypes.GetPassiveBonus(gangName, 'bribeEffectiveness')
    end
    
    return FreeGangs.Config.CrimeFamily.PoliticalImmunity.BribeCostReduction
end

-- ============================================================================
-- INITIALIZATION & LOADING
-- ============================================================================

---Load archetype data from database on startup
function FreeGangs.Server.Archetypes.Initialize()
    -- Load main corners
    local mainCornerData = FreeGangs.Server.DB.GetAllGangMetadata('main_corner')
    if mainCornerData then
        for _, data in ipairs(mainCornerData) do
            MainCorners[data.gang_name] = data.value
        end
    end
    
    -- Load halcon network states
    local halconData = FreeGangs.Server.DB.GetAllGangMetadata('halcon_enabled')
    if halconData then
        for _, data in ipairs(halconData) do
            HalconNetworkEnabled[data.gang_name] = data.value == 'true' or data.value == true
        end
    end
    
    if FreeGangs.Debug then
        print('[FREE-GANGS] Archetypes module initialized')
        print('[FREE-GANGS] - Loaded ' .. FreeGangs.Utils.TableLength(MainCorners) .. ' main corners')
        print('[FREE-GANGS] - Loaded ' .. FreeGangs.Utils.TableLength(HalconNetworkEnabled) .. ' halcon networks')
    end
end

-- ============================================================================
-- UTILITY EXPORTS
-- ============================================================================

---Get archetype info for a gang
---@param gangName string
---@return table|nil
function FreeGangs.Server.Archetypes.GetGangArchetypeInfo(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return nil end
    
    return {
        archetype = gang.archetype,
        label = FreeGangs.ArchetypeLabels[gang.archetype],
        passives = FreeGangs.Server.Archetypes.GetAllPassiveBonuses(gangName),
        unlockedTiers = FreeGangs.Server.Archetypes.GetUnlockedTiers(gangName),
        tierActivities = FreeGangs.ArchetypeTierActivities[gang.archetype],
    }
end

return FreeGangs.Server.Archetypes
