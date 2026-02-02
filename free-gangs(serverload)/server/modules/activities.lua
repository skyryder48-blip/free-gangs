--[[
    FREE-GANGS: Server Activities Module
    
    Handles all criminal activity processing on the server side:
    - Mugging validation and rewards
    - Pickpocketing validation and loot
    - Drug sales processing
    - Protection racket registration and collection
    
    All activities integrate with reputation, territory, and heat systems.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Activities = {}

-- ============================================================================
-- LOCAL CACHES & CONSTANTS
-- ============================================================================

-- Track NPC cooldowns globally (netId -> timestamp)
local npcCooldowns = {
    mugging = {},
    pickpocket = {},
    drugSale = {},
}

-- Track player activity stats per hour (for diminishing returns)
local playerHourlyStats = {}

-- Track protection collection times
local protectionCollections = {}

-- ============================================================================
-- MODULE DELEGATES
-- ============================================================================

---Get zone control tier for a gang in a zone
---@param zoneName string
---@param gangName string
---@return table
local function GetZoneControlTier(zoneName, gangName)
    local tierData = FreeGangs.Server.Territory.GetControlTier(zoneName, gangName)
    local influence = FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)
    return {
        tier = tierData.tier or 1,
        drugProfitMod = tierData.drugProfit or -0.20,
        canCollectProtection = tierData.canCollectProtection or false,
        protectionMultiplier = tierData.protectionMultiplier or 0,
        influence = influence,
    }
end

---Add heat between gangs
---@param gangA string
---@param gangB string
---@param amount number
---@param reason string
local function AddHeat(gangA, gangB, amount, reason)
    if not gangA or not gangB or gangA == gangB then return end
    FreeGangs.Server.Heat.Add(gangA, gangB, amount, reason)
end

---Get heat stage between gangs
---@param gangA string
---@param gangB string
---@return string stage
local function GetHeatStage(gangA, gangB)
    return FreeGangs.Server.Heat.GetStage(gangA, gangB)
end

---Add zone influence
---@param zoneName string
---@param gangName string
---@param amount number
local function AddZoneInfluence(zoneName, gangName, amount)
    FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, amount, 'activity')
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Clean up expired NPC cooldowns
local function CleanupNPCCooldowns()
    local now = os.time()
    
    for category, cooldowns in pairs(npcCooldowns) do
        for netId, expiry in pairs(cooldowns) do
            if now > expiry then
                cooldowns[netId] = nil
            end
        end
    end
end

---Clean up old hourly stats
local function CleanupHourlyStats()
    local currentHour = math.floor(os.time() / 3600)
    
    for citizenid, data in pairs(playerHourlyStats) do
        if data.hour ~= currentHour then
            playerHourlyStats[citizenid] = nil
        end
    end
end

---Get player's hourly stats
---@param citizenid string
---@return table
local function GetPlayerHourlyStats(citizenid)
    local currentHour = math.floor(os.time() / 3600)
    
    if not playerHourlyStats[citizenid] or playerHourlyStats[citizenid].hour ~= currentHour then
        playerHourlyStats[citizenid] = {
            hour = currentHour,
            drugSales = 0,
            muggings = 0,
            pickpockets = 0,
        }
    end
    
    return playerHourlyStats[citizenid]
end

---Calculate diminishing returns multiplier
---@param salesThisHour number
---@return number multiplier (0.2 to 1.0)
local function GetDiminishingReturnsMultiplier(salesThisHour)
    local config = FreeGangs.Config.Reputation.DiminishingReturns
    if not config.Enabled then return 1.0 end
    
    if salesThisHour <= config.SalesThreshold then
        return 1.0
    end
    
    local excessSales = salesThisHour - config.SalesThreshold
    local multiplier = 1.0 - (excessSales * config.DecayRate)
    return math.max(config.MinMultiplier, multiplier)
end

