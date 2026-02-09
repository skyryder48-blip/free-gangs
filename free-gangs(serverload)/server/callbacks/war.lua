--[[
    FREE-GANGS: War Callbacks
    
    Server-side callbacks for war-related operations.
    Uses ox_lib callback system for client-server communication.
]]

-- Ensure module namespace exists
FreeGangs.Server = FreeGangs.Server or {}

-- ============================================================================
-- WAR DATA CALLBACKS
-- ============================================================================

---Get active wars for a gang
lib.callback.register(FreeGangs.Callbacks.GET_ACTIVE_WARS, function(source, gangName)
    if not gangName then
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return {}
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member then
            return {}
        end
        
        gangName = member.gang_name
    end
    
    return FreeGangs.Server.War.GetGangWars(gangName, false)
end)

---Get war history for a gang
lib.callback.register(FreeGangs.Callbacks.GET_WAR_HISTORY, function(source, gangName)
    if not gangName then
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return {}
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member then
            return {}
        end
        
        gangName = member.gang_name
    end
    
    return FreeGangs.Server.War.GetGangWars(gangName, true)
end)

---Get pending war declarations
lib.callback.register('free-gangs:callback:getPendingWars', function(source, gangName)
    if not gangName then
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return {}
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member then
            return {}
        end
        
        gangName = member.gang_name
    end
    
    return FreeGangs.Server.War.GetPendingDeclarations(gangName)
end)

---Get war by ID
lib.callback.register('free-gangs:callback:getWar', function(source, warId)
    return FreeGangs.Server.War.GetById(warId)
end)

---Check if two gangs are at war
lib.callback.register('free-gangs:callback:areGangsAtWar', function(source, gangA, gangB)
    return FreeGangs.Server.War.IsAtWarWith(gangA, gangB)
end)

---Get all active wars (admin only)
lib.callback.register('free-gangs:callback:getAllActiveWars', function(source)
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return nil
    end
    
    return FreeGangs.Server.War.GetAllActive()
end)

-- ============================================================================
-- WAR ACTION CALLBACKS
-- ============================================================================

---Declare war on another gang
lib.callback.register('free-gangs:callback:declareWar', function(source, defenderGang, collateral, terms)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return nil, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return nil, 'Not in a gang'
    end
    
    -- Verify permission (must be boss/officer)
    local hasPermission = FreeGangs.Server.Member.HasPermission(
        member.gang_name, 
        citizenId, 
        FreeGangs.Permissions.DECLARE_WAR
    )
    
    if not hasPermission then
        return nil, 'You do not have permission to declare war'
    end
    
    local warId, errorMsg = FreeGangs.Server.War.Declare(member.gang_name, defenderGang, collateral, terms)
    
    if warId then
        -- Log the player who declared
        FreeGangs.Server.DB.Log(member.gang_name, citizenId, 'war_declared_by', FreeGangs.LogCategories.WAR, {
            defender = defenderGang,
            collateral = collateral,
            war_id = warId,
        })
    end
    
    return warId, errorMsg
end)

---Accept a war declaration
lib.callback.register('free-gangs:callback:acceptWar', function(source, warId, matchCollateral)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return false, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return false, 'Not in a gang'
    end
    
    -- Verify permission (must be boss/officer)
    local hasPermission = FreeGangs.Server.Member.HasPermission(
        member.gang_name, 
        citizenId, 
        FreeGangs.Permissions.ACCEPT_WAR
    )
    
    if not hasPermission then
        return false, 'You do not have permission to accept war'
    end
    
    local war = FreeGangs.Server.War.GetById(warId)
    if not war then
        return false, 'War declaration not found'
    end
    
    -- Calculate collateral (match attacker by default, or custom)
    local defenderCollateral = matchCollateral and war.attacker_collateral or matchCollateral
    
    local success, errorMsg = FreeGangs.Server.War.Accept(warId, member.gang_name, defenderCollateral)
    
    if success then
        FreeGangs.Server.DB.Log(member.gang_name, citizenId, 'war_accepted_by', FreeGangs.LogCategories.WAR, {
            attacker = war.attacker,
            war_id = warId,
        })
    end
    
    return success, errorMsg
end)

---Decline a war declaration
lib.callback.register('free-gangs:callback:declineWar', function(source, warId)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return false, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return false, 'Not in a gang'
    end
    
    -- Verify permission (must be boss/officer)
    local hasPermission = FreeGangs.Server.Member.HasPermission(
        member.gang_name, 
        citizenId, 
        FreeGangs.Permissions.DECLINE_WAR
    )
    
    if not hasPermission then
        return false, 'You do not have permission to decline war'
    end
    
    local success, errorMsg = FreeGangs.Server.War.Decline(warId, member.gang_name)
    
    if success then
        FreeGangs.Server.DB.Log(member.gang_name, citizenId, 'war_declined_by', FreeGangs.LogCategories.WAR, {
            war_id = warId,
        })
    end
    
    return success, errorMsg
end)

