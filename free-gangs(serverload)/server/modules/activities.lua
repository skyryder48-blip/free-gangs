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

-- Dynamic drug market: track sales volume per zone per drug
-- Structure: { [zoneName] = { [drugItem] = { count = N, timestamps = { ... } } } }
local drugMarketData = {}

-- Active drought events: { [drugItem] = { startTime = N, duration = N, multiplier = N } }
local activeDroughts = {}

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
    local now = FreeGangs.Utils.GetTimestamp()
    
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
    local currentHour = math.floor(FreeGangs.Utils.GetTimestamp() / 3600)
    
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
    local currentHour = math.floor(FreeGangs.Utils.GetTimestamp() / 3600)
    
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
    return expiry and FreeGangs.Utils.GetTimestamp() < expiry
end

---Check if NPC is on cooldown (exposed for callback validation)
---@param netId number
---@param activity string
---@return boolean
function FreeGangs.Server.Activities.IsNPCOnCooldown(netId, activity)
    return IsNPCOnCooldown(netId, activity)
end

---Set NPC cooldown
---@param netId number
---@param activity string
---@param seconds number
local function SetNPCCooldown(netId, activity, seconds)
    npcCooldowns[activity] = npcCooldowns[activity] or {}
    npcCooldowns[activity][netId] = FreeGangs.Utils.GetTimestamp() + seconds
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