---Check if NPC is on cooldown for activity
---@param netId number
---@param activity string
---@return boolean
local function IsNPCOnCooldown(netId, activity)
    local cooldowns = npcCooldowns[activity]
    if not cooldowns then return false end
    
    local expiry = cooldowns[netId]
    return expiry and os.time() < expiry
end

---Set NPC cooldown
---@param netId number
---@param activity string
---@param seconds number
local function SetNPCCooldown(netId, activity, seconds)
    npcCooldowns[activity] = npcCooldowns[activity] or {}
    npcCooldowns[activity][netId] = os.time() + seconds
end

---Generate loot from loot table
---@param lootTable table
---@param rolls number
---@return table items, number cash
local function GenerateLoot(lootTable, rolls)
    rolls = rolls or 1
    local items = {}
    local totalCash = 0
    
    for i = 1, rolls do
        for _, loot in pairs(lootTable) do
            local roll = math.random(100)
            if roll <= loot.chance then
                if loot.item == 'money' or loot.item == 'cash' then
                    local amount = math.random(loot.min, loot.max)
                    totalCash = totalCash + amount
                else
                    local amount = math.random(loot.min, loot.max)
                    local found = false
                    for _, existingItem in pairs(items) do
                        if existingItem.item == loot.item then
                            existingItem.amount = existingItem.amount + amount
                            found = true
                            break
                        end
                    end
                    if not found then
                        items[#items + 1] = { item = loot.item, amount = amount }
                    end
                end
            end
        end
    end
    
    return items, totalCash
end

---Format loot for display
---@param items table
---@param cash number
---@return string
local function FormatLootDisplay(items, cash)
    local parts = {}
    
    if cash > 0 then
        parts[#parts + 1] = FreeGangs.Bridge.FormatMoney(cash)
    end
    
    for _, item in pairs(items) do
        local label = FreeGangs.Bridge.GetItemLabel(item.item) or item.item
        if item.amount > 1 then
            parts[#parts + 1] = string.format('%dx %s', item.amount, label)
        else
            parts[#parts + 1] = label
        end
    end
    
    return #parts > 0 and table.concat(parts, ', ') or 'nothing'
end

---Award loot to player
---@param source number
---@param items table
---@param cash number
---@return boolean success
local function AwardLoot(source, items, cash)
    local success = true
    
    if cash > 0 then
        if not FreeGangs.Bridge.AddMoney(source, cash, 'cash', 'gang-activity') then
            success = false
        end
    end
    
    for _, item in pairs(items) do
        if not FreeGangs.Bridge.AddItem(source, item.item, item.amount) then
            FreeGangs.Utils.Debug('Failed to add item:', item.item)
        end
    end
    
    return success
end

-- ============================================================================
-- MUGGING SYSTEM
-- ============================================================================

---Process a mugging attempt
---@param source number Player source
---@param targetNetId number Target NPC network ID
---@return boolean success
---@return string message
---@return table|nil rewards
function FreeGangs.Server.Activities.Mug(source, targetNetId)
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end
    
    -- Check player cooldown
    local cooldownRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'mugging')
    if cooldownRemaining > 0 then
        return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(cooldownRemaining * 1000)), nil
    end
    
    -- Check NPC cooldown (each NPC can only be mugged once)
    if IsNPCOnCooldown(targetNetId, 'mugging') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end
    
    -- Set cooldowns
    FreeGangs.Server.SetCooldown(source, 'mugging', FreeGangs.Config.Activities.Mugging.PlayerCooldown)
    SetNPCCooldown(targetNetId, 'mugging', 86400)
    
    -- Generate loot
    local config = FreeGangs.Config.Activities.Mugging
    local baseCash = math.random(config.MinCash, config.MaxCash)
    local items, additionalCash = GenerateLoot(config.LootTable, 1)
    local totalCash = baseCash + additionalCash
    
    -- Award loot
    local awardSuccess = AwardLoot(source, items, totalCash)
    if not awardSuccess then
        FreeGangs.Utils.Debug('Failed to award mugging loot to', citizenid)
    end
    
    -- Get activity points
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.MUGGING]
    
    -- Add reputation
    local repAmount = activityPoints.masterRep
    FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'mugging')
    
    -- Add zone influence if in a territory
    local currentZone = FreeGangs.Server.GetPlayerZone(source)
    if currentZone then
        local influenceAmount = activityPoints.zoneInfluence
        AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
    end
    
    -- Add heat
    local heatAmount = activityPoints.heat
    FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)
    
    -- If in rival territory, add heat with that gang
    if currentZone then
        local territory = FreeGangs.Server.Territories[currentZone]
        if territory then
            local owner = FreeGangs.Server.GetZoneOwner(currentZone)
            if owner and owner ~= gangData.gang.name then
                AddHeat(gangData.gang.name, owner, math.floor(heatAmount / 2), 'mugging_in_territory')
            end
        end
    end
    
    -- Update hourly stats
    local stats = GetPlayerHourlyStats(citizenid)
    stats.muggings = stats.muggings + 1
    
    -- Log activity
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'mugging', FreeGangs.LogCategories.ACTIVITY, {
        targetNetId = targetNetId,
        cash = totalCash,
        items = items,
        zone = currentZone,
    })
    
    local lootDisplay = FormatLootDisplay(items, totalCash)
    return true, FreeGangs.L('activities', 'mugging_success', lootDisplay), {
        cash = totalCash,
        items = items,
        rep = repAmount,
        heat = heatAmount,
    }
