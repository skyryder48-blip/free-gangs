--[[
    FREE-GANGS: Heat Callbacks
    
    Server-side callbacks for heat-related operations.
    Uses ox_lib callback system for client-server communication.
]]

-- Ensure module namespace exists
FreeGangs.Server = FreeGangs.Server or {}

-- ============================================================================
-- HEAT DATA CALLBACKS
-- ============================================================================

---Get heat level between two gangs
lib.callback.register(FreeGangs.Callbacks.GET_HEAT_LEVEL, function(source, gangA, gangB)
    -- If no specific target, get caller's gang heat
    if not gangA then
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return nil
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member then
            return nil
        end
        
        gangA = member.gang_name
    end
    
    if gangB then
        -- Specific heat between two gangs
        return {
            gang_a = gangA,
            gang_b = gangB,
            heat_level = FreeGangs.Server.Heat.Get(gangA, gangB),
            stage = FreeGangs.Server.Heat.GetStage(gangA, gangB),
        }
    else
        -- All heat for one gang
        return FreeGangs.Server.Heat.GetGangHeat(gangA)
    end
end)

---Get heat stage info
lib.callback.register('free-gangs:callback:getHeatStageInfo', function(source, stage)
    if not stage then
        -- Return all stage info
        return FreeGangs.HeatStageThresholds
    end
    
    return FreeGangs.HeatStageThresholds[stage]
end)

---Get rivals for a gang (gangs with non-zero heat)
lib.callback.register('free-gangs:callback:getRivals', function(source, gangName)
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
    
    return FreeGangs.Server.Heat.GetRivals(gangName)
end)

---Get all heat data (admin only)
lib.callback.register('free-gangs:callback:getAllHeat', function(source)
    -- Check admin permission
    if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return nil
    end
    
    return FreeGangs.Server.Heat.GetAll()
end)

-- ============================================================================
-- HEAT MODIFICATION CALLBACKS
-- ============================================================================

---Add heat between gangs (admin or system use)
lib.callback.register('free-gangs:callback:addHeat', function(source, gangA, gangB, amount, reason)
    -- Verify source is admin or system
    if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        -- For non-admin, verify they're in one of the gangs
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return false, 'Player not found'
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member or (member.gang_name ~= gangA and member.gang_name ~= gangB) then
            return false, 'Not authorized'
        end
    end
    
    local newHeat, stageChange = FreeGangs.Server.Heat.Add(gangA, gangB, amount, reason)
    
    return true, {
        new_heat = newHeat,
        stage_changed = stageChange ~= nil,
        new_stage = stageChange,
    }
end)

---Set heat between gangs (admin only)
lib.callback.register('free-gangs:callback:setHeat', function(source, gangA, gangB, heat, reason)
    -- Admin only
    if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    local newHeat = FreeGangs.Server.Heat.Set(gangA, gangB, heat, reason or 'admin_callback')
    
    return true, newHeat
end)

---Reset heat between gangs (admin only)
lib.callback.register('free-gangs:callback:resetHeat', function(source, gangA, gangB)
    -- Admin only
    if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
        return false, 'Admin permission required'
    end
    
    FreeGangs.Server.Heat.Reset(gangA, gangB, source)
    
    return true
end)

-- ============================================================================
-- HEAT CHECK CALLBACKS
-- ============================================================================

---Check if gangs can declare war
lib.callback.register('free-gangs:callback:canDeclareWar', function(source, attackerGang, defenderGang)
    -- Verify source is in attacker gang
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenId then
        return false, 'Player not found'
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member or member.gang_name ~= attackerGang then
        return false, 'Not in this gang'
    end
    
    return FreeGangs.Server.Heat.CanDeclareWar(attackerGang, defenderGang)
end)

---Check if gangs are in rivalry (profit/protection effects apply)
lib.callback.register('free-gangs:callback:isRivalry', function(source, gangA, gangB)
    return FreeGangs.Server.Heat.IsRivalry(gangA, gangB)
end)

---Check if a specific heat effect applies
lib.callback.register('free-gangs:callback:hasHeatEffect', function(source, gangA, gangB, effect)
    return FreeGangs.Server.Heat.HasEffect(gangA, gangB, effect)
end)

---Get rivalry profit modifier for zone
lib.callback.register('free-gangs:callback:getRivalryProfitModifier', function(source, gangName, zoneName)
    if not gangName then
        local citizenId = FreeGangs.Bridge.GetCitizenId(source)
        if not citizenId then
            return 1.0
        end
        
        local member = FreeGangs.Server.DB.GetMember(citizenId)
        if not member then
            return 1.0
        end
        
        gangName = member.gang_name
    end
    
    return FreeGangs.Server.Heat.GetRivalryProfitModifier(gangName, zoneName)
end)

-- ============================================================================
-- EVENT HANDLERS FOR HEAT
-- ============================================================================

---Handle heat from player activities
RegisterNetEvent(FreeGangs.Events.Server.ADD_HEAT, function(targetGang, amount, reason)
    local source = source
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    
    if not citizenId then
        return
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return
    end
    
    -- Validate target gang exists
    if not FreeGangs.Server.Gangs[targetGang] then
        return
    end
    
    -- Validate amount is reasonable (anti-exploit)
    if type(amount) ~= 'number' or amount < 0 or amount > 50 then
        FreeGangs.Utils.Log(string.format('Suspicious heat request from %s: %d', citizenId, amount or 0))
        return
    end
    
    FreeGangs.Server.Heat.Add(member.gang_name, targetGang, amount, reason or 'player_action')
end)

-- ============================================================================
-- SYNC EVENTS
-- ============================================================================

---Player requesting full heat sync
RegisterNetEvent('free-gangs:server:requestHeatSync', function()
    local source = source
    local citizenId = FreeGangs.Bridge.GetCitizenId(source)
    
    if not citizenId then
        return
    end
    
    local member = FreeGangs.Server.DB.GetMember(citizenId)
    if not member then
        return
    end
    
    FreeGangs.Server.Heat.SyncToPlayer(source, member.gang_name)
end)

-- ============================================================================
-- MODULE RETURN
-- ============================================================================

FreeGangs.Utils.Log('Heat callbacks loaded')