---Record a crime stat for lifetime tracking
---@param citizenid string
---@param crimeType string (mugging, pickpocket, drug_sale, etc.)
---@param data table Optional data {cashEarned, itemsFound, quantity, etc.}
local function RecordCrimeStat(citizenid, crimeType, data)
    data = data or {}
    MySQL.query([[
        INSERT INTO freegangs_crime_stats (citizenid, crime_type, total_count, total_cash_earned, last_performed)
        VALUES (?, ?, 1, ?, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE
            total_count = total_count + 1,
            total_cash_earned = total_cash_earned + ?,
            last_performed = CURRENT_TIMESTAMP
    ]], { citizenid, crimeType, data.cash or 0, data.cash or 0 })
end

---Trigger police dispatch event for crime activities
---@param source number Player source
---@param crimeType string Type of crime (mugging, pickpocket, drug_sale)
---@param severity number 1-5 severity rating
---@param data table Additional data
local function TriggerDispatch(source, crimeType, severity, data)
    local playerPed = GetPlayerPed(source)
    local coords = GetEntityCoords(playerPed)

    local dispatchData = {
        source = source,
        crimeType = crimeType,
        severity = severity,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        zone = FreeGangs.Server.GetPlayerZone(source),
        timestamp = FreeGangs.Utils.GetTimestamp(),
    }

    -- Merge additional data
    if data then
        for k, v in pairs(data) do
            dispatchData[k] = v
        end
    end

    -- Fire server event for external dispatch scripts to listen
    TriggerEvent('freegangs:dispatch:crimeReport', dispatchData)

    -- Also trigger via exports if dispatch resource exists
    if GetResourceState('ps-dispatch') == 'started' or
       GetResourceState('cd_dispatch') == 'started' or
       GetResourceState('qs-dispatch') == 'started' or
       GetResourceState('core_dispatch') == 'started' then
        TriggerEvent('freegangs:dispatch:alert', dispatchData)
    end
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
function FreeGangs.Server.Activities.Mug(source, targetNetId, npcCategory)
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership (optional - non-gang players can mug but don't earn rep)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)

    -- Check player cooldown
    local cooldownRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'mugging')
    if cooldownRemaining > 0 then
        return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(cooldownRemaining * 1000)), nil
    end

    -- Check NPC cooldown (each NPC can only be mugged once)
    if IsNPCOnCooldown(targetNetId, 'mugging') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end

    -- NPC Resistance check
    local config = FreeGangs.Config.Activities.Mugging
    local resistConfig = FreeGangs.Config.Activities.Mugging.Resistance
    local resisted = false
    if resistConfig and resistConfig.Enabled then
        local resistChance = resistConfig.BaseResistChance or 5
        local categoryConfig = nil

        if npcCategory and resistConfig.Categories and resistConfig.Categories[npcCategory] then
            categoryConfig = resistConfig.Categories[npcCategory]
            resistChance = categoryConfig.resistChance or resistChance
        end

        if math.random(100) <= resistChance then
            resisted = true
        end
    end

    if resisted then
        -- NPC fought back - no loot, still set cooldowns
        FreeGangs.Server.SetCooldown(source, 'mugging', config.PlayerCooldown)
        SetNPCCooldown(targetNetId, 'mugging', config.NPCCooldown or 86400)

        -- Still generate heat even on failed mugging
        if gangData then
            local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.MUGGING]
            FreeGangs.Server.AddPlayerHeat(citizenid, activityPoints.heat)

            FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'mugging_resisted', FreeGangs.LogCategories.ACTIVITY, {
                targetNetId = targetNetId,
                npcCategory = npcCategory,
                zone = FreeGangs.Server.GetPlayerZone(source),
            })
        end

        return false, FreeGangs.L('activities', 'mugging_resisted'), { resisted = true, npcCategory = npcCategory }
    end

    -- Use category-specific loot table and cash multiplier if available
    local lootTable = config.LootTable
    local cashMultiplier = 1.0

    if npcCategory and resistConfig and resistConfig.Enabled and resistConfig.Categories[npcCategory] then
        local categoryConfig = resistConfig.Categories[npcCategory]
        if categoryConfig.lootTable then
            lootTable = categoryConfig.lootTable
        end
        cashMultiplier = categoryConfig.cashMultiplier or 1.0
    end

    local baseCash = math.floor(math.random(config.MinCash, config.MaxCash) * cashMultiplier)
    local items, additionalCash = GenerateLoot(lootTable, 1)
    local totalCash = baseCash + additionalCash

    -- Award loot
    local awardSuccess = AwardLoot(source, items, totalCash)
    if not awardSuccess then
        FreeGangs.Utils.Debug('Failed to award mugging loot to', citizenid)
        return false, FreeGangs.L('errors', 'generic'), nil
    end

    -- Set cooldowns only after successful loot award
    FreeGangs.Server.SetCooldown(source, 'mugging', FreeGangs.Config.Activities.Mugging.PlayerCooldown)
    SetNPCCooldown(targetNetId, 'mugging', FreeGangs.Config.Activities.Mugging.NPCCooldown or 86400)

    local repAmount = 0
    local heatAmount = 0
    local currentZone = FreeGangs.Server.GetPlayerZone(source)

    -- Gang-specific rewards: reputation, influence, heat, logging
    if gangData then
        local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.MUGGING]

        repAmount = activityPoints.masterRep
        FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'mugging')

        if currentZone then
            local influenceAmount = activityPoints.zoneInfluence
            AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
        end

        heatAmount = activityPoints.heat
        FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)

        if currentZone then
            local territory = FreeGangs.Server.Territories[currentZone]
            if territory then
                local owner = FreeGangs.Server.GetZoneOwner(currentZone)
                if owner and owner ~= gangData.gang.name then
                    AddHeat(gangData.gang.name, owner, math.floor(heatAmount / 2), 'mugging_in_territory')
                end
            end
        end

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'mugging', FreeGangs.LogCategories.ACTIVITY, {
            targetNetId = targetNetId,
            cash = totalCash,
            items = items,
            zone = currentZone,
        })
    end

    -- Update hourly stats
    local stats = GetPlayerHourlyStats(citizenid)
    stats.muggings = stats.muggings + 1

    -- Record lifetime crime stat
    RecordCrimeStat(citizenid, 'mugging', { cash = totalCash })

    -- Trigger police dispatch
    TriggerDispatch(source, 'mugging', 3, { weapon = true })

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
function FreeGangs.Server.Activities.Pickpocket(source, targetNetId, successfulRolls)
    successfulRolls = tonumber(successfulRolls) or 0

    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end

    -- Check gang membership (optional - non-gang players can pickpocket but don't earn rep)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)

    -- Check player cooldown
    local cooldownRemaining = FreeGangs.Server.GetCooldownRemaining(source, 'pickpocket')
    if cooldownRemaining > 0 then
        return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(cooldownRemaining * 1000)), nil
    end

    -- Check NPC cooldown
    if IsNPCOnCooldown(targetNetId, 'pickpocket') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end

    -- Set NPC cooldown regardless of outcome
    SetNPCCooldown(targetNetId, 'pickpocket', FreeGangs.Config.Activities.Pickpocket.NPCCooldown)

    local currentZone = FreeGangs.Server.GetPlayerZone(source)

    if successfulRolls <= 0 then
        -- Failed pickpocket (0 rolls completed)
        if gangData then
            local failHeat = FreeGangs.Config.Heat.Points.PickpocketFail
            FreeGangs.Server.AddPlayerHeat(citizenid, failHeat)

            FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'pickpocket_fail', FreeGangs.LogCategories.ACTIVITY, {
                targetNetId = targetNetId,
                zone = currentZone,
            })

            TriggerDispatch(source, 'pickpocket', 1, {})
            return false, FreeGangs.L('activities', 'pickpocket_fail'), { heat = failHeat, detected = true }
        end

        TriggerDispatch(source, 'pickpocket', 1, {})
        return false, FreeGangs.L('activities', 'pickpocket_fail'), { detected = true }
    end

    -- Successful pickpocket - scale loot by rolls completed
    local config = FreeGangs.Config.Activities.Pickpocket
    local maxRolls = config.LootRolls or 3
    successfulRolls = math.min(successfulRolls, maxRolls)

    local items, cash = GenerateLoot(config.LootTable, successfulRolls)

    AwardLoot(source, items, cash)

    -- Set player cooldown after any successful rolls
    FreeGangs.Server.SetCooldown(source, 'pickpocket', config.PlayerCooldown or 120)

    local repAmount = 0
    local heatAmount = 0

    -- Gang-specific rewards: reputation, influence, heat, logging
    if gangData then
        local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PICKPOCKET]
        local rollRatio = successfulRolls / maxRolls

        repAmount = math.ceil(activityPoints.masterRep * rollRatio)
        FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'pickpocket')

        if currentZone then
            local influenceAmount = math.ceil(activityPoints.zoneInfluence * rollRatio)
            AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
        end

        heatAmount = activityPoints.heat
        if heatAmount > 0 then
            FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)
        end

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'pickpocket_success', FreeGangs.LogCategories.ACTIVITY, {
            targetNetId = targetNetId,
            cash = cash,
            items = items,
            rolls = successfulRolls,
            maxRolls = maxRolls,
            zone = currentZone,
        })
    end

    -- Update hourly stats
    local stats = GetPlayerHourlyStats(citizenid)
    stats.pickpockets = stats.pickpockets + 1

    -- Record lifetime crime stat
    RecordCrimeStat(citizenid, 'pickpocket', { cash = cash })

    return true, FreeGangs.L('activities', 'pickpocket_success'), {
        cash = cash,
        items = items,
        rep = repAmount,
        heat = heatAmount,
        rolls = successfulRolls,
    }
end

-- ============================================================================
-- DYNAMIC DRUG MARKET HELPERS
-- ============================================================================

