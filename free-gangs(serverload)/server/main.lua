--[[
    FREE-GANGS: Server Main
    
    Server-side initialization, event handlers, and core functionality.
    This is the entry point for all server-side operations.
]]

-- Ensure FreeGangs table exists
FreeGangs = FreeGangs or {}
FreeGangs.Server = FreeGangs.Server or {}

-- Server-side caches (populated on startup)
FreeGangs.Server.Gangs = {}           -- Gang data cache
FreeGangs.Server.Territories = {}     -- Territory data cache
FreeGangs.Server.Heat = {}            -- Heat data cache
FreeGangs.Server.ActiveWars = {}      -- Active wars cache
FreeGangs.Server.Bribes = {}          -- Active bribes cache
FreeGangs.Server.PlayerCooldowns = {} -- Per-player cooldowns
FreeGangs.Server.Ready = false        -- System ready flag

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the gang system
local function Initialize()
    FreeGangs.Utils.Log('Initializing FREE-GANGS system...')
    
    -- Wait for database to be ready
    MySQL.ready(function()
        FreeGangs.Utils.Log('Database connection established')
        
        -- Run database migrations/setup
        FreeGangs.Server.DB.Initialize()
        
        -- Load all data into cache
        FreeGangs.Server.LoadAllData()
        
        -- Start background threads
        FreeGangs.Server.StartBackgroundTasks()
        
        -- Mark system as ready
        FreeGangs.Server.Ready = true
        FreeGangs.Utils.Log('FREE-GANGS system initialized successfully!')
        
        -- Notify any waiting clients
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, -1)
    end)
end