---Surrender from active war
lib.callback.register('free-gangs:callback:surrenderWar', function(source, warId)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return false, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return false, 'Not in a gang'
    end
    
    -- Verify permission (boss only for surrender)
    local hasPermission = FreeGangs.Server.Member.HasPermission(
        member.gang_name, 
        citizenId, 
        FreeGangs.Permissions.SURRENDER_WAR
    )
    
    if not hasPermission then
        return false, 'Only the gang leader can surrender'
    end
    
    local success, errorMsg = FreeGangs.Server.War.Surrender(warId, member.gang_name)
    
    if success then
        FreeGangs.Server.DB.Log(member.gang_name, citizenId, 'war_surrendered_by', FreeGangs.LogCategories.WAR, {
            war_id = warId,
        })
    end
    
    return success, errorMsg
end)

---Request peace
lib.callback.register('free-gangs:callback:requestPeace', function(source, warId)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return false, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return false, 'Not in a gang'
    end
    
    -- Verify permission (boss only for peace requests)
    local hasPermission = FreeGangs.Server.Member.HasPermission(
        member.gang_name, 
        citizenId, 
        FreeGangs.Permissions.REQUEST_PEACE
    )
    
    if not hasPermission then
        return false, 'Only the gang leader can request peace'
    end
    
    local success, message = FreeGangs.Server.War.RequestPeace(warId, member.gang_name)
    
    if success then
        FreeGangs.Server.DB.Log(member.gang_name, citizenId, 'peace_requested_by', FreeGangs.LogCategories.WAR, {
            war_id = warId,
        })
    end
    
    return success, message
end)

-- ============================================================================
-- WAR VALIDATION CALLBACKS
-- ============================================================================

---Get war requirements/validation for declaration
lib.callback.register('free-gangs:callback:getWarRequirements', function(source, defenderGang)
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return nil, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return nil, 'Not in a gang'
    end
    
    local attackerGang = member.gang_name
    local attackerData = FreeGangs.Server.Gangs[attackerGang]
    local defenderData = FreeGangs.Server.Gangs[defenderGang]
    
    if not defenderData then
        return nil, 'Target gang does not exist'
    end
    
    local heatLevel = FreeGangs.Server.Heat.Get(attackerGang, defenderGang)
    local minHeat = FreeGangs.Config.War.MinHeatForWar
    
    local hasCooldown, cooldownUntil = FreeGangs.Server.DB.CheckWarCooldown(attackerGang, defenderGang)
    local isAtWar = FreeGangs.Server.War.IsAtWarWith(attackerGang, defenderGang)
    local hasPending = FreeGangs.Server.War.GetPending(attackerGang, defenderGang) ~= nil
    
    return {
        attacker = {
            name = attackerGang,
            label = attackerData.label,
            war_chest = attackerData.war_chest or 0,
        },
        defender = {
            name = defenderGang,
            label = defenderData.label,
        },
        heat = {
            current = heatLevel,
            required = minHeat,
            sufficient = heatLevel >= minHeat,
        },
        collateral = {
            min = FreeGangs.Config.War.MinCollateral,
            max = FreeGangs.Config.War.MaxCollateral,
            min_balance = FreeGangs.Config.War.WarChest.MinBalanceForWar,
        },
        blockers = {
            already_at_war = isAtWar,
            pending_declaration = hasPending,
            on_cooldown = hasCooldown,
            cooldown_until = hasCooldown and cooldownUntil or nil,
        },
        can_declare = heatLevel >= minHeat and not isAtWar and not hasPending and not hasCooldown,
    }
end)

---Check cooldown status
lib.callback.register('free-gangs:callback:getWarCooldown', function(source, gangA, gangB)
    local hasCooldown, cooldownUntil = FreeGangs.Server.DB.CheckWarCooldown(gangA, gangB)
    
    return {
        has_cooldown = hasCooldown,
        cooldown_until = cooldownUntil,
        remaining_seconds = hasCooldown and (cooldownUntil - os.time()) or 0,
    }
end)

-- ============================================================================
-- ADMIN CALLBACKS
-- ============================================================================

---Admin end war
lib.callback.register('free-gangs:callback:adminEndWar', function(source, warId, winner)
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    return FreeGangs.Server.War.AdminEnd(warId, winner, source)
end)

---Admin cancel war
lib.callback.register('free-gangs:callback:adminCancelWar', function(source, warId)
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    return FreeGangs.Server.War.End(warId, nil, 'admin_cancelled')
end)