---Get dynamic market supply multiplier for a drug in a zone
---@param zoneName string|nil
---@param drugItem string
---@return number multiplier (0.5 to 1.25)
local function GetDynamicMarketMultiplier(zoneName, drugItem)
    local marketConfig = FreeGangs.Config.Activities.DrugSales.DynamicMarket
    if not marketConfig or not marketConfig.Enabled then return 1.0 end

    -- Check drought bonus first
    local droughtMult = 1.0
    local drought = activeDroughts[drugItem]
    if drought and FreeGangs.Utils.GetTimestamp() < (drought.startTime + drought.duration) then
        droughtMult = drought.multiplier or marketConfig.Drought.PriceMultiplier
    end

    if not zoneName then return droughtMult end

    local zoneData = drugMarketData[zoneName]
    if not zoneData or not zoneData[drugItem] then
        -- No sales in this zone = undersupply bonus
        return (marketConfig.UndersupplyBonus or 1.25) * droughtMult
    end

    -- Clean old timestamps
    local now = FreeGangs.Utils.GetTimestamp()
    local window = marketConfig.TrackingWindow or 3600
    local drugData = zoneData[drugItem]
    local validTimestamps = {}
    for _, ts in ipairs(drugData.timestamps or {}) do
        if now - ts <= window then
            validTimestamps[#validTimestamps + 1] = ts
        end
    end
    drugData.timestamps = validTimestamps
    drugData.count = #validTimestamps

    local salesCount = drugData.count
    local threshold = marketConfig.SaturationThreshold or 15

    if salesCount <= threshold then
        return 1.0 * droughtMult
    end

    -- Oversupply penalty
    local excessSales = salesCount - threshold
    local penalty = excessSales * (marketConfig.SupplyPenaltyRate or 0.03)
    local supplyMult = math.max(marketConfig.MinSupplyMultiplier or 0.50, 1.0 - penalty)

    return supplyMult * droughtMult
end

---Record a drug sale in the market tracker
---@param zoneName string|nil
---@param drugItem string
---@param quantity number
local function RecordDrugSale(zoneName, drugItem, quantity)
    local marketConfig = FreeGangs.Config.Activities.DrugSales.DynamicMarket
    if not marketConfig or not marketConfig.Enabled then return end
    if not zoneName then return end

    drugMarketData[zoneName] = drugMarketData[zoneName] or {}
    drugMarketData[zoneName][drugItem] = drugMarketData[zoneName][drugItem] or { count = 0, timestamps = {} }

    local now = FreeGangs.Utils.GetTimestamp()
    for i = 1, quantity do
        table.insert(drugMarketData[zoneName][drugItem].timestamps, now)
    end
    drugMarketData[zoneName][drugItem].count = #drugMarketData[zoneName][drugItem].timestamps
end

---Check and potentially trigger drought events (called periodically)
local function CheckDroughtEvents()
    local marketConfig = FreeGangs.Config.Activities.DrugSales.DynamicMarket
    if not marketConfig or not marketConfig.Enabled then return end

    local droughtConfig = marketConfig.Drought
    if not droughtConfig or not droughtConfig.Enabled then return end

    -- Clean expired droughts
    local now = FreeGangs.Utils.GetTimestamp()
    for drug, drought in pairs(activeDroughts) do
        if now >= (drought.startTime + drought.duration) then
            activeDroughts[drug] = nil
            FreeGangs.Utils.Log('[DrugMarket] Drought ended for ' .. drug)
        end
    end

    -- Count active droughts
    local activeCount = 0
    for _ in pairs(activeDroughts) do activeCount = activeCount + 1 end

    if activeCount >= (droughtConfig.MaxActive or 1) then return end

    -- Roll for new drought
    if math.random(100) <= (droughtConfig.ChancePerHour or 8) then
        local sellableDrugs = FreeGangs.Config.Activities.DrugSales.SellableDrugs or {}
        if #sellableDrugs == 0 then return end

        local drug = sellableDrugs[math.random(#sellableDrugs)]
        if activeDroughts[drug] then return end -- Already in drought

        local duration = math.random(droughtConfig.MinDuration or 1800, droughtConfig.MaxDuration or 5400)
        activeDroughts[drug] = {
            startTime = now,
            duration = duration,
            multiplier = droughtConfig.PriceMultiplier or 2.0,
        }

        local drugLabel = FreeGangs.Bridge.GetItemLabel(drug) or drug
        FreeGangs.Utils.Log('[DrugMarket] Drought started for ' .. drugLabel .. ' (' .. math.floor(duration/60) .. ' min)')

        -- Notify all online players (optional flavor text)
        TriggerClientEvent('freegangs:client:drugDroughtNotice', -1, drug, drugLabel)
    end
end

---Get active drought info (for client display)
---@return table droughts
function FreeGangs.Server.Activities.GetActiveDroughts()
    local result = {}
    local now = FreeGangs.Utils.GetTimestamp()
    for drug, drought in pairs(activeDroughts) do
        if now < (drought.startTime + drought.duration) then
            result[drug] = {
                remaining = (drought.startTime + drought.duration) - now,
                multiplier = drought.multiplier,
            }
        end
    end
    return result
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
    
    if zoneName and gangName then
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
    -- Validate and sanitize quantity
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    quantity = math.min(quantity, 10) -- Cap at 10 per transaction
    
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership (optional - non-gang players can sell but don't earn rep)
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    local gangName = gangData and gangData.gang.name or nil

    -- Check time restriction
    if not IsDrugSaleHoursActive() then
        return false, FreeGangs.L('activities', 'drug_sale_wrong_time'), nil
    end

    -- Check player cooldown
    local drugCooldown = FreeGangs.Server.GetCooldownRemaining(source, 'drug_sale')
    if drugCooldown > 0 then
        return false, FreeGangs.L('activities', 'on_cooldown', FreeGangs.Utils.FormatDuration(drugCooldown * 1000)), nil
    end

    -- Check if player has the drug
    if not FreeGangs.Bridge.HasItem(source, drugItem, quantity) then
        return false, FreeGangs.L('activities', 'drug_sale_no_product'), nil
    end
    
    -- Check NPC cooldown
    if IsNPCOnCooldown(targetNetId, 'drugSale') then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end
    
    -- Validate drug item against whitelist
    local sellableDrugs = FreeGangs.Config.Activities.DrugSales.SellableDrugs or {}
    local isValidDrug = false
    for _, validDrug in pairs(sellableDrugs) do
        if validDrug == drugItem then
            isValidDrug = true
            break
        end
    end
    if not isValidDrug then
        return false, FreeGangs.L('activities', 'drug_sale_no_product'), nil
    end

    -- Get drug config (per-drug pricing or defaults)
    local drugConfig = FreeGangs.Config.Activities.DrugSales.Drugs and
                       FreeGangs.Config.Activities.DrugSales.Drugs[drugItem]
    if not drugConfig then
        drugConfig = { basePrice = 50, minPrice = 25, maxPrice = 100 }
    end

    -- Random sale chance (use SuccessChance.Base config, convert from decimal to percentage)
    local successChanceConfig = FreeGangs.Config.Activities.DrugSales.SuccessChance
    local saleChance = successChanceConfig and math.floor((successChanceConfig.Base or 0.60) * 100) or 85
    local currentZone = FreeGangs.Server.GetPlayerZone(source)
    
    -- Modify chance based on territory (gang members only)
    if currentZone and gangName then
        local controlTier = GetZoneControlTier(currentZone, gangName)
        local ownTerritoryBonus = successChanceConfig and math.floor((successChanceConfig.OwnTerritory or 0.20) * 100) or 10
        local rivalTerritoryPenalty = successChanceConfig and math.floor(math.abs((successChanceConfig.RivalTerritory or -0.30) * 100)) or 20
        if controlTier.influence >= 51 then
            saleChance = saleChance + ownTerritoryBonus
        elseif controlTier.influence < 10 then
            saleChance = saleChance - rivalTerritoryPenalty
        end
    end
    
    -- Roll for sale
    if math.random(100) > saleChance then
        local npcBlockDuration = FreeGangs.Config.Activities.DrugSales.NPCBlockDuration or 999999
        SetNPCCooldown(targetNetId, 'drugSale', npcBlockDuration)
        return false, FreeGangs.L('activities', 'drug_sale_fail'), { rejected = true }
    end
    
    -- Set NPC permanent block (one transaction per NPC for all players)
    local npcBlockDuration = FreeGangs.Config.Activities.DrugSales.NPCBlockDuration or 999999
    SetNPCCooldown(targetNetId, 'drugSale', npcBlockDuration)

    -- Set player cooldown (short, allows rapid transactions with different NPCs)
    FreeGangs.Server.SetCooldown(source, 'drug_sale', FreeGangs.Config.Activities.DrugSales.PlayerCooldown or 15)
    
    -- Calculate price
    local basePrice = math.random(drugConfig.minPrice or drugConfig.basePrice * 0.8, 
                                   drugConfig.maxPrice or drugConfig.basePrice * 1.2)
    local finalPrice, modifiers = CalculateDrugPrice(basePrice * quantity, gangName, currentZone)

    -- Apply dynamic market supply/demand multiplier
    local marketMult = GetDynamicMarketMultiplier(currentZone, drugItem)
    finalPrice = math.floor(finalPrice * marketMult)
    modifiers.market = marketMult

    -- Apply diminishing returns
    local stats = GetPlayerHourlyStats(citizenid)
    local diminishingMult = GetDiminishingReturnsMultiplier(stats.drugSales)
    finalPrice = math.floor(finalPrice * diminishingMult)
    modifiers.diminishing = diminishingMult
    
    -- Remove drug and give money (atomic: rollback on failure)
    if not FreeGangs.Bridge.RemoveItem(source, drugItem, quantity) then
        return false, FreeGangs.L('errors', 'generic'), nil
    end

    if not FreeGangs.Bridge.AddMoney(source, finalPrice, 'cash', 'drug-sale') then
        -- Rollback: give item back
        FreeGangs.Bridge.AddItem(source, drugItem, quantity)
        return false, FreeGangs.L('errors', 'generic'), nil
    end
    
    -- Update stats
    stats.drugSales = stats.drugSales + quantity

    -- Record sale in dynamic market tracker
    RecordDrugSale(currentZone, drugItem, quantity)

    local repAmount = 0
    local heatAmount = 0

    -- Gang-specific rewards: reputation, influence, heat, logging
    if gangData then
        local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.DRUG_SALE]

        repAmount = math.floor(activityPoints.masterRep * quantity * diminishingMult)
        FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'drug_sale')

        if currentZone then
            local influenceAmount = activityPoints.zoneInfluence * quantity
            AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
        end

        heatAmount = activityPoints.heat * quantity
        FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'drug_sale', FreeGangs.LogCategories.ACTIVITY, {
            drug = drugItem,
            quantity = quantity,
            price = finalPrice,
            modifiers = modifiers,
            zone = currentZone,
        })
    end

    -- Record lifetime crime stat
    RecordCrimeStat(citizenid, 'drug_sale', { cash = finalPrice })

    -- Trigger police dispatch
    TriggerDispatch(source, 'drug_sale', 2, { drug = drugItem, quantity = quantity })

    local drugLabel = FreeGangs.Bridge.GetItemLabel(drugItem) or drugItem
    return true, FreeGangs.L('activities', 'drug_sale_success', quantity, drugLabel, FreeGangs.Bridge.FormatMoney(finalPrice)), {
        drug = drugItem,
        quantity = quantity,
        price = finalPrice,
        modifiers = modifiers,
        rep = repAmount,
        heat = heatAmount,
        diminishing = diminishingMult,
    }
end

-- ============================================================================
-- PROTECTION RACKET SYSTEM
-- ============================================================================

-- In-memory cache for failed registration cooldowns: { [businessId] = { [gangName] = timestamp } }
local protectionFailCooldowns = {}

---Get protection config helper
---@return table
local function GetProtectionConfig()
    return FreeGangs.Config.Activities.Protection or {}
end

---Validate player proximity to business coords
---@param source number Player source
---@param businessCoords table { x, y, z }
---@param maxDistance number
---@return boolean
local function ValidateProtectionProximity(source, businessCoords, maxDistance)
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed == 0 then return false end
    local playerCoords = GetEntityCoords(playerPed)
    local dx = playerCoords.x - (businessCoords.x or businessCoords[1] or 0)
    local dy = playerCoords.y - (businessCoords.y or businessCoords[2] or 0)
    local dz = playerCoords.z - (businessCoords.z or businessCoords[3] or 0)
    return (dx * dx + dy * dy + dz * dz) <= (maxDistance * maxDistance)
end

---Look up a business from config by its ID
---@param businessId string
---@return table|nil
local function FindBusinessConfig(businessId)
    local businesses = GetProtectionConfig().Businesses or {}
    for _, biz in ipairs(businesses) do
        if biz.id == businessId then return biz end
    end
    return nil
end

---Calculate intimidation success chance (strategic formula)
---@param gangName string Attempting gang
---@param zoneName string Zone the business is in
---@param existingProtector string|nil Gang currently protecting (nil if unprotected)
---@return number chance 0-100
---@return table factors Breakdown for logging
local function CalculateIntimidationChance(gangName, zoneName, existingProtector)
    local config = GetProtectionConfig()
    local intim = config.Intimidation or {}
    local minControl = config.MinControlForProtection or 51

    local base = intim.BaseSuccessChance or 50
    local factors = { base = base }

    -- 1) Zone control bonus: +ControlBonus per % above minimum
    local gangInfluence = FreeGangs.Server.Territory.GetInfluence(zoneName, gangName) or 0
    local controlBonus = math.max(0, (gangInfluence - minControl) * (intim.ControlBonus or 0.8))
    factors.controlBonus = FreeGangs.Utils.Round(controlBonus, 1)

    -- 2) Already-extorted penalty
    local extortedPenalty = 0
    if existingProtector and existingProtector ~= gangName then
        extortedPenalty = intim.AlreadyExtortedPenalty or 25
    end
    factors.extortedPenalty = extortedPenalty

    -- 3) Heat penalty with the current protector
    local heatPenalty = 0
    if existingProtector and existingProtector ~= gangName then
        local heatLevel = FreeGangs.Server.Heat.Get(gangName, existingProtector) or 0
        heatPenalty = heatLevel * (intim.HeatPenaltyPerPoint or 0.3)
    end
    factors.heatPenalty = FreeGangs.Utils.Round(heatPenalty, 1)

    -- 4) Total zone contestation penalty (sum of ALL rival influence)
    local contestPenalty = 0
    local territory = FreeGangs.Server.Territories[zoneName]
    if territory and territory.influence then
        local totalRivalInfluence = 0
        for rival, inf in pairs(territory.influence) do
            if rival ~= gangName and inf > 0 then
                totalRivalInfluence = totalRivalInfluence + inf
            end
        end
        contestPenalty = totalRivalInfluence * (intim.ContestationPenalty or 0.2)
    end
    factors.contestPenalty = FreeGangs.Utils.Round(contestPenalty, 1)

    local finalChance = base + controlBonus - extortedPenalty - heatPenalty - contestPenalty
    finalChance = FreeGangs.Utils.Clamp(finalChance, 5, 95) -- Always 5-95% bounds
    factors.final = FreeGangs.Utils.Round(finalChance, 1)

    return finalChance, factors
