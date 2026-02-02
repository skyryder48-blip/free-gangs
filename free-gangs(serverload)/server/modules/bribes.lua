--[[
    FREE-GANGS: Server Bribes Module
    
    Handles all server-side bribery operations including contact management,
    payment processing, ability usage, and maintenance checks.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Bribes = {}

-- Active bribe contacts (per gang)
FreeGangs.Server.ActiveBribes = {}

-- Spawned contact NPCs (for all players to see)
FreeGangs.Server.SpawnedContacts = {}

-- Approach cooldowns { [gangName] = timestamp }
FreeGangs.Server.ApproachCooldowns = {}

-- Pending bribe windows { [gangName_contactType] = { expires = timestamp, contact = type } }
FreeGangs.Server.PendingBribes = {}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the bribery system
function FreeGangs.Server.Bribes.Initialize()
    FreeGangs.Utils.Log('Initializing bribery system...')
    
    -- Load existing bribes from database
    FreeGangs.Server.Bribes.LoadFromDatabase()
    
    -- Start background tasks
    FreeGangs.Server.Bribes.StartPaymentChecker()
    FreeGangs.Server.Bribes.StartContactSpawner()
    
    FreeGangs.Utils.Log('Bribery system initialized')
end

---Load all active bribes from database
function FreeGangs.Server.Bribes.LoadFromDatabase()
    local results = MySQL.query.await([[
        SELECT * FROM freegangs_bribes WHERE status != 'terminated'
    ]])
    
    if not results then return end
    
    for _, row in pairs(results) do
        local gangName = row.gang_name
        FreeGangs.Server.ActiveBribes[gangName] = FreeGangs.Server.ActiveBribes[gangName] or {}
        FreeGangs.Server.ActiveBribes[gangName][row.contact_type] = {
            id = row.id,
            contactType = row.contact_type,
            contactLevel = row.contact_level or 1,
            establishedAt = row.established_at,
            lastPayment = row.last_payment,
            nextPayment = row.next_payment,
            missedPayments = row.missed_payments or 0,
            status = row.status,
            metadata = row.metadata and json.decode(row.metadata) or {},
        }
    end
    
    FreeGangs.Utils.Debug('Loaded bribes for ' .. FreeGangs.Utils.TableLength(FreeGangs.Server.ActiveBribes) .. ' gangs')
end

-- ============================================================================
-- CONTACT SPAWNING
-- ============================================================================

---Start the contact spawner background task
function FreeGangs.Server.Bribes.StartContactSpawner()
    local interval = FreeGangs.Config.BribeContacts.SpawnSettings.spawnCheckInterval * 1000
    
    CreateThread(function()
        while true do
            Wait(interval)
            FreeGangs.Server.Bribes.SpawnContacts()
        end
    end)
end

---Spawn contacts based on current time and schedules
function FreeGangs.Server.Bribes.SpawnContacts()
    local currentHour = GetClockHours()
    local currentDay = FreeGangs.Utils.GetCurrentDay()
    
    for contactType, schedule in pairs(FreeGangs.Config.BribeContacts.Schedules) do
        -- Check if this contact should be active now
        local isActiveTime = FreeGangs.Server.Bribes.IsContactActiveTime(contactType, currentHour, currentDay)
        
        if isActiveTime then
            -- Check if we need to spawn this contact
            local spawned = FreeGangs.Server.SpawnedContacts[contactType]
            if not spawned or (spawned.despawnAt and os.time() > spawned.despawnAt) then
                FreeGangs.Server.Bribes.SpawnContact(contactType)
            end
        else
            -- Despawn if active but shouldn't be
            if FreeGangs.Server.SpawnedContacts[contactType] then
                FreeGangs.Server.Bribes.DespawnContact(contactType)
            end
        end
    end
end

---Check if contact type should be active at current time
---@param contactType string
---@param currentHour number
---@param currentDay string
---@return boolean
function FreeGangs.Server.Bribes.IsContactActiveTime(contactType, currentHour, currentDay)
    local schedule = FreeGangs.Config.BribeContacts.Schedules[contactType]
    if not schedule then return false end
    
    -- Check day
    local dayActive = false
    for _, day in pairs(schedule.daysActive) do
        if string.lower(day) == string.lower(currentDay) then
            dayActive = true
            break
        end
    end
    if not dayActive then return false end
    
    -- Check hour (handle overnight schedules)
    local startHour = schedule.startHour
    local endHour = schedule.endHour
    
    if startHour < endHour then
        -- Same day schedule (e.g., 18:00 - 23:00)
        return currentHour >= startHour and currentHour < endHour
    else
        -- Overnight schedule (e.g., 22:00 - 06:00)
        return currentHour >= startHour or currentHour < endHour
    end
end

---Spawn a specific contact type
---@param contactType string
function FreeGangs.Server.Bribes.SpawnContact(contactType)
    local locations = FreeGangs.Config.BribeContacts.SpawnLocations[contactType]
    if not locations or #locations == 0 then return end
    
    -- Pick random location
    local location = locations[math.random(#locations)]
    
    -- Store spawn info (clients will handle actual NPC creation)
    FreeGangs.Server.SpawnedContacts[contactType] = {
        coords = location.coords,
        pedModel = location.pedModel,
        scenario = location.scenario,
        label = location.label,
        spawnedAt = os.time(),
        despawnAt = os.time() + FreeGangs.Config.BribeContacts.SpawnSettings.contactDuration,
    }
    
    -- Notify all clients about new contact
    TriggerClientEvent('freegangs:client:contactSpawned', -1, contactType, FreeGangs.Server.SpawnedContacts[contactType])
    
    FreeGangs.Utils.Debug('Spawned ' .. contactType .. ' contact at ' .. location.label)
end

---Despawn a contact
---@param contactType string
function FreeGangs.Server.Bribes.DespawnContact(contactType)
    if not FreeGangs.Server.SpawnedContacts[contactType] then return end
    
    FreeGangs.Server.SpawnedContacts[contactType] = nil
    
    -- Notify all clients
    TriggerClientEvent('freegangs:client:contactDespawned', -1, contactType)
    
    FreeGangs.Utils.Debug('Despawned ' .. contactType .. ' contact')
end

---Get all currently spawned contacts
---@return table
function FreeGangs.Server.Bribes.GetSpawnedContacts()
    return FreeGangs.Server.SpawnedContacts
end

-- ============================================================================
-- APPROACH & ESTABLISHMENT
-- ============================================================================

---Attempt to approach a contact
---@param source number Player source
---@param contactType string
---@return boolean success
---@return string|nil error
function FreeGangs.Server.Bribes.Approach(source, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    -- Get player's gang
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false, 'You are not in a gang' end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    -- Check if contact type is spawned
    if not FreeGangs.Server.SpawnedContacts[contactType] then
        return false, 'Contact not available'
    end
    
    -- Check master level requirement
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return false, 'Invalid contact type' end
    
    if gang.master_level < contactInfo.minLevel then
        return false, 'Gang level too low (requires level ' .. contactInfo.minLevel .. ')'
    end
    
    -- Check if gang already has this contact
    if FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType] then
        local bribe = FreeGangs.Server.ActiveBribes[gangName][contactType]
        if bribe.status == 'active' then
            return false, 'You already have this contact'
        end
    end
    
    -- Check approach cooldown
    local cooldownKey = gangName .. '_approach'
    if FreeGangs.Server.ApproachCooldowns[cooldownKey] then
        if os.time() < FreeGangs.Server.ApproachCooldowns[cooldownKey] then
            local remaining = FreeGangs.Server.ApproachCooldowns[cooldownKey] - os.time()
            return false, 'Gang is on approach cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
        end
    end
    
    -- Check for terminated cooldown
    local termCooldownKey = gangName .. '_' .. contactType .. '_terminated'
    if FreeGangs.Server.ApproachCooldowns[termCooldownKey] then
        if os.time() < FreeGangs.Server.ApproachCooldowns[termCooldownKey] then
            local remaining = FreeGangs.Server.ApproachCooldowns[termCooldownKey] - os.time()
            return false, 'Cannot approach this contact yet (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
        end
    end
    
    -- Check rank permission (officers+ only)
    if membership.rank < 2 then
        return false, 'Only officers can establish contacts'
    end
    
    -- Random success chance based on gang level (50% base + 5% per level above requirement)
    local successChance = 0.50 + (gang.master_level - contactInfo.minLevel) * 0.05
    
    -- Crime Family bonus
    if gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        successChance = successChance + 0.20 -- +20% for Crime Families
    end
    
    local roll = math.random()
    
    if roll <= successChance then
        -- Success - open bribe window
        local pendingKey = gangName .. '_' .. contactType
        FreeGangs.Server.PendingBribes[pendingKey] = {
            expires = os.time() + (FreeGangs.Config.Bribes.Approach.BribeWindowMinutes * 60),
            contactType = contactType,
            initiator = citizenid,
        }
        
        FreeGangs.Utils.Debug('Approach success: ' .. gangName .. ' -> ' .. contactType)
        
        -- Log the approach
        FreeGangs.Server.DB.Log(gangName, citizenid, 'bribe_approach_success', FreeGangs.LogCategories.BRIBE, {
            contactType = contactType,
        })
        
        return true, nil
    else
        -- Failure - set cooldown and deduct rep
        local cooldownHours = FreeGangs.Config.Bribes.Approach.FailCooldownHours
        FreeGangs.Server.ApproachCooldowns[cooldownKey] = os.time() + (cooldownHours * 3600)
        
        -- Deduct reputation
        local repLoss = FreeGangs.Config.Bribes.Approach.FailRepLoss
        FreeGangs.Server.Reputation.RemoveReputation(gangName, repLoss, 'Failed bribe approach')
        
        -- Despawn the contact
        FreeGangs.Server.Bribes.DespawnContact(contactType)
        
        FreeGangs.Utils.Debug('Approach failed: ' .. gangName .. ' -> ' .. contactType)
        
        -- Log the failure
        FreeGangs.Server.DB.Log(gangName, citizenid, 'bribe_approach_failed', FreeGangs.LogCategories.BRIBE, {
            contactType = contactType,
            repLoss = repLoss,
            cooldownHours = cooldownHours,
        })
        
        return false, 'The contact rejected your approach. (-' .. repLoss .. ' rep)'
    end
end

---Establish a bribe relationship
---@param source number Player source
---@param gangName string
---@param contactType string
---@return boolean success
---@return string|nil error
function FreeGangs.Server.Bribes.Establish(source, gangName, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    -- Verify pending bribe window
    local pendingKey = gangName .. '_' .. contactType
    local pending = FreeGangs.Server.PendingBribes[pendingKey]
    
    if not pending then
        return false, 'No pending bribe window'
    end
    
    if os.time() > pending.expires then
        FreeGangs.Server.PendingBribes[pendingKey] = nil
        -- Apply timeout penalty
        local repLoss = FreeGangs.Config.Bribes.Approach.TimeoutRepLoss
        FreeGangs.Server.Reputation.RemoveReputation(gangName, repLoss, 'Bribe window expired')
        
        local cooldownHours = FreeGangs.Config.Bribes.Approach.TimeoutCooldownHours
        local termCooldownKey = gangName .. '_' .. contactType .. '_terminated'
        FreeGangs.Server.ApproachCooldowns[termCooldownKey] = os.time() + (cooldownHours * 3600)
        
        return false, 'Bribe window expired (-' .. repLoss .. ' rep)'
    end
    
    -- Get contact info
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Calculate initial payment
    local initialCost = contactInfo.weeklyCost
    if contactInfo.initialBribe then
        initialCost = contactInfo.initialBribe -- City Official special case
    end
    
    -- Apply Crime Family discount
    if gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        local passives = FreeGangs.ArchetypePassiveBonuses[gang.archetype]
        if passives and passives.bribeEffectiveness then
            initialCost = math.floor(initialCost * (1 - passives.bribeEffectiveness))
        end
    end
    
    -- Check treasury
    if (gang.treasury or 0) < initialCost then
        return false, 'Insufficient treasury funds (need ' .. FreeGangs.Utils.FormatMoney(initialCost) .. ')'
    end
    
    -- Deduct from treasury
    gang.treasury = gang.treasury - initialCost
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Calculate next payment date (7 days)
    local nextPayment = os.time() + (7 * 24 * 3600)
    
    -- Insert into database
    local insertId = MySQL.insert.await([[
        INSERT INTO freegangs_bribes (gang_name, contact_type, contact_level, last_payment, next_payment, status, metadata)
        VALUES (?, ?, 1, NOW(), FROM_UNIXTIME(?), 'active', '{}')
    ]], { gangName, contactType, nextPayment })
    
    if not insertId then
        -- Refund treasury
        gang.treasury = gang.treasury + initialCost
        return false, 'Failed to establish bribe'
    end
    
    -- Add to active bribes
    FreeGangs.Server.ActiveBribes[gangName] = FreeGangs.Server.ActiveBribes[gangName] or {}
    FreeGangs.Server.ActiveBribes[gangName][contactType] = {
        id = insertId,
        contactType = contactType,
        contactLevel = 1,
        establishedAt = os.time(),
        lastPayment = os.time(),
        nextPayment = nextPayment,
        missedPayments = 0,
        status = 'active',
        metadata = {},
    }
    
    -- Clear pending window
    FreeGangs.Server.PendingBribes[pendingKey] = nil
    
    -- Add reputation
    FreeGangs.Server.Reputation.AddReputation(gangName, 25, 'Established bribe contact')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'bribe_established', FreeGangs.LogCategories.BRIBE, {
        contactType = contactType,
        cost = initialCost,
    })
    
    -- Notify gang members
    FreeGangs.Server.NotifyGangOnline(gangName, string.format(
        FreeGangs.Locale('bribes.established'),
        FreeGangs.Locale('bribes.contacts.' .. contactType)
    ), 'success')
    
    FreeGangs.Utils.Log(gangName .. ' established ' .. contactType .. ' bribe')
    
    return true
end

-- ============================================================================
-- PAYMENT MANAGEMENT
-- ============================================================================

---Start the payment checker background task
function FreeGangs.Server.Bribes.StartPaymentChecker()
    CreateThread(function()
        while true do
            Wait(60000) -- Check every minute
            FreeGangs.Server.Bribes.CheckPayments()
        end
    end)
end

---Check all bribes for due/overdue payments
function FreeGangs.Server.Bribes.CheckPayments()
    local now = os.time()
    local reminderHours = FreeGangs.Config.BribeContacts.PaymentReminders.reminderHours
    
    for gangName, bribes in pairs(FreeGangs.Server.ActiveBribes) do
        for contactType, bribe in pairs(bribes) do
            if bribe.status ~= 'terminated' and bribe.nextPayment then
                local timeUntilDue = bribe.nextPayment - now
                local hoursUntilDue = timeUntilDue / 3600
                
                -- Check for reminders
                for _, reminderHour in pairs(reminderHours) do
                    -- Send reminder if within hour window (with 5 minute tolerance)
                    if hoursUntilDue > 0 and hoursUntilDue <= reminderHour and hoursUntilDue > (reminderHour - 0.1) then
                        FreeGangs.Server.NotifyGangOfficers(gangName, string.format(
                            FreeGangs.Locale('bribes.payment_due'),
                            FreeGangs.Locale('bribes.contacts.' .. contactType),
                            math.ceil(hoursUntilDue)
                        ), 'warning')
                        break
                    end
                end
                
                -- Check for missed payment
                if timeUntilDue < 0 then
                    FreeGangs.Server.Bribes.HandleMissedPayment(gangName, contactType)
                end
            end
        end
    end
end

---Handle a missed payment
---@param gangName string
---@param contactType string
function FreeGangs.Server.Bribes.HandleMissedPayment(gangName, contactType)
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    if not bribe then return end
    
    bribe.missedPayments = (bribe.missedPayments or 0) + 1
    
    local penalties = FreeGangs.Config.BribeContacts.PaymentReminders.penalties
    
    if bribe.missedPayments == 1 then
        -- First miss: pause and increase cost
        bribe.status = 'paused'
        bribe.metadata.costMultiplier = 1 + (penalties.firstMiss.costIncrease or 0.50)
        
        -- Update database
        MySQL.update([[
            UPDATE freegangs_bribes 
            SET status = 'paused', missed_payments = ?, metadata = ?
            WHERE gang_name = ? AND contact_type = ?
        ]], { bribe.missedPayments, json.encode(bribe.metadata), gangName, contactType })
        
        FreeGangs.Server.NotifyGangOfficers(gangName, string.format(
            'Missed payment to %s! Effects paused, next payment +50%% cost.',
            FreeGangs.Locale('bribes.contacts.' .. contactType)
        ), 'error')
        
        -- Set next payment to 24 hours from now
        bribe.nextPayment = os.time() + (24 * 3600)
        
    elseif bribe.missedPayments >= 2 then
        -- Second miss: terminate
        FreeGangs.Server.Bribes.Terminate(gangName, contactType, 'missed_payments')
    end
    
    FreeGangs.Server.DB.Log(gangName, nil, 'bribe_payment_missed', FreeGangs.LogCategories.BRIBE, {
        contactType = contactType,
        missedCount = bribe.missedPayments,
    })
end

---Make a bribe payment
---@param source number Player source
---@param gangName string
---@param contactType string
---@return boolean success
---@return string|nil error
function FreeGangs.Server.Bribes.MakePayment(source, gangName, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    if not bribe then return false, 'Bribe not found' end
    
    if bribe.status == 'terminated' then
        return false, 'This contact has been terminated'
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    -- Calculate payment amount
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local baseCost = contactInfo.weeklyCost
    
    -- City Official maintenance is 25% of initial
    if contactType == FreeGangs.BribeContacts.CITY_OFFICIAL then
        baseCost = math.floor(contactInfo.initialBribe * 0.25)
        
        -- Crime Family reduced maintenance
        if gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
            baseCost = math.floor(contactInfo.initialBribe * 0.10)
        end
    end
    
    -- Apply multiplier from missed payments
    local multiplier = bribe.metadata.costMultiplier or 1.0
    
    -- Apply heat multiplier
    local maxHeat = FreeGangs.Server.Bribes.GetGangMaxHeat(gangName)
    if maxHeat >= 90 then
        multiplier = multiplier + 1.0 -- +100%
    end
    
    local paymentAmount = math.floor(baseCost * multiplier)
    
    -- Check treasury
    if (gang.treasury or 0) < paymentAmount then
        return false, 'Insufficient treasury funds (need ' .. FreeGangs.Utils.FormatMoney(paymentAmount) .. ')'
    end
    
    -- Deduct from treasury
    gang.treasury = gang.treasury - paymentAmount
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Calculate payment interval based on heat
    local paymentIntervalDays = 7
    if maxHeat >= 75 then
        paymentIntervalDays = 3
    elseif maxHeat >= 50 then
        paymentIntervalDays = 5
    end
    
    -- Update bribe status
    bribe.lastPayment = os.time()
    bribe.nextPayment = os.time() + (paymentIntervalDays * 24 * 3600)
    bribe.status = 'active'
    bribe.metadata.costMultiplier = 1.0 -- Reset multiplier
    
    -- Update database
    MySQL.update([[
        UPDATE freegangs_bribes 
        SET last_payment = NOW(), next_payment = FROM_UNIXTIME(?), status = 'active', missed_payments = 0, metadata = ?
        WHERE gang_name = ? AND contact_type = ?
    ]], { bribe.nextPayment, json.encode(bribe.metadata), gangName, contactType })
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'bribe_payment', FreeGangs.LogCategories.BRIBE, {
        contactType = contactType,
        amount = paymentAmount,
        nextPaymentDays = paymentIntervalDays,
    })
    
    FreeGangs.Bridge.Notify(source, string.format(
        FreeGangs.Locale('bribes.payment_made'),
        FreeGangs.Locale('bribes.contacts.' .. contactType)
    ), 'success')
    
    return true
end

---Terminate a bribe relationship
---@param gangName string
---@param contactType string
---@param reason string
function FreeGangs.Server.Bribes.Terminate(gangName, contactType, reason)
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    if not bribe then return end
    
    bribe.status = 'terminated'
    
    -- Update database
    MySQL.update([[
        UPDATE freegangs_bribes SET status = 'terminated' WHERE gang_name = ? AND contact_type = ?
    ]], { gangName, contactType })
    
    -- Apply penalties
    local penalties = FreeGangs.Config.BribeContacts.PaymentReminders.penalties.secondMiss
    
    if reason == 'missed_payments' then
        -- Rep loss
        FreeGangs.Server.Reputation.RemoveReputation(gangName, penalties.repLoss, 'Lost bribe contact')
        
        -- Set cooldown
        local termCooldownKey = gangName .. '_' .. contactType .. '_terminated'
        FreeGangs.Server.ApproachCooldowns[termCooldownKey] = os.time() + (penalties.cooldownHours * 3600)
    end
    
    -- Remove from active bribes
    FreeGangs.Server.ActiveBribes[gangName][contactType] = nil
    
    -- Notify gang
    FreeGangs.Server.NotifyGangOnline(gangName, string.format(
        FreeGangs.Locale('bribes.terminated'),
        FreeGangs.Locale('bribes.contacts.' .. contactType)
    ), 'error')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, nil, 'bribe_terminated', FreeGangs.LogCategories.BRIBE, {
        contactType = contactType,
        reason = reason,
    })
    
    FreeGangs.Utils.Log(gangName .. ' lost ' .. contactType .. ' contact (' .. reason .. ')')
end

-- ============================================================================
-- ABILITY USAGE
-- ============================================================================

---Use a bribe ability
---@param source number Player source
---@param contactType string
---@param abilityName string
---@param params table Additional parameters
---@return boolean success
---@return any result
function FreeGangs.Server.Bribes.UseAbility(source, contactType, abilityName, params)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false, 'Not in a gang' end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Check if bribe is active
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    if not bribe or bribe.status ~= 'active' then
        return false, 'Bribe contact not active'
    end
    
    -- Check permission
    if not FreeGangs.Server.HasPermission(citizenid, gangName, FreeGangs.Permissions.USE_BRIBES) then
        return false, 'No permission to use bribes'
    end
    
    -- Get ability config
    local abilities = FreeGangs.Config.BribeContacts.Abilities[contactType]
    if not abilities then return false, 'Invalid contact type' end
    
    -- Handle different abilities
    local result, err = FreeGangs.Server.Bribes.ExecuteAbility(source, gangName, gang, contactType, abilityName, params)
    
    if result then
        -- Add heat
        local contactInfo = FreeGangs.BribeContactInfo[contactType]
        if contactInfo and contactInfo.heatPerUse > 0 then
            -- Add heat with rival gangs in the area
            local rivals = FreeGangs.Server.Heat.GetRivals(gangName)
            for _, rivalGang in ipairs(rivals) do
                FreeGangs.Server.Heat.Add(gangName, rivalGang, contactInfo.heatPerUse, 'bribe_use')
            end
        end
        
        -- Log usage
        FreeGangs.Server.DB.Log(gangName, citizenid, 'bribe_ability_used', FreeGangs.LogCategories.BRIBE, {
            contactType = contactType,
            ability = abilityName,
            params = params,
        })
    end
    
    return result, err
end

---Execute a specific ability
---@param source number
---@param gangName string
---@param gang table
---@param contactType string
---@param abilityName string
---@param params table
---@return boolean, any
function FreeGangs.Server.Bribes.ExecuteAbility(source, gangName, gang, contactType, abilityName, params)
    local abilities = FreeGangs.Config.BribeContacts.Abilities[contactType]
    
    if contactType == FreeGangs.BribeContacts.DISPATCHER and abilityName == 'redirect' then
        return FreeGangs.Server.Bribes.AbilityDispatchRedirect(source, gangName, gang)
        
    elseif contactType == FreeGangs.BribeContacts.DETECTIVE and abilityName == 'exchange' then
        return FreeGangs.Server.Bribes.AbilityDetectiveExchange(source, gangName, gang)
        
    elseif contactType == FreeGangs.BribeContacts.JUDGE then
        if abilityName == 'reduce_sentence' then
            return FreeGangs.Server.Bribes.AbilityReduceSentence(source, gangName, gang, params)
        elseif abilityName == 'release' then
            return FreeGangs.Server.Bribes.AbilityImmediateRelease(source, gangName, gang, params)
        end
        
    elseif contactType == FreeGangs.BribeContacts.PRISON_GUARD then
        if abilityName == 'contraband' then
            return FreeGangs.Server.Bribes.AbilityContrabandDelivery(source, gangName, gang, params)
        elseif abilityName == 'escape' then
            return FreeGangs.Server.Bribes.AbilityHelpEscape(source, gangName, gang, params)
        end
        
    elseif contactType == FreeGangs.BribeContacts.CITY_OFFICIAL and abilityName == 'kickback' then
        return FreeGangs.Server.Bribes.AbilityCollectKickback(source, gangName, gang)
    end
    
    return false, 'Unknown ability'
end

-- ============================================================================
-- SPECIFIC ABILITY IMPLEMENTATIONS
-- ============================================================================

---Dispatcher redirect ability
function FreeGangs.Server.Bribes.AbilityDispatchRedirect(source, gangName, gang)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.DISPATCHER].active
    
    -- Check master level
    if gang.master_level < (config.requiredLevel or 5) then
        return false, 'Requires gang level ' .. config.requiredLevel
    end
    
    -- Check cooldown
    local cooldownKey = gangName .. '_dispatch_redirect'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'On cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Check treasury
    local cost = config.cost or 2000
    if (gang.treasury or 0) < cost then
        return false, 'Insufficient treasury funds'
    end
    
    -- Deduct cost
    gang.treasury = gang.treasury - cost
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldownSeconds)
    
    -- Trigger dispatch redirect effect
    TriggerEvent('freegangs:server:dispatchRedirected', gangName, source)
    
    FreeGangs.Bridge.Notify(source, FreeGangs.Locale('bribes.dispatch_redirected'), 'success')
    
    return true, { cost = cost }
end

---Detective evidence exchange
function FreeGangs.Server.Bribes.AbilityDetectiveExchange(source, gangName, gang)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.DETECTIVE].active
    
    -- Check cooldown
    local cooldownKey = gangName .. '_detective_exchange'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'On cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Roll loot
    local loot = {}
    for _, item in pairs(config.lootTable) do
        if math.random(100) <= item.chance then
            local amount = math.random(item.min, item.max)
            loot[#loot + 1] = { item = item.item, amount = amount }
            FreeGangs.Bridge.AddItem(source, item.item, amount)
        end
    end
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldownSeconds)
    
    FreeGangs.Bridge.Notify(source, 'Evidence exchange complete', 'success')
    
    return true, { loot = loot }