---Admin set war cooldown
lib.callback.register('free-gangs:callback:adminSetWarCooldown', function(source, gangA, gangB, hours)
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    local cooldownUntil = os.time() + (hours * 3600)
    FreeGangs.Server.DB.SetWarCooldown(gangA, gangB, cooldownUntil, 'admin_set')
    
    return true
end)

---Admin clear war cooldown
lib.callback.register('free-gangs:callback:adminClearWarCooldown', function(source, gangA, gangB)
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    -- Set cooldown to past time
    FreeGangs.Server.DB.SetWarCooldown(gangA, gangB, os.time() - 1, 'admin_cleared')
    
    return true
end)

-- ============================================================================
-- EVENT HANDLERS FOR WAR
-- ============================================================================

---Handle war declaration event
RegisterNetEvent(FreeGangs.Events.Server.DECLARE_WAR, function(defenderGang, collateral)
    local source = source
    
    -- Delegate to callback logic
    local warId, errorMsg = lib.callback.await('free-gangs:callback:declareWar', source, defenderGang, collateral)
    
    if not warId then
        FreeGangs.Bridge.Notify(source, errorMsg or 'Failed to declare war', 'error')
    end
end)

---Handle war acceptance event
RegisterNetEvent(FreeGangs.Events.Server.ACCEPT_WAR, function(warId)
    local source = source
    
    local success, errorMsg = lib.callback.await('free-gangs:callback:acceptWar', source, warId, true)
    
    if not success then
        FreeGangs.Bridge.Notify(source, errorMsg or 'Failed to accept war', 'error')
    end
end)

---Handle surrender event
RegisterNetEvent(FreeGangs.Events.Server.SURRENDER, function(warId)
    local source = source
    
    local success, errorMsg = lib.callback.await('free-gangs:callback:surrenderWar', source, warId)
    
    if not success then
        FreeGangs.Bridge.Notify(source, errorMsg or 'Failed to surrender', 'error')
    end
end)

-- ============================================================================
-- KILL EVENT HANDLER
-- ============================================================================

---Handle player death during war
AddEventHandler('qbx_medical:server:onPlayerDeath', function(source, data)
    local victimCitizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not victimCitizenId then return end
    
    local victimMember = FreeGangs.Server.DB.GetMember(victimCitizenId)
    if not victimMember then return end
    
    local victimGang = victimMember.gang_name
    
    -- Check if killer info is available
    local killerId = data and data.killerServerId
    if not killerId then return end
    
    local killerCitizenId = FreeGangs.Bridge.GetCitizenId(killerId)
    if not killerCitizenId then return end
    
    local killerMember = FreeGangs.Server.DB.GetMember(killerCitizenId)
    if not killerMember then return end
    
    local killerGang = killerMember.gang_name
    
    -- Same gang kills don't count
    if killerGang == victimGang then return end
    
    -- Check if these gangs are at war
    local war = FreeGangs.Server.War.GetActive(killerGang, victimGang)
    if not war then return end
    
    -- Record the kill
    FreeGangs.Server.War.RecordKill(war.id, killerGang, killerCitizenId, victimCitizenId)
    
    -- Also add heat from the kill
    local heatAmount = FreeGangs.Config.Heat.Points.RivalKill or 20
    FreeGangs.Server.Heat.Add(killerGang, victimGang, heatAmount, 'war_kill')
end)

-- Alternative death handler for different medical scripts
RegisterNetEvent('hospital:server:onPlayerDeath', function(killerId)
    local source = source
    local victimCitizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not victimCitizenId then return end
    
    local victimMember = FreeGangs.Server.DB.GetMember(victimCitizenId)
    if not victimMember then return end
    
    if not killerId or killerId == source then return end
    
    local killerCitizenId = FreeGangs.Bridge.GetCitizenId(killerId)
    if not killerCitizenId then return end
    
    local killerMember = FreeGangs.Server.DB.GetMember(killerCitizenId)
    if not killerMember then return end
    
    if killerMember.gang_name == victimMember.gang_name then return end
    
    local war = FreeGangs.Server.War.GetActive(killerMember.gang_name, victimMember.gang_name)
    if not war then return end
    
    FreeGangs.Server.War.RecordKill(war.id, killerMember.gang_name, killerCitizenId, victimCitizenId)
end)

-- ============================================================================
-- SYNC EVENTS
-- ============================================================================

---Player requesting full war sync
RegisterNetEvent('free-gangs:server:requestWarSync', function()
    local source = source
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    
    if not citizenId then
        return
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return
    end
    
    FreeGangs.Server.War.SyncToPlayer(source, member.gang_name)
end)

-- ============================================================================
-- MODULE RETURN
-- ============================================================================

FreeGangs.Utils.Log('War callbacks loaded')
