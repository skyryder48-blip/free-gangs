--[[
    FREE-GANGS: War System Module
    
    Handles war declarations, acceptance/decline, war resolution,
    kill tracking, collateral management, and cooldowns.
    
    War Flow:
    1. Attacker declares war (requires 90+ heat, collateral)
    2. Defender must accept (match collateral) within 24 hours
    3. War is active until surrender, peace, or admin end
    4. Winner takes all collateral, 48-hour cooldown applies
]]

-- Ensure module namespace exists
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.War = {}

-- ============================================================================
-- LOCAL CONSTANTS
-- ============================================================================

local WAR_PENDING_TIMEOUT_MS = 24 * 60 * 60 * 1000 -- 24 hours
local WAR_COOLDOWN_HOURS = 48

-- ============================================================================
-- WAR VALIDATION
-- ============================================================================

---Validate war declaration requirements
---@param attackerGang string
---@param defenderGang string
---@param collateral number
---@return boolean valid
---@return string|nil errorMessage
local function ValidateWarDeclaration(attackerGang, defenderGang, collateral)
    -- Check gangs exist
    local attackerData = FreeGangs.Server.Gangs[attackerGang]
    local defenderData = FreeGangs.Server.Gangs[defenderGang]
    
    if not attackerData then
        return false, 'Your gang does not exist'
    end
    
    if not defenderData then
        return false, 'Target gang does not exist'
    end
    
    -- Can't declare war on yourself
    if attackerGang == defenderGang then
        return false, 'Cannot declare war on your own gang'
    end
    
    -- Check heat requirement
    local heatLevel = FreeGangs.Server.Heat.Get(attackerGang, defenderGang)
    local minHeat = FreeGangs.Config.War.MinHeatForWar
    
    if heatLevel < minHeat then
        return false, string.format('Requires %d heat with target (current: %d)', minHeat, heatLevel)
    end
    
    -- Check collateral range
    local minCollateral = FreeGangs.Config.War.MinCollateral
    local maxCollateral = FreeGangs.Config.War.MaxCollateral
    
    if collateral < minCollateral then
        return false, string.format('Minimum collateral is %s', FreeGangs.Utils.FormatMoney(minCollateral))
    end
    
    if collateral > maxCollateral then
        return false, string.format('Maximum collateral is %s', FreeGangs.Utils.FormatMoney(maxCollateral))
    end
    
    -- Check attacker has enough in war chest
    local warChest = attackerData.war_chest or 0
    local minBalance = FreeGangs.Config.War.WarChest.MinBalanceForWar
    
    if warChest < collateral then
        return false, string.format('Insufficient war chest funds (have: %s, need: %s)', 
            FreeGangs.Utils.FormatMoney(warChest), FreeGangs.Utils.FormatMoney(collateral))
    end
    
    if warChest < minBalance then
        return false, string.format('War chest needs minimum %s balance', FreeGangs.Utils.FormatMoney(minBalance))
    end
    
    -- Check not already at war
    if FreeGangs.Server.War.IsAtWarWith(attackerGang, defenderGang) then
        return false, 'Already at war with this gang'
    end
    
    -- Check cooldown
    local hasCooldown, cooldownUntil = FreeGangs.Server.DB.CheckWarCooldown(attackerGang, defenderGang)
    if hasCooldown then
        local remaining = cooldownUntil - os.time()
        return false, string.format('War cooldown active: %s remaining', FreeGangs.Utils.FormatDuration(remaining * 1000))
    end
    
    -- Check no pending war
    local pendingWar = FreeGangs.Server.War.GetPending(attackerGang, defenderGang)
    if pendingWar then
        return false, 'A war declaration is already pending with this gang'
    end
    
    return true, nil
end