end

---Register a business for protection (with strategic intimidation)
---@param source number Player source
---@param businessId string Business ID from config
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Activities.RegisterProtection(source, businessId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, FreeGangs.L('errors', 'not_loaded'), nil end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, FreeGangs.L('gangs', 'not_in_gang'), nil end

    if not FreeGangs.Server.HasPermission(source, FreeGangs.Permissions.COLLECT_PROTECTION) then
        return false, FreeGangs.L('general', 'no_permission'), nil
    end

    -- Validate business exists in config
    local bizConfig = FindBusinessConfig(businessId)
    if not bizConfig then return false, FreeGangs.L('activities', 'invalid_target'), nil end

    local config = GetProtectionConfig()
    local zoneName = bizConfig.zone

    -- Validate proximity
    if not ValidateProtectionProximity(source, bizConfig.coords, config.RegistrationDistance or 5.0) then
        return false, FreeGangs.L('activities', 'protection_too_far'), nil
    end

    -- Check zone control meets minimum
    local gangInfluence = FreeGangs.Server.Territory.GetInfluence(zoneName, gangData.gang.name) or 0
    local minControl = config.MinControlForProtection or 51
    if gangInfluence < minControl then
        return false, FreeGangs.L('activities', 'protection_need_control'), nil
    end

    -- Check failed attempt cooldown
    local now = FreeGangs.Utils.GetTimestamp()
    local failCooldown = config.Intimidation and config.Intimidation.FailCooldown or 1800
    local bizCooldowns = protectionFailCooldowns[businessId]
    if bizCooldowns and bizCooldowns[gangData.gang.name] then
        local elapsed = now - bizCooldowns[gangData.gang.name]
        if elapsed < failCooldown then
            return false, FreeGangs.L('activities', 'protection_fail_cooldown'), nil
        end
    end

    -- Check existing protection
    local existing = FreeGangs.Server.DB.GetBusinessProtection(businessId)
    local existingProtector = nil
    if existing and existing.status == 'active' then
        if existing.gang_name == gangData.gang.name then
            return false, FreeGangs.L('activities', 'protection_already_yours'), nil
        end
        existingProtector = existing.gang_name
    end

    -- Calculate intimidation success chance
    local chance, factors = CalculateIntimidationChance(gangData.gang.name, zoneName, existingProtector)

    -- Roll the dice
    local roll = math.random(100)
    local success = roll <= chance

    if not success then
        -- Track fail cooldown
        protectionFailCooldowns[businessId] = protectionFailCooldowns[businessId] or {}
        protectionFailCooldowns[businessId][gangData.gang.name] = now

        -- Add fail heat
        local failHeat = config.Intimidation and config.Intimidation.FailHeat or 5
        FreeGangs.Server.AddPlayerHeat(citizenid, failHeat)

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_intimidation_failed', FreeGangs.LogCategories.ACTIVITY, {
            business_id = businessId, zone = zoneName, chance = chance, roll = roll, factors = factors,
        })

        return false, FreeGangs.L('activities', 'protection_intimidation_fail'), { chance = chance, factors = factors }
    end

    -- Success: register protection
    local payout = math.random(config.BasePayoutMin or 200, config.BasePayoutMax or 800)

    local insertData = {
        gang_name = gangData.gang.name,
        business_id = businessId,
        business_label = bizConfig.label,
        zone_name = zoneName,
        coords = bizConfig.coords,
        payout_base = payout,
        business_type = bizConfig.type or 'npc_shop',
        established_by = citizenid,
    }

    local insertId = FreeGangs.Server.DB.RegisterProtection(insertData)
    if not insertId then return false, FreeGangs.L('errors', 'server_error'), nil end

    -- Activity rewards
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PROTECTION_REGISTER]
    FreeGangs.Server.AddGangReputation(gangData.gang.name, activityPoints.masterRep, citizenid, 'protection_registered')
    if zoneName then
        AddZoneInfluence(zoneName, gangData.gang.name, activityPoints.zoneInfluence)
    end
    FreeGangs.Server.AddPlayerHeat(citizenid, activityPoints.heat)

    -- Record crime stat + dispatch
    RecordCrimeStat(citizenid, 'protection_register', { cash = 0 })
    TriggerDispatch(source, 'extortion', 2, { business = bizConfig.label })

    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_registered', FreeGangs.LogCategories.ACTIVITY, {
        business_id = businessId, business_label = bizConfig.label, zone = zoneName,
        chance = chance, roll = roll, factors = factors, payout_base = payout,
    })

    return true, FreeGangs.L('activities', 'protection_registered', bizConfig.label), {
        business = bizConfig.label,
        chance = chance,
        rep = activityPoints.masterRep,
        heat = activityPoints.heat,
    }
