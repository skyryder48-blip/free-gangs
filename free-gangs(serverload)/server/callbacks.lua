--[[
    FREE-GANGS: Server Callbacks Module
    
    Consolidated lib.callback registrations for all client requests.
    Provides data retrieval for gang info, members, territories, heat,
    wars, bribes, activities, and validation callbacks.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Callbacks = {}

-- ============================================================================
-- GANG DATA CALLBACKS
-- ============================================================================

---Get player's gang data
lib.callback.register(FreeGangs.Callbacks.GET_PLAYER_GANG, function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local gangData = FreeGangs.Server.Gangs[membership.gang_name]
    if not gangData then return nil end
    
    -- Include membership data
    return {
        name = gangData.name,
        label = gangData.label,
        archetype = gangData.archetype,
        color = gangData.color,
        master_rep = gangData.master_rep,
        master_level = gangData.master_level,
        treasury = gangData.treasury,
        war_chest = gangData.war_chest,
        membership = {
            citizenid = membership.citizenid,
            rank = membership.rank,
            rankName = membership.rank_name,
            isBoss = membership.is_boss,
            isOfficer = membership.is_officer,
            permissions = membership.permissions,
            individual_rep = membership.individual_rep,
            joined_at = membership.joined_at,
        },
    }
end)

---Get gang info by name
lib.callback.register(FreeGangs.Callbacks.GET_GANG_DATA, function(source, gangName)
    if not gangName then return nil end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return nil end
    
    -- Get member count
    local members = FreeGangs.Server.DB.GetGangMembers(gangName)
    local memberCount = members and #members or 0
    
    -- Get controlled zone count
    local controlledZones = 0
    for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
        local influence = territory.influence and territory.influence[gangName] or 0
        if influence >= FreeGangs.Config.Territory.MajorityThreshold then
            controlledZones = controlledZones + 1
        end
    end
    
    return {
        name = gangData.name,
        label = gangData.label,
        archetype = gangData.archetype,
        color = gangData.color,
        logo = gangData.logo,
        master_rep = gangData.master_rep,
        master_level = gangData.master_level,
        treasury = gangData.treasury,
        war_chest = gangData.war_chest,
        created_at = gangData.created_at,
        member_count = memberCount,
        controlled_zones = controlledZones,
        settings = gangData.settings,
    }
end)

---Get all gangs (public info only)
lib.callback.register(FreeGangs.Callbacks.GET_ALL_GANGS, function(source)
    local gangs = {}
    
    for gangName, gangData in pairs(FreeGangs.Server.Gangs or {}) do
        -- Get member count
        local members = FreeGangs.Server.DB.GetGangMembers(gangName)
        local memberCount = members and #members or 0
        
        -- Get territory count
        local territoryCount = 0
        for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
            local influence = territory.influence and territory.influence[gangName] or 0
            if influence >= FreeGangs.Config.Territory.MajorityThreshold then
                territoryCount = territoryCount + 1
            end
        end
        
        table.insert(gangs, {
            name = gangData.name,
            label = gangData.label,
            archetype = gangData.archetype,
            color = gangData.color,
            master_level = gangData.master_level,
            member_count = memberCount,
            territory_count = territoryCount,
        })
    end
    
    -- Sort by master level descending
    table.sort(gangs, function(a, b)
        return (a.master_level or 1) > (b.master_level or 1)
    end)
    
    return gangs
end)

---Get gang members
lib.callback.register(FreeGangs.Callbacks.GET_GANG_MEMBERS, function(source, gangName)
    if not gangName then return {} end
    
    -- Verify requester is in this gang (or admin)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    
    if not membership or membership.gang_name ~= gangName then
        -- Check if admin
        if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return {}
        end
    end
    
    local members = FreeGangs.Server.DB.GetGangMembers(gangName)
    if not members then return {} end
    
    -- Enrich with online status and player names
    local enrichedMembers = {}
    local onlinePlayers = FreeGangs.Bridge.GetPlayers()
    
    for _, member in ipairs(members) do
        -- Check if online
        local isOnline = false
        local playerName = member.name
        
        for playerSource, player in pairs(onlinePlayers) do
            if player.PlayerData.citizenid == member.citizenid then
                isOnline = true
                playerName = FreeGangs.Bridge.GetPlayerName(playerSource)
                break
            end
        end
        
        table.insert(enrichedMembers, {
            citizenid = member.citizenid,
            name = playerName or member.citizenid,
            rank = member.rank,
            rank_name = member.rank_name,
            is_boss = member.is_boss,
            is_officer = member.is_officer,
            individual_rep = member.individual_rep,
            joined_at = member.joined_at,
            is_online = isOnline,
            last_seen = member.last_seen,
        })
    end
    
    return enrichedMembers
end)

-- ============================================================================
-- TERRITORY CALLBACKS
-- ============================================================================

---Get all territories
lib.callback.register(FreeGangs.Callbacks.GET_TERRITORIES, function(source)
    local territories = {}
    
    for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
        territories[zoneName] = {
            name = zoneName,
            label = territory.label,
            zone_type = territory.zone_type,
            coords = territory.coords,
            radius = territory.radius,
            size = territory.size,
            influence = territory.influence or {},
            cooldown_until = territory.cooldown_until,
        }
    end
    
    return territories
end)

---Get specific territory info
lib.callback.register(FreeGangs.Callbacks.GET_TERRITORY_INFO, function(source, zoneName)
    if not zoneName then return nil end
    
    local territory = FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName]
    if not territory then return nil end
    
    return {
        name = zoneName,
        label = territory.label,
        zone_type = territory.zone_type,
        coords = territory.coords,
        radius = territory.radius,
        size = territory.size,
        influence = territory.influence or {},
        cooldown_until = territory.cooldown_until,
    }
end)

---Get zone control percentage
lib.callback.register(FreeGangs.Callbacks.GET_ZONE_CONTROL, function(source, zoneName, gangName)
    if not zoneName then return 0 end
    
    local territory = FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName]
    if not territory or not territory.influence then return 0 end
    
    if gangName then
        return territory.influence[gangName] or 0
    end
    
    return territory.influence
end)