---Load all data from database into cache
function FreeGangs.Server.LoadAllData()
    FreeGangs.Utils.Log('Loading data from database...')
    
    -- Load gangs
    local gangs = FreeGangs.Server.DB.GetAllGangs()
    for _, gang in pairs(gangs) do
        FreeGangs.Server.Gangs[gang.name] = gang
        
        -- Register gang with QBox if it doesn't exist
        FreeGangs.Server.RegisterGangWithQBox(gang)
    end
    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.Gangs) .. ' gangs')
    
    -- Load territories
    local territories = FreeGangs.Server.DB.GetAllTerritories()
    for _, territory in pairs(territories) do
        FreeGangs.Server.Territories[territory.name] = territory
    end
    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.Territories) .. ' territories')
    
    -- Load heat data
    local heatData = FreeGangs.Server.DB.GetAllHeat()
    for _, heat in pairs(heatData) do
        local key = heat.gang_a .. '_' .. heat.gang_b
        FreeGangs.Server.Heat[key] = heat
    end
    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.Heat) .. ' heat records')
    
    -- Load active wars
    local wars = FreeGangs.Server.DB.GetActiveWars()
    for _, war in pairs(wars) do
        FreeGangs.Server.ActiveWars[war.id] = war
    end
    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.ActiveWars) .. ' active wars')
    
    -- Load active bribes
    local bribes = FreeGangs.Server.DB.GetAllActiveBribes()
    for _, bribe in pairs(bribes) do
        if not FreeGangs.Server.Bribes[bribe.gang_name] then
            FreeGangs.Server.Bribes[bribe.gang_name] = {}
        end
        FreeGangs.Server.Bribes[bribe.gang_name][bribe.contact_type] = bribe
    end
    FreeGangs.Utils.Log('Loaded bribe data for ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.Bribes) .. ' gangs')
end

---Register a gang with QBox framework
---@param gang table
function FreeGangs.Server.RegisterGangWithQBox(gang)
    local grades = {}
    
    -- Get ranks from database
    local ranks = FreeGangs.Server.DB.GetGangRanks(gang.name)
    
    if #ranks > 0 then
        for _, rank in pairs(ranks) do
            grades[tostring(rank.rank_level)] = {
                name = rank.name,
                isboss = rank.is_boss == 1,
            }
        end
    else
        -- Use default ranks based on archetype
        local defaultRanks = FreeGangs.DefaultRanks[gang.archetype] or FreeGangs.DefaultRanks[FreeGangs.Archetypes.STREET]
        for level, rankData in pairs(defaultRanks) do
            grades[tostring(level)] = {
                name = rankData.name,
                isboss = rankData.isBoss,
            }
        end
    end
    
    -- Create gang in QBox
    FreeGangs.Bridge.CreateGang(gang.name, gang.label, grades)
end

-- ============================================================================
-- BACKGROUND TASKS
-- ============================================================================

---Start all background tasks
function FreeGangs.Server.StartBackgroundTasks()
    -- Reputation decay task
    CreateThread(function()
        local decayInterval = FreeGangs.Config.Reputation.DecayIntervalHours * 60 * 60 * 1000 -- Convert to ms
        while true do
            Wait(decayInterval)
            FreeGangs.Server.ProcessReputationDecay()
        end
    end)
    
    -- Territory influence decay task
    CreateThread(function()
        local decayInterval = FreeGangs.Config.Territory.DecayIntervalHours * 60 * 60 * 1000
        while true do
            Wait(decayInterval)
            FreeGangs.Server.ProcessTerritoryDecay()
        end
    end)
    
    -- Heat decay task
    CreateThread(function()
        local decayInterval = FreeGangs.Config.Heat.GangDecayMinutes * 60 * 1000
        while true do
            Wait(decayInterval)
            FreeGangs.Server.ProcessHeatDecay()
        end
    end)
    
    -- Bribe payment check task
    CreateThread(function()
        while true do
            Wait(60000) -- Check every minute
            FreeGangs.Server.ProcessBribePayments()
        end
    end)
    
    -- Cache flush task (write-behind pattern)
    CreateThread(function()
        while true do
            Wait(10000) -- Flush every 10 seconds
            FreeGangs.Server.Cache.Flush()
        end
    end)
    
    -- Cleanup expired cooldowns
    CreateThread(function()
        while true do
            Wait(300000) -- Every 5 minutes
            FreeGangs.Server.CleanupCooldowns()
        end
    end)
    
    FreeGangs.Utils.Log('Background tasks started')
end

---Process reputation decay for all gangs
function FreeGangs.Server.ProcessReputationDecay()
    local decayAmount = FreeGangs.Config.Reputation.DecayAmount
    
    for gangName, gang in pairs(FreeGangs.Server.Gangs) do
        local oldRep = gang.master_rep
        local newRep = math.max(FreeGangs.Config.Reputation.MinReputation, oldRep - decayAmount)
        
        if newRep ~= oldRep then
            FreeGangs.Server.SetGangReputation(gangName, newRep, 'decay')
            
            -- Check for level change
            local oldLevel = FreeGangs.Utils.GetReputationLevel(oldRep)
            local newLevel = FreeGangs.Utils.GetReputationLevel(newRep)
            
            if newLevel < oldLevel then
                FreeGangs.Server.OnLevelChange(gangName, oldLevel, newLevel)
            end
        end
    end
    
    FreeGangs.Utils.Debug('Processed reputation decay for all gangs')
end

---Process territory influence decay
function FreeGangs.Server.ProcessTerritoryDecay()
    local decayPercent = FreeGangs.Config.Territory.DecayPercentage
    
    for zoneName, territory in pairs(FreeGangs.Server.Territories) do
        local influence = territory.influence or {}
        local changed = false
        
        for gangName, percent in pairs(influence) do
            local newPercent = math.max(0, percent - decayPercent)
            if newPercent ~= percent then
                influence[gangName] = newPercent > 0 and newPercent or nil
                changed = true
            end
        end
        
        if changed then
            FreeGangs.Server.UpdateTerritoryInfluence(zoneName, influence)
        end
    end
    
    FreeGangs.Utils.Debug('Processed territory decay')
end

---Process heat decay between gangs
function FreeGangs.Server.ProcessHeatDecay()
    local decayRate = FreeGangs.Config.Heat.GangDecayRate
    
    for key, heatData in pairs(FreeGangs.Server.Heat) do
        if heatData.heat_level > 0 then
            local newHeat = math.max(0, heatData.heat_level - decayRate)
            
            if newHeat ~= heatData.heat_level then
                local oldStage = FreeGangs.Utils.GetHeatStage(heatData.heat_level)
                local newStage = FreeGangs.Utils.GetHeatStage(newHeat)
                
                heatData.heat_level = newHeat
                heatData.stage = newStage
                
                -- Mark for database update
                FreeGangs.Server.Cache.MarkDirty('heat', key)
                
                -- Notify if stage changed
                if newStage ~= oldStage then
                    FreeGangs.Server.OnHeatStageChange(heatData.gang_a, heatData.gang_b, oldStage, newStage)
                end
            end
        end
    end
    
    FreeGangs.Utils.Debug('Processed heat decay')
end

---Process bribe payment deadlines
function FreeGangs.Server.ProcessBribePayments()
    local currentTime = os.time()
    
    for gangName, bribes in pairs(FreeGangs.Server.Bribes) do
        for contactType, bribe in pairs(bribes) do
            if bribe.status == FreeGangs.BribeStatus.ACTIVE and bribe.next_payment then
                local nextPayment = bribe.next_payment
                
                -- Check if payment is overdue
                if currentTime > nextPayment then
                    FreeGangs.Server.HandleMissedBribePayment(gangName, contactType)
                -- Check if we need to send a reminder (24 hours before)
                elseif currentTime > (nextPayment - 86400) then
                    FreeGangs.Server.SendBribePaymentReminder(gangName, contactType)
                end
            end
        end
    end
end

---Cleanup expired cooldowns
function FreeGangs.Server.CleanupCooldowns()
    local currentTime = os.time()
    
    for source, cooldowns in pairs(FreeGangs.Server.PlayerCooldowns) do
        for cooldownType, expiry in pairs(cooldowns) do
            if currentTime > expiry then
                cooldowns[cooldownType] = nil
            end
        end
        
        -- Remove player entry if no cooldowns remain
        if not next(cooldowns) then
            FreeGangs.Server.PlayerCooldowns[source] = nil
        end
    end
end

-- ============================================================================
-- PLAYER CONNECTION HANDLERS
-- ============================================================================

---Handle player loading
---@param source number
local function OnPlayerLoaded(source)
    if not FreeGangs.Server.Ready then
        -- Wait for system to be ready
        while not FreeGangs.Server.Ready do
            Wait(100)
        end
    end
    
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end
    
    -- Get player's gang membership from database
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    
    if membership then
        -- Sync with client
        local gangData = FreeGangs.Server.Gangs[membership.gang_name]
        if gangData then
            TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
                gang = gangData,
                membership = membership,
                territories = FreeGangs.Server.GetGangTerritories(membership.gang_name),
            })
        end
    end
    
    -- Initialize player cooldowns
    FreeGangs.Server.PlayerCooldowns[source] = {}
    
    FreeGangs.Utils.Debug('Player loaded:', source, citizenid)