end

---Judge reduce sentence
function FreeGangs.Server.Bribes.AbilityReduceSentence(source, gangName, gang, params)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.JUDGE].active.options.reduce_sentence
    
    local targetCitizenid = params.targetCitizenid
    local minutesToReduce = params.minutes or 5
    
    if not targetCitizenid then
        return false, 'Target player not specified'
    end
    
    -- Calculate cost
    local cost = minutesToReduce * config.costPerMinute
    
    -- Check treasury
    if (gang.treasury or 0) < cost then
        return false, 'Insufficient treasury funds (need ' .. FreeGangs.Utils.FormatMoney(cost) .. ')'
    end
    
    -- Deduct cost
    gang.treasury = gang.treasury - cost
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Reduce sentence via Prison module
    TriggerEvent('freegangs:server:reduceSentence', targetCitizenid, minutesToReduce)
    FreeGangs.Server.Prison.AddInfluence(gangName, 1, 'Bribe: sentence reduction')
    
    FreeGangs.Bridge.Notify(source, string.format(FreeGangs.Locale('bribes.sentence_reduced'), minutesToReduce), 'success')
    
    return true, { cost = cost, reduced = minutesToReduce }
end

---Judge immediate release
function FreeGangs.Server.Bribes.AbilityImmediateRelease(source, gangName, gang, params)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.JUDGE].active.options.immediate_release
    
    local targetCitizenid = params.targetCitizenid
    if not targetCitizenid then
        return false, 'Target player not specified'
    end
    
    -- Check cooldown
    local cooldownKey = gangName .. '_judge_release'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'On cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Check treasury
    local cost = config.cost
    if (gang.treasury or 0) < cost then
        return false, 'Insufficient treasury funds (need ' .. FreeGangs.Utils.FormatMoney(cost) .. ')'
    end
    
    -- Deduct cost
    gang.treasury = gang.treasury - cost
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldownSeconds)
    
    -- Release prisoner via Prison module
    TriggerEvent('freegangs:server:releasePrisoner', targetCitizenid)
    FreeGangs.Server.Prison.UnregisterJailedMember(targetCitizenid, gangName)
    FreeGangs.Server.Prison.AddInfluence(gangName, 2, 'Bribe: prisoner release')
    
    FreeGangs.Bridge.Notify(source, FreeGangs.Locale('bribes.prisoner_released'), 'success')
    
    return true, { cost = cost }