---Validate war acceptance requirements
---@param warId number
---@param defenderGang string
---@param defenderCollateral number
---@return boolean valid
---@return string|nil errorMessage
local function ValidateWarAcceptance(warId, defenderGang, defenderCollateral)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War declaration not found'
    end
    
    if war.defender ~= defenderGang then
        return false, 'This war declaration is not for your gang'
    end
    
    if war.status ~= FreeGangs.WarStatus.PENDING then
        return false, 'This war is no longer pending'
    end
    
    -- Check defender collateral matches attacker
    if defenderCollateral < war.attacker_collateral then
        return false, string.format('Must match attacker collateral of %s', 
            FreeGangs.Utils.FormatMoney(war.attacker_collateral))
    end
    
    -- Check defender has enough in war chest
    local defenderData = FreeGangs.Server.Gangs[defenderGang]
    if not defenderData then
        return false, 'Your gang does not exist'
    end
    
    local warChest = defenderData.war_chest or 0
    if warChest < defenderCollateral then
        return false, string.format('Insufficient war chest funds (have: %s, need: %s)',
            FreeGangs.Utils.FormatMoney(warChest), FreeGangs.Utils.FormatMoney(defenderCollateral))
    end
    
    return true, nil
end

-- ============================================================================
-- CORE WAR FUNCTIONS
-- ============================================================================

---Declare war on another gang
---@param attackerGang string
---@param defenderGang string
---@param collateral number
---@param terms table|nil Optional war terms
---@return number|nil warId
---@return string|nil errorMessage
function FreeGangs.Server.War.Declare(attackerGang, defenderGang, collateral, terms)
    -- Validate
    local valid, errorMsg = ValidateWarDeclaration(attackerGang, defenderGang, collateral)
    if not valid then
        return nil, errorMsg
    end
    
    -- Deduct collateral from attacker's war chest
    local attackerData = FreeGangs.Server.Gangs[attackerGang]
    attackerData.war_chest = attackerData.war_chest - collateral
    FreeGangs.Server.Cache.MarkDirty('gang', attackerGang)
    
    -- Create war record
    local warData = {
        attacker = attackerGang,
        defender = defenderGang,
        attacker_collateral = collateral,
        terms = terms or {},
    }
    
    local warId = FreeGangs.Server.DB.CreateWar(warData)
    
    if not warId then
        -- Refund collateral on failure
        attackerData.war_chest = attackerData.war_chest + collateral
        return nil, 'Failed to create war record'
    end
    
    -- Add to active wars cache
    FreeGangs.Server.ActiveWars[warId] = {
        id = warId,
        attacker = attackerGang,
        defender = defenderGang,
        attacker_collateral = collateral,
        defender_collateral = 0,
        status = FreeGangs.WarStatus.PENDING,
        attacker_kills = 0,
        defender_kills = 0,
        terms = terms or {},
        started_at = nil,
        created_at = os.time(),
    }
    
    -- Log the declaration
    FreeGangs.Server.DB.Log(attackerGang, nil, 'war_declared', FreeGangs.LogCategories.WAR, {
        target_gang = defenderGang,
        collateral = collateral,
        war_id = warId,
    })
    
    -- Notify both gangs
    local attackerLabel = attackerData.label
    local defenderData = FreeGangs.Server.Gangs[defenderGang]
    local defenderLabel = defenderData.label
    
    FreeGangs.Bridge.NotifyGang(attackerGang, 
        string.format('War declared on %s! Collateral: %s. Awaiting response...', 
            defenderLabel, FreeGangs.Utils.FormatMoney(collateral)), 
        'warning')
    
    FreeGangs.Bridge.NotifyGang(defenderGang, 
        string.format('%s has declared war! Collateral: %s. You have 24 hours to respond.', 
            attackerLabel, FreeGangs.Utils.FormatMoney(collateral)), 
        'error')
    
    -- Discord webhook
    FreeGangs.Server.SendDiscordWebhook('War Declaration', string.format(
        '**%s** has declared war on **%s**!\nCollateral: %s\nAwaiting defender response...',
        attackerLabel, defenderLabel, FreeGangs.Utils.FormatMoney(collateral)
    ), 16711680)
    
    -- Schedule auto-cancel if not accepted
    FreeGangs.Server.War.SchedulePendingTimeout(warId)
    
    return warId, nil
end