end

---Handle player disconnection
---@param source number
local function OnPlayerDropped(source)
    -- Clean up player-specific data
    FreeGangs.Server.PlayerCooldowns[source] = nil

    -- Invalidate gang data cache
    if FreeGangs.Server.InvalidatePlayerGangCache then
        FreeGangs.Server.InvalidatePlayerGangCache(source)
    end

    FreeGangs.Utils.Debug('Player dropped:', source)
end

-- ============================================================================
-- COOLDOWN MANAGEMENT
-- ============================================================================

---Set a cooldown for a player
---@param source number
---@param cooldownType string
---@param durationSeconds number
function FreeGangs.Server.SetCooldown(source, cooldownType, durationSeconds)
    if not FreeGangs.Server.PlayerCooldowns[source] then
        FreeGangs.Server.PlayerCooldowns[source] = {}
    end
    FreeGangs.Server.PlayerCooldowns[source][cooldownType] = os.time() + durationSeconds
end

---Check if a player is on cooldown
---@param source number
---@param cooldownType string
---@return boolean onCooldown
---@return number|nil remainingSeconds
function FreeGangs.Server.IsOnCooldown(source, cooldownType)
    local cooldowns = FreeGangs.Server.PlayerCooldowns[source]
    if not cooldowns or not cooldowns[cooldownType] then
        return false, nil
    end
    
    local remaining = cooldowns[cooldownType] - os.time()
    if remaining > 0 then
        return true, remaining
    end
    
    -- Expired, clean up
    cooldowns[cooldownType] = nil
    return false, nil
end

---Get remaining cooldown time in seconds
---@param source number
---@param cooldownType string
---@return number seconds remaining (0 if not on cooldown)
function FreeGangs.Server.GetCooldownRemaining(source, cooldownType)
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownType)
    if not onCooldown then
        return 0
    end
    return remaining or 0
end

-- ============================================================================
-- GANG DATA HELPERS
-- ============================================================================

---Get gang data from cache
---@param gangName string
---@return table|nil
function FreeGangs.Server.GetGang(gangName)
    return FreeGangs.Server.Gangs[gangName]
end

---Get all gangs
---@return table
function FreeGangs.Server.GetAllGangs()
    return FreeGangs.Server.Gangs