end

-- ============================================================================
-- PICKPOCKETING SYSTEM
-- ============================================================================

---Process a pickpocket attempt
---@param source number Player source
---@param targetNetId number Target NPC network ID
---@param success boolean Whether the minigame was successful
---@return boolean success
---@return string message
---@return table|nil rewards
function FreeGangs.Server.Activities.Pickpocket(source, targetNetId, success)
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end
    
    -- Check NPC cooldown
    if IsNPCOnCooldown(targetNetId, 'pickpocket') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end
    
    -- Set NPC cooldown regardless of success
    SetNPCCooldown(targetNetId, 'pickpocket', FreeGangs.Config.Activities.Pickpocket.NPCCooldown)
    
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PICKPOCKET]
    local currentZone = FreeGangs.Server.GetPlayerZone(source)
    
    if not success then
        -- Failed pickpocket - add heat and potentially alert police
        local failHeat = FreeGangs.Config.Heat.Points.PickpocketFail
        FreeGangs.Server.AddPlayerHeat(citizenid, failHeat)
        
        -- Log failure
        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'pickpocket_fail', FreeGangs.LogCategories.ACTIVITY, {
            targetNetId = targetNetId,
            zone = currentZone,
        })
        
        return false, FreeGangs.L('activities', 'pickpocket_fail'), { heat = failHeat, detected = true }
    end
    
    -- Successful pickpocket
    local config = FreeGangs.Config.Activities.Pickpocket
    local items, cash = GenerateLoot(config.LootTable, config.LootRolls)
    
    -- Award loot
    AwardLoot(source, items, cash)
    
    -- Add zone influence
    if currentZone then
        AddZoneInfluence(currentZone, gangData.gang.name, activityPoints.zoneInfluence)
    end
    
    -- Update hourly stats
    local stats = GetPlayerHourlyStats(citizenid)
    stats.pickpockets = stats.pickpockets + 1
    
    -- Log success
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'pickpocket_success', FreeGangs.LogCategories.ACTIVITY, {
        targetNetId = targetNetId,
        cash = cash,
        items = items,
        zone = currentZone,
    })
    
    local lootDisplay = FormatLootDisplay(items, cash)
    return true, FreeGangs.L('activities', 'pickpocket_success'), {
        cash = cash,
        items = items,
        heat = 0,
    }
end

-- ============================================================================
-- DRUG SALES SYSTEM
-- ============================================================================