---Accept a war declaration
---@param warId number
---@param defenderGang string
---@param defenderCollateral number|nil Defaults to attacker collateral
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.Accept(warId, defenderGang, defenderCollateral)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War declaration not found'
    end
    
    -- Default to matching collateral
    defenderCollateral = defenderCollateral or war.attacker_collateral
    
    -- Validate
    local valid, errorMsg = ValidateWarAcceptance(warId, defenderGang, defenderCollateral)
    if not valid then
        return false, errorMsg
    end
    
    -- Deduct collateral from defender's war chest
    local defenderData = FreeGangs.Server.Gangs[defenderGang]
    defenderData.war_chest = defenderData.war_chest - defenderCollateral
    FreeGangs.Server.Cache.MarkDirty('gang', defenderGang)
    
    -- Update war record
    war.defender_collateral = defenderCollateral
    war.status = FreeGangs.WarStatus.ACTIVE
    war.started_at = os.time()
    
    FreeGangs.Server.DB.AcceptWar(warId, defenderCollateral)
    
    -- Log
    FreeGangs.Server.DB.Log(defenderGang, nil, 'war_accepted', FreeGangs.LogCategories.WAR, {
        attacker_gang = war.attacker,
        collateral = defenderCollateral,
        war_id = warId,
    })
    
    -- Notify both gangs
    local attackerData = FreeGangs.Server.Gangs[war.attacker]
    
    FreeGangs.Bridge.NotifyGang(war.attacker, 
        string.format('WAR BEGINS! %s has accepted the challenge!', defenderData.label), 
        'error')
    
    FreeGangs.Bridge.NotifyGang(defenderGang, 
        string.format('WAR BEGINS! You have accepted %s\'s declaration!', attackerData.label), 
        'error')
    
    -- Sync to all clients
    FreeGangs.Server.War.SyncToClients(warId)
    
    -- Discord webhook
    FreeGangs.Server.SendDiscordWebhook('War Active', string.format(
        '⚔️ WAR HAS BEGUN! ⚔️\n**%s** vs **%s**\nTotal collateral: %s',
        attackerData.label, defenderData.label,
        FreeGangs.Utils.FormatMoney(war.attacker_collateral + defenderCollateral)
    ), 8388608)
    
    return true, nil
end

---Decline a war declaration
---@param warId number
---@param defenderGang string
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.Decline(warId, defenderGang)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War declaration not found'
    end
    
    if war.defender ~= defenderGang then
        return false, 'This war declaration is not for your gang'
    end
    
    if war.status ~= FreeGangs.WarStatus.PENDING then
        return false, 'This war is no longer pending'
    end
    
    -- Declining means forfeiting - attacker wins by default
    return FreeGangs.Server.War.End(warId, war.attacker, 'defender_forfeit')
end

---Surrender from an active war
---@param warId number
---@param surrenderingGang string
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.Surrender(warId, surrenderingGang)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War not found'
    end
    
    if war.status ~= FreeGangs.WarStatus.ACTIVE then
        return false, 'War is not active'
    end
    
    if surrenderingGang ~= war.attacker and surrenderingGang ~= war.defender then
        return false, 'Your gang is not part of this war'
    end
    
    -- Determine winner
    local winner = surrenderingGang == war.attacker and war.defender or war.attacker
    
    return FreeGangs.Server.War.End(warId, winner, 'surrender')
end

---Request mutual peace (both sides must agree)
---@param warId number
---@param requestingGang string
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.RequestPeace(warId, requestingGang)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War not found'
    end
    
    if war.status ~= FreeGangs.WarStatus.ACTIVE then
        return false, 'War is not active'
    end
    
    if requestingGang ~= war.attacker and requestingGang ~= war.defender then
        return false, 'Your gang is not part of this war'
    end
    
    -- Initialize peace request tracking
    war.peace_requests = war.peace_requests or {}
    war.peace_requests[requestingGang] = os.time()
    
    -- Check if both sides have requested peace within 5 minutes of each other
    local otherGang = requestingGang == war.attacker and war.defender or war.attacker
    local otherRequest = war.peace_requests[otherGang]
    
    if otherRequest and (os.time() - otherRequest) < 300 then
        -- Both agreed - mutual peace
        return FreeGangs.Server.War.End(warId, nil, 'mutual_peace')
    end
    
    -- Notify other gang
    local requestingData = FreeGangs.Server.Gangs[requestingGang]
    FreeGangs.Bridge.NotifyGang(otherGang, 
        string.format('%s is requesting peace. To accept, your leader must also request peace.', requestingData.label), 
        'info')
    
    return true, 'Peace request sent. The other gang must also request peace within 5 minutes.'