-- ============================================================================
-- HEAT & WAR CALLBACKS
-- ============================================================================

---Get heat data for a gang
lib.callback.register('free-gangs:callback:getHeatData', function(source, gangName)
    if not gangName then return {} end
    
    -- Verify requester is in this gang
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    
    if not membership or membership.gang_name ~= gangName then
        return {}
    end
    
    local heatData = {}
    
    -- Get all heat relationships for this gang
    for key, heat in pairs(FreeGangs.Server.Heat or {}) do
        local gang1, gang2 = key:match('(.+):(.+)')
        if gang1 == gangName then
            heatData[gang2] = heat
        elseif gang2 == gangName then
            heatData[gang1] = heat
        end
    end
    
    return heatData
end)

---Get heat level between two gangs
lib.callback.register(FreeGangs.Callbacks.GET_HEAT_LEVEL, function(source, gang1, gang2)
    if not gang1 or not gang2 then return 0 end
    
    -- Heat is symmetric, order doesn't matter but we use consistent key
    local key = gang1 < gang2 and (gang1 .. ':' .. gang2) or (gang2 .. ':' .. gang1)
    return FreeGangs.Server.Heat and FreeGangs.Server.Heat[key] or 0
end)

---Get active wars for a gang
lib.callback.register(FreeGangs.Callbacks.GET_ACTIVE_WARS, function(source, gangName)
    if not gangName then return {} end
    
    local activeWars = {}
    
    for warId, war in pairs(FreeGangs.Server.ActiveWars or {}) do
        if war.attacker_gang == gangName or war.defender_gang == gangName then
            table.insert(activeWars, {
                id = warId,
                attacker_gang = war.attacker_gang,
                defender_gang = war.defender_gang,
                attacker_kills = war.attacker_kills or 0,
                defender_kills = war.defender_kills or 0,
                collateral_amount = war.collateral_amount,
                status = war.status,
                started_at = war.started_at,
                declared_at = war.declared_at,
            })
        end
    end
    
    return activeWars
end)

---Get war history for a gang
lib.callback.register(FreeGangs.Callbacks.GET_WAR_HISTORY, function(source, gangName)
    if not gangName then return {} end
    
    return FreeGangs.Server.DB.GetWarHistory(gangName, 10) or {}
end)

-- ============================================================================
-- BRIBE CALLBACKS
-- ============================================================================

