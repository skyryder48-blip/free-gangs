--[[
    FREE-GANGS: Core Gang Callbacks

    Registers callbacks for gang data, members, validation,
    and other core operations not covered by module-specific callback files.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}

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

    -- Derive boss/officer status from rank (rank 5 = boss, rank >= 2 = officer)
    local rank = membership.rank or 0
    local isBoss = rank == 5
    local isOfficer = rank >= 2

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
            rank = rank,
            rankName = membership.rank_name,
            isBoss = isBoss,
            isOfficer = isOfficer,
            permissions = membership.permissions,
            individual_rep = membership.personal_rep or 0,
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
-- HEAT DATA CALLBACK
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

-- ============================================================================
-- BRIBE DATA CALLBACKS
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
    return FreeGangs.Utils.GetTimestamp()
end)

---Get game time
lib.callback.register('free-gangs:callback:getGameTime', function(source)
    return FreeGangs.Bridge.GetGameTime()
end)

---Ping (connection check)
lib.callback.register('free-gangs:callback:ping', function(source)
    return true
end)

FreeGangs.Utils.Log('Core gang callbacks registered')