---Check if current game time is within drug sale hours
---@return boolean
local function IsDrugSaleHoursActive()
    local gameHour = GetClockHours and GetClockHours() or 12
    local startHour = FreeGangs.Config.Activities.DrugSales.AllowedStartHour
    local endHour = FreeGangs.Config.Activities.DrugSales.AllowedEndHour
    
    if startHour > endHour then
        return gameHour >= startHour or gameHour < endHour
    else
        return gameHour >= startHour and gameHour < endHour
    end
end

---Get drug sell price with modifiers
---@param basePrice number
---@param gangName string
---@param zoneName string|nil
---@return number finalPrice
---@return table modifiers
local function CalculateDrugPrice(basePrice, gangName, zoneName)
    local modifiers = {
        base = basePrice,
        territory = 0,
        rivalry = 0,
        archetype = 0,
        diminishing = 1.0,
        final = basePrice,
    }
    
    if zoneName then
        local controlTier = GetZoneControlTier(zoneName, gangName)
        modifiers.territory = basePrice * controlTier.drugProfitMod
        
        -- Check rivalry penalty
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory then
            local owner = FreeGangs.Server.GetZoneOwner(zoneName)
            if owner and owner ~= gangName then
                local stage = GetHeatStage(gangName, owner)
                if stage == FreeGangs.HeatStages.RIVALRY or stage == FreeGangs.HeatStages.WAR_READY then
                    modifiers.rivalry = -basePrice * FreeGangs.Config.Heat.Rivalry.ProfitReduction
                end
            end
        end
    end
    
    -- Apply archetype bonus
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang and gang.archetype == FreeGangs.Archetypes.STREET then
        local bonus = FreeGangs.ArchetypePassiveBonuses[FreeGangs.Archetypes.STREET].drugProfit
        modifiers.archetype = basePrice * bonus
    end
    
    modifiers.final = math.max(1, math.floor(basePrice + modifiers.territory + modifiers.rivalry + modifiers.archetype))
    return modifiers.final, modifiers
end

---Process a drug sale
---@param source number Player source
---@param targetNetId number Target NPC network ID
---@param drugItem string Drug item name
---@param quantity number Amount to sell
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Activities.SellDrug(source, targetNetId, drugItem, quantity)
    quantity = quantity or 1
    
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end
    
    -- Check time restriction
    if not IsDrugSaleHoursActive() then
        return false, FreeGangs.L('activities', 'drug_sale_wrong_time'), nil
    end
    
    -- Check if player has the drug
    if not FreeGangs.Bridge.HasItem(source, drugItem, quantity) then
        return false, FreeGangs.L('activities', 'drug_sale_no_product'), nil
    end
    
    -- Check NPC cooldown
    if IsNPCOnCooldown(targetNetId, 'drugSale') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end
    
    -- Get drug config
    local drugConfig = FreeGangs.Config.Activities.DrugSales.Drugs and 
                       FreeGangs.Config.Activities.DrugSales.Drugs[drugItem]
    if not drugConfig then
        drugConfig = { basePrice = 50, minPrice = 25, maxPrice = 100 }
    end
    
    -- Random sale chance
    local saleChance = FreeGangs.Config.Activities.DrugSales.BaseSuccessChance or 85
    local currentZone = FreeGangs.Server.GetPlayerZone(source)
    
    -- Modify chance based on territory
    if currentZone then
        local controlTier = GetZoneControlTier(currentZone, gangData.gang.name)
        if controlTier.influence >= 51 then
            saleChance = saleChance + 10
        elseif controlTier.influence < 10 then
            saleChance = saleChance - 20
        end
    end
    
    -- Roll for sale
    if math.random(100) > saleChance then
        SetNPCCooldown(targetNetId, 'drugSale', 60)
        return false, FreeGangs.L('activities', 'drug_sale_fail'), { rejected = true }
    end
    
    -- Set NPC cooldown
    SetNPCCooldown(targetNetId, 'drugSale', FreeGangs.Config.Activities.DrugSales.NPCCooldown or 300)
    
    -- Calculate price
    local basePrice = math.random(drugConfig.minPrice or drugConfig.basePrice * 0.8, 
                                   drugConfig.maxPrice or drugConfig.basePrice * 1.2)
    local finalPrice, modifiers = CalculateDrugPrice(basePrice * quantity, gangData.gang.name, currentZone)
    
    -- Apply diminishing returns
    local stats = GetPlayerHourlyStats(citizenid)
    local diminishingMult = GetDiminishingReturnsMultiplier(stats.drugSales)
    finalPrice = math.floor(finalPrice * diminishingMult)
    modifiers.diminishing = diminishingMult
    
    -- Remove drug and give money
    if not FreeGangs.Bridge.RemoveItem(source, drugItem, quantity) then
        return false, FreeGangs.L('errors', 'generic'), nil
    end
    
    FreeGangs.Bridge.AddMoney(source, finalPrice, 'cash', 'drug-sale')
    
    -- Update stats
    stats.drugSales = stats.drugSales + quantity
    
    -- Get activity points
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.DRUG_SALE]
    
    -- Add reputation
    local repAmount = math.floor(activityPoints.masterRep * quantity * diminishingMult)
    FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'drug_sale')
    
    -- Add zone influence
    if currentZone then
        local influenceAmount = activityPoints.zoneInfluence * quantity
        AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
    end
    
    -- Add heat
    local heatAmount = activityPoints.heat * quantity
    FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)
    
    -- Log activity
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'drug_sale', FreeGangs.LogCategories.ACTIVITY, {
        drug = drugItem,
        quantity = quantity,
        price = finalPrice,
        modifiers = modifiers,
        zone = currentZone,
    })
    
    local drugLabel = FreeGangs.Bridge.GetItemLabel(drugItem) or drugItem
    return true, FreeGangs.L('activities', 'drug_sale_success', drugLabel, FreeGangs.Bridge.FormatMoney(finalPrice)), {
        drug = drugItem,
        quantity = quantity,
        price = finalPrice,
        modifiers = modifiers,
        rep = repAmount,
        heat = heatAmount,
    }
