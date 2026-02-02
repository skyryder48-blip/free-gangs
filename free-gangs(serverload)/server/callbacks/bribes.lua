--[[
    FREE-GANGS: Server Bribe Callbacks
    
    Registers all lib.callback handlers for bribe-related operations.
    These callbacks are called from the client to perform server-side actions.
]]

-- ============================================================================
-- DATA RETRIEVAL CALLBACKS
-- ============================================================================

---Get all currently spawned contacts
lib.callback.register('freegangs:getSpawnedContacts', function(source)
    return FreeGangs.Server.Bribes.GetSpawnedContacts()
end)

---Get gang's bribe data
lib.callback.register('freegangs:bribes:getGangBribes', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return {} end
    
    return FreeGangs.Server.Bribes.GetGangBribes(membership.gang_name)
end)

---Get payment info for a contact
lib.callback.register('freegangs:bribes:getPaymentInfo', function(source, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return nil end
    
    local gangName = membership.gang_name
    local bribe = FreeGangs.Server.ActiveBribes[gangName] and FreeGangs.Server.ActiveBribes[gangName][contactType]
    
    if not bribe then return nil end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    
    -- Calculate payment amount with modifiers
    local baseCost = contactInfo.weeklyCost
    
    -- City Official maintenance
    if contactType == FreeGangs.BribeContacts.CITY_OFFICIAL then
        baseCost = math.floor(contactInfo.initialBribe * 0.25)
        if gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
            baseCost = math.floor(contactInfo.initialBribe * 0.10)
        end
    end
    
    -- Apply multiplier from missed payments
    local multiplier = bribe.metadata.costMultiplier or 1.0
    
    -- Apply heat multiplier
    local maxHeat = FreeGangs.Server.Bribes.GetGangMaxHeat(gangName)
    if maxHeat >= 90 then
        multiplier = multiplier + 1.0
    end
    
    local amount = math.floor(baseCost * multiplier)
    
    -- Calculate next due date
    local nextDue = nil
    if bribe.nextPayment then
        local timeUntil = bribe.nextPayment - os.time()
        if timeUntil > 0 then
            nextDue = FreeGangs.Utils.FormatDuration(timeUntil * 1000)
        else
            nextDue = 'Overdue!'
        end
    end
    
    return {
        amount = amount,
        nextDue = nextDue,
        status = bribe.status,
        missedPayments = bribe.missedPayments,
    }
end)

---Get list of jailed gang members
lib.callback.register('freegangs:bribes:getJailedMembers', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return {} end
    
    local gangName = membership.gang_name
    local members = FreeGangs.Server.DB.GetGangMembers(gangName)
    
    local jailed = {}
    
    -- Get jailed members from Prison module
    local jailedCitizenIds = FreeGangs.Server.Prison.GetJailedMembers(gangName)
    local jailedLookup = {}
    for _, cid in ipairs(jailedCitizenIds) do
        jailedLookup[cid] = true
    end

    for _, member in pairs(members) do
        local player = FreeGangs.Bridge.GetPlayerByCitizenId(member.citizenid)
        if player then
            local isJailed = jailedLookup[member.citizenid] or false
            local timeRemaining = '0 min'

            if isJailed then
                jailed[#jailed + 1] = {
                    citizenid = member.citizenid,
                    name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                    timeRemaining = timeRemaining,
                }
            end
        end
    end
    
    return jailed
end)

---Check if gang can access a specific contact type
lib.callback.register('freegangs:bribes:canAccess', function(source, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then return false end
    
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return false end
    
    return gang.master_level >= contactInfo.minLevel
end)

-- ============================================================================
-- ACTION CALLBACKS
-- ============================================================================

---Approach a contact
lib.callback.register('freegangs:bribes:approach', function(source, contactType)
    return FreeGangs.Server.Bribes.Approach(source, contactType)
end)

---Establish a bribe relationship
lib.callback.register('freegangs:bribes:establish', function(source, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false, 'Not in a gang' end
    
    return FreeGangs.Server.Bribes.Establish(source, membership.gang_name, contactType)
end)

---Make a payment
lib.callback.register('freegangs:bribes:makePayment', function(source, contactType)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Player not found' end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false, 'Not in a gang' end
    
    return FreeGangs.Server.Bribes.MakePayment(source, membership.gang_name, contactType)
end)

---Use a bribe ability
lib.callback.register('freegangs:bribes:useAbility', function(source, contactType, abilityName, params)
    return FreeGangs.Server.Bribes.UseAbility(source, contactType, abilityName, params or {})
end)

-- ============================================================================
-- PASSIVE EFFECT CALLBACKS
-- ============================================================================

---Check if dispatch should be blocked (for integration with dispatch systems)
lib.callback.register('freegangs:bribes:shouldBlockDispatch', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local gangName = membership.gang_name
    
    -- Check if has Beat Cop bribe
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.BEAT_COP) then
        return false
    end
    
    -- Check zone control (>50% required)
    local control = FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)

    return control >= 50
end)

---Get dispatch delay for a zone (for integration with dispatch systems)
lib.callback.register('freegangs:bribes:getDispatchDelay', function(source, zoneName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    local gangName = membership.gang_name
    
    -- Check if has Dispatcher bribe
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.DISPATCHER) then
        return 0
    end
    
    -- Check zone control (>50% required)
    local control = FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)

    if control >= 50 then
        return 60 -- 60 second delay
    end
    
    return 0
end)