end

---Prison guard contraband delivery
function FreeGangs.Server.Bribes.AbilityContrabandDelivery(source, gangName, gang, params)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.PRISON_GUARD].active.options.contraband_delivery
    
    local targetCitizenid = params.targetCitizenid
    local items = params.items
    
    if not targetCitizenid or not items then
        return false, 'Target and items required'
    end
    
    -- Check cooldown
    local cooldownKey = gangName .. '_contraband'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'On cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Check prison control for free delivery
    local prisonControl = FreeGangs.Server.Bribes.GetPrisonControl(gangName)
    local cost = config.cost
    
    if prisonControl >= 50 then
        cost = 0 -- Free with 50%+ prison control
    end
    
    -- Check treasury
    if cost > 0 and (gang.treasury or 0) < cost then
        return false, 'Insufficient treasury funds'
    end
    
    -- Verify items are allowed
    for _, item in pairs(items) do
        local allowed = false
        for _, allowedItem in pairs(config.allowedItems) do
            if item.name == allowedItem then
                allowed = true
                break
            end
        end
        if not allowed then
            return false, 'Item not allowed: ' .. item.name
        end
        
        -- Check player has the item
        if not FreeGangs.Bridge.HasItem(source, item.name, item.amount or 1) then
            return false, 'You don\'t have ' .. item.name
        end
    end
    
    -- Remove items from player
    for _, item in pairs(items) do
        FreeGangs.Bridge.RemoveItem(source, item.name, item.amount or 1)
    end
    
    -- Deduct cost
    if cost > 0 then
        gang.treasury = gang.treasury - cost
        FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    end
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldownSeconds)
    
    -- Deliver contraband via Prison module
    FreeGangs.Server.Prison.DeliverContraband(source, targetCitizenid, items)
    
    FreeGangs.Bridge.Notify(source, FreeGangs.Locale('bribes.contraband_delivered'), 'success')
    
    return true, { cost = cost, items = items }