---Get active bribes for a gang
lib.callback.register(FreeGangs.Callbacks.GET_ACTIVE_BRIBES, function(source, gangName)
    if not gangName then return {} end
    
    -- Verify requester is in this gang and has permission
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    
    if not membership or membership.gang_name ~= gangName then
        return {}
    end
    
    -- Only officers can view bribes
    if not membership.is_officer and not membership.is_boss then
        return {}
    end
    
    return FreeGangs.Server.Bribes and FreeGangs.Server.Bribes[gangName] or {}
end)

---Get specific bribe status
lib.callback.register(FreeGangs.Callbacks.GET_BRIBE_STATUS, function(source, gangName, contactType)
    if not gangName or not contactType then return nil end
    
    local gangBribes = FreeGangs.Server.Bribes and FreeGangs.Server.Bribes[gangName]
    if not gangBribes then return nil end
    
    return gangBribes[contactType]
end)

-- ============================================================================
-- ACTIVITY CALLBACKS
-- ============================================================================

---Check if player can perform an activity
lib.callback.register(FreeGangs.Callbacks.CAN_PERFORM_ACTIVITY, function(source, activityType, params)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false, 'Not in a gang' end
    
    -- Check cooldowns
    local cooldownKey = activityType .. '_' .. citizenid
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'On cooldown: ' .. FreeGangs.Utils.FormatDuration(remaining * 1000)
    end
    
    -- Activity-specific checks
    if activityType == 'drug_sale' then
        -- Check time restriction
        local hour = FreeGangs.Bridge.GetGameTime()
        local config = FreeGangs.Config.Activities.DrugSales
        if hour < config.AllowedStartHour and hour >= config.AllowedEndHour then
            return false, 'Corner sales only between 4 PM and 7 AM'
        end
        
        -- Check if player has drugs
        local hasDrugs = false
        for _, drug in ipairs(config.SellableDrugs) do
            if FreeGangs.Bridge.HasItem(source, drug, 1) then
                hasDrugs = true
                break
            end
        end
        if not hasDrugs then
            return false, 'No drugs to sell'
        end
    elseif activityType == 'mugging' then
        -- Check if player has weapon
        local config = FreeGangs.Config.Activities.Mugging
        local hasWeapon = false
        -- This would need actual weapon check implementation
        -- For now, assume true
        hasWeapon = true
        if not hasWeapon then
            return false, 'Requires weapon'
        end
    elseif activityType == 'graffiti' then
        -- Check if player has spray can
        local config = FreeGangs.Config.Activities.Graffiti
        if not FreeGangs.Bridge.HasItem(source, config.RequiredItem, 1) then
            return false, 'Requires spray paint'
        end
        
        -- Check spray limit
        local spraysThisCycle = FreeGangs.Server.DB.GetSprayCount(citizenid, config.CycleDurationHours)
        if spraysThisCycle >= config.MaxSpraysPerCycle then
            return false, 'Maximum sprays reached for this cycle'
        end
    elseif activityType == 'protection' then
        -- Check zone control
        local gangData = FreeGangs.Server.Gangs[membership.gang_name]
        -- Would need zone check implementation
    end
    
    return true, nil
end)

---Get protection businesses for a gang
lib.callback.register(FreeGangs.Callbacks.GET_PROTECTION_BUSINESSES, function(source, gangName)
    if not gangName then return {} end
    
    -- Get businesses in controlled zones
    local businesses = FreeGangs.Server.DB.GetProtectionBusinesses(gangName) or {}
    
    -- Add additional info
    for _, business in ipairs(businesses) do
        -- Calculate if collection is ready
        if business.last_collection then
            local cooldownSeconds = FreeGangs.Config.Activities.Protection.CollectionIntervalHours * 3600
            business.ready_at = business.last_collection + cooldownSeconds
            business.is_ready = os.time() >= business.ready_at
        else
            business.is_ready = true
        end
    end
    
    return businesses
end)

-- ============================================================================
-- GRAFFITI CALLBACKS
-- ============================================================================

---Get nearby graffiti
lib.callback.register(FreeGangs.Callbacks.GET_NEARBY_GRAFFITI, function(source, coords, radius)
    if not coords then return {} end
    radius = radius or FreeGangs.Config.Activities.Graffiti.RenderDistance
    
    local nearbyGraffiti = {}
    local allGraffiti = FreeGangs.Server.DB.GetGraffiti()
    
    for _, tag in ipairs(allGraffiti or {}) do
        local distance = #(vec3(coords.x, coords.y, coords.z) - vec3(tag.x, tag.y, tag.z))
        if distance <= radius then
            table.insert(nearbyGraffiti, {
                id = tag.id,
                gang_name = tag.gang_name,
                citizenid = tag.citizenid,
                x = tag.x,
                y = tag.y,
                z = tag.z,
                rotation = tag.rotation,
                zone_name = tag.zone_name,
                sprayed_at = tag.sprayed_at,
            })
        end
    end
    
    return nearbyGraffiti
end)