end

-- ============================================================================
-- PROTECTION RACKET SYSTEM
-- ============================================================================

---Register a business for protection
---@param source number Player source
---@param businessData table Business information
---@return boolean success
---@return string message
function FreeGangs.Server.Activities.RegisterProtection(source, businessData)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded')
    end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang')
    end
    
    -- Check permission
    if not FreeGangs.Server.HasPermission(source, FreeGangs.Permissions.COLLECT_PROTECTION) then
        if not gangData.membership.isBoss and gangData.membership.is_boss ~= 1 then
            return false, FreeGangs.L('general', 'no_permission')
        end
    end
    
    -- Check zone control requirement
    local zoneName = businessData.zone_name
    if zoneName then
        local controlTier = GetZoneControlTier(zoneName, gangData.gang.name)
        if not controlTier.canCollectProtection then
            return false, FreeGangs.L('activities', 'protection_need_control')
        end
    end
    
    -- Check if business already registered
    local existingProtection = MySQL.single.await([[
        SELECT gang_name, status FROM freegangs_protection WHERE business_id = ? AND status = 'active'
    ]], { businessData.business_id })
    
    if existingProtection then
        if existingProtection.gang_name == gangData.gang.name then
            return false, 'Already registered to your gang'
        else
            return false, 'This business is protected by another gang'
        end
    end
    
    -- Register protection
    local insertData = {
        gang_name = gangData.gang.name,
        business_id = businessData.business_id,
        business_label = businessData.business_label,
        zone_name = zoneName,
        coords = businessData.coords,
        payout_base = businessData.payout_base or FreeGangs.Config.Activities.Protection.BasePayout or 500,
        established_by = citizenid,
    }
    
    local insertId = FreeGangs.Server.DB.RegisterProtection(insertData)
    if not insertId then
        return false, FreeGangs.L('errors', 'server_error')
    end
    
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_registered', FreeGangs.LogCategories.ACTIVITY, {
        business_id = businessData.business_id,
        business_label = businessData.business_label,
        zone = zoneName,
    })
    
    return true, FreeGangs.L('activities', 'protection_registered', businessData.business_label or businessData.business_id)