end

---Collect protection money from a business
---@param source number Player source
---@param businessId string Business identifier
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Activities.CollectProtection(source, businessId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, FreeGangs.L('errors', 'not_loaded'), nil end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, FreeGangs.L('gangs', 'not_in_gang'), nil end

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

    -- Validate proximity to business
    local bizConfig = FindBusinessConfig(businessId)
    local config = GetProtectionConfig()
    local collectionDist = config.CollectionDistance or 10.0
    if bizConfig then
        if not ValidateProtectionProximity(source, bizConfig.coords, collectionDist) then
            return false, FreeGangs.L('activities', 'protection_too_far'), nil
        end
    end

    -- Check collection cooldown
    local collectionCooldownHours = config.CollectionIntervalHours or 4
    local collectionCooldown = collectionCooldownHours * 3600
    local lastCollection = protectionCollections[businessId] or 0
    local now = FreeGangs.Utils.GetTimestamp()

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

    -- Claim slot atomically
    protectionCollections[businessId] = now

    -- Check zone control
    local zoneName = protection.zone_name
    local controlTier = GetZoneControlTier(zoneName, gangData.gang.name)

    if not controlTier.canCollectProtection then
        FreeGangs.Server.DB.SuspendProtection(businessId)
        return false, FreeGangs.L('activities', 'protection_suspended'), nil
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
                    return false, FreeGangs.L('activities', 'protection_rivalry_blocked'), nil
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

    -- Apply contested zone penalty (dynamic based on opposition influence)
    if zoneName and controlTier.influence < 80 then
        local oppositionInfluence = 100 - controlTier.influence
        local penaltyPercent = math.floor(oppositionInfluence / 5) * 5
        multiplier = multiplier * (1 - (penaltyPercent / 100))
    end

    local finalPayout = math.floor(basePayout * multiplier)

    -- Persist collection timestamp
    FreeGangs.Server.DB.UpdateProtectionCollection(businessId)

    -- Give money
    FreeGangs.Bridge.AddMoney(source, finalPayout, 'cash', 'protection-collection')

    -- Activity rewards
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PROTECTION_COLLECT]
    FreeGangs.Server.AddGangReputation(gangData.gang.name, activityPoints.masterRep, citizenid, 'protection_collection')

    if zoneName then
        AddZoneInfluence(zoneName, gangData.gang.name, activityPoints.zoneInfluence)
    end

    FreeGangs.Server.AddPlayerHeat(citizenid, activityPoints.heat)

    -- Record crime stat + dispatch
    RecordCrimeStat(citizenid, 'protection_collect', { cash = finalPayout })
    TriggerDispatch(source, 'extortion', 2, { business = protection.business_label or businessId })

    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_collected', FreeGangs.LogCategories.ACTIVITY, {
        business_id = businessId, payout = finalPayout, multiplier = multiplier, zone = zoneName,
    })

    return true, FreeGangs.L('activities', 'protection_collected', FreeGangs.Bridge.FormatMoney(finalPayout)), {
        payout = finalPayout,
        business = protection.business_label or businessId,
        rep = activityPoints.masterRep,
        heat = activityPoints.heat,
    }