end

---End a war
---@param warId number
---@param winner string|nil Winning gang (nil for draw/mutual peace)
---@param reason string
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.End(warId, winner, reason)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return false, 'War not found'
    end
    
    -- Determine final status
    local status
    if reason == 'mutual_peace' then
        status = FreeGangs.WarStatus.DRAW
    elseif winner == war.attacker then
        status = FreeGangs.WarStatus.ATTACKER_WON
    elseif winner == war.defender then
        status = FreeGangs.WarStatus.DEFENDER_WON
    else
        status = FreeGangs.WarStatus.CANCELLED
    end
    
    -- Calculate collateral distribution
    local totalCollateral = (war.attacker_collateral or 0) + (war.defender_collateral or 0)
    local attackerData = FreeGangs.Server.Gangs[war.attacker]
    local defenderData = FreeGangs.Server.Gangs[war.defender]
    
    if reason == 'mutual_peace' then
        -- Return collateral to each side
        if attackerData then
            attackerData.war_chest = (attackerData.war_chest or 0) + (war.attacker_collateral or 0)
            FreeGangs.Server.Cache.MarkDirty('gang', war.attacker)
        end
        if defenderData then
            defenderData.war_chest = (defenderData.war_chest or 0) + (war.defender_collateral or 0)
            FreeGangs.Server.Cache.MarkDirty('gang', war.defender)
        end
    elseif winner then
        -- Winner takes all
        local winnerData = FreeGangs.Server.Gangs[winner]
        if winnerData then
            winnerData.war_chest = (winnerData.war_chest or 0) + totalCollateral
            FreeGangs.Server.Cache.MarkDirty('gang', winner)
        end
        
        -- Award reputation to winner
        local repGain = FreeGangs.Utils.CalculateActivityPoints(FreeGangs.Activities.WAR_VICTORY, winnerData.archetype)
        if repGain and repGain.masterRep > 0 then
            FreeGangs.Server.Reputation.Add(winner, repGain.masterRep, 'war_victory')
        end
    else
        -- Cancelled - return collateral
        if attackerData and war.attacker_collateral then
            attackerData.war_chest = (attackerData.war_chest or 0) + war.attacker_collateral
            FreeGangs.Server.Cache.MarkDirty('gang', war.attacker)
        end
    end
    
    -- Update war record
    war.status = status
    war.winner = winner
    war.ended_at = os.time()
    
    FreeGangs.Server.DB.UpdateWarStatus(warId, status, winner)
    
    -- Set cooldown
    local cooldownUntil = os.time() + (WAR_COOLDOWN_HOURS * 3600)
    FreeGangs.Server.DB.SetWarCooldown(war.attacker, war.defender, cooldownUntil, reason)
    
    -- Log
    FreeGangs.Server.DB.Log(war.attacker, nil, 'war_ended', FreeGangs.LogCategories.WAR, {
        defender = war.defender,
        winner = winner,
        reason = reason,
        status = status,
        attacker_kills = war.attacker_kills,
        defender_kills = war.defender_kills,
    })
    
    -- Notify both gangs
    local winnerMsg = winner and string.format('%s has won!', FreeGangs.Server.Gangs[winner].label) or 'No winner declared.'
    
    if attackerData then
        FreeGangs.Bridge.NotifyGang(war.attacker, 
            string.format('War with %s has ended! %s', defenderData.label, winnerMsg), 
            winner == war.attacker and 'success' or 'error')
    end
    
    if defenderData then
        FreeGangs.Bridge.NotifyGang(war.defender, 
            string.format('War with %s has ended! %s', attackerData.label, winnerMsg), 
            winner == war.defender and 'success' or 'error')
    end
    
    -- Remove from active wars cache
    FreeGangs.Server.ActiveWars[warId] = nil
    
    -- Sync to clients
    TriggerClientEvent(FreeGangs.Events.Client.UPDATE_WAR, -1, {
        war_id = warId,
        ended = true,
        winner = winner,
        reason = reason,
    })
    
    -- Discord webhook
    local statusLabel = FreeGangs.WarStatusInfo[status] and FreeGangs.WarStatusInfo[status].label or 'Unknown'
    FreeGangs.Server.SendDiscordWebhook('War Ended', string.format(
        'War between **%s** and **%s** has ended!\n**Result:** %s\n**Reason:** %s\nKills: %d - %d',
        attackerData and attackerData.label or war.attacker,
        defenderData and defenderData.label or war.defender,
        statusLabel,
        reason,
        war.attacker_kills or 0,
        war.defender_kills or 0
    ), winner and 65280 or 16776960) -- Green for win, yellow for draw
    
    -- Reduce heat after war
    FreeGangs.Server.Heat.Set(war.attacker, war.defender, 50, 'post_war')
    
    return true, nil