end

---Collect protection money from a business
---@param source number Player source
---@param businessId string Business identifier
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Activities.CollectProtection(source, businessId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end
    
    -- Check permission
    if not FreeGangs.Server.HasPermission(source, FreeGangs.Permissions.COLLECT_PROTECTION) then
        return false, FreeGangs.L('activities', 'protection_no_permission'), nil
    end
    
    -- Get protection record
    local protection = MySQL.single.await([[
        SELECT * FROM freegangs_protection WHERE business_id = ? AND gang_name = ? AND status = 'active'
    ]], { businessId, gangData.gang.name })
    
    if not protection then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end
    
    -- Check collection cooldown
    local collectionCooldown = FreeGangs.Config.Activities.Protection and 
                               FreeGangs.Config.Activities.Protection.CollectionInterval or 14400
    local lastCollection = protectionCollections[businessId] or 0
    local now = os.time()
    
    if protection.last_collection then
        local lastDbCollection = FreeGangs.Utils.ParseTimestamp(protection.last_collection)
        if lastDbCollection and lastDbCollection > lastCollection then
            lastCollection = lastDbCollection
        end
    end
    
    if now - lastCollection < collectionCooldown then
        local remaining = collectionCooldown - (now - lastCollection)
        return false, FreeGangs.L('activities', 'protection_not_ready') .. ' (' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ')', nil
    end
    
    -- Check zone control
    local zoneName = protection.zone_name
    local controlTier = GetZoneControlTier(zoneName, gangData.gang.name)
    
    if not controlTier.canCollectProtection then
        MySQL.update.await([[
            UPDATE freegangs_protection SET status = 'suspended' WHERE business_id = ?
        ]], { businessId })
        return false, FreeGangs.L('activities', 'protection_need_control'), nil
    end
    
    -- Check rivalry effect
    if zoneName then
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory then
            local owner = FreeGangs.Server.GetZoneOwner(zoneName)
            if owner and owner ~= gangData.gang.name then
                local stage = GetHeatStage(gangData.gang.name, owner)
                if (stage == FreeGangs.HeatStages.RIVALRY or stage == FreeGangs.HeatStages.WAR_READY) 
                   and FreeGangs.Config.Heat.Rivalry.ProtectionStopped then
                    return false, 'Protection collection suspended due to gang rivalry', nil
                end
            end
        end
    end
    
    -- Calculate payout
    local basePayout = protection.payout_base or 500
    local multiplier = controlTier.protectionMultiplier or 1
    
    -- Apply archetype bonus
    if gangData.gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        multiplier = multiplier * (1 + FreeGangs.ArchetypePassiveBonuses[FreeGangs.Archetypes.CRIME_FAMILY].protectionIncome)
    end
    
    -- Apply contested zone penalty
    if zoneName and controlTier.influence < 80 then
        local oppositionInfluence = 100 - controlTier.influence
        local penaltyPercent = math.floor(oppositionInfluence / 5) * 5
        multiplier = multiplier * (1 - (penaltyPercent / 100))
    end
    
    local finalPayout = math.floor(basePayout * multiplier)
    
    -- Update collection timestamp
    protectionCollections[businessId] = now
    FreeGangs.Server.DB.UpdateProtectionCollection(businessId)
    
    -- Give money
    FreeGangs.Bridge.AddMoney(source, finalPayout, 'cash', 'protection-collection')
    
    -- Get activity points
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PROTECTION_COLLECT]
    
    -- Add reputation
    FreeGangs.Server.AddGangReputation(gangData.gang.name, activityPoints.masterRep, citizenid, 'protection_collection')
    
    -- Add zone influence
    if zoneName then
        AddZoneInfluence(zoneName, gangData.gang.name, activityPoints.zoneInfluence)
    end
    
    -- Add heat
    FreeGangs.Server.AddPlayerHeat(citizenid, activityPoints.heat)
    
    -- Log activity
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_collected', FreeGangs.LogCategories.ACTIVITY, {
        business_id = businessId,
        payout = finalPayout,
        multiplier = multiplier,
        zone = zoneName,
    })
    
    return true, FreeGangs.L('activities', 'protection_collected', FreeGangs.Bridge.FormatMoney(finalPayout)), {
        payout = finalPayout,
        business = protection.business_label or businessId,
        rep = activityPoints.masterRep,
        heat = activityPoints.heat,
    }