end

---Take over a rival gang's protected business
---@param source number Player source
---@param businessId string Business ID
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Activities.TakeoverProtection(source, businessId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, FreeGangs.L('errors', 'not_loaded'), nil end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then return false, FreeGangs.L('gangs', 'not_in_gang'), nil end

    local config = GetProtectionConfig()
    local takeoverConfig = config.Takeover or {}

    if not takeoverConfig.Enabled then
        return false, FreeGangs.L('activities', 'protection_takeover_disabled'), nil
    end

    if not FreeGangs.Server.HasPermission(source, FreeGangs.Permissions.COLLECT_PROTECTION) then
        return false, FreeGangs.L('general', 'no_permission'), nil
    end

    -- Validate business exists
    local bizConfig = FindBusinessConfig(businessId)
    if not bizConfig then return false, FreeGangs.L('activities', 'invalid_target'), nil end

    -- Validate proximity
    if not ValidateProtectionProximity(source, bizConfig.coords, config.RegistrationDistance or 5.0) then
        return false, FreeGangs.L('activities', 'protection_too_far'), nil
    end

    -- Get existing protection (must be owned by a rival)
    local existing = FreeGangs.Server.DB.GetBusinessProtection(businessId)
    if not existing or existing.status ~= 'active' then
        return false, FreeGangs.L('activities', 'invalid_target'), nil
    end

    if existing.gang_name == gangData.gang.name then
        return false, FreeGangs.L('activities', 'protection_already_yours'), nil
    end

    local rivalGang = existing.gang_name
    local zoneName = bizConfig.zone

    -- Check zone control
    local gangInfluence = FreeGangs.Server.Territory.GetInfluence(zoneName, gangData.gang.name) or 0
    local minControl = config.MinControlForProtection or 51
    if gangInfluence < minControl then
        return false, FreeGangs.L('activities', 'protection_need_control'), nil
    end

    -- Check takeover cooldown
    local now = FreeGangs.Utils.GetTimestamp()
    if existing.last_takeover then
        local lastTakeover = FreeGangs.Utils.ParseTimestamp(existing.last_takeover)
        if lastTakeover then
            local cooldown = takeoverConfig.CooldownAfterTakeover or 7200
            if now - lastTakeover < cooldown then
                return false, FreeGangs.L('activities', 'protection_takeover_cooldown'), nil
            end
        end
    end

    -- Check fail cooldown (shares with registration)
    local failCooldown = config.Intimidation and config.Intimidation.FailCooldown or 1800
    local bizCooldowns = protectionFailCooldowns[businessId]
    if bizCooldowns and bizCooldowns[gangData.gang.name] then
        if now - bizCooldowns[gangData.gang.name] < failCooldown then
            return false, FreeGangs.L('activities', 'protection_fail_cooldown'), nil
        end
    end

    -- Calculate intimidation chance with takeover penalty
    local chance, factors = CalculateIntimidationChance(gangData.gang.name, zoneName, rivalGang)
    local takeoverPenalty = takeoverConfig.SuccessPenalty or 15
    chance = FreeGangs.Utils.Clamp(chance - takeoverPenalty, 5, 95)
    factors.takeoverPenalty = takeoverPenalty
    factors.final = FreeGangs.Utils.Round(chance, 1)

    -- Roll
    local roll = math.random(100)
    local success = roll <= chance

    if not success then
        protectionFailCooldowns[businessId] = protectionFailCooldowns[businessId] or {}
        protectionFailCooldowns[businessId][gangData.gang.name] = now

        local failHeat = config.Intimidation and config.Intimidation.FailHeat or 5
        FreeGangs.Server.AddPlayerHeat(citizenid, failHeat)
        AddHeat(gangData.gang.name, rivalGang, failHeat, 'protection_takeover_attempt')

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_takeover_failed', FreeGangs.LogCategories.ACTIVITY, {
            business_id = businessId, rival = rivalGang, zone = zoneName,
            chance = chance, roll = roll, factors = factors,
        })

        return false, FreeGangs.L('activities', 'protection_intimidation_fail'), { chance = chance, factors = factors }
    end

    -- Success: transfer protection
    local newPayout = math.random(config.BasePayoutMin or 200, config.BasePayoutMax or 800)
    FreeGangs.Server.DB.TransferProtection(businessId, gangData.gang.name, citizenid, newPayout)

    -- Generate heat between gangs
    local takeoverHeat = takeoverConfig.HeatGenerated or 20
    AddHeat(gangData.gang.name, rivalGang, takeoverHeat, 'protection_takeover')

    -- Activity rewards
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.PROTECTION_TAKEOVER]
    FreeGangs.Server.AddGangReputation(gangData.gang.name, activityPoints.masterRep, citizenid, 'protection_takeover')
    if zoneName then
        AddZoneInfluence(zoneName, gangData.gang.name, activityPoints.zoneInfluence)
    end
    FreeGangs.Server.AddPlayerHeat(citizenid, activityPoints.heat)

    -- Record crime stat + dispatch
    RecordCrimeStat(citizenid, 'protection_takeover', { cash = 0 })
    TriggerDispatch(source, 'extortion', 3, { business = bizConfig.label })

    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'protection_takeover', FreeGangs.LogCategories.ACTIVITY, {
        business_id = businessId, rival = rivalGang, zone = zoneName,
        chance = chance, roll = roll, factors = factors, heat = takeoverHeat,
    })

    return true, FreeGangs.L('activities', 'protection_takeover_success', rivalGang), {
        business = bizConfig.label,
        rival = rivalGang,
        chance = chance,
        rep = activityPoints.masterRep,
        heat = activityPoints.heat + takeoverHeat,
    }
