--[[
    FREE-GANGS: Server Activities Callbacks
    
    Registers all ox_lib callbacks for criminal activities.
    These provide validated server responses to client requests.
]]

-- ============================================================================
-- ACTIVITY VALIDATION CALLBACKS
-- ============================================================================

---Check if player can perform an activity
lib.callback.register(FreeGangs.Callbacks.CAN_PERFORM_ACTIVITY, function(source, activity, data)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded')
    end
    
    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang')
    end
    
    if activity == 'mugging' then
        -- Check cooldown
        local cooldownRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'mugging')
        if cooldownRemaining > 0 then
            return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(cooldownRemaining * 1000))
        end
        return true
        
    elseif activity == 'pickpocket' then
        -- No player cooldown for pickpocketing, only NPC cooldown (validated on completion)
        return true
        
    elseif activity == 'drug_sale' then
        -- Check time restriction using server-side game time (don't trust client)
        local gameHour = GetClockHours and GetClockHours() or 12
        local startHour = FreeGangs.Config.Activities.DrugSales.AllowedStartHour
        local endHour = FreeGangs.Config.Activities.DrugSales.AllowedEndHour

        local validTime
        if startHour > endHour then
            validTime = gameHour >= startHour or gameHour < endHour
        else
            validTime = gameHour >= startHour and gameHour < endHour
        end

        if not validTime then
            return false, FreeGangs.L('activities', 'drug_sale_wrong_time')
        end
        return true
        
    elseif activity == 'protection_collect' then
        -- Check permission
        if not FreeGangs.Server.HasPermission(source, FreeGangs.Permissions.COLLECT_PROTECTION) then
            return false, FreeGangs.L('activities', 'protection_no_permission')
        end
        return true
        
    elseif activity == 'graffiti' then
        -- Check for spray can
        local sprayCanItem = FreeGangs.Config.Activities.Graffiti and
                            FreeGangs.Config.Activities.Graffiti.RequiredItem or 'spray_can'
        if not FreeGangs.Bridge.HasItem(source, sprayCanItem, 1) then
            return false, FreeGangs.L('activities', 'graffiti_no_spray')
        end
        return true
    end

    -- Deny unknown activity types by default
    return false, 'Unknown activity'
end)

-- ============================================================================
-- MUGGING CALLBACKS
-- ============================================================================

---Process mugging completion
lib.callback.register('freegangs:activities:completeMugging', function(source, targetNetId)
    if not targetNetId or type(targetNetId) ~= 'number' then return false, 'Invalid target' end
    return FreeGangs.Server.Activities.Mug(source, targetNetId)
end)

---Validate mugging target
lib.callback.register('freegangs:activities:validateMugTarget', function(source, targetNetId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Not loaded' end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, 'Not in gang' end
    
    -- Check player cooldown
    local cooldownRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'mugging')
    if cooldownRemaining > 0 then
        return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(cooldownRemaining * 1000))
    end
    
    return true
end)

-- ============================================================================
-- PICKPOCKETING CALLBACKS
-- ============================================================================

---Process pickpocket completion
lib.callback.register('freegangs:activities:completePickpocket', function(source, targetNetId, success)
    return FreeGangs.Server.Activities.Pickpocket(source, targetNetId, success)
end)