end

-- ============================================================================
-- KILL TRACKING
-- ============================================================================

---Record a kill during war
---@param warId number
---@param killerGang string
---@param killerCitizenId string|nil
---@param victimCitizenId string|nil
function FreeGangs.Server.War.RecordKill(warId, killerGang, killerCitizenId, victimCitizenId)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return
    end
    
    if war.status ~= FreeGangs.WarStatus.ACTIVE then
        return
    end
    
    -- Determine which side got the kill
    local isAttacker = killerGang == war.attacker
    
    if isAttacker then
        war.attacker_kills = (war.attacker_kills or 0) + 1
    else
        war.defender_kills = (war.defender_kills or 0) + 1
    end
    
    -- Update database
    FreeGangs.Server.DB.IncrementWarKills(warId, isAttacker)
    
    -- Log
    FreeGangs.Server.DB.Log(killerGang, killerCitizenId, 'war_kill', FreeGangs.LogCategories.WAR, {
        war_id = warId,
        victim = victimCitizenId,
        attacker_kills = war.attacker_kills,
        defender_kills = war.defender_kills,
    })
    
    -- Notify gangs
    local score = string.format('%d - %d', war.attacker_kills, war.defender_kills)
    FreeGangs.Bridge.NotifyGang(war.attacker, string.format('War kill recorded! Score: %s', score), 'info')
    FreeGangs.Bridge.NotifyGang(war.defender, string.format('War kill recorded! Score: %s', score), 'info')
    
    -- Sync to clients
    FreeGangs.Server.War.SyncToClients(warId)
end

-- ============================================================================
-- WAR QUERIES
-- ============================================================================

---Check if two gangs are at war
---@param gangA string
---@param gangB string
---@return boolean
function FreeGangs.Server.War.IsAtWarWith(gangA, gangB)
    for _, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.status == FreeGangs.WarStatus.ACTIVE then
            if (war.attacker == gangA and war.defender == gangB) or
               (war.attacker == gangB and war.defender == gangA) then
                return true
            end
        end
    end
    return false
end

---Get active war between two gangs
---@param gangA string
---@param gangB string
---@return table|nil war
function FreeGangs.Server.War.GetActive(gangA, gangB)
    for _, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.status == FreeGangs.WarStatus.ACTIVE then
            if (war.attacker == gangA and war.defender == gangB) or
               (war.attacker == gangB and war.defender == gangA) then
                return war
            end
        end
    end
    return nil
end

---Get pending war between two gangs
---@param gangA string
---@param gangB string
---@return table|nil war
function FreeGangs.Server.War.GetPending(gangA, gangB)
    for _, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.status == FreeGangs.WarStatus.PENDING then
            if (war.attacker == gangA and war.defender == gangB) or
               (war.attacker == gangB and war.defender == gangA) then
                return war
            end
        end
    end
    return nil
