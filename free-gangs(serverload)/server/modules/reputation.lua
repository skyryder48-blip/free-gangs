--[[
    FREE-GANGS: Reputation System Module
    
    Handles master reputation tracking, level progression, and decay.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Reputation = {}

-- Track recent activity for diminishing returns
local recentActivity = {} -- gangName -> { activity -> { count, lastReset } }

-- ============================================================================
-- REPUTATION MANAGEMENT
-- ============================================================================

---Add reputation to a gang
---@param gangName string
---@param amount number
---@param activity string|nil Activity type that generated the rep
---@param source number|nil Player source for logging
---@return number actualAmount The actual amount added after modifiers
function FreeGangs.Server.Reputation.Add(gangName, amount, activity, source)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return 0 end
    
    local originalAmount = amount
    
    -- Apply activity multipliers from config
    if activity then
        local multipliers = FreeGangs.Config.Reputation.Multipliers
        if multipliers[activity] then
            amount = math.floor(amount * multipliers[activity])
        end
        
        -- Apply diminishing returns for certain activities
        if FreeGangs.Config.Reputation.DiminishingReturns.Enabled then
            amount = FreeGangs.Server.Reputation.ApplyDiminishingReturns(gangName, activity, amount)
        end
    end
    
    -- Apply archetype bonuses
    amount = FreeGangs.Server.Reputation.ApplyArchetypeBonuses(gangName, activity, amount)
    
    -- Calculate new rep
    local oldRep = gang.master_rep or 0
    local newRep = oldRep + amount
    
    -- Ensure minimum
    newRep = math.max(FreeGangs.Config.Reputation.MinReputation, newRep)
    
    -- Update gang
    gang.master_rep = newRep
    
    -- Check for level change
    local oldLevel = gang.master_level
    local newLevel = FreeGangs.GetReputationLevel(newRep)
    
    if newLevel ~= oldLevel then
        gang.master_level = newLevel
        FreeGangs.Server.Reputation.OnLevelChange(gangName, oldLevel, newLevel)
    end
    
    -- Mark for cache flush
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Sync to GlobalState
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    -- Log if significant
    if amount ~= 0 then
        local citizenid = source and FreeGangs.Bridge.GetCitizenId(source) or nil
        FreeGangs.Server.DB.Log(gangName, citizenid, 'reputation_gain', FreeGangs.LogCategories.REPUTATION, {
            amount = amount,
            originalAmount = originalAmount,
            activity = activity,
            oldRep = oldRep,
            newRep = newRep,
        })
    end
    
    return amount
end

---Remove reputation from a gang
---@param gangName string
---@param amount number
---@param reason string|nil
---@param source number|nil
---@return number actualAmount
function FreeGangs.Server.Reputation.Remove(gangName, amount, reason, source)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return 0 end
    
    local oldRep = gang.master_rep or 0
    local newRep = math.max(FreeGangs.Config.Reputation.MinReputation, oldRep - amount)
    local actualLoss = oldRep - newRep
    
    gang.master_rep = newRep
    
    -- Check for level change
    local oldLevel = gang.master_level
    local newLevel = FreeGangs.GetReputationLevel(newRep)
    
    if newLevel ~= oldLevel then
        gang.master_level = newLevel
        FreeGangs.Server.Reputation.OnLevelChange(gangName, oldLevel, newLevel)
    end
    
    -- Mark for cache flush
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Sync
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    -- Log
    if actualLoss > 0 then
        local citizenid = source and FreeGangs.Bridge.GetCitizenId(source) or nil
        FreeGangs.Server.DB.Log(gangName, citizenid, 'reputation_loss', FreeGangs.LogCategories.REPUTATION, {
            amount = actualLoss,
            reason = reason,
            oldRep = oldRep,
            newRep = newRep,
        })
    end
    
    return actualLoss
end

---Set reputation directly (admin use)
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean
function FreeGangs.Server.Reputation.Set(gangName, amount, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    local oldRep = gang.master_rep
    local oldLevel = gang.master_level
    
    gang.master_rep = math.max(FreeGangs.Config.Reputation.MinReputation, amount)
    gang.master_level = FreeGangs.GetReputationLevel(gang.master_rep)
    
    if gang.master_level ~= oldLevel then
        FreeGangs.Server.Reputation.OnLevelChange(gangName, oldLevel, gang.master_level)
    end
    
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    FreeGangs.Server.DB.Log(gangName, nil, 'reputation_set', FreeGangs.LogCategories.ADMIN, {
        oldRep = oldRep,
        newRep = gang.master_rep,
        reason = reason,
    })
    
    return true
end

-- ============================================================================
-- LEVEL CHANGE HANDLING
-- ============================================================================

---Handle level change events
---@param gangName string
---@param oldLevel number
---@param newLevel number
function FreeGangs.Server.Reputation.OnLevelChange(gangName, oldLevel, newLevel)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end
    
    local levelInfo = FreeGangs.ReputationLevels[newLevel]
    local isLevelUp = newLevel > oldLevel
    
    -- Notify gang
    local message
    if isLevelUp then
        message = string.format(FreeGangs.Config.Messages.LevelUp, newLevel, levelInfo.name)
        FreeGangs.Bridge.NotifyGang(gangName, message, 'success')
    else
        message = string.format(FreeGangs.Config.Messages.LevelDown, newLevel, levelInfo.name)
        FreeGangs.Bridge.NotifyGang(gangName, message, 'error')
    end
    
    -- Update all online members with new data
    local onlineMembers = FreeGangs.Server.Member.GetOnlineMembers(gangName)
    for _, member in pairs(onlineMembers) do
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, member.source, {
            gang = FreeGangs.Server.Gang.GetClientData(gangName),
            levelChange = {
                oldLevel = oldLevel,
                newLevel = newLevel,
                isLevelUp = isLevelUp,
            },
        })
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, nil, 'level_change', FreeGangs.LogCategories.REPUTATION, {
        oldLevel = oldLevel,
        newLevel = newLevel,
        isLevelUp = isLevelUp,
    })
    
    -- Discord webhook
    FreeGangs.Server.SendDiscordWebhook('Gang Level ' .. (isLevelUp and 'Up' or 'Down'), string.format(
        '**%s** has %s to Level %d (%s)',
        gang.label,
        isLevelUp and 'risen' or 'fallen',
        newLevel,
        levelInfo.name
    ), isLevelUp and 3066993 or 15158332)
    
    -- Handle unlock/lock of features
    if isLevelUp then
        FreeGangs.Server.Reputation.ProcessUnlocks(gangName, oldLevel, newLevel)
    else
        FreeGangs.Server.Reputation.ProcessLocks(gangName, newLevel, oldLevel)
    end
end

---Process unlocked features on level up
---@param gangName string
---@param fromLevel number
---@param toLevel number
function FreeGangs.Server.Reputation.ProcessUnlocks(gangName, fromLevel, toLevel)
    for level = fromLevel + 1, toLevel do
        local levelData = FreeGangs.ReputationLevels[level]
        if levelData and levelData.unlocks then
            for _, unlock in pairs(levelData.unlocks) do
                FreeGangs.Utils.Debug('Gang ' .. gangName .. ' unlocked: ' .. unlock)
                -- Future: Could trigger specific events for unlocks
            end
        end
    end
end

---Process locked features on level down
---@param gangName string
---@param currentLevel number
---@param previousLevel number
function FreeGangs.Server.Reputation.ProcessLocks(gangName, currentLevel, previousLevel)
    -- Check if territories need to be reduced
    local maxTerritories = FreeGangs.GetMaxTerritories(currentLevel)
    local currentTerritories = FreeGangs.Server.GetGangTerritories(gangName)
    local territoryCount = FreeGangs.Utils.TableLength(currentTerritories)
    
    if territoryCount > maxTerritories and maxTerritories > 0 then
        -- Notify that some territories may be lost
        FreeGangs.Bridge.NotifyGang(gangName, 
            'Warning: You now exceed your maximum territory limit. Maintain your influence or risk losing control.', 
            'warning')
    end
end

-- ============================================================================
-- DIMINISHING RETURNS
-- ============================================================================

---Apply diminishing returns to reputation gain
---@param gangName string
---@param activity string
---@param amount number
---@return number
function FreeGangs.Server.Reputation.ApplyDiminishingReturns(gangName, activity, amount)
    if not activity then return amount end
    
    local config = FreeGangs.Config.Reputation.DiminishingReturns
    
    -- Only apply to drug sales currently
    if activity ~= 'DrugSale' then return amount end
    
    -- Initialize tracking
    if not recentActivity[gangName] then
        recentActivity[gangName] = {}
    end
    
    if not recentActivity[gangName][activity] then
        recentActivity[gangName][activity] = {
            count = 0,
            lastReset = FreeGangs.Utils.GetTimestamp(),
        }
    end
    
    local tracking = recentActivity[gangName][activity]
    local currentTime = FreeGangs.Utils.GetTimestamp()
    
    -- Reset hourly
    if currentTime - tracking.lastReset > 3600 then
        tracking.count = 0
        tracking.lastReset = currentTime
    end
    
    tracking.count = tracking.count + 1
    
    -- Apply diminishing returns if over threshold
    if tracking.count > config.SalesThreshold then
        local overThreshold = tracking.count - config.SalesThreshold
        local multiplier = math.max(config.MinMultiplier, 1 - (overThreshold * config.DecayRate))
        amount = math.floor(amount * multiplier)
    end
    
    return amount
end

-- ============================================================================
-- ARCHETYPE BONUSES
-- ============================================================================

---Apply archetype-specific bonuses to reputation
---@param gangName string
---@param activity string|nil
---@param amount number
---@return number
function FreeGangs.Server.Reputation.ApplyArchetypeBonuses(gangName, activity, amount)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang or not activity then return amount end
    
    local passives = FreeGangs.ArchetypePassiveBonuses[gang.archetype]
    if not passives then return amount end
    
    -- Street Gang: +20% from drug sales
    if gang.archetype == FreeGangs.Archetypes.STREET and activity == 'DrugSale' then
        amount = math.floor(amount * (1 + passives.drugProfit))
    end
    
    -- Crime Family: +25% from protection
    if gang.archetype == FreeGangs.Archetypes.CRIME_FAMILY and activity == 'Protection' then
        amount = math.floor(amount * (1 + passives.protectionIncome))
    end
    
    return amount
end

-- ============================================================================
-- DECAY PROCESSING
-- ============================================================================

---Process reputation decay for all gangs (called from background task)
function FreeGangs.Server.Reputation.ProcessDecay()
    local config = FreeGangs.Config.Reputation
    local decayAmount = config.DecayAmount
    
    for gangName, gang in pairs(FreeGangs.Server.Gangs) do
        if gang.master_rep > 0 then
            -- Base decay
            FreeGangs.Server.Reputation.Remove(gangName, decayAmount, 'periodic_decay')
            
            -- Additional decay for inactive gangs (no territory)
            local territories = FreeGangs.Server.GetGangTerritories(gangName)
            local hasTerritory = false
            
            for _, territory in pairs(territories) do
                if territory.influence >= FreeGangs.Config.Territory.MinInfluenceForBenefits then
                    hasTerritory = true
                    break
                end
            end
            
            if not hasTerritory then
                -- Check inactivity duration (would need to track this)
                -- For now, apply additional decay
                FreeGangs.Server.Reputation.Remove(gangName, config.InactivityDecayAmount, 'inactivity_decay')
            end
        end
    end
    
    FreeGangs.Utils.Debug('Processed reputation decay for all gangs')
end

-- ============================================================================
-- ACTIVITY REPUTATION REWARDS
-- ============================================================================

---Award reputation for an activity
---@param gangName string
---@param activityType string Activity type from FreeGangs.Activities
---@param source number|nil Player source
---@param multiplier number|nil Optional multiplier
---@return number repAwarded
function FreeGangs.Server.Reputation.AwardForActivity(gangName, activityType, source, multiplier)
    local activityData = FreeGangs.ActivityValues[activityType]
    if not activityData then return 0 end
    
    local repAmount = activityData.masterRep
    if repAmount == 0 then return 0 end
    
    if multiplier then
        repAmount = math.floor(repAmount * multiplier)
    end
    
    if repAmount > 0 then
        return FreeGangs.Server.Reputation.Add(gangName, repAmount, activityType, source)
    elseif repAmount < 0 then
        return -FreeGangs.Server.Reputation.Remove(gangName, math.abs(repAmount), activityType, source)
    end
    
    return 0
end

-- ============================================================================
-- QUERIES
-- ============================================================================

---Get reputation info for display
---@param gangName string
---@return table|nil
function FreeGangs.Server.Reputation.GetInfo(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return nil end
    
    local currentLevel = gang.master_level
    local currentRep = gang.master_rep
    local levelInfo = FreeGangs.ReputationLevels[currentLevel]
    local nextLevelInfo = FreeGangs.ReputationLevels[currentLevel + 1]
    
    local progress = 100
    local repToNextLevel = 0
    
    if nextLevelInfo then
        local repInLevel = currentRep - levelInfo.repRequired
        local repNeeded = nextLevelInfo.repRequired - levelInfo.repRequired
        progress = math.floor((repInLevel / repNeeded) * 100)
        repToNextLevel = nextLevelInfo.repRequired - currentRep
    end
    
    return {
        currentRep = currentRep,
        currentLevel = currentLevel,
        levelName = levelInfo.name,
        progress = progress,
        repToNextLevel = repToNextLevel,
        nextLevelName = nextLevelInfo and nextLevelInfo.name or 'MAX',
        maxTerritories = FreeGangs.GetMaxTerritories(currentLevel),
        unlocks = levelInfo.unlocks,
    }
end

---Check if gang has unlocked a feature
---@param gangName string
---@param feature string
---@return boolean
function FreeGangs.Server.Reputation.HasUnlock(gangName, feature)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    local level = gang.master_level
    
    for lvl = 1, level do
        local levelData = FreeGangs.ReputationLevels[lvl]
        if levelData and levelData.unlocks then
            for _, unlock in pairs(levelData.unlocks) do
                if unlock == feature then
                    return true
                end
            end
        end
    end
    
    return false
end

-- ============================================================================
-- EXPORTS REGISTRATION
-- ============================================================================

-- These will be registered in server/main.lua
FreeGangs.Server.Reputation.Exports = {
    AddMasterRep = function(gangName, amount, reason)
        return FreeGangs.Server.Reputation.Add(gangName, amount, reason)
    end,
    
    RemoveMasterRep = function(gangName, amount, reason)
        return FreeGangs.Server.Reputation.Remove(gangName, amount, reason)
    end,
    
    GetMasterRep = function(gangName)
        local gang = FreeGangs.Server.Gangs[gangName]
        return gang and gang.master_rep or 0
    end,
    
    GetMasterLevel = function(gangName)
        local gang = FreeGangs.Server.Gangs[gangName]
        return gang and gang.master_level or 0
    end,
}

return FreeGangs.Server.Reputation