end

---Get available businesses for a zone (with status info)
---@param gangName string
---@param zoneName string
---@return table businesses List of { id, label, coords, type, pedModel, status, protector, isReady, timeRemaining }
function FreeGangs.Server.Activities.GetZoneBusinesses(gangName, zoneName)
    local config = GetProtectionConfig()
    local businesses = config.Businesses or {}
    local now = FreeGangs.Utils.GetTimestamp()
    local collectionCooldown = (config.CollectionIntervalHours or 4) * 3600

    -- Filter to this zone
    local zoneBusinesses = {}
    for _, biz in ipairs(businesses) do
        if biz.zone == zoneName then
            zoneBusinesses[#zoneBusinesses + 1] = biz
        end
    end

    -- Get existing protection records for this zone
    local zoneProtection = FreeGangs.Server.DB.GetZoneProtection(zoneName)
    local protectionMap = {}
    for _, record in ipairs(zoneProtection) do
        protectionMap[record.business_id] = record
    end

    local result = {}
    for _, biz in ipairs(zoneBusinesses) do
        local record = protectionMap[biz.id]
        local entry = {
            id = biz.id,
            label = biz.label,
            coords = { x = biz.coords.x, y = biz.coords.y, z = biz.coords.z },
            type = biz.type,
            pedModel = biz.pedModel,
            status = 'unprotected',
            protector = nil,
            isReady = false,
            timeRemaining = 0,
            payout_base = 0,
        }

        if record and record.status == 'active' then
            entry.status = record.gang_name == gangName and 'owned' or 'rival'
            entry.protector = record.gang_name
            entry.payout_base = record.payout_base or 0

            if entry.status == 'owned' then
                local lastCollection = 0
                if protectionCollections[biz.id] then
                    lastCollection = protectionCollections[biz.id]
                end
                if record.last_collection then
                    local dbTime = FreeGangs.Utils.ParseTimestamp(record.last_collection)
                    if dbTime and dbTime > lastCollection then lastCollection = dbTime end
                end
                entry.isReady = (now - lastCollection) >= collectionCooldown
                entry.timeRemaining = entry.isReady and 0 or (collectionCooldown - (now - lastCollection))
            end
        end

        result[#result + 1] = entry
    end

    return result
end

---Get all protection businesses for a gang (legacy compat)
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
    
    local newRep = math.max(0, gang.master_rep + amount)
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

-- Player gang data cache: source -> { data, expiry }
local playerGangCache = {}
local GANG_CACHE_TTL = 30 -- Cache for 30 seconds

---Get player's gang data (optimized: single DB query + cache)
---@param source number
---@return table|nil {gang, membership}
function FreeGangs.Server.GetPlayerGangData(source)
    local now = FreeGangs.Utils.GetTimestamp()
    local cached = playerGangCache[source]
    if cached and now < cached.expiry then
        return cached.data
    end

    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end

    -- Single DB query instead of looping all gangs
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or not membership.gang_name then
        playerGangCache[source] = { data = nil, expiry = now + GANG_CACHE_TTL }
        return nil
    end

    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then
        playerGangCache[source] = { data = nil, expiry = now + GANG_CACHE_TTL }
        return nil
    end

    local data = { gang = gang, membership = membership }
    playerGangCache[source] = { data = data, expiry = now + GANG_CACHE_TTL }
    return data
end

---Invalidate a player's cached gang data
---@param source number
function FreeGangs.Server.InvalidatePlayerGangCache(source)
    playerGangCache[source] = nil
end

---Invalidate all cached gang data (e.g., on gang structure changes)
function FreeGangs.Server.InvalidateAllPlayerGangCache()
    playerGangCache = {}
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
-- DB COMPATIBILITY
-- ============================================================================

-- DB.GetMember wrapper: used by heat/war callbacks with (citizenid) or (gangName, citizenid)
if not FreeGangs.Server.DB.GetMember then
    function FreeGangs.Server.DB.GetMember(gangNameOrCitizenid, citizenid)
        if citizenid then
            -- Called as GetMember(gangName, citizenid) - check specific gang
            local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
            if membership and membership.gang_name == gangNameOrCitizenid then
                return membership
            end
            return nil
        else
            -- Called as GetMember(citizenid) - get any gang membership
            return FreeGangs.Server.DB.GetPlayerMembership(gangNameOrCitizenid)
        end
    end
end

-- ============================================================================
-- EXTERNAL DRUG BUYER PED INTEGRATION
-- ============================================================================

---Process a drug sale from an external buyer ped (spawned by another script)
---Awards XP/rep/influence but the calling script handles the transaction
---@param source number Player source
---@param drugItem string Drug item name
---@param quantity number Amount sold
---@param cashEarned number Cash the player received (for stat tracking)
---@return boolean success
---@return table|nil rewards
function FreeGangs.Server.Activities.ProcessExternalDrugSale(source, drugItem, quantity, cashEarned)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, nil end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    local currentZone = FreeGangs.Server.GetPlayerZone(source)

    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    cashEarned = tonumber(cashEarned) or 0

    local repAmount = 0
    local heatAmount = 0

    if gangData then
        local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.DRUG_SALE]
        local stats = GetPlayerHourlyStats(citizenid)
        local diminishingMult = GetDiminishingReturnsMultiplier(stats.drugSales)

        repAmount = math.floor(activityPoints.masterRep * quantity * diminishingMult)
        FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'drug_sale')

        if currentZone then
            local influenceAmount = activityPoints.zoneInfluence * quantity
            AddZoneInfluence(currentZone, gangData.gang.name, influenceAmount)
        end

        heatAmount = activityPoints.heat * quantity
        FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)

        stats.drugSales = stats.drugSales + quantity

        FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'external_drug_sale', FreeGangs.LogCategories.ACTIVITY, {
            drug = drugItem,
            quantity = quantity,
            cash = cashEarned,
            zone = currentZone,
        })
    end

    -- Record lifetime stats
    RecordCrimeStat(citizenid, 'drug_sale', { cash = cashEarned })

    -- Record in dynamic market
    RecordDrugSale(currentZone, drugItem, quantity)

    -- Trigger dispatch
    TriggerDispatch(source, 'drug_sale', 2, { drug = drugItem, quantity = quantity })

    return true, {
        rep = repAmount,
        heat = heatAmount,
    }
end

-- ============================================================================
-- CLEANUP THREADS
-- ============================================================================

CreateThread(function()
    CleanupNPCCooldowns()
    CleanupHourlyStats()
    while true do
        Wait(300000) -- 5 minutes
        CleanupNPCCooldowns()
        CleanupHourlyStats()
    end
end)

-- Drought event check thread (runs hourly)
CreateThread(function()
    Wait(60000) -- Initial 1-minute delay
    while true do
        CheckDroughtEvents()
        Wait(3600000) -- Check every hour
    end
end)

return FreeGangs.Server.Activities