end

---Get all wars involving a gang
---@param gangName string
---@param includeEnded boolean|nil
---@return table wars
function FreeGangs.Server.War.GetGangWars(gangName, includeEnded)
    local wars = {}
    
    -- Check active wars cache first
    for _, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.attacker == gangName or war.defender == gangName then
            wars[#wars + 1] = war
        end
    end
    
    -- If including ended, fetch from database
    if includeEnded then
        local dbWars = FreeGangs.Server.DB.GetGangWars(gangName)
        for _, war in ipairs(dbWars) do
            -- Avoid duplicates
            local isDuplicate = false
            for _, existing in ipairs(wars) do
                if existing.id == war.id then
                    isDuplicate = true
                    break
                end
            end
            if not isDuplicate then
                wars[#wars + 1] = war
            end
        end
    end
    
    return wars
end

---Get pending war declarations for a gang (as defender)
---@param gangName string
---@return table pendingWars
function FreeGangs.Server.War.GetPendingDeclarations(gangName)
    local pending = {}
    
    for _, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.status == FreeGangs.WarStatus.PENDING and war.defender == gangName then
            pending[#pending + 1] = war
        end
    end
    
    return pending
end

---Get war by ID
---@param warId number
---@return table|nil war
function FreeGangs.Server.War.GetById(warId)
    return FreeGangs.Server.ActiveWars[warId]
end

-- ============================================================================
-- PENDING WAR TIMEOUT
-- ============================================================================

---Schedule auto-cancel for pending war
---@param warId number
function FreeGangs.Server.War.SchedulePendingTimeout(warId)
    local timeoutHours = FreeGangs.Config.War.PendingTimeoutHours or 24
    local timeoutMs = timeoutHours * 60 * 60 * 1000
    
    SetTimeout(timeoutMs, function()
        FreeGangs.Server.War.CheckPendingTimeout(warId)
    end)
end

---Check and handle pending war timeout
---@param warId number
function FreeGangs.Server.War.CheckPendingTimeout(warId)
    local war = FreeGangs.Server.ActiveWars[warId]
    
    if not war then
        return -- Already resolved
    end
    
    if war.status ~= FreeGangs.WarStatus.PENDING then
        return -- No longer pending
    end
    
    -- Auto-forfeit - attacker wins
    FreeGangs.Utils.Log('War ' .. warId .. ' timed out, defender forfeits')
    FreeGangs.Server.War.End(warId, war.attacker, 'timeout_forfeit')
end

-- ============================================================================
-- CLIENT SYNCHRONIZATION
-- ============================================================================

---Sync war data to relevant clients
---@param warId number
function FreeGangs.Server.War.SyncToClients(warId)
    local war = FreeGangs.Server.ActiveWars[warId]
    if not war then return end
    
    local syncData = {
        id = war.id,
        attacker = war.attacker,
        defender = war.defender,
        attacker_collateral = war.attacker_collateral,
        defender_collateral = war.defender_collateral,
        status = war.status,
        attacker_kills = war.attacker_kills,
        defender_kills = war.defender_kills,
        started_at = war.started_at,
    }
    
    -- Get online members of both gangs
    local players = FreeGangs.Bridge.GetPlayers()
    
    for source, player in pairs(players) do
        local playerGang = player.PlayerData.gang and player.PlayerData.gang.name
        if playerGang == war.attacker or playerGang == war.defender then
            TriggerClientEvent(FreeGangs.Events.Client.UPDATE_WAR, source, syncData)
        end
    end
end

---Send full war state to a player
---@param source number
---@param gangName string
function FreeGangs.Server.War.SyncToPlayer(source, gangName)
    local wars = FreeGangs.Server.War.GetGangWars(gangName, false)
    local pending = FreeGangs.Server.War.GetPendingDeclarations(gangName)
    
    TriggerClientEvent(FreeGangs.Events.Client.UPDATE_WAR, source, {
        full_sync = true,
        gang = gangName,
        wars = wars,
        pending = pending,
    })
end

-- ============================================================================
-- ADMIN FUNCTIONS
-- ============================================================================

---Admin force end war
---@param warId number
---@param winner string|nil
---@param adminSource number|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.War.AdminEnd(warId, winner, adminSource)
    local adminName = adminSource == 0 and 'Console' or FreeGangs.Bridge.GetPlayerName(adminSource)
    
    local success, errorMsg = FreeGangs.Server.War.End(warId, winner, 'admin_ended')
    
    if success then
        FreeGangs.Server.DB.Log(nil, nil, 'war_admin_ended', FreeGangs.LogCategories.ADMIN, {
            war_id = warId,
            winner = winner,
            admin = adminName,
        })
    end
    
    return success, errorMsg
end

---Get all active wars (for admin panel)
---@return table wars
function FreeGangs.Server.War.GetAllActive()
    local wars = {}
    
    for id, war in pairs(FreeGangs.Server.ActiveWars) do
        if war.status == FreeGangs.WarStatus.PENDING or war.status == FreeGangs.WarStatus.ACTIVE then
            wars[#wars + 1] = war
        end
    end
    
    return wars
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    -- Force declare war
    RegisterCommand('fg_declarewar', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local attacker = args[1]
        local defender = args[2]
        local collateral = tonumber(args[3]) or 5000
        
        if not attacker or not defender then
            print('[free-gangs:debug] Usage: /fg_declarewar [attacker] [defender] [collateral]')
            return
        end
        
        -- Force heat to 100 for testing
        FreeGangs.Server.Heat.Set(attacker, defender, 100, 'debug')
        
        local warId, errorMsg = FreeGangs.Server.War.Declare(attacker, defender, collateral)
        if warId then
            print('[free-gangs:debug] War declared, ID: ' .. warId)
        else
            print('[free-gangs:debug] Failed: ' .. (errorMsg or 'Unknown error'))
        end
    end, false)
    
    -- Force accept war
    RegisterCommand('fg_acceptwar', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local warId = tonumber(args[1])
        if not warId then
            print('[free-gangs:debug] Usage: /fg_acceptwar [warId]')
            return
        end
        
        local war = FreeGangs.Server.ActiveWars[warId]
        if not war then
            print('[free-gangs:debug] War not found')
            return
        end
        
        local success, errorMsg = FreeGangs.Server.War.Accept(warId, war.defender)
        if success then
            print('[free-gangs:debug] War accepted')
        else
            print('[free-gangs:debug] Failed: ' .. (errorMsg or 'Unknown error'))
        end
    end, false)
    
    -- List active wars
    RegisterCommand('fg_wars', function(source)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        print('[free-gangs:debug] Active Wars:')
        for id, war in pairs(FreeGangs.Server.ActiveWars) do
            print(string.format('  #%d: %s vs %s (%s) - Kills: %d/%d',
                id, war.attacker, war.defender, war.status,
                war.attacker_kills or 0, war.defender_kills or 0))
        end
    end, false)
    
    -- Admin end war
    RegisterCommand('fg_endwar', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local warId = tonumber(args[1])
        local winner = args[2] -- Optional
        
        if not warId then
            print('[free-gangs:debug] Usage: /fg_endwar [warId] [winner]')
            return
        end
        
        local success, errorMsg = FreeGangs.Server.War.AdminEnd(warId, winner, source)
        if success then
            print('[free-gangs:debug] War ended')
        else
            print('[free-gangs:debug] Failed: ' .. (errorMsg or 'Unknown error'))
        end
    end, false)
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('AreGangsAtWar', function(gangA, gangB)
    return FreeGangs.Server.War.IsAtWarWith(gangA, gangB)
end)

exports('DeclareWar', function(attacker, defender, collateral)
    return FreeGangs.Server.War.Declare(attacker, defender, collateral)
end)

exports('GetActiveWar', function(gangA, gangB)
    return FreeGangs.Server.War.GetActive(gangA, gangB)
end)

-- ============================================================================
-- MODULE RETURN
-- ============================================================================

FreeGangs.Utils.Log('War module loaded')

return FreeGangs.Server.War