end

---Get gang territories
---@param gangName string
---@return table
function FreeGangs.Server.GetGangTerritories(gangName)
    local territories = {}
    
    for zoneName, territory in pairs(FreeGangs.Server.Territories) do
        local influence = territory.influence or {}
        if influence[gangName] and influence[gangName] > 0 then
            territories[zoneName] = {
                name = zoneName,
                label = territory.label,
                influence = influence[gangName],
                totalInfluence = influence,
                isMajority = influence[gangName] >= FreeGangs.Config.Territory.MajorityThreshold,
            }
        end
    end
    
    return territories
end

---Set gang reputation
---@param gangName string
---@param reputation number
---@param reason string|nil
function FreeGangs.Server.SetGangReputation(gangName, reputation, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end
    
    local oldRep = gang.master_rep
    gang.master_rep = reputation
    gang.master_level = FreeGangs.Utils.GetReputationLevel(reputation)
    
    -- Mark for database update
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Log the change
    FreeGangs.Server.DB.Log(gangName, nil, 'reputation_change', FreeGangs.LogCategories.REPUTATION, {
        oldRep = oldRep,
        newRep = reputation,
        change = reputation - oldRep,
        reason = reason,
    })
end

---Handle level change events
---@param gangName string
---@param oldLevel number
---@param newLevel number
function FreeGangs.Server.OnLevelChange(gangName, oldLevel, newLevel)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end
    
    local levelInfo = FreeGangs.ReputationLevels[newLevel]
    local message
    
    if newLevel > oldLevel then
        message = string.format(FreeGangs.Config.Messages.LevelUp, newLevel, levelInfo.name)
    else
        message = string.format(FreeGangs.Config.Messages.LevelDown, newLevel, levelInfo.name)
    end
    
    -- Notify all gang members
    FreeGangs.Bridge.NotifyGang(gangName, message, newLevel > oldLevel and 'success' or 'warning')
    
    -- Log the event
    FreeGangs.Server.DB.Log(gangName, nil, 'level_change', FreeGangs.LogCategories.REPUTATION, {
        oldLevel = oldLevel,
        newLevel = newLevel,
    })
    
    -- Send Discord webhook if configured
    FreeGangs.Server.SendDiscordWebhook('Level Change', string.format(
        '**%s** has %s to Level %d (%s)',
        gang.label,
        newLevel > oldLevel and 'risen' or 'fallen',
        newLevel,
        levelInfo.name
    ))
end

---Handle heat stage change events
---@param gangA string
---@param gangB string
---@param oldStage string
---@param newStage string
function FreeGangs.Server.OnHeatStageChange(gangA, gangB, oldStage, newStage)
    local gangAData = FreeGangs.Server.Gangs[gangA]
    local gangBData = FreeGangs.Server.Gangs[gangB]
    
    if not gangAData or not gangBData then return end
    
    local stageInfo = FreeGangs.HeatStageThresholds[newStage]
    
    -- Notify both gangs
    local message = string.format(FreeGangs.Config.Messages.StageChanged, gangBData.label, stageInfo.label)
    FreeGangs.Bridge.NotifyGang(gangA, message, 'warning')
    
    message = string.format(FreeGangs.Config.Messages.StageChanged, gangAData.label, stageInfo.label)
    FreeGangs.Bridge.NotifyGang(gangB, message, 'warning')
end

-- ============================================================================
-- DISCORD WEBHOOK
-- ============================================================================

---Send a Discord webhook notification
---@param title string
---@param message string
---@param color number|nil
function FreeGangs.Server.SendDiscordWebhook(title, message, color)
    local webhook = FreeGangs.Config.General.DiscordWebhook
    if not webhook or webhook == '' then return end
    
    local embed = {
        {
            title = 'FREE-GANGS: ' .. title,
            description = message,
            color = color or 16711680, -- Red
            footer = {
                text = os.date('%Y-%m-%d %H:%M:%S')
            }
        }
    }
    
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({
        username = 'FREE-GANGS',
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- QBox player loaded event
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    OnPlayerLoaded(source)
end)

-- Alternative event for QBox
AddEventHandler('qbx_core:server:playerLoaded', function(player)
    OnPlayerLoaded(player.PlayerData.source)
end)

-- Player dropped event
AddEventHandler('playerDropped', function(reason)
    OnPlayerDropped(source)
end)

-- Resource stop - flush all caches
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    FreeGangs.Utils.Log('Resource stopping, flushing cache...')
    FreeGangs.Server.Cache.Flush(true) -- Force immediate flush
end)

-- ============================================================================
-- CORE GANG EVENT HANDLERS
-- ============================================================================

-- Gang creation
RegisterNetEvent(FreeGangs.Events.Server.CREATE_GANG, function(data)
    local source = source
    if not data or type(data) ~= 'table' then
        FreeGangs.Bridge.Notify(source, 'Invalid gang creation data', 'error')
        return
    end

    local success, result = FreeGangs.Server.Gang.Create(data, source)
    if not success then
        FreeGangs.Bridge.Notify(source, result or 'Failed to create gang', 'error')
        return
    end

    -- Send updated gang data to the creator
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if citizenid then
        local gangData = FreeGangs.Server.Gang.GetClientData(result)
        local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
            gang = gangData,
            membership = membership,
        })
    end