-- ============================================================================
-- VALIDATION CALLBACKS
-- ============================================================================

---Validate if player has permission
lib.callback.register(FreeGangs.Callbacks.VALIDATE_PERMISSION, function(source, permission)
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
end)

---Validate if player has minimum rank
lib.callback.register(FreeGangs.Callbacks.VALIDATE_RANK, function(source, minRank)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    return membership.rank >= minRank
end)

---Check if player can create a gang
lib.callback.register('free-gangs:callback:canCreateGang', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    -- Check if already in gang
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if membership then return false end
    
    -- Check cooldown
    local onCooldown = FreeGangs.Server.IsOnCooldown(source, 'gang_create')
    if onCooldown then return false end
    
    -- Check required items
    local config = FreeGangs.Config.General
    if config.GangCreationItems and #config.GangCreationItems > 0 then
        for _, required in pairs(config.GangCreationItems) do
            if required.item == 'money' then
                if FreeGangs.Bridge.GetMoney(source, 'cash') < required.amount then
                    return false
                end
            else
                if not FreeGangs.Bridge.HasItem(source, required.item, required.amount) then
                    return false
                end
            end
        end
    end
    
    return true
end)

-- ============================================================================
-- ARCHETYPE CALLBACKS
-- ============================================================================

---Get archetype tier access
lib.callback.register('free-gangs:callback:getTierAccess', function(source, gangName)
    if not gangName then return {} end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return {} end
    
    local level = gangData.master_level or 1
    
    return {
        tier1 = level >= 4,
        tier2 = level >= 6,
        tier3 = level >= 8,
        archetype = gangData.archetype,
    }
end)

---Get archetype passive bonuses
lib.callback.register('free-gangs:callback:getPassiveBonuses', function(source, gangName)
    if not gangName then return {} end
    
    local gangData = FreeGangs.Server.Gangs[gangName]
    if not gangData then return {} end
    
    local bonuses = FreeGangs.ArchetypePassiveBonuses[gangData.archetype]
    return bonuses or {}
end)

-- ============================================================================
-- LEADERBOARD CALLBACKS
-- ============================================================================

---Get gang leaderboard
lib.callback.register('free-gangs:callback:getLeaderboard', function(source, category)
    category = category or 'reputation'
    
    local leaderboard = {}
    
    for gangName, gangData in pairs(FreeGangs.Server.Gangs or {}) do
        local entry = {
            name = gangName,
            label = gangData.label,
            color = gangData.color,
            archetype = gangData.archetype,
        }
        
        if category == 'reputation' then
            entry.value = gangData.master_rep or 0
            entry.level = gangData.master_level or 1
        elseif category == 'territories' then
            local count = 0
            for zoneName, territory in pairs(FreeGangs.Server.Territories or {}) do
                local influence = territory.influence and territory.influence[gangName] or 0
                if influence >= FreeGangs.Config.Territory.MajorityThreshold then
                    count = count + 1
                end
            end
            entry.value = count
        elseif category == 'wars' then
            local stats = FreeGangs.Server.DB.GetWarStats(gangName)
            entry.value = stats and stats.wins or 0
            entry.losses = stats and stats.losses or 0
        end
        
        table.insert(leaderboard, entry)
    end
    
    -- Sort by value descending
    table.sort(leaderboard, function(a, b)
        return (a.value or 0) > (b.value or 0)
    end)
    
    return leaderboard
end)

-- ============================================================================
-- UTILITY CALLBACKS
-- ============================================================================

---Get server time (for sync)
lib.callback.register('free-gangs:callback:getServerTime', function(source)
    return os.time()
end)

---Get game time
lib.callback.register('free-gangs:callback:getGameTime', function(source)
    return FreeGangs.Bridge.GetGameTime()
end)

---Ping (connection check)
lib.callback.register('free-gangs:callback:ping', function(source)
    return true
end)

FreeGangs.Utils.Log('Server callbacks registered')

return FreeGangs.Server.Callbacks