end

---Prison guard help escape
function FreeGangs.Server.Bribes.AbilityHelpEscape(source, gangName, gang, params)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.PRISON_GUARD].active.options.help_escape
    
    local targetCitizenid = params.targetCitizenid
    if not targetCitizenid then
        return false, 'Target player not specified'
    end
    
    -- Check cooldown
    local cooldownKey = gangName .. '_escape'
    if FreeGangs.Server.IsOnCooldown(source, cooldownKey) then
        local _, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
        return false, 'On cooldown (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Check prison control for reduced cost
    local prisonControl = FreeGangs.Server.Bribes.GetPrisonControl(gangName)
    local cost = config.cost
    
    local bonuses = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.PRISON_GUARD].active.prisonControlBonuses
    if prisonControl >= 75 and bonuses[75] then
        cost = bonuses[75].reducedEscapeCost or cost
    end
    
    -- Check treasury
    if (gang.treasury or 0) < cost then
        return false, 'Insufficient treasury funds (need ' .. FreeGangs.Utils.FormatMoney(cost) .. ')'
    end
    
    -- Deduct cost
    gang.treasury = gang.treasury - cost
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldownSeconds)
    
    -- Help escape via Prison module
    FreeGangs.Server.Prison.HelpEscape(source, targetCitizenid)
    
    return true, { cost = cost }