end)

-- Gang deletion (boss only)
RegisterNetEvent(FreeGangs.Events.Server.DELETE_GANG, function()
    local source = source
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.is_boss then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local success, err = FreeGangs.Server.Gang.Delete(membership.gang_name, 'Dissolved by boss')
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to delete gang', 'error')
    end
end)

-- Join gang (via invitation acceptance)
RegisterNetEvent(FreeGangs.Events.Server.JOIN_GANG, function(gangName)
    local source = source
    if not gangName then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local success, err = FreeGangs.Server.Member.Add(citizenid, gangName, 0)
    if success and FreeGangs.Server.InvalidatePlayerGangCache then
        FreeGangs.Server.InvalidatePlayerGangCache(source)
    end
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to join gang', 'error')
    end
end)

-- Leave gang
RegisterNetEvent(FreeGangs.Events.Server.LEAVE_GANG, function()
    local source = source
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NotInGang, 'error')
        return
    end

    local success, err = FreeGangs.Server.Member.Remove(citizenid, membership.gang_name, 'Left voluntarily')
    if success and FreeGangs.Server.InvalidatePlayerGangCache then
        FreeGangs.Server.InvalidatePlayerGangCache(source)
    end
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to leave gang', 'error')
    end
end)

-- Invite player
RegisterNetEvent('free-gangs:server:invitePlayer', function(targetServerId)
    local source = source
    if not targetServerId then return end

    local success, err = FreeGangs.Server.Member.Invite(source, tonumber(targetServerId))
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to send invite', 'error')
    end
end)

-- Kick member
RegisterNetEvent(FreeGangs.Events.Server.KICK_MEMBER, function(targetCitizenid)
    local source = source
    if not targetCitizenid then return end

    local success, err = FreeGangs.Server.Member.Kick(source, targetCitizenid)
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to kick member', 'error')
    end
end)

-- Promote member
RegisterNetEvent(FreeGangs.Events.Server.PROMOTE_MEMBER, function(targetCitizenid)
    local source = source
    if not targetCitizenid then return end

    local success, err = FreeGangs.Server.Member.Promote(source, targetCitizenid)
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to promote member', 'error')
    end
end)

-- Demote member
RegisterNetEvent(FreeGangs.Events.Server.DEMOTE_MEMBER, function(targetCitizenid)
    local source = source
    if not targetCitizenid then return end

    local success, err = FreeGangs.Server.Member.Demote(source, targetCitizenid)
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to demote member', 'error')
    end
end)

-- Treasury deposit
RegisterNetEvent(FreeGangs.Events.Server.DEPOSIT_TREASURY, function(amount)
    local source = source
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NotInGang, 'error')
        return
    end

    local success, err = FreeGangs.Server.Gang.DepositTreasury(membership.gang_name, source, amount)
    if success then
        FreeGangs.Bridge.Notify(source, 'Deposited ' .. FreeGangs.Utils.FormatMoney(amount) .. ' to treasury', 'success')
        -- Update client gang data
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
            gang = FreeGangs.Server.Gang.GetClientData(membership.gang_name),
            membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid),
        })
    else
        FreeGangs.Bridge.Notify(source, err or FreeGangs.Config.Messages.InsufficientFunds, 'error')
    end
end)