end

---Get all protection businesses for a gang
---@param gangName string
---@return table businesses
function FreeGangs.Server.Activities.GetGangProtectionBusinesses(gangName)
    return FreeGangs.Server.DB.GetGangProtection(gangName)
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Add reputation to a gang
---@param gangName string
---@param amount number
---@param citizenid string|nil
---@param reason string|nil
function FreeGangs.Server.AddGangReputation(gangName, amount, citizenid, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end
    
    local multiplierKey = reason and FreeGangs.Config.Reputation.Multipliers and 
                          FreeGangs.Config.Reputation.Multipliers[reason]
    if multiplierKey then
        amount = math.floor(amount * multiplierKey)
    end
    
    local newRep = gang.master_rep + amount
    FreeGangs.Server.SetGangReputation(gangName, newRep, reason)
end

---Add heat to a player
---@param citizenid string
---@param amount number
function FreeGangs.Server.AddPlayerHeat(citizenid, amount)
    MySQL.query([[
        INSERT INTO freegangs_player_heat (citizenid, heat_points) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE heat_points = LEAST(100, heat_points + ?), last_activity = CURRENT_TIMESTAMP
    ]], { citizenid, amount, amount })
end

---Get player's current zone
---@param source number
---@return string|nil zoneName
function FreeGangs.Server.GetPlayerZone(source)
    local player = FreeGangs.Bridge.GetPlayer(source)
    if not player then return nil end
    
    local playerState = Player(source).state
    return playerState and playerState.currentZone or nil
end

---Get zone owner
---@param zoneName string
---@return string|nil gangName
function FreeGangs.Server.GetZoneOwner(zoneName)
    local territory = FreeGangs.Server.Territories[zoneName]
    if not territory or not territory.influence then return nil end
    
    local highestGang = nil
    local highestInfluence = 0
    
    for gangName, influence in pairs(territory.influence) do
        if influence > highestInfluence then
            highestInfluence = influence
            highestGang = gangName
        end
    end
    
    if highestInfluence >= FreeGangs.Config.Territory.MajorityThreshold then
        return highestGang
    end
    
    return nil
end

---Get player's gang data
---@param source number
---@return table|nil {gang, membership}
function FreeGangs.Server.GetPlayerGangData(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end
    
    for gangName, gang in pairs(FreeGangs.Server.Gangs) do
        local member = FreeGangs.Server.DB.GetMember(gangName, citizenid)
        if member then
            return { gang = gang, membership = member }
        end
    end
    
    return nil
end

---Check if player has a specific permission
---@param source number
---@param permission string
---@return boolean
function FreeGangs.Server.HasPermission(source, permission)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false end
    
    local membership = gangData.membership
    
    if membership.is_boss == 1 then return true end
    
    local personalPerms = membership.permissions
    if type(personalPerms) == 'string' then
        personalPerms = json.decode(personalPerms) or {}
    end
    if personalPerms and personalPerms[permission] then
        return true
    end
    
    local rankPerms = FreeGangs.DefaultRankPermissions[tostring(membership.rank)]
    return rankPerms and rankPerms[permission] or false
end

-- ============================================================================
-- CLEANUP THREADS
-- ============================================================================

CreateThread(function()
    while true do
        Wait(300000)
        CleanupNPCCooldowns()
        CleanupHourlyStats()
    end
end)

return FreeGangs.Server.Activities
