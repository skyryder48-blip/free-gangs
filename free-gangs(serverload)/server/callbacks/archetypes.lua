--[[
    FREE-GANGS: Server Archetypes Callbacks
    
    Handles all client-server callbacks for archetype and prison functionality
    using ox_lib callback system.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Callbacks = FreeGangs.Server.Callbacks or {}

-- ============================================================================
-- ARCHETYPE INFORMATION CALLBACKS
-- ============================================================================

---Get archetype info for current player's gang
lib.callback.register('free-gangs:callback:getArchetypeInfo', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    return FreeGangs.Server.Archetypes.GetGangArchetypeInfo(membership.gang_name)
end)

---Get passive bonuses for player's gang
lib.callback.register('free-gangs:callback:getPassiveBonuses', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return {} end
    
    return FreeGangs.Server.Archetypes.GetAllPassiveBonuses(membership.gang_name)
end)

---Get unlocked tiers for player's gang
lib.callback.register('free-gangs:callback:getUnlockedTiers', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return {} end
    
    return FreeGangs.Server.Archetypes.GetUnlockedTiers(membership.gang_name)
end)

---Check if player's gang has access to a specific tier
lib.callback.register('free-gangs:callback:hasTierAccess', function(source, tier)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    return FreeGangs.Server.Archetypes.HasTierAccess(membership.gang_name, tier)
end)

---Get available tier activities for player's archetype
lib.callback.register('free-gangs:callback:getTierActivities', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then return nil end
    
    local activities = FreeGangs.ArchetypeTierActivities[gang.archetype]
    local unlocked = FreeGangs.Server.Archetypes.GetUnlockedTiers(membership.gang_name)
    
    local result = {}
    for tier, activity in pairs(activities or {}) do
        result[tier] = {
            name = activity.name,
            description = activity.description,
            minLevel = activity.minLevel,
            unlocked = unlocked[tier] == true,
        }
    end
    
    return result
end)

-- ============================================================================
-- TIER ACTIVITY EXECUTION CALLBACKS
-- ============================================================================

---Execute a tier activity
lib.callback.register('free-gangs:callback:executeTierActivity', function(source, activityName, params)
    local success, message = FreeGangs.Server.Archetypes.ExecuteTierActivity(source, activityName, params)
    return { success = success, message = message }
end)

-- ============================================================================
-- STREET GANG SPECIFIC CALLBACKS
-- ============================================================================

---Set main corner
lib.callback.register('free-gangs:callback:setMainCorner', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Street.SetMainCorner(source, membership.gang_name, { zoneName = zoneName })
    return { success = success, message = message }
end)

---Get main corner
lib.callback.register('free-gangs:callback:getMainCorner', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    return FreeGangs.Server.Archetypes.Street.GetMainCorner(membership.gang_name)
end)

---Start block party
lib.callback.register('free-gangs:callback:startBlockParty', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Street.StartBlockParty(source, membership.gang_name, { zoneName = zoneName })
    return { success = success, message = message }
end)

---Check block party status
lib.callback.register('free-gangs:callback:getBlockPartyStatus', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local active, party = FreeGangs.Server.Archetypes.Street.IsBlockPartyActive(membership.gang_name)
    if not active then return nil end
    
    return {
        active = true,
        zoneName = party.zoneName,
        startTime = party.startTime,
        endTime = party.endTime,
        remaining = party.endTime - FreeGangs.Utils.GetTimestamp(),
    }
end)

---Accept drive-by contract
lib.callback.register('free-gangs:callback:acceptDriveByContract', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Street.AcceptDriveByContract(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---Complete drive-by contract
lib.callback.register('free-gangs:callback:completeDriveByContract', function(source, contractId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Street.CompleteContract(source, membership.gang_name, contractId)
    return { success = success, message = message }
end)

-- ============================================================================
-- MC SPECIFIC CALLBACKS
-- ============================================================================

---Start prospect run
lib.callback.register('free-gangs:callback:startProspectRun', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.MC.StartProspectRun(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---Complete prospect run
lib.callback.register('free-gangs:callback:completeProspectRun', function(source, runId, success)
    return FreeGangs.Server.Archetypes.MC.CompleteProspectRun(source, runId, success)
end)

---Start club run
lib.callback.register('free-gangs:callback:startClubRun', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.MC.StartClubRun(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---Join club run
lib.callback.register('free-gangs:callback:joinClubRun', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.MC.JoinClubRun(source, membership.gang_name)
    return { success = success, message = message }
end)

---Start territory ride
lib.callback.register('free-gangs:callback:startTerritoryRide', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.MC.StartTerritoryRide(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---End territory ride
lib.callback.register('free-gangs:callback:endTerritoryRide', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.MC.EndTerritoryRide(membership.gang_name)
    return { success = success, message = message }
end)

-- ============================================================================
-- CARTEL SPECIFIC CALLBACKS
-- ============================================================================

---Toggle Halcon Network
lib.callback.register('free-gangs:callback:toggleHalconNetwork', function(source, enabled)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Cartel.ToggleHalconNetwork(source, membership.gang_name, { enabled = enabled })
    return { success = success, message = message }
end)

---Get Halcon Network status
lib.callback.register('free-gangs:callback:getHalconStatus', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    return FreeGangs.Server.Archetypes.Cartel.IsHalconNetworkEnabled(membership.gang_name)
end)

---Start convoy protection
lib.callback.register('free-gangs:callback:startConvoyProtection', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Cartel.StartConvoyProtection(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---Access exclusive supplier
lib.callback.register('free-gangs:callback:accessExclusiveSupplier', function(source, supplierType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.Cartel.AccessExclusiveSupplier(source, membership.gang_name, { supplierType = supplierType })
    return { success = success, message = message }
end)

-- ============================================================================
-- CRIME FAMILY SPECIFIC CALLBACKS
-- ============================================================================

---Collect tribute
lib.callback.register('free-gangs:callback:collectTribute', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.CrimeFamily.CollectTribute(source, membership.gang_name, {})
    return { success = success, message = message }
end)

---Link heist for reputation
lib.callback.register('free-gangs:callback:linkHeist', function(source, heistName, payout)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.CrimeFamily.LinkHeist(source, membership.gang_name, { heistName = heistName, payout = payout })
    return { success = success, message = message }
end)

---Start high-value contract
lib.callback.register('free-gangs:callback:startHighValueContract', function(source, contractType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'Unable to identify player' } end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return { success = false, message = 'Not in a gang' } end
    
    local success, message = FreeGangs.Server.Archetypes.CrimeFamily.StartHighValueContract(source, membership.gang_name, { contractType = contractType })
    return { success = success, message = message }
end)

---Check political immunity status
lib.callback.register('free-gangs:callback:checkPoliticalImmunity', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local success, benefits = FreeGangs.Server.Archetypes.CrimeFamily.CheckPoliticalImmunity(source, membership.gang_name, {})
    if success then
        return benefits
    end
    return nil
end)

---Get bribe discount
lib.callback.register('free-gangs:callback:getBribeDiscount', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    return FreeGangs.Server.Archetypes.CrimeFamily.GetBribeDiscount(membership.gang_name)
end)

-- ============================================================================
-- BONUS CALCULATION CALLBACKS
-- ============================================================================

---Apply archetype bonus to a value
lib.callback.register('free-gangs:callback:applyArchetypeBonus', function(source, baseValue, bonusType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return baseValue end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return baseValue end
    
    return FreeGangs.Server.Archetypes.ApplyBonus(membership.gang_name, baseValue, bonusType)
end)

---Get specific passive bonus value
lib.callback.register('free-gangs:callback:getPassiveBonus', function(source, bonusType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    return FreeGangs.Server.Archetypes.GetPassiveBonus(membership.gang_name, bonusType)
end)

---Get main corner bonus for drug sale
lib.callback.register('free-gangs:callback:getMainCornerBonus', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    return FreeGangs.Server.Archetypes.Street.GetMainCornerBonus(membership.gang_name, zoneName)
end)

---Get loyalty multiplier (block party bonus)
lib.callback.register('free-gangs:callback:getLoyaltyMultiplier', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 1.0 end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 1.0 end
    
    return FreeGangs.Server.Archetypes.Street.GetLoyaltyMultiplier(membership.gang_name, zoneName)
end)

---Get tribute cut percentage
lib.callback.register('free-gangs:callback:getTributeCut', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    return FreeGangs.Server.Archetypes.CrimeFamily.GetTributeCut(membership.gang_name, zoneName)
end)

-- ============================================================================
-- ADMIN CALLBACKS
-- ============================================================================

---Admin: Set gang archetype (requires permission)
lib.callback.register('free-gangs:callback:admin:setArchetype', function(source, gangName, archetype)
    -- Check admin permission
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return { success = false, message = 'No permission' }
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then
        return { success = false, message = 'Gang not found' }
    end
    
    if not FreeGangs.ArchetypeLabels[archetype] then
        return { success = false, message = 'Invalid archetype' }
    end
    
    -- Update archetype
    gang.archetype = archetype
    FreeGangs.Server.DB.UpdateGang(gangName, { archetype = archetype })
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    -- Log
    local adminCitizenId = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, adminCitizenId, 'archetype_changed_admin', FreeGangs.LogCategories.ADMIN, {
        newArchetype = archetype,
    })
    
    return { success = true, message = 'Archetype changed to ' .. FreeGangs.ArchetypeLabels[archetype].label }
end)

---Admin: Set prison control
lib.callback.register('free-gangs:callback:admin:setPrisonControl', function(source, gangName, control)
    -- Check admin permission
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return { success = false, message = 'No permission' }
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then
        return { success = false, message = 'Gang not found' }
    end
    
    control = math.max(0, math.min(100, control))
    
    -- Calculate difference and adjust
    local current = FreeGangs.Server.Prison.GetControlLevel(gangName)
    if control > current then
        FreeGangs.Server.Prison.AddInfluence(gangName, control - current, 'Admin set')
    elseif control < current then
        FreeGangs.Server.Prison.RemoveInfluence(gangName, current - control, 'Admin set')
    end
    
    return { success = true, message = 'Prison control set to ' .. control .. '%' }
end)

return FreeGangs.Server.Callbacks