-- Treasury withdrawal
RegisterNetEvent(FreeGangs.Events.Server.WITHDRAW_TREASURY, function(amount)
    local source = source
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NotInGang, 'error')
        return
    end

    -- Check permission
    if not membership.is_boss and not FreeGangs.Server.Member.HasPermission(source, FreeGangs.Permissions.WITHDRAW_TREASURY) then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local success, err = FreeGangs.Server.Gang.WithdrawTreasury(membership.gang_name, source, amount)
    if success then
        FreeGangs.Bridge.Notify(source, 'Withdrew ' .. FreeGangs.Utils.FormatMoney(amount) .. ' from treasury', 'success')
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
            gang = FreeGangs.Server.Gang.GetClientData(membership.gang_name),
            membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid),
        })
    else
        FreeGangs.Bridge.Notify(source, err or FreeGangs.Config.Messages.InsufficientFunds, 'error')
    end
end)

-- War chest deposit
RegisterNetEvent(FreeGangs.Events.Server.DEPOSIT_WARCHEST, function(amount)
    local source = source
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NotInGang, 'error')
        return
    end

    local success, err = FreeGangs.Server.Gang.DepositWarChest(membership.gang_name, source, amount)
    if success then
        FreeGangs.Bridge.Notify(source, 'Deposited ' .. FreeGangs.Utils.FormatMoney(amount) .. ' to war chest', 'success')
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
            gang = FreeGangs.Server.Gang.GetClientData(membership.gang_name),
            membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid),
        })
    else
        FreeGangs.Bridge.Notify(source, err or FreeGangs.Config.Messages.InsufficientFunds, 'error')
    end
end)

-- Open gang stash
RegisterNetEvent(FreeGangs.Events.Server.OPEN_STASH, function()
    local source = source
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NotInGang, 'error')
        return
    end

    if not FreeGangs.Server.Member.HasPermission(source, FreeGangs.Permissions.ACCESS_GANG_STASH) then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then return end

    local stashConfig = FreeGangs.Config.Stash.GangStash
    local slots = stashConfig.BaseSlots + (stashConfig.SlotsPerLevel * (gang.master_level or 1))

    exports.ox_inventory:openInventory(source, {
        type = 'stash',
        id = 'freegangs_' .. membership.gang_name,
        label = gang.label .. ' Stash',
        slots = slots,
        weight = stashConfig.BaseWeight,
    })
end)

-- Update gang color (boss only)
RegisterNetEvent('free-gangs:server:updateGangColor', function(color)
    local source = source
    if not color then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.is_boss then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local success = FreeGangs.Server.Gang.UpdateColor(membership.gang_name, color)
    if success then
        FreeGangs.Bridge.Notify(source, 'Gang color updated', 'success')
    else
        FreeGangs.Bridge.Notify(source, 'Invalid color', 'error')
    end
end)

-- Update rank names (boss only)
RegisterNetEvent('free-gangs:server:updateRankNames', function(rankNames)
    local source = source
    if not rankNames or type(rankNames) ~= 'table' then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.is_boss then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    for rankLevel, name in pairs(rankNames) do
        if type(name) == 'string' and #name > 0 then
            FreeGangs.Server.Gang.UpdateRankName(membership.gang_name, tonumber(rankLevel), name)
        end
    end

    FreeGangs.Bridge.Notify(source, 'Rank names updated', 'success')
end)

-- Transfer leadership (boss only)
RegisterNetEvent('free-gangs:server:transferLeadership', function(newLeaderCitizenid)
    local source = source
    if not newLeaderCitizenid then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.is_boss then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end

    -- Verify new leader is in the same gang
    local targetMembership = FreeGangs.Server.DB.GetPlayerMembership(newLeaderCitizenid)
    if not targetMembership or targetMembership.gang_name ~= gangName then
        FreeGangs.Bridge.Notify(source, 'Target is not in your gang', 'error')
        return
    end

    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local bossRank = 5
    local bossRankName = defaultRanks[bossRank] and defaultRanks[bossRank].name or 'Boss'
    local officerRank = 4
    local officerRankName = defaultRanks[officerRank] and defaultRanks[officerRank].name or 'Officer'

    -- Promote new leader to boss
    FreeGangs.Server.DB.UpdateMemberRank(newLeaderCitizenid, gangName, bossRank, bossRankName)
    FreeGangs.Bridge.SetPlayerGangGrade(newLeaderCitizenid, gangName, bossRank)

    -- Demote old leader to officer
    FreeGangs.Server.DB.UpdateMemberRank(citizenid, gangName, officerRank, officerRankName)
    FreeGangs.Bridge.SetPlayerGangGrade(citizenid, gangName, officerRank)

    FreeGangs.Bridge.NotifyGang(gangName, 'Leadership has been transferred', 'inform')

    -- Update both clients
    TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
        gang = FreeGangs.Server.Gang.GetClientData(gangName),
        membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid),
    })

    local newLeaderPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(newLeaderCitizenid)
    if newLeaderPlayer then
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, newLeaderPlayer.PlayerData.source, {
            gang = FreeGangs.Server.Gang.GetClientData(gangName),
            membership = FreeGangs.Server.DB.GetPlayerMembership(newLeaderCitizenid),
        })
    end