end

---City official kickback collection
function FreeGangs.Server.Bribes.AbilityCollectKickback(source, gangName, gang)
    local config = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.CITY_OFFICIAL].passive
    
    -- Check if kickback is available (every 2 hours)
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][FreeGangs.BribeContacts.CITY_OFFICIAL]
    if not bribe then return false, 'No city official contact' end
    
    local lastKickback = bribe.metadata.lastKickback or 0
    local timeSinceKickback = os.time() - lastKickback
    
    if timeSinceKickback < config.intervalSeconds then
        local remaining = config.intervalSeconds - timeSinceKickback
        return false, 'Kickback not ready (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')'
    end
    
    -- Calculate kickback amount
    local payoutRange = config.payoutRanges[gang.archetype] or config.payoutRanges[FreeGangs.Archetypes.STREET]
    local baseAmount = math.random(payoutRange.min, payoutRange.max)
    local finalAmount = math.floor(baseAmount * payoutRange.multiplier)
    
    -- Add to treasury
    gang.treasury = (gang.treasury or 0) + finalAmount
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Update last kickback time
    bribe.metadata.lastKickback = os.time()
    MySQL.update([[
        UPDATE freegangs_bribes SET metadata = ? WHERE gang_name = ? AND contact_type = ?
    ]], { json.encode(bribe.metadata), gangName, FreeGangs.BribeContacts.CITY_OFFICIAL })
    
    FreeGangs.Bridge.Notify(source, 'Received kickback: ' .. FreeGangs.Utils.FormatMoney(finalAmount), 'success')
    
    return true, { amount = finalAmount }
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get gang's bribes for client display
---@param gangName string
---@return table
function FreeGangs.Server.Bribes.GetGangBribes(gangName)
    local bribes = FreeGangs.Server.ActiveBribes[gangName] or {}
    local result = {}
    
    for contactType, bribe in pairs(bribes) do
        if bribe.status ~= 'terminated' then
            result[contactType] = {
                contactType = contactType,
                contactLevel = bribe.contactLevel,
                status = bribe.status,
                nextPayment = bribe.nextPayment,
                missedPayments = bribe.missedPayments,
            }
        end
    end
    
    return result
