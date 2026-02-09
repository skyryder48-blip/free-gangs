--[[
    FREE-GANGS: UI Menus Module
    
    Comprehensive ox_lib context menus for gang management.
    Provides the main gang menu (F6), dashboard, member management,
    territory overview, war status, bribes, treasury, and settings.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.UI = FreeGangs.Client.UI or {}

-- ============================================================================
-- MAIN GANG MENU
-- ============================================================================

---Open the main gang operations menu
function FreeGangs.Client.UI.OpenMainMenu()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then
        FreeGangs.Client.UI.ShowNoGangMenu()
        return
    end
    
    local membership = gangData.membership
    local isBoss = membership and membership.isBoss
    local isOfficer = membership and (membership.isOfficer or membership.isBoss)
    
    -- Get archetype info for icon
    local archetypeInfo = FreeGangs.ArchetypeLabels[gangData.archetype] or {}
    local archetypeIcon = FreeGangs.Client.UI.GetArchetypeIcon(gangData.archetype)
    
    local options = {
        {
            title = FreeGangs.L('menu', 'dashboard'),
            description = 'View gang overview and statistics',
            icon = 'chart-line',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenDashboard()
            end,
        },
        {
            title = FreeGangs.L('menu', 'members'),
            description = string.format('%d members online', FreeGangs.Client.UI.GetOnlineMemberCount()),
            icon = 'users',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenMemberRoster()
            end,
        },
        {
            title = FreeGangs.L('menu', 'territory'),
            description = 'View territory control and influence',
            icon = 'map-marked-alt',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenTerritoryMap()
            end,
        },
        -- Prison Operations
        {
            title = 'Prison Operations',
            icon = 'building-shield',
            iconColor = FreeGangs.Config.UI and FreeGangs.Config.UI.Theme and FreeGangs.Config.UI.Theme.AccentColor or '#e74c3c',
            description = 'Manage prison control and operations',
            onSelect = function()
                if FreeGangs.Client.Prison and FreeGangs.Client.Prison.OpenMenu then
                    FreeGangs.Client.Prison.OpenMenu()
                else
                    lib.notify({ title = 'Error', description = 'Prison module not available', type = 'error' })
                end
            end,
        },
        {
            title = FreeGangs.L('menu', 'reputation'),
            description = string.format('Level %d - %s', gangData.master_level or 1, 
                FreeGangs.ReputationLevels[gangData.master_level or 1].name),
            icon = 'star',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenReputationStats()
            end,
        },
        {
            title = FreeGangs.L('menu', 'wars'),
            description = 'View rivalries and active wars',
            icon = 'crosshairs',
            iconColor = FreeGangs.Config.UI.Theme.PrimaryColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenWarStatus()
            end,
        },
    }
    
    -- Officer+ options
    if isOfficer then
        table.insert(options, {
            title = FreeGangs.L('menu', 'bribes'),
            description = 'Manage corrupt contacts',
            icon = 'handshake',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.OpenBribesMenu()
            end,
        })
    end
    
    table.insert(options, {
        title = FreeGangs.L('menu', 'activities'),
        description = 'Criminal operations',
        icon = 'mask',
        iconColor = FreeGangs.Config.UI.Theme.PrimaryColor,
        onSelect = function()
            FreeGangs.Client.UI.OpenActivitiesMenu()
        end,
    })
    
    table.insert(options, {
        title = FreeGangs.L('menu', 'treasury'),
        description = string.format('Balance: %s', FreeGangs.Utils.FormatMoney(gangData.treasury or 0)),
        icon = 'coins',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        onSelect = function()
            FreeGangs.Client.UI.OpenTreasury()
        end,
    })
    
    table.insert(options, {
        title = FreeGangs.L('menu', 'stash'),
        description = 'Access gang storage',
        icon = 'box',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        onSelect = function()
            TriggerServerEvent(FreeGangs.Events.Server.OPEN_STASH)
        end,
    })
    
    -- Boss-only settings
    if isBoss then
        table.insert(options, {
            title = FreeGangs.L('menu', 'settings'),
            description = 'Configure gang settings',
            icon = 'cog',
            iconColor = '#888888',
            onSelect = function()
                FreeGangs.Client.UI.OpenSettings()
            end,
        })
    end
    
    -- Leave gang option (non-boss only)
    if not isBoss then
        table.insert(options, {
            title = 'Leave Gang',
            description = 'Leave your current gang',
            icon = 'door-open',
            iconColor = '#FF4444',
            onSelect = function()
                FreeGangs.Client.UI.ConfirmLeaveGang()
            end,
        })
    end
    
    lib.registerContext({
        id = 'freegangs_main',
        title = gangData.label or 'Gang Operations',
        options = options,
    })
    
    lib.showContext('freegangs_main')
end

---Show menu for players not in a gang
function FreeGangs.Client.UI.ShowNoGangMenu()
    local options = {
        {
            title = 'Create a Gang',
            description = 'Establish your own criminal organization',
            icon = 'plus-circle',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.ShowGangCreation()
            end,
        },
        {
            title = 'View Gangs',
            description = 'See active gangs in the city',
            icon = 'eye',
            iconColor = '#888888',
            onSelect = function()
                FreeGangs.Client.UI.ShowGangList()
            end,
        },
    }
    
    lib.registerContext({
        id = 'freegangs_no_gang',
        title = 'Gang Operations',
        options = options,
    })
    
    lib.showContext('freegangs_no_gang')
end

-- ============================================================================
-- DASHBOARD MENU
-- ============================================================================

---Open the gang dashboard with detailed stats
function FreeGangs.Client.UI.OpenDashboard()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- Fetch fresh data from server
    local dashboardData = lib.callback.await(FreeGangs.Callbacks.GET_GANG_DATA, false, gangData.name)
    if not dashboardData then
        FreeGangs.Bridge.Notify('Failed to load dashboard data', 'error')
        return
    end
    
    local levelInfo = FreeGangs.ReputationLevels[dashboardData.master_level or 1]
    local nextLevel = FreeGangs.ReputationLevels[(dashboardData.master_level or 1) + 1]
    local progress = 0
    
    if nextLevel then
        local currentRep = dashboardData.master_rep or 0
        local neededRep = nextLevel.repRequired - levelInfo.repRequired
        local earnedRep = currentRep - levelInfo.repRequired
        progress = math.floor((earnedRep / neededRep) * 100)
    end
    
    local archetypeInfo = FreeGangs.ArchetypeLabels[dashboardData.archetype] or { label = 'Unknown' }
    
    local options = {
        {
            title = 'Gang Information',
            icon = 'info-circle',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Name', value = dashboardData.label },
                { label = 'Type', value = archetypeInfo.label },
                { label = 'Founded', value = dashboardData.created_at and FreeGangs.Utils.FormatTime(dashboardData.created_at, '%Y-%m-%d') or 'Unknown' },
                { label = 'Color', value = dashboardData.color or '#FFFFFF' },
            },
        },
        {
            title = 'Reputation',
            icon = 'star',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            progress = progress,
            colorScheme = 'yellow',
            metadata = {
                { label = 'Level', value = string.format('%d - %s', dashboardData.master_level or 1, levelInfo.name) },
                { label = 'Total Rep', value = FreeGangs.Utils.FormatNumber(dashboardData.master_rep or 0) },
                { label = 'Progress', value = nextLevel and string.format('%d%%', progress) or 'Max Level' },
            },
        },
        {
            title = 'Membership',
            icon = 'users',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Total Members', value = tostring(dashboardData.member_count or 0) },
                { label = 'Online Now', value = tostring(FreeGangs.Client.UI.GetOnlineMemberCount()) },
                { label = 'Your Rank', value = gangData.membership and gangData.membership.rankName or 'Member' },
            },
        },
        {
            title = 'Finances',
            icon = 'coins',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Treasury', value = FreeGangs.Utils.FormatMoney(dashboardData.treasury or 0) },
                { label = 'War Chest', value = FreeGangs.Utils.FormatMoney(dashboardData.war_chest or 0) },
            },
        },
        {
            title = 'Territory',
            icon = 'map',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Controlled Zones', value = tostring(dashboardData.controlled_zones or 0) },
                { label = 'Max Territories', value = tostring(levelInfo.maxTerritories == -1 and 'Unlimited' or levelInfo.maxTerritories) },
            },
        },
    }

    -- Prison control info
    local prisonControl = lib.callback.await('free-gangs:callback:getPrisonControl', false) or 0
    if prisonControl > 0 then
        table.insert(options, {
            title = 'Prison Control',
            icon = 'building-shield',
            iconColor = prisonControl >= 51 and '#27ae60' or '#e67e22',
            progress = prisonControl,
            colorScheme = prisonControl >= 51 and 'green' or 'orange',
            metadata = {
                { label = 'Control', value = math.floor(prisonControl) .. '%' },
                { label = 'Status', value = prisonControl >= 51 and 'Controlled' or 'Contested' },
            },
        })
    end

    -- Add unlocks info
    if levelInfo.unlocks and #levelInfo.unlocks > 0 then
        table.insert(options, {
            title = 'Current Unlocks',
            icon = 'unlock',
            iconColor = '#00FF00',
            description = table.concat(levelInfo.unlocks, ', '),
        })
    end
    
    lib.registerContext({
        id = 'freegangs_dashboard',
        title = 'Dashboard - ' .. (dashboardData.label or 'Gang'),
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_dashboard')
end

-- ============================================================================
-- MEMBER ROSTER MENU
-- ============================================================================

---Open the member roster with management options
function FreeGangs.Client.UI.OpenMemberRoster()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local membership = gangData.membership
    local canManage = membership and (membership.isOfficer or membership.isBoss)
    
    -- Fetch members from server
    local members = lib.callback.await(FreeGangs.Callbacks.GET_GANG_MEMBERS, false, gangData.name)
    if not members then
        FreeGangs.Bridge.Notify('Failed to load member list', 'error')
        return
    end
    
    local options = {}
    
    -- Add invite option if permitted
    if canManage then
        table.insert(options, {
            title = FreeGangs.L('menu', 'invite_member'),
            description = 'Invite a player to join',
            icon = 'user-plus',
            iconColor = '#00FF00',
            onSelect = function()
                FreeGangs.Client.UI.ShowInviteInput()
            end,
        })
    end
    
    -- Sort members by rank (highest first)
    table.sort(members, function(a, b)
        return (a.rank or 0) > (b.rank or 0)
    end)
    
    -- List members
    for _, member in ipairs(members) do
        local isOnline = member.is_online
        local statusIcon = isOnline and '🟢' or '🔴'
        local rankInfo = FreeGangs.DefaultRanks[gangData.archetype] and 
                        FreeGangs.DefaultRanks[gangData.archetype][member.rank] or { name = 'Member' }
        
        local memberOptions = {
            title = string.format('%s %s', statusIcon, member.name or member.citizenid),
            description = string.format('%s (Rank %d)', member.rank_name or rankInfo.name, member.rank or 0),
            icon = 'user',
            iconColor = isOnline and '#00FF00' or '#888888',
            metadata = {
                { label = 'Joined', value = member.joined_at and FreeGangs.Utils.FormatTime(member.joined_at, '%Y-%m-%d') or 'Unknown' },
                { label = 'Individual Rep', value = FreeGangs.Utils.FormatNumber(member.individual_rep or 0) },
            },
        }
        
        -- Add management options if permitted and not self
        if canManage and member.citizenid ~= FreeGangs.Bridge.GetCitizenId() then
            local canPromote = membership.rank > member.rank
            local canKick = membership.isBoss or (membership.rank > member.rank)
            
            if canPromote or canKick then
                memberOptions.onSelect = function()
                    FreeGangs.Client.UI.OpenMemberManagement(member)
                end
            end
        end
        
        table.insert(options, memberOptions)
    end
    
    lib.registerContext({
        id = 'freegangs_roster',
        title = string.format('Member Roster (%d)', #members),
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_roster')
end

---Open management options for a specific member
---@param member table
function FreeGangs.Client.UI.OpenMemberManagement(member)
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local membership = gangData.membership
    local options = {}
    
    local maxRank = membership.rank - 1 -- Can promote up to one below own rank
    local canPromote = member.rank < maxRank
    local canDemote = member.rank > 0
    
    if canPromote then
        table.insert(options, {
            title = FreeGangs.L('menu', 'promote_member'),
            description = 'Increase their rank',
            icon = 'arrow-up',
            iconColor = '#00FF00',
            onSelect = function()
                FreeGangs.Client.UI.ConfirmRankChange(member, 'promote')
            end,
        })
    end
    
    if canDemote then
        table.insert(options, {
            title = FreeGangs.L('menu', 'demote_member'),
            description = 'Decrease their rank',
            icon = 'arrow-down',
            iconColor = '#FFAA00',
            onSelect = function()
                FreeGangs.Client.UI.ConfirmRankChange(member, 'demote')
            end,
        })
    end
    
    table.insert(options, {
        title = FreeGangs.L('menu', 'kick_member'),
        description = 'Remove from gang',
        icon = 'user-times',
        iconColor = '#FF0000',
        onSelect = function()
            FreeGangs.Client.UI.ConfirmKickMember(member)
        end,
    })
    
    lib.registerContext({
        id = 'freegangs_member_manage',
        title = 'Manage: ' .. (member.name or member.citizenid),
        menu = 'freegangs_roster',
        options = options,
    })
    
    lib.showContext('freegangs_member_manage')
end

-- ============================================================================
-- TERRITORY MAP MENU
-- ============================================================================

---Open the territory map overview
function FreeGangs.Client.UI.OpenTerritoryMap()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- Fetch territories from server
    local territories = lib.callback.await(FreeGangs.Callbacks.GET_TERRITORIES, false)
    if not territories then
        FreeGangs.Bridge.Notify('Failed to load territory data', 'error')
        return
    end
    
    local options = {}
    local ownedCount = 0
    local contestedCount = 0
    
    for zoneName, territory in pairs(territories) do
        local ourInfluence = territory.influence and territory.influence[gangData.name] or 0
        local owner = FreeGangs.Client.GetZoneOwner(territory)
        local isOwned = owner == gangData.name
        local isContested = ourInfluence > 10 and not isOwned
        
        if isOwned then ownedCount = ownedCount + 1 end
        if isContested then contestedCount = contestedCount + 1 end
        
        local zoneTypeInfo = FreeGangs.ZoneTypeInfo[territory.zoneType] or { label = 'Unknown', icon = 'map-marker' }
        local statusColor = isOwned and '#00FF00' or (isContested and '#FFAA00' or '#888888')
        
        local metadata = {
            { label = 'Your Influence', value = string.format('%d%%', ourInfluence) },
            { label = 'Zone Type', value = zoneTypeInfo.label },
        }
        
        if owner then
            table.insert(metadata, { label = 'Controlled By', value = owner })
        end
        
        -- Get control tier benefits
        local tier = FreeGangs.Client.UI.GetInfluenceTier(ourInfluence)
        if tier.benefits then
            table.insert(metadata, { label = 'Benefits', value = tier.benefits })
        end
        
        table.insert(options, {
            title = territory.label or zoneName,
            description = isOwned and 'Controlled' or (isContested and 'Contested' or 'Not controlled'),
            icon = zoneTypeInfo.icon,
            iconColor = statusColor,
            progress = ourInfluence,
            colorScheme = isOwned and 'green' or (isContested and 'yellow' or 'gray'),
            metadata = metadata,
            onSelect = function()
                FreeGangs.Client.UI.ShowTerritoryDetails(zoneName, territory)
            end,
        })
    end
    
    -- Sort: owned first, then contested, then by name
    table.sort(options, function(a, b)
        local aOwned = a.description == 'Controlled' and 1 or 0
        local bOwned = b.description == 'Controlled' and 1 or 0
        if aOwned ~= bOwned then return aOwned > bOwned end
        return a.title < b.title
    end)
    
    -- Add summary at top
    table.insert(options, 1, {
        title = 'Territory Summary',
        icon = 'chart-pie',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        metadata = {
            { label = 'Controlled', value = tostring(ownedCount) },
            { label = 'Contested', value = tostring(contestedCount) },
            { label = 'Total Zones', value = tostring(FreeGangs.Utils.TableLength(territories)) },
        },
    })
    
    lib.registerContext({
        id = 'freegangs_territory',
        title = 'Territory Map',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_territory')
end

---Show detailed territory information
---@param zoneName string
---@param territory table
function FreeGangs.Client.UI.ShowTerritoryDetails(zoneName, territory)
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local ourInfluence = territory.influence and territory.influence[gangData.name] or 0
    local options = {}
    
    -- Influence breakdown
    if territory.influence then
        local influenceList = {}
        for gang, influence in pairs(territory.influence) do
            table.insert(influenceList, { gang = gang, influence = influence })
        end
        table.sort(influenceList, function(a, b) return a.influence > b.influence end)
        
        for i, data in ipairs(influenceList) do
            if i <= 5 then -- Show top 5
                local isUs = data.gang == gangData.name
                table.insert(options, {
                    title = data.gang,
                    description = string.format('%d%% influence', data.influence),
                    icon = isUs and 'flag' or 'users',
                    iconColor = isUs and FreeGangs.Config.UI.Theme.AccentColor or '#888888',
                    progress = data.influence,
                    colorScheme = isUs and 'green' or 'gray',
                })
            end
        end
    end
    
    -- Zone benefits based on control
    local tier = FreeGangs.Client.UI.GetInfluenceTier(ourInfluence)
    table.insert(options, {
        title = 'Current Benefits',
        icon = 'gift',
        iconColor = tier.color,
        description = tier.benefits or 'No benefits at current influence',
    })
    
    -- Cooldown status
    if territory.cooldownUntil and territory.cooldownUntil > FreeGangs.Utils.GetTimestamp() then
        local remaining = territory.cooldownUntil - FreeGangs.Utils.GetTimestamp()
        table.insert(options, {
            title = 'Capture Cooldown',
            icon = 'clock',
            iconColor = '#FF4444',
            description = FreeGangs.Utils.FormatDuration(remaining * 1000),
        })
    end
    
    lib.registerContext({
        id = 'freegangs_territory_detail',
        title = territory.label or zoneName,
        menu = 'freegangs_territory',
        options = options,
    })
    
    lib.showContext('freegangs_territory_detail')
end

-- ============================================================================
-- REPUTATION STATS MENU
-- ============================================================================

---Open reputation statistics view
function FreeGangs.Client.UI.OpenReputationStats()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local options = {}
    local currentLevel = gangData.master_level or 1
    local currentRep = gangData.master_rep or 0
    
    -- Current status
    local levelInfo = FreeGangs.ReputationLevels[currentLevel]
    local nextLevel = FreeGangs.ReputationLevels[currentLevel + 1]
    
    table.insert(options, {
        title = string.format('Level %d: %s', currentLevel, levelInfo.name),
        icon = 'crown',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        description = string.format('%s total reputation', FreeGangs.Utils.FormatNumber(currentRep)),
    })
    
    if nextLevel then
        local neededRep = nextLevel.repRequired - currentRep
        table.insert(options, {
            title = 'Progress to Next Level',
            icon = 'arrow-up',
            iconColor = '#00FF00',
            progress = math.floor(((currentRep - levelInfo.repRequired) / (nextLevel.repRequired - levelInfo.repRequired)) * 100),
            colorScheme = 'green',
            description = string.format('%s rep needed for Level %d', FreeGangs.Utils.FormatNumber(neededRep), currentLevel + 1),
        })
    end
    
    -- Unlocks overview
    table.insert(options, {
        title = 'Current Unlocks',
        icon = 'unlock',
        iconColor = '#00FF00',
        description = levelInfo.unlocks and table.concat(levelInfo.unlocks, ', ') or 'Basic features',
    })
    
    if nextLevel and nextLevel.unlocks then
        table.insert(options, {
            title = 'Next Level Unlocks',
            icon = 'lock',
            iconColor = '#888888',
            description = table.concat(nextLevel.unlocks, ', '),
        })
    end
    
    -- Level requirements overview
    table.insert(options, {
        title = 'All Level Requirements',
        icon = 'list',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        onSelect = function()
            FreeGangs.Client.UI.ShowAllLevels()
        end,
    })
    
    lib.registerContext({
        id = 'freegangs_reputation',
        title = 'Reputation Stats',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_reputation')
end

---Show all reputation levels
function FreeGangs.Client.UI.ShowAllLevels()
    local gangData = FreeGangs.Client.PlayerGang
    local currentLevel = gangData and gangData.master_level or 1
    
    local options = {}
    
    for level = 1, 10 do
        local levelInfo = FreeGangs.ReputationLevels[level]
        local isUnlocked = level <= currentLevel
        local isCurrent = level == currentLevel
        
        table.insert(options, {
            title = string.format('Level %d: %s', level, levelInfo.name),
            description = string.format('Requires %s rep | Max %s territories',
                FreeGangs.Utils.FormatNumber(levelInfo.repRequired),
                levelInfo.maxTerritories == -1 and 'unlimited' or tostring(levelInfo.maxTerritories)),
            icon = isCurrent and 'star' or (isUnlocked and 'check' or 'lock'),
            iconColor = isCurrent and FreeGangs.Config.UI.Theme.AccentColor or (isUnlocked and '#00FF00' or '#888888'),
        })
    end
    
    lib.registerContext({
        id = 'freegangs_all_levels',
        title = 'Reputation Levels',
        menu = 'freegangs_reputation',
        options = options,
    })
    
    lib.showContext('freegangs_all_levels')
end

-- ============================================================================
-- WAR STATUS MENU
-- ============================================================================

---Open war and rivalry status
function FreeGangs.Client.UI.OpenWarStatus()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- Fetch heat and war data
    local heatData = lib.callback.await('free-gangs:callback:getHeatData', false, gangData.name)
    local activeWars = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_WARS, false, gangData.name)
    
    local options = {}
    
    -- Active wars section
    if activeWars and #activeWars > 0 then
        for _, war in ipairs(activeWars) do
            local enemyGang = war.attacker_gang == gangData.name and war.defender_gang or war.attacker_gang
            local isAttacker = war.attacker_gang == gangData.name
            
            table.insert(options, {
                title = string.format('⚔️ WAR: %s', enemyGang),
                description = isAttacker and 'You declared war' or 'War declared on you',
                icon = 'crosshairs',
                iconColor = '#FF0000',
                metadata = {
                    { label = 'Our Kills', value = tostring(isAttacker and war.attacker_kills or war.defender_kills) },
                    { label = 'Their Kills', value = tostring(isAttacker and war.defender_kills or war.attacker_kills) },
                    { label = 'Collateral', value = FreeGangs.Utils.FormatMoney(war.collateral_amount) },
                    { label = 'Started', value = war.started_at and FreeGangs.Utils.FormatTime(war.started_at, '%m/%d %H:%M') or 'Pending' },
                },
                onSelect = function()
                    FreeGangs.Client.UI.ShowWarDetails(war)
                end,
            })
        end
    else
        table.insert(options, {
            title = 'No Active Wars',
            icon = 'peace',
            iconColor = '#00FF00',
            description = 'Your gang is at peace',
        })
    end
    
    -- Heat with other gangs
    if heatData then
        table.insert(options, {
            title = '─── Rivalries ───',
            icon = 'thermometer-half',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        })
        
        for otherGang, heat in pairs(heatData) do
            local stage = FreeGangs.Client.UI.GetHeatStage(heat)
            local stageInfo = FreeGangs.HeatStageThresholds[stage]
            
            table.insert(options, {
                title = otherGang,
                description = string.format('%s (%d heat)', stageInfo.label, heat),
                icon = 'fire',
                iconColor = stageInfo.color,
                progress = heat,
                colorScheme = heat >= 75 and 'red' or (heat >= 50 and 'orange' or (heat >= 30 and 'yellow' or 'gray')),
                onSelect = function()
                    FreeGangs.Client.UI.ShowRivalryDetails(otherGang, heat)
                end,
            })
        end
    end
    
    -- Declare war option if eligible
    local membership = gangData.membership
    if membership and membership.isBoss then
        table.insert(options, {
            title = 'Declare War',
            description = 'Requires 90+ heat with target gang',
            icon = 'skull-crossbones',
            iconColor = '#FF0000',
            onSelect = function()
                FreeGangs.Client.UI.ShowWarDeclarationTargets(heatData)
            end,
        })
    end
    
    lib.registerContext({
        id = 'freegangs_wars',
        title = 'Wars & Rivalries',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_wars')
end

---Show detailed war information
---@param war table
function FreeGangs.Client.UI.ShowWarDetails(war)
    local gangData = FreeGangs.Client.PlayerGang
    local isAttacker = war.attacker_gang == gangData.name
    local enemyGang = isAttacker and war.defender_gang or war.attacker_gang
    local membership = gangData.membership
    
    local options = {
        {
            title = 'War Statistics',
            icon = 'chart-bar',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Your Gang Kills', value = tostring(isAttacker and war.attacker_kills or war.defender_kills) },
                { label = 'Enemy Kills', value = tostring(isAttacker and war.defender_kills or war.attacker_kills) },
                { label = 'Collateral at Stake', value = FreeGangs.Utils.FormatMoney(war.collateral_amount * 2) },
            },
        },
        {
            title = 'Duration',
            icon = 'clock',
            iconColor = '#888888',
            description = war.started_at and FreeGangs.Utils.FormatDuration((FreeGangs.Utils.GetTimestamp() - war.started_at) * 1000) or 'Not started',
        },
    }
    
    -- Boss options
    if membership and membership.isBoss then
        table.insert(options, {
            title = 'Surrender',
            description = 'End the war in defeat (lose collateral)',
            icon = 'flag',
            iconColor = '#FF4444',
            onSelect = function()
                FreeGangs.Client.UI.ConfirmSurrender(war)
            end,
        })
        
        table.insert(options, {
            title = 'Request Peace',
            description = 'Propose mutual peace (collateral returned)',
            icon = 'handshake',
            iconColor = '#00FF00',
            onSelect = function()
                TriggerServerEvent('free-gangs:server:requestPeace', war.id)
            end,
        })
    end
    
    lib.registerContext({
        id = 'freegangs_war_detail',
        title = 'War with ' .. enemyGang,
        menu = 'freegangs_wars',
        options = options,
    })
    
    lib.showContext('freegangs_war_detail')
end

-- ============================================================================
-- BRIBES MENU
-- ============================================================================

---Open bribery contacts menu
function FreeGangs.Client.UI.OpenBribesMenu()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- Fetch active bribes
    local activeBribes = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_BRIBES, false, gangData.name)
    
    local options = {}
    
    -- Show established contacts
    if activeBribes and FreeGangs.Utils.TableLength(activeBribes) > 0 then
        table.insert(options, {
            title = '─── Active Contacts ───',
            icon = 'address-book',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        })
        
        for contactType, bribe in pairs(activeBribes) do
            local contactInfo = FreeGangs.BribeContactInfo[contactType]
            if contactInfo then
                local dueDate = bribe.next_payment_due
                local isDue = dueDate and dueDate <= FreeGangs.Utils.GetTimestamp() + 86400 -- Due within 24h
                
                table.insert(options, {
                    title = contactInfo.label,
                    description = isDue and '⚠️ Payment due soon!' or 'Active',
                    icon = contactInfo.icon,
                    iconColor = isDue and '#FF4444' or '#00FF00',
                    metadata = {
                        { label = 'Weekly Cost', value = FreeGangs.Utils.FormatMoney(contactInfo.weeklyCost) },
                        { label = 'Status', value = bribe.is_paused and 'Paused' or 'Active' },
                    },
                    onSelect = function()
                        FreeGangs.Client.UI.ShowBribeDetails(contactType, bribe)
                    end,
                })
            end
        end
    else
        table.insert(options, {
            title = 'No Active Contacts',
            icon = 'user-slash',
            iconColor = '#888888',
            description = 'Find and establish contacts in the city',
        })
    end
    
    -- Show available contacts
    table.insert(options, {
        title = '─── Available Contacts ───',
        icon = 'search',
        iconColor = FreeGangs.Config.UI.Theme.AccentColor,
    })
    
    local masterLevel = gangData.master_level or 1
    
    for contactType, info in pairs(FreeGangs.BribeContactInfo) do
        if not (activeBribes and activeBribes[contactType]) then
            local canUnlock = masterLevel >= info.minLevel
            
            table.insert(options, {
                title = info.label,
                description = canUnlock and 'Available to establish' or string.format('Requires Level %d', info.minLevel),
                icon = info.icon,
                iconColor = canUnlock and '#FFAA00' or '#444444',
                disabled = not canUnlock,
                metadata = {
                    { label = 'Weekly Cost', value = FreeGangs.Utils.FormatMoney(info.weeklyCost) },
                    { label = 'Min Level', value = tostring(info.minLevel) },
                },
            })
        end
    end
    
    lib.registerContext({
        id = 'freegangs_bribes',
        title = 'Corrupt Contacts',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_bribes')
end

---Show bribe contact details and abilities
---@param contactType string
---@param bribe table
function FreeGangs.Client.UI.ShowBribeDetails(contactType, bribe)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return end
    
    local options = {
        {
            title = 'Contact Status',
            icon = 'info-circle',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Status', value = bribe.is_paused and 'Paused' or 'Active' },
                { label = 'Established', value = bribe.established_at and FreeGangs.Utils.FormatTime(bribe.established_at, '%Y-%m-%d') or 'Unknown' },
                { label = 'Missed Payments', value = tostring(bribe.missed_payments or 0) },
            },
        },
    }
    
    -- Payment option
    if bribe.next_payment_due then
        local remaining = bribe.next_payment_due - FreeGangs.Utils.GetTimestamp()
        table.insert(options, {
            title = 'Make Payment',
            description = remaining > 0 and 
                string.format('Due in %s', FreeGangs.Utils.FormatDuration(remaining * 1000)) or
                'Payment overdue!',
            icon = 'money-bill',
            iconColor = remaining <= 86400 and '#FF4444' or '#00FF00',
            onSelect = function()
                FreeGangs.Client.UI.ShowBribePaymentConfirm(contactType, contactInfo.weeklyCost)
            end,
        })
    end
    
    -- Abilities
    if contactInfo.abilities then
        table.insert(options, {
            title = '─── Abilities ───',
            icon = 'magic',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        })
        
        for _, ability in ipairs(contactInfo.abilities) do
            table.insert(options, {
                title = ability.name,
                description = ability.description,
                icon = ability.icon,
                iconColor = bribe.is_paused and '#888888' or FreeGangs.Config.UI.Theme.AccentColor,
                disabled = bribe.is_paused,
                onSelect = function()
                    TriggerServerEvent(FreeGangs.Events.Server.USE_BRIBE, contactType, ability.id)
                end,
            })
        end
    end
    
    -- Terminate option
    table.insert(options, {
        title = 'Terminate Contact',
        description = 'End the relationship',
        icon = 'user-times',
        iconColor = '#FF0000',
        onSelect = function()
            FreeGangs.Client.UI.ConfirmTerminateBribe(contactType)
        end,
    })
    
    lib.registerContext({
        id = 'freegangs_bribe_detail',
        title = contactInfo.label,
        menu = 'freegangs_bribes',
        options = options,
    })
    
    lib.showContext('freegangs_bribe_detail')
end

-- ============================================================================
-- ACTIVITIES MENU
-- ============================================================================

---Open criminal activities menu
function FreeGangs.Client.UI.OpenActivitiesMenu()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local archetypeInfo = FreeGangs.ArchetypeLabels[gangData.archetype] or {}
    local tierActivities = FreeGangs.ArchetypeTierActivities[gangData.archetype] or {}
    local masterLevel = gangData.master_level or 1
    
    local options = {
        {
            title = '─── Basic Activities ───',
            icon = 'tasks',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        },
        {
            title = 'Corner Drug Sales',
            description = 'Sell drugs to NPCs (4 PM - 7 AM)',
            icon = 'cannabis',
            iconColor = '#00FF00',
            onSelect = function()
                FreeGangs.Bridge.Notify('Approach an NPC to make a sale', 'inform')
            end,
        },
        {
            title = 'Spray Graffiti',
            description = '+10 zone loyalty per tag',
            icon = 'spray-can',
            iconColor = '#FF00FF',
            onSelect = function()
                TriggerEvent('free-gangs:client:startGraffiti')
            end,
        },
        {
            title = 'Mugging',
            description = 'Rob NPCs (requires weapon)',
            icon = 'mask',
            iconColor = '#FF4444',
            onSelect = function()
                FreeGangs.Bridge.Notify('Target an NPC with a weapon equipped', 'inform')
            end,
        },
        {
            title = 'Pickpocketing',
            description = 'Steal from unsuspecting NPCs',
            icon = 'hand-paper',
            iconColor = '#FFAA00',
            onSelect = function()
                FreeGangs.Bridge.Notify('Approach an NPC carefully', 'inform')
            end,
        },
    }
    
    -- Archetype-specific activities
    if tierActivities then
        table.insert(options, {
            title = string.format('─── %s Activities ───', archetypeInfo.label or 'Special'),
            icon = FreeGangs.Client.UI.GetArchetypeIcon(gangData.archetype),
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        })
        
        for tier = 1, 3 do
            local activity = tierActivities[tier]
            if activity then
                local isUnlocked = masterLevel >= activity.minLevel
                
                table.insert(options, {
                    title = activity.name,
                    description = isUnlocked and activity.description or 
                        string.format('🔒 Requires Level %d', activity.minLevel),
                    icon = isUnlocked and 'star' or 'lock',
                    iconColor = isUnlocked and FreeGangs.Config.UI.Theme.AccentColor or '#444444',
                    disabled = not isUnlocked,
                    onSelect = isUnlocked and function()
                        TriggerServerEvent('free-gangs:server:startTierActivity', gangData.archetype, tier)
                    end or nil,
                })
            end
        end
    end
    
    lib.registerContext({
        id = 'freegangs_activities',
        title = 'Criminal Activities',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_activities')
end

-- ============================================================================
-- TREASURY MENU
-- ============================================================================

---Open treasury management menu
function FreeGangs.Client.UI.OpenTreasury()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local membership = gangData.membership
    local canWithdraw = membership and (membership.isBoss or FreeGangs.Client.HasPermission('treasury_withdraw'))
    
    local options = {
        {
            title = FreeGangs.L('treasury', 'title'),
            icon = 'piggy-bank',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            metadata = {
                { label = 'Balance', value = FreeGangs.Utils.FormatMoney(gangData.treasury or 0) },
            },
        },
        {
            title = FreeGangs.L('treasury', 'deposit'),
            description = 'Add money from your pocket',
            icon = 'arrow-down',
            iconColor = '#00FF00',
            onSelect = function()
                FreeGangs.Client.UI.ShowDepositInput('treasury')
            end,
        },
    }
    
    if canWithdraw then
        table.insert(options, {
            title = FreeGangs.L('treasury', 'withdraw'),
            description = 'Withdraw money to your pocket',
            icon = 'arrow-up',
            iconColor = '#FF4444',
            onSelect = function()
                FreeGangs.Client.UI.ShowWithdrawInput('treasury')
            end,
        })
    end
    
    -- War Chest section
    table.insert(options, {
        title = '─── War Chest ───',
        icon = 'shield-alt',
        iconColor = FreeGangs.Config.UI.Theme.PrimaryColor,
    })
    
    table.insert(options, {
        title = FreeGangs.L('treasury', 'warchest_title'),
        icon = 'shield-alt',
        iconColor = FreeGangs.Config.UI.Theme.PrimaryColor,
        metadata = {
            { label = 'Balance', value = FreeGangs.Utils.FormatMoney(gangData.war_chest or 0) },
        },
    })
    
    table.insert(options, {
        title = FreeGangs.L('treasury', 'warchest_deposit'),
        description = 'Fund war operations',
        icon = 'arrow-down',
        iconColor = '#00FF00',
        onSelect = function()
            FreeGangs.Client.UI.ShowDepositInput('warchest')
        end,
    })
    
    lib.registerContext({
        id = 'freegangs_treasury',
        title = 'Gang Finances',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_treasury')
end

-- ============================================================================
-- SETTINGS MENU (BOSS ONLY)
-- ============================================================================

---Open gang settings (boss only)
function FreeGangs.Client.UI.OpenSettings()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local membership = gangData.membership
    if not membership or not membership.isBoss then
        FreeGangs.Bridge.Notify(FreeGangs.L('gang', 'no_permission'), 'error')
        return
    end
    
    local options = {
        {
            title = 'Gang Color',
            description = 'Change your gang\'s color',
            icon = 'palette',
            iconColor = gangData.color or '#FFFFFF',
            onSelect = function()
                FreeGangs.Client.UI.ShowColorPicker()
            end,
        },
        {
            title = 'Rank Names',
            description = 'Customize rank titles',
            icon = 'tags',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.ShowRankCustomization()
            end,
        },
        {
            title = 'Stash Location',
            description = 'Move gang stash',
            icon = 'map-marker-alt',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                TriggerServerEvent('free-gangs:server:relocateStash')
            end,
        },
        {
            title = 'Transfer Leadership',
            description = 'Give boss role to another member',
            icon = 'crown',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.ShowLeadershipTransfer()
            end,
        },
    }
    
    -- Archetype-specific settings
    if gangData.archetype == FreeGangs.Archetypes.STREET then
        table.insert(options, {
            title = FreeGangs.L('menu', 'set_main_corner'),
            description = 'Designate main corner for bonus rep',
            icon = 'map-pin',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            onSelect = function()
                FreeGangs.Client.UI.ShowMainCornerSelection()
            end,
        })
    end
    
    -- Danger zone
    table.insert(options, {
        title = '─── Danger Zone ───',
        icon = 'exclamation-triangle',
        iconColor = '#FF0000',
    })
    
    table.insert(options, {
        title = FreeGangs.L('gang', 'dissolve_title'),
        description = 'Permanently delete your gang',
        icon = 'trash',
        iconColor = '#FF0000',
        onSelect = function()
            FreeGangs.Client.UI.ConfirmDissolveGang()
        end,
    })
    
    lib.registerContext({
        id = 'freegangs_settings',
        title = 'Gang Settings',
        menu = 'freegangs_main',
        options = options,
    })
    
    lib.showContext('freegangs_settings')
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get archetype icon
---@param archetype string
---@return string
function FreeGangs.Client.UI.GetArchetypeIcon(archetype)
    local icons = {
        [FreeGangs.Archetypes.STREET] = 'street-view',
        [FreeGangs.Archetypes.MC] = 'motorcycle',
        [FreeGangs.Archetypes.CARTEL] = 'cannabis',
        [FreeGangs.Archetypes.CRIME_FAMILY] = 'user-tie',
    }
    return icons[archetype] or 'users'
end

---Get online member count
---@return number
function FreeGangs.Client.UI.GetOnlineMemberCount()
    -- This would need to be fetched from cache or server
    -- For now return cached value or 0
    return FreeGangs.Client.Cache.Get('onlineMembers') or 0
end

---Get influence tier info
---@param influence number
---@return table
function FreeGangs.Client.UI.GetInfluenceTier(influence)
    if influence >= 80 then
        return { tier = 6, color = '#00FF00', benefits = '+15% profits, 2x protection, discount bribes' }
    elseif influence >= 51 then
        return { tier = 5, color = '#00DD00', benefits = '+10% profits, protection collection' }
    elseif influence >= 25 then
        return { tier = 4, color = '#88FF00', benefits = '+5% profits, Level 1 bribes' }
    elseif influence >= 11 then
        return { tier = 3, color = '#FFFF00', benefits = 'Base profits' }
    elseif influence >= 6 then
        return { tier = 2, color = '#FFAA00', benefits = '-15% profits' }
    else
        return { tier = 1, color = '#FF0000', benefits = '-20% profits' }
    end
end

---Get heat stage from heat level
---@param heat number
---@return string
function FreeGangs.Client.UI.GetHeatStage(heat)
    if heat >= 90 then return FreeGangs.HeatStages.WAR_READY
    elseif heat >= 75 then return FreeGangs.HeatStages.RIVALRY
    elseif heat >= 50 then return FreeGangs.HeatStages.COLD_WAR
    elseif heat >= 30 then return FreeGangs.HeatStages.TENSION
    else return FreeGangs.HeatStages.NEUTRAL
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

---Handle open gang UI event
RegisterNetEvent(FreeGangs.Events.Client.OPEN_GANG_UI, function()
    FreeGangs.Client.UI.OpenMainMenu()
end)

---Handle open menu event
RegisterNetEvent(FreeGangs.Events.Client.OPEN_MENU, function(menuId)
    if menuId == 'main' then
        FreeGangs.Client.UI.OpenMainMenu()
    elseif menuId == 'dashboard' then
        FreeGangs.Client.UI.OpenDashboard()
    elseif menuId == 'roster' then
        FreeGangs.Client.UI.OpenMemberRoster()
    elseif menuId == 'territory' then
        FreeGangs.Client.UI.OpenTerritoryMap()
    elseif menuId == 'wars' then
        FreeGangs.Client.UI.OpenWarStatus()
    elseif menuId == 'bribes' then
        FreeGangs.Client.UI.OpenBribesMenu()
    elseif menuId == 'treasury' then
        FreeGangs.Client.UI.OpenTreasury()
    elseif menuId == 'settings' then
        FreeGangs.Client.UI.OpenSettings()
    end
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    RegisterCommand('fg_menu', function()
        FreeGangs.Client.UI.OpenMainMenu()
    end, false)
end

return FreeGangs.Client.UI