---Validate pickpocket target
lib.callback.register('freegangs:activities:validatePickpocketTarget', function(source, targetNetId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Not loaded' end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, 'Not in gang' end
    
    return true
end)

-- ============================================================================
-- DRUG SALE CALLBACKS
-- ============================================================================

---Process drug sale
lib.callback.register('freegangs:activities:completeDrugSale', function(source, targetNetId, drugItem, quantity)
    -- Validate parameters
    if not targetNetId or type(targetNetId) ~= 'number' then return false, 'Invalid target' end
    if not drugItem or type(drugItem) ~= 'string' then return false, 'Invalid drug item' end
    return FreeGangs.Server.Activities.SellDrug(source, targetNetId, drugItem, quantity or 1)
end)

---Get player's drug inventory
lib.callback.register('freegangs:activities:getDrugInventory', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end

    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return {} end

    -- Use SellableDrugs from config (array of item names)
    local sellableDrugs = FreeGangs.Config.Activities.DrugSales and
                          FreeGangs.Config.Activities.DrugSales.SellableDrugs

    -- Also check Drugs table (keyed config) for backwards compatibility
    local drugsConfig = FreeGangs.Config.Activities.DrugSales and
                       FreeGangs.Config.Activities.DrugSales.Drugs

    local drugItems = {}

    if sellableDrugs and #sellableDrugs > 0 then
        for _, itemName in pairs(sellableDrugs) do
            local count = FreeGangs.Bridge.GetItemCount(source, itemName)
            if count > 0 then
                drugItems[#drugItems + 1] = {
                    item = itemName,
                    label = FreeGangs.Bridge.GetItemLabel(itemName) or itemName,
                    count = count,
                }
            end
        end
    elseif drugsConfig then
        for itemName, _ in pairs(drugsConfig) do
            local count = FreeGangs.Bridge.GetItemCount(source, itemName)
            if count > 0 then
                drugItems[#drugItems + 1] = {
                    item = itemName,
                    label = FreeGangs.Bridge.GetItemLabel(itemName) or itemName,
                    count = count,
                }
            end
        end
    end

    return drugItems
end)

---Validate drug sale (check time, have product, etc.)
lib.callback.register('freegangs:activities:validateDrugSale', function(source, drugItem, quantity)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Not loaded' end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, 'Not in gang' end
    
    -- Check if player has the drug
    if not FreeGangs.Bridge.HasItem(source, drugItem, quantity or 1) then
        return false, FreeGangs.L('activities', 'drug_sale_no_product')
    end
    
    return true
end)

-- ============================================================================
-- PROTECTION RACKET CALLBACKS
-- ============================================================================

---Get protection businesses for a gang
lib.callback.register(FreeGangs.Callbacks.GET_PROTECTION_BUSINESSES, function(source)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return {} end
    
    local businesses = FreeGangs.Server.Activities.GetGangProtectionBusinesses(gangData.gang.name)
    
    -- Add ready status to each business
    local now = os.time()
    local collectionCooldownHours = FreeGangs.Config.Activities.Protection and
                                    FreeGangs.Config.Activities.Protection.CollectionIntervalHours or 4
    local collectionCooldown = collectionCooldownHours * 3600
    
    for _, business in pairs(businesses) do
        local lastCollection = 0
        if business.last_collection then
            lastCollection = FreeGangs.Utils.ParseTimestamp(business.last_collection) or 0
        end
        
        business.isReady = (now - lastCollection) >= collectionCooldown
        business.nextCollection = lastCollection + collectionCooldown
        business.timeRemaining = business.isReady and 0 or (business.nextCollection - now)
    end
    
    return businesses
end)

---Register protection
lib.callback.register('freegangs:activities:registerProtection', function(source, businessData)
    return FreeGangs.Server.Activities.RegisterProtection(source, businessData)
end)

---Collect protection
lib.callback.register('freegangs:activities:collectProtection', function(source, businessId)
    return FreeGangs.Server.Activities.CollectProtection(source, businessId)
end)

-- ============================================================================
-- GRAFFITI CALLBACKS
-- ============================================================================

---Spray graffiti
lib.callback.register('freegangs:graffiti:spray', function(source, coords, rotation, image)
    return FreeGangs.Server.Graffiti.Spray(source, coords, rotation, image)
end)

---Remove graffiti
lib.callback.register('freegangs:graffiti:remove', function(source, tagId)
    return FreeGangs.Server.Graffiti.Remove(source, tagId)
end)

---Get nearby graffiti
lib.callback.register(FreeGangs.Callbacks.GET_NEARBY_GRAFFITI, function(source, coords, radius)
    coords = coords or GetEntityCoords(GetPlayerPed(source))
    return FreeGangs.Server.Graffiti.GetNearby(coords, radius or 100)
end)

---Get zone graffiti
lib.callback.register('freegangs:graffiti:getZoneTags', function(source, zoneName)
    return FreeGangs.Server.Graffiti.GetZoneTags(zoneName)
end)

---Get gang graffiti
lib.callback.register('freegangs:graffiti:getGangTags', function(source)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return {} end
    
    return FreeGangs.Server.Graffiti.GetGangTags(gangData.gang.name)
end)

-- ============================================================================
-- ACTIVITY STATS CALLBACKS
-- ============================================================================

---Get player's activity stats
lib.callback.register('freegangs:activities:getStats', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return nil end
    
    -- Get current zone info
    local currentZone = FreeGangs.Server.GetPlayerZone(source)
    local zoneInfo = nil
    
    if currentZone then
        local territory = FreeGangs.Server.Territories[currentZone]
        if territory then
            local influence = territory.influence or {}
            local gangInfluence = influence[gangData.gang.name] or 0
            
            -- Find control tier
            local controlTier = 1
            for tier, tierData in pairs(FreeGangs.ZoneControlTiers) do
                if gangInfluence >= tierData.minControl and gangInfluence <= tierData.maxControl then
                    controlTier = tier
                    break
                end
            end
            
            zoneInfo = {
                name = currentZone,
                label = territory.label,
                influence = gangInfluence,
                controlTier = controlTier,
                tierData = FreeGangs.ZoneControlTiers[controlTier],
            }
        end
    end
    
    return {
        gang = gangData.gang.name,
        gangLabel = gangData.gang.label,
        archetype = gangData.gang.archetype,
        level = gangData.gang.master_level,
        rep = gangData.gang.master_rep,
        zone = zoneInfo,
    }
end)

---Get activity cooldowns
lib.callback.register('freegangs:activities:getCooldowns', function(source)
    local cooldowns = {}
    
    -- Mugging cooldown
    local muggingRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'mugging')
    if muggingRemaining > 0 then
        cooldowns.mugging = {
            remaining = muggingRemaining,
            formatted = FreeGangs.Utils.FormatDuration(muggingRemaining * 1000),
        }
    end

    -- Pickpocket cooldown
    local pickpocketRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'pickpocket')
    if pickpocketRemaining > 0 then
        cooldowns.pickpocket = {
            remaining = pickpocketRemaining,
            formatted = FreeGangs.Utils.FormatDuration(pickpocketRemaining * 1000),
        }
    end
    
    -- Add other activity cooldowns as needed
    
    return cooldowns