end)

-- Relocate stash (boss only)
RegisterNetEvent('free-gangs:server:relocateStash', function()
    local source = source
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.is_boss then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    if not FreeGangs.Config.Stash.AllowStashRelocation then
        FreeGangs.Bridge.Notify(source, 'Stash relocation is disabled', 'error')
        return
    end

    FreeGangs.Bridge.Notify(source, 'Stash relocation is not yet implemented', 'inform')
end)

-- Request peace (war)
RegisterNetEvent('free-gangs:server:requestPeace', function(warId)
    local source = source
    if not warId then return end

    local success, err = lib.callback.await('free-gangs:callback:requestPeace', source, warId)
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to request peace', 'error')
    end
end)

-- Decline war
RegisterNetEvent('free-gangs:server:declineWar', function(warId)
    local source = source
    if not warId then return end

    local success, err = lib.callback.await('free-gangs:callback:declineWar', source, warId)
    if not success then
        FreeGangs.Bridge.Notify(source, err or 'Failed to decline war', 'error')
    end
end)

-- Terminate bribe
RegisterNetEvent('free-gangs:server:terminateBribe', function(contactType)
    local source = source
    if not contactType then return end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return end

    if not FreeGangs.Server.Member.HasPermission(source, FreeGangs.Permissions.MANAGE_BRIBES) then
        FreeGangs.Bridge.Notify(source, FreeGangs.Config.Messages.NoPermission, 'error')
        return
    end

    local gangBribes = FreeGangs.Server.Bribes and FreeGangs.Server.Bribes[membership.gang_name]
    if gangBribes and gangBribes[contactType] then
        gangBribes[contactType] = nil
        FreeGangs.Bridge.Notify(source, 'Contact terminated', 'success')
    else
        FreeGangs.Bridge.Notify(source, 'No active contact of that type', 'error')
    end
end)

-- Set main corner (Street Gang archetype)
RegisterNetEvent('free-gangs:server:setMainCorner', function(zoneName)
    local source = source
    if not zoneName then return end

    local success = lib.callback.await('free-gangs:callback:setMainCorner', source, zoneName)
    if success then
        FreeGangs.Bridge.Notify(source, 'Main corner set to ' .. zoneName, 'success')
    else
        FreeGangs.Bridge.Notify(source, 'Failed to set main corner', 'error')
    end
end)

-- ============================================================================
-- COMMANDS (Development/Admin)
-- ============================================================================

if FreeGangs.Config.General.Debug then
    -- Debug command to check gang data
    RegisterCommand('fg_debug', function(source, args)
        if source ~= 0 then
            -- Check admin permission
            if not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
                FreeGangs.Bridge.Notify(source, 'No permission', 'error')
                return
            end
        end
        
        local gangName = args[1]
        if gangName then
            local gang = FreeGangs.Server.GetGang(gangName)
            if gang then
                print('[free-gangs:debug] Gang Data:')
                FreeGangs.Utils.PrintTable(gang)
            else
                print('[free-gangs:debug] Gang not found: ' .. gangName)
            end
        else
            print('[free-gangs:debug] All Gangs:')
            for name, _ in pairs(FreeGangs.Server.Gangs) do
                print('  - ' .. name)
            end
        end
    end, false)
    
    -- Debug command to check territories
    RegisterCommand('fg_territories', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        print('[free-gangs:debug] Territories:')
        for name, territory in pairs(FreeGangs.Server.Territories) do
            print(string.format('  %s: %s', name, json.encode(territory.influence or {})))
        end
    end, false)
end

-- ============================================================================
-- STARTUP
-- ============================================================================

-- Initialize on resource start
CreateThread(function()
    Wait(1000) -- Small delay to ensure all files are loaded
    Initialize()
end)

return FreeGangs.Server