end

---Check if gang has active bribe of type
---@param gangName string
---@param contactType string
---@return boolean
function FreeGangs.Server.Bribes.HasActiveBribe(gangName, contactType)
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    return bribe and bribe.status == 'active'
end

---Get gang's maximum heat with any other gang
---@param gangName string
---@return number
function FreeGangs.Server.Bribes.GetGangMaxHeat(gangName)
    local records = FreeGangs.Server.Heat.GetGangHeat(gangName)
    if records and #records > 0 then
        return records[1].heat_level -- Already sorted descending
    end
    return 0
end

---Get gang's prison control percentage
---@param gangName string
---@return number
function FreeGangs.Server.Bribes.GetPrisonControl(gangName)
    return FreeGangs.Server.Prison.GetControlLevel(gangName)
end

---Get bribe cost for display (with all modifiers)
---@param gangName string
---@param contactType string
---@return number
function FreeGangs.Server.Bribes.GetDisplayCost(gangName, contactType)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return 0 end
    
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return 0 end
    
    return FreeGangs.Utils.CalculateBribeCost(contactType, gang.archetype, FreeGangs.Server.Bribes.GetGangMaxHeat(gangName))
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    RegisterCommand('fg_spawncontact', function(source, args)
        if not FreeGangs.Server.IsAdmin(source) then return end
        
        local contactType = args[1]
        if not contactType or not FreeGangs.BribeContactInfo[contactType] then
            FreeGangs.Bridge.Notify(source, 'Usage: /fg_spawncontact [contact_type]', 'error')
            return
        end
        
        FreeGangs.Server.Bribes.SpawnContact(contactType)
        FreeGangs.Bridge.Notify(source, 'Spawned ' .. contactType .. ' contact', 'success')
    end, true)
    
    RegisterCommand('fg_establishbribe', function(source, args)
        if not FreeGangs.Server.IsAdmin(source) then return end
        
        local contactType = args[1]
        local citizenid = FreeGangs.Bridge.GetCitizenId(source)
        local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
        
        if not membership then
            FreeGangs.Bridge.Notify(source, 'Not in a gang', 'error')
            return
        end
        
        -- Force establish without approach
        local gangName = membership.gang_name
        local pendingKey = gangName .. '_' .. contactType
        FreeGangs.Server.PendingBribes[pendingKey] = {
            expires = os.time() + 600,
            contactType = contactType,
            initiator = citizenid,
        }
        
        local success, err = FreeGangs.Server.Bribes.Establish(source, gangName, contactType)
        if not success then
            FreeGangs.Bridge.Notify(source, err, 'error')
        end
    end, true)
    
    RegisterCommand('fg_bribeuse', function(source, args)
        if not FreeGangs.Server.IsAdmin(source) then return end
        
        local contactType = args[1]
        local ability = args[2]
        
        local success, result = FreeGangs.Server.Bribes.UseAbility(source, contactType, ability, {})
        if success then
            FreeGangs.Bridge.Notify(source, 'Ability used: ' .. json.encode(result), 'success')
        else
            FreeGangs.Bridge.Notify(source, result, 'error')
        end
    end, true)
end

return FreeGangs.Server.Bribes