---Get sentence modifier for a player (for integration with jail systems)
lib.callback.register('freegangs:bribes:getSentenceModifier', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 1.0 end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 1.0 end
    
    local gangName = membership.gang_name
    
    -- Check if has Judge bribe
    if FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.JUDGE) then
        return 0.70 -- -30% sentence
    end
    
    return 1.0
end)

---Get arms trafficking discount (for integration with arms systems)
lib.callback.register('freegangs:bribes:getArmsDiscount', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end
    
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Check if has Customs bribe
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.CUSTOMS) then
        return 0
    end
    
    -- Get discount based on master level
    local abilities = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.CUSTOMS]
    if not abilities or not abilities.active then return 0 end
    
    local discounts = abilities.active.discountByLevel
    local discount = 0
    
    for level, disc in pairs(discounts) do
        if gang.master_level >= level and disc > discount then
            discount = disc
        end
    end
    
    return discount
end)

-- ============================================================================
-- ADMIN CALLBACKS
-- ============================================================================

---Admin: Get all active bribes for display
lib.callback.register('freegangs:admin:getAllBribes', function(source)
    if not FreeGangs.Server.IsAdmin(source) then
        return {}
    end
    
    local allBribes = {}
    
    for gangName, bribes in pairs(FreeGangs.Server.ActiveBribes) do
        for contactType, bribe in pairs(bribes) do
            allBribes[#allBribes + 1] = {
                gangName = gangName,
                contactType = contactType,
                status = bribe.status,
                establishedAt = bribe.establishedAt,
                nextPayment = bribe.nextPayment,
                missedPayments = bribe.missedPayments,
            }
        end
    end
    
    return allBribes
end)

---Admin: Force establish bribe for gang
lib.callback.register('freegangs:admin:forceEstablishBribe', function(source, gangName, contactType)
    if not FreeGangs.Server.IsAdmin(source) then
        return false, 'No permission'
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    -- Create pending window
    local pendingKey = gangName .. '_' .. contactType
    FreeGangs.Server.PendingBribes[pendingKey] = {
        expires = os.time() + 600,
        contactType = contactType,
        initiator = 'admin',
    }
    
    return FreeGangs.Server.Bribes.Establish(source, gangName, contactType)
end)

---Admin: Terminate bribe for gang
lib.callback.register('freegangs:admin:terminateBribe', function(source, gangName, contactType)
    if not FreeGangs.Server.IsAdmin(source) then
        return false, 'No permission'
    end
    
    FreeGangs.Server.Bribes.Terminate(gangName, contactType, 'admin_action')
    return true
end)

-- ============================================================================
-- EXPORT FUNCTIONS (For other resources to use)
-- ============================================================================

-- Check if gang has active bribe
exports('HasActiveBribe', function(gangName, contactType)
    return FreeGangs.Server.Bribes.HasActiveBribe(gangName, contactType)
end)

-- Get gang's bribes
exports('GetGangBribes', function(gangName)
    return FreeGangs.Server.Bribes.GetGangBribes(gangName)
end)

-- Get sentence modifier for player
exports('GetSentenceModifier', function(citizenid)
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 1.0 end
    
    local gangName = membership.gang_name
    
    if FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.JUDGE) then
        return 0.70
    end
    
    return 1.0
end)

-- Check dispatch block
exports('ShouldBlockDispatch', function(citizenid, zoneName)
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local gangName = membership.gang_name
    
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.BEAT_COP) then
        return false
    end
    
    -- Check zone control
    local control = 0
    if FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName] then
        local influence = FreeGangs.Server.Territories[zoneName].influence
        control = influence and influence[gangName] or 0
    end
    
    return control >= 50
end)

-- Get dispatch delay
exports('GetDispatchDelay', function(citizenid, zoneName)
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    local gangName = membership.gang_name
    
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.DISPATCHER) then
        return 0
    end
    
    -- Check zone control
    local control = 0
    if FreeGangs.Server.Territories and FreeGangs.Server.Territories[zoneName] then
        local influence = FreeGangs.Server.Territories[zoneName].influence
        control = influence and influence[gangName] or 0
    end
    
    if control >= 50 then
        return 60
    end
    
    return 0
end)

-- Get arms discount
exports('GetArmsDiscount', function(citizenid)
    local membership = FreeGangs.Server.GetPlayerMembership(citizenid)
    if not membership then return 0 end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    if not FreeGangs.Server.Bribes.HasActiveBribe(gangName, FreeGangs.BribeContacts.CUSTOMS) then
        return 0
    end
    
    local abilities = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.CUSTOMS]
    if not abilities or not abilities.active then return 0 end
    
    local discounts = abilities.active.discountByLevel
    local discount = 0
    
    for level, disc in pairs(discounts) do
        if gang.master_level >= level and disc > discount then
            discount = disc
        end
    end
    
    return discount
end)

FreeGangs.Utils.Log('Bribe callbacks registered')