end)

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

-- Handle mugging start (for tracking)
RegisterNetEvent('freegangs:server:startMugging', function(targetNetId)
    local source = source
    -- Client is notifying server of mugging start
    -- This allows server-side validation if needed
    FreeGangs.Utils.Debug('Player', source, 'starting mugging on', targetNetId)
end)

-- Handle pickpocket start
RegisterNetEvent('freegangs:server:startPickpocket', function(targetNetId)
    local source = source
    FreeGangs.Utils.Debug('Player', source, 'starting pickpocket on', targetNetId)
end)

-- Handle drug sale start
RegisterNetEvent('freegangs:server:startDrugSale', function(targetNetId)
    local source = source
    FreeGangs.Utils.Debug('Player', source, 'starting drug sale to', targetNetId)
end)

-- Handle graffiti start
RegisterNetEvent('freegangs:server:startGraffiti', function(coords)
    local source = source
    FreeGangs.Utils.Debug('Player', source, 'starting graffiti at', json.encode(coords))
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    -- Test spray command
    RegisterCommand('fg_spray', function(source, args)
        if source == 0 then return end
        
        local ped = GetPlayerPed(source)
        local coords = GetEntityCoords(ped)
        
        local success, message, result = FreeGangs.Server.Graffiti.Spray(
            source,
            { x = coords.x, y = coords.y, z = coords.z },
            { x = 0, y = 0, z = GetEntityHeading(ped) }
        )
        
        FreeGangs.Bridge.Notify(source, message, success and 'success' or 'error')
        print('[free-gangs:debug] Spray result:', success, message, json.encode(result or {}))
    end, false)
    
    -- Test protection command
    RegisterCommand('fg_protection', function(source, args)
        if source == 0 then return end
        
        local businessId = args[1] or 'test_business'
        local success, message, result = FreeGangs.Server.Activities.CollectProtection(source, businessId)
        
        FreeGangs.Bridge.Notify(source, message, success and 'success' or 'error')
        print('[free-gangs:debug] Protection result:', success, message, json.encode(result or {}))
    end, false)
    
    -- Test drug sale command
    RegisterCommand('fg_drugsale', function(source, args)
        if source == 0 then return end
        
        local drug = args[1] or 'weed'
        local quantity = tonumber(args[2]) or 1
        
        local success, message, result = FreeGangs.Server.Activities.SellDrug(source, 0, drug, quantity)
        
        FreeGangs.Bridge.Notify(source, message, success and 'success' or 'error')
        print('[free-gangs:debug] Drug sale result:', success, message, json.encode(result or {}))
    end, false)
end

return true
