--[[
    FREE-GANGS: Server Prison Module
    
    Handles prison zone special mechanics including:
    - Prison zone control tracking
    - Smuggle missions
    - Prison guard bribe interactions
    - Contraband delivery
    - Help escape functionality
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Prison = {}

-- Runtime state
local PrisonInfluence = {}           -- gangName -> influence percentage
local ActiveSmuggleMissions = {}     -- gangName -> { missionId, citizenid, items, status }
local JailedMembers = {}             -- gangName -> { citizenid[] }
local ContrabandDeliveries = {}      -- citizenid -> { items, deliveredAt }
local EscapeRequests = {}            -- citizenid -> { requestedBy, gangName, timestamp }

-- ============================================================================
-- PRISON ZONE CONTROL
-- ============================================================================

---Get prison zone control for a gang
---@param gangName string
---@return number controlPercent (0-100)
function FreeGangs.Server.Prison.GetControlLevel(gangName)
    return PrisonInfluence[gangName] or 0
end

---Get all gangs' prison control
---@return table gangInfluence
function FreeGangs.Server.Prison.GetAllControl()
    return FreeGangs.Utils.DeepCopy(PrisonInfluence)
end

---Add prison influence for a gang
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
function FreeGangs.Server.Prison.AddInfluence(gangName, amount, reason)
    if not FreeGangs.Server.Gangs[gangName] then
        return false
    end
    
    local current = PrisonInfluence[gangName] or 0
    local newValue = math.min(100, current + amount)
    
    -- Reduce other gangs proportionally if total would exceed 100
    local totalInfluence = amount
    for gName, influence in pairs(PrisonInfluence) do
        if gName ~= gangName then
            totalInfluence = totalInfluence + influence
        end
    end
    
    if totalInfluence > 100 then
        local reduction = (totalInfluence - 100) / (FreeGangs.Utils.TableLength(PrisonInfluence) - 1)
        for gName, influence in pairs(PrisonInfluence) do
            if gName ~= gangName and influence > 0 then
                PrisonInfluence[gName] = math.max(0, influence - reduction)
            end
        end
    end
    
    PrisonInfluence[gangName] = newValue
    
    -- Check for benefit threshold changes
    FreeGangs.Server.Prison.CheckBenefitThresholds(gangName, current, newValue)
    
    -- Mark dirty for database sync
    FreeGangs.Server.Cache.MarkDirty('prison_influence', gangName)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, nil, 'prison_influence_gained', FreeGangs.LogCategories.ACTIVITY, {
        amount = amount,
        newTotal = newValue,
        reason = reason,
    })
    
    return true
end

---Remove prison influence from a gang
---@param gangName string
---@param amount number
---@param reason string|nil
---@return boolean success
function FreeGangs.Server.Prison.RemoveInfluence(gangName, amount, reason)
    local current = PrisonInfluence[gangName] or 0
    if current <= 0 then return false end
    
    local newValue = math.max(0, current - amount)
    PrisonInfluence[gangName] = newValue
    
    -- Check for benefit threshold changes
    FreeGangs.Server.Prison.CheckBenefitThresholds(gangName, current, newValue)
    
    -- Mark dirty
    FreeGangs.Server.Cache.MarkDirty('prison_influence', gangName)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, nil, 'prison_influence_lost', FreeGangs.LogCategories.ACTIVITY, {
        amount = amount,
        newTotal = newValue,
        reason = reason,
    })
    
    return true
end

---Check if benefit thresholds were crossed
---@param gangName string
---@param oldControl number
---@param newControl number
function FreeGangs.Server.Prison.CheckBenefitThresholds(gangName, oldControl, newControl)
    local config = FreeGangs.Config.Prison.ControlBenefits
    
    for threshold, benefits in pairs(config) do
        -- Gained threshold
        if oldControl < threshold and newControl >= threshold then
            FreeGangs.Server.NotifyGangMembers(gangName, 
                'Prison control reached ' .. threshold .. '%! New benefits unlocked.',
                'success')
            
            FreeGangs.Server.DB.Log(gangName, nil, 'prison_threshold_reached', FreeGangs.LogCategories.SYSTEM, {
                threshold = threshold,
                benefits = benefits,
            })
        -- Lost threshold
        elseif oldControl >= threshold and newControl < threshold then
            FreeGangs.Server.NotifyGangMembers(gangName,
                'Prison control dropped below ' .. threshold .. '%. Benefits lost.',
                'warning')
            
            FreeGangs.Server.DB.Log(gangName, nil, 'prison_threshold_lost', FreeGangs.LogCategories.SYSTEM, {
                threshold = threshold,
            })
        end
    end
end

---Check if gang has specific prison benefit
---@param gangName string
---@param benefit string
---@return boolean
function FreeGangs.Server.Prison.HasBenefit(gangName, benefit)
    local control = FreeGangs.Server.Prison.GetControlLevel(gangName)
    local config = FreeGangs.Config.Prison.ControlBenefits
    
    for threshold, benefits in pairs(config) do
        if control >= threshold then
            for _, b in ipairs(benefits) do
                if b == benefit then
                    return true
                end
            end
        end
    end
    
    return false
end

---Get all active benefits for a gang
---@param gangName string
---@return table benefits
function FreeGangs.Server.Prison.GetActiveBenefits(gangName)
    local control = FreeGangs.Server.Prison.GetControlLevel(gangName)
    local config = FreeGangs.Config.Prison.ControlBenefits
    local benefits = {}
    
    for threshold, thresholdBenefits in pairs(config) do
        if control >= threshold then
            for _, benefit in ipairs(thresholdBenefits) do
                benefits[benefit] = true
            end
        end
    end
    
    return benefits
end

-- ============================================================================
-- JAILED MEMBER TRACKING
-- ============================================================================

---Register a gang member as jailed
---@param citizenid string
---@param gangName string
---@param jailTime number Jail time in seconds
---@return boolean
function FreeGangs.Server.Prison.RegisterJailedMember(citizenid, gangName, jailTime)
    if not JailedMembers[gangName] then
        JailedMembers[gangName] = {}
    end
    
    -- Check if already registered
    for _, id in ipairs(JailedMembers[gangName]) do
        if id == citizenid then
            return false -- Already jailed
        end
    end
    
    table.insert(JailedMembers[gangName], citizenid)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'member_jailed', FreeGangs.LogCategories.ACTIVITY, {
        jailTime = jailTime,
    })
    
    -- Notify gang leadership
    FreeGangs.Server.NotifyGangOfficers(gangName, 
        'A gang member has been jailed. Smuggle missions now available.',
        'inform')
    
    return true
end

---Remove a gang member from jailed status
---@param citizenid string
---@param gangName string
---@return boolean
function FreeGangs.Server.Prison.UnregisterJailedMember(citizenid, gangName)
    if not JailedMembers[gangName] then return false end
    
    for i, id in ipairs(JailedMembers[gangName]) do
        if id == citizenid then
            table.remove(JailedMembers[gangName], i)
            
            FreeGangs.Server.DB.Log(gangName, citizenid, 'member_released', FreeGangs.LogCategories.ACTIVITY, {})
            
            return true
        end
    end
    
    return false
end

---Check if gang has any jailed members
---@param gangName string
---@return boolean
function FreeGangs.Server.Prison.HasJailedMembers(gangName)
    return JailedMembers[gangName] and #JailedMembers[gangName] > 0
end

---Get all jailed members for a gang
---@param gangName string
---@return table citizenids
function FreeGangs.Server.Prison.GetJailedMembers(gangName)
    return JailedMembers[gangName] or {}
end

-- ============================================================================
-- SMUGGLE MISSIONS (TIER 1)
-- ============================================================================

---Start a smuggle mission
---@param source number
---@param gangName string|nil If nil, will be determined from player
---@return boolean success
---@return string|nil message
function FreeGangs.Server.Prison.StartSmuggleMission(source, gangName)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Unable to identify player' end
    
    -- Get gang if not provided
    if not gangName then
        local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
        if not membership then return false, 'You are not in a gang' end
        gangName = membership.gang_name
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    local config = FreeGangs.Config.PrisonActivities.SmuggleMissions
    
    -- Check level requirement
    if gang.master_level < config.minLevel then
        return false, 'Requires Master Level ' .. config.minLevel
    end
    
    -- Check jailed member requirement
    if config.requireJailedMember and not FreeGangs.Server.Prison.HasJailedMembers(gangName) then
        return false, 'Requires a gang member to be jailed'
    end
    
    -- Check cooldown
    local cooldownKey = 'smuggle_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Smuggle missions on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Check if mission already active
    if ActiveSmuggleMissions[gangName] then
        return false, 'A smuggle mission is already in progress'
    end
    
    -- Generate mission
    local missionId = FreeGangs.Utils.GenerateId('sm')
    local missionType = FreeGangs.Server.Prison.SelectMissionType()
    local riskLevel = FreeGangs.Server.Prison.SelectRiskLevel()
    
    -- Get jailed member to deliver to
    local jailedMembers = FreeGangs.Server.Prison.GetJailedMembers(gangName)
    local targetCitizenId = jailedMembers[math.random(#jailedMembers)]
    
    -- Calculate payout
    local basePayout = math.random(config.payout.min, config.payout.max)
    local riskConfig = config.riskLevels[riskLevel]
    local finalPayout = math.floor(basePayout * riskConfig.payoutMult)
    
    -- Select items to smuggle
    local missionTypeConfig = config.types[missionType]
    local itemsToSmuggle = {}
    local itemCount = math.random(1, 3)
    for i = 1, itemCount do
        local item = missionTypeConfig.items[math.random(#missionTypeConfig.items)]
        table.insert(itemsToSmuggle, item)
    end
    
    -- Create mission
    ActiveSmuggleMissions[gangName] = {
        missionId = missionId,
        citizenid = citizenid,
        source = source,
        targetCitizenId = targetCitizenId,
        missionType = missionType,
        riskLevel = riskLevel,
        items = itemsToSmuggle,
        payout = finalPayout,
        rep = config.repReward,
        detectionChance = riskConfig.detectionChance,
        status = 'active',
        startTime = FreeGangs.Utils.GetTimestamp(),
    }
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.cooldown)
    
    -- Send to client
    TriggerClientEvent('free-gangs:client:startSmuggleMission', source, {
        missionId = missionId,
        missionType = missionType,
        riskLevel = riskLevel,
        items = itemsToSmuggle,
        payout = finalPayout,
        targetName = FreeGangs.Bridge.GetPlayerNameByCitizenId(targetCitizenId),
    })
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'smuggle_mission_started', FreeGangs.LogCategories.ACTIVITY, {
        missionId = missionId,
        missionType = missionType,
        riskLevel = riskLevel,
        payout = finalPayout,
    })
    
    return true, 'Smuggle mission started'
end

---Select a random mission type based on weights
---@return string missionType
function FreeGangs.Server.Prison.SelectMissionType()
    local config = FreeGangs.Config.PrisonActivities.SmuggleMissions.types
    local totalWeight = 0
    
    for _, typeConfig in pairs(config) do
        totalWeight = totalWeight + typeConfig.weight
    end
    
    local roll = math.random(totalWeight)
    local cumulative = 0
    
    for typeName, typeConfig in pairs(config) do
        cumulative = cumulative + typeConfig.weight
        if roll <= cumulative then
            return typeName
        end
    end
    
    return 'contraband' -- Fallback
end

---Select a random risk level
---@return string riskLevel
function FreeGangs.Server.Prison.SelectRiskLevel()
    local levels = { 'low', 'medium', 'high' }
    return levels[math.random(#levels)]
end

---Complete a smuggle mission
---@param source number
---@param gangName string
---@param success boolean
---@param detected boolean
---@return boolean
function FreeGangs.Server.Prison.CompleteSmuggleMission(source, gangName, success, detected)
    local mission = ActiveSmuggleMissions[gangName]
    if not mission then return false end
    
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if mission.citizenid ~= citizenid then return false end
    
    if success and not detected then
        -- Full success
        FreeGangs.Bridge.AddMoney(source, mission.payout, 'cash', 'Smuggle mission')
        FreeGangs.Server.Reputation.Add(gangName, mission.rep, 'Smuggle mission completed')
        
        -- Add prison influence
        FreeGangs.Server.Prison.AddInfluence(gangName, 2, 'Smuggle mission')
        
        FreeGangs.Bridge.Notify(source, 'Smuggle mission complete! +$' .. FreeGangs.Utils.FormatMoney(mission.payout), 'success')
        
        FreeGangs.Server.DB.Log(gangName, citizenid, 'smuggle_mission_completed', FreeGangs.LogCategories.ACTIVITY, {
            missionId = mission.missionId,
            payout = mission.payout,
        })
    elseif detected then
        -- Detected - partial or no payout
        local partialPayout = math.floor(mission.payout * 0.25)
        if partialPayout > 0 then
            FreeGangs.Bridge.AddMoney(source, partialPayout, 'cash', 'Smuggle mission (partial)')
        end
        
        FreeGangs.Bridge.Notify(source, 'Detected! Mission compromised. ' .. (partialPayout > 0 and '+$' .. FreeGangs.Utils.FormatMoney(partialPayout) or ''), 'warning')
        
        -- Lose some influence
        FreeGangs.Server.Prison.RemoveInfluence(gangName, 1, 'Smuggle mission detected')
        
        FreeGangs.Server.DB.Log(gangName, citizenid, 'smuggle_mission_detected', FreeGangs.LogCategories.ACTIVITY, {
            missionId = mission.missionId,
        })
    else
        -- Failed
        FreeGangs.Bridge.Notify(source, 'Smuggle mission failed!', 'error')
        
        FreeGangs.Server.Prison.RemoveInfluence(gangName, 2, 'Smuggle mission failed')
        
        FreeGangs.Server.DB.Log(gangName, citizenid, 'smuggle_mission_failed', FreeGangs.LogCategories.ACTIVITY, {
            missionId = mission.missionId,
        })
    end
    
    ActiveSmuggleMissions[gangName] = nil
    return true
end

-- ============================================================================
-- CONTRABAND DELIVERY (GUARD BRIBE ABILITY)
-- ============================================================================

---Deliver contraband to a jailed member
---@param source number
---@param targetCitizenId string
---@param items table Items to deliver
---@return boolean success
---@return string|nil message
function FreeGangs.Server.Prison.DeliverContraband(source, targetCitizenId, items)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Unable to identify player' end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false, 'You are not in a gang' end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    local config = FreeGangs.Config.PrisonActivities.GuardBribes
    
    -- Check level requirement
    if gang.master_level < config.minLevel then
        return false, 'Requires Master Level ' .. config.minLevel
    end
    
    -- Check if target is jailed gang member
    local jailedMembers = FreeGangs.Server.Prison.GetJailedMembers(gangName)
    local isJailed = false
    for _, id in ipairs(jailedMembers) do
        if id == targetCitizenId then
            isJailed = true
            break
        end
    end
    
    if not isJailed then
        return false, 'Target is not a jailed gang member'
    end
    
    -- Check cooldown
    local cooldownKey = 'contraband_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Contraband delivery on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Check cost (free at 50%+ control)
    local cost = config.services.contraband.cost
    if FreeGangs.Server.Prison.HasBenefit(gangName, 'free_contraband') then
        cost = 0
    end
    
    if cost > 0 then
        if FreeGangs.Bridge.GetMoney(source, 'cash') < cost then
            return false, 'Insufficient funds. Need $' .. FreeGangs.Utils.FormatMoney(cost)
        end
        FreeGangs.Bridge.RemoveMoney(source, cost, 'cash', 'Contraband delivery')
    end
    
    -- Check player has items
    for _, item in ipairs(items) do
        if not FreeGangs.Bridge.HasItem(source, item.name, item.count or 1) then
            return false, 'You don\'t have the required items'
        end
    end
    
    -- Remove items from player
    for _, item in ipairs(items) do
        FreeGangs.Bridge.RemoveItem(source, item.name, item.count or 1)
    end
    
    -- Store for jailed player to receive
    ContrabandDeliveries[targetCitizenId] = {
        items = items,
        deliveredBy = citizenid,
        deliveredAt = FreeGangs.Utils.GetTimestamp(),
    }
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.services.contraband.cooldown)
    
    -- Notify jailed player if online
    local jailedPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(targetCitizenId)
    if jailedPlayer then
        TriggerClientEvent('free-gangs:client:contrabandReady', jailedPlayer.PlayerData.source, items)
        FreeGangs.Bridge.Notify(jailedPlayer.PlayerData.source, 'Contraband package ready for pickup', 'inform')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'contraband_delivered', FreeGangs.LogCategories.ACTIVITY, {
        target = targetCitizenId,
        items = items,
        cost = cost,
    })
    
    FreeGangs.Bridge.Notify(source, 'Contraband delivered successfully' .. (cost > 0 and '. Cost: $' .. FreeGangs.Utils.FormatMoney(cost) or ''), 'success')
    
    return true, 'Contraband delivered'
end

---Claim contraband delivery (called by jailed player)
---@param source number
---@return boolean success
---@return table|nil items
function FreeGangs.Server.Prison.ClaimContraband(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, nil end
    
    local delivery = ContrabandDeliveries[citizenid]
    if not delivery then return false, nil end
    
    -- Give items to player
    for _, item in ipairs(delivery.items) do
        FreeGangs.Bridge.AddItem(source, item.name, item.count or 1)
    end
    
    -- Clear delivery
    ContrabandDeliveries[citizenid] = nil
    
    FreeGangs.Bridge.Notify(source, 'Contraband collected', 'success')
    
    return true, delivery.items
end

-- ============================================================================
-- HELP ESCAPE (GUARD BRIBE ABILITY)
-- ============================================================================

---Initiate a prison escape for a member
---@param source number
---@param targetCitizenId string
---@return boolean success
---@return string|nil message
function FreeGangs.Server.Prison.HelpEscape(source, targetCitizenId)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false, 'Unable to identify player' end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false, 'You are not in a gang' end
    
    local gangName = membership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    local config = FreeGangs.Config.PrisonActivities.GuardBribes
    
    -- Check level requirement
    if gang.master_level < config.minLevel then
        return false, 'Requires Master Level ' .. config.minLevel
    end
    
    -- Check if target is jailed gang member
    local jailedMembers = FreeGangs.Server.Prison.GetJailedMembers(gangName)
    local isJailed = false
    for _, id in ipairs(jailedMembers) do
        if id == targetCitizenId then
            isJailed = true
            break
        end
    end
    
    if not isJailed then
        return false, 'Target is not a jailed gang member'
    end
    
    -- Check cooldown
    local cooldownKey = 'help_escape_' .. gangName
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(source, cooldownKey)
    if onCooldown then
        return false, 'Help escape on cooldown. ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' remaining'
    end
    
    -- Calculate cost (reduced at 75%+ control)
    local cost = config.services.helpEscape.cost
    if FreeGangs.Server.Prison.HasBenefit(gangName, 'reduced_escape_cost') then
        cost = FreeGangs.Config.PrisonActivities.PrisonControl.benefits.reducedEscapeCost
    end
    
    -- Check funds
    if FreeGangs.Bridge.GetMoney(source, 'cash') < cost then
        return false, 'Insufficient funds. Need $' .. FreeGangs.Utils.FormatMoney(cost)
    end
    
    -- Remove payment
    FreeGangs.Bridge.RemoveMoney(source, cost, 'cash', 'Prison escape bribe')
    
    -- Store escape request
    EscapeRequests[targetCitizenId] = {
        requestedBy = citizenid,
        gangName = gangName,
        timestamp = FreeGangs.Utils.GetTimestamp(),
        cost = cost,
    }
    
    -- Set cooldown
    FreeGangs.Server.SetCooldown(source, cooldownKey, config.services.helpEscape.cooldown)
    
    -- Trigger escape for jailed player
    local jailedPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(targetCitizenId)
    if jailedPlayer then
        -- This would integrate with the jail script
        -- For now, send event that jail scripts can listen to
        TriggerEvent('free-gangs:server:prisonEscapeInitiated', targetCitizenId, gangName)
        TriggerClientEvent('free-gangs:client:escapeInitiated', jailedPlayer.PlayerData.source)
        FreeGangs.Bridge.Notify(jailedPlayer.PlayerData.source, 'Escape route opened! Move quickly!', 'success')
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'prison_escape_initiated', FreeGangs.LogCategories.ACTIVITY, {
        target = targetCitizenId,
        cost = cost,
    })
    
    FreeGangs.Bridge.Notify(source, 'Prison escape initiated. Cost: $' .. FreeGangs.Utils.FormatMoney(cost), 'success')
    
    -- Add prison influence
    FreeGangs.Server.Prison.AddInfluence(gangName, 3, 'Prison escape')
    
    return true, 'Escape initiated'
end

---Complete prison escape (called when player escapes)
---@param citizenid string
function FreeGangs.Server.Prison.CompleteEscape(citizenid)
    local escapeRequest = EscapeRequests[citizenid]
    if not escapeRequest then return end
    
    local gangName = escapeRequest.gangName
    
    -- Remove from jailed list
    FreeGangs.Server.Prison.UnregisterJailedMember(citizenid, gangName)
    
    -- Clear request
    EscapeRequests[citizenid] = nil
    
    -- Notify gang
    FreeGangs.Server.NotifyGangMembers(gangName, 'Prison escape successful!', 'success')
    
    -- Bonus rep
    FreeGangs.Server.Reputation.Add(gangName, 25, 'Successful prison escape')
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'prison_escape_completed', FreeGangs.LogCategories.ACTIVITY, {})
end

-- ============================================================================
-- PRISON CONTROL TIER 3 (51%+ Control)
-- ============================================================================

---Check if gang has full prison control benefits
---@param gangName string
---@return boolean, table|nil benefits
function FreeGangs.Server.Prison.HasFullControl(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, nil end
    
    local config = FreeGangs.Config.PrisonActivities.PrisonControl
    
    -- Check level requirement
    if gang.master_level < config.minLevel then
        return false, nil
    end
    
    -- Check control requirement
    local control = FreeGangs.Server.Prison.GetControlLevel(gangName)
    if control < config.minControl then
        return false, nil
    end
    
    return true, config.benefits
end

---Get jail time reduction for a gang member
---@param gangName string
---@return number reductionPercent (0-1)
function FreeGangs.Server.Prison.GetJailTimeReduction(gangName)
    local hasControl, benefits = FreeGangs.Server.Prison.HasFullControl(gangName)
    if not hasControl then return 0 end
    
    return benefits.jailReduction or 0
end

-- ============================================================================
-- PRISON INFLUENCE DECAY
-- ============================================================================

---Process prison influence decay (called periodically)
function FreeGangs.Server.Prison.ProcessDecay()
    local decayAmount = 1 -- 1% decay per cycle
    
    for gangName, influence in pairs(PrisonInfluence) do
        if influence > 0 then
            FreeGangs.Server.Prison.RemoveInfluence(gangName, decayAmount, 'Natural decay')
        end
    end
    
    if FreeGangs.Debug then
        print('[FREE-GANGS] Prison influence decay processed')
    end
end

-- ============================================================================
-- DATA RETRIEVAL
-- ============================================================================

---Get prison data for client
---@param gangName string
---@return table
function FreeGangs.Server.Prison.GetDataForClient(gangName)
    local control = FreeGangs.Server.Prison.GetControlLevel(gangName)
    local benefits = FreeGangs.Server.Prison.GetActiveBenefits(gangName)
    local jailedMembers = FreeGangs.Server.Prison.GetJailedMembers(gangName)
    local hasFullControl, fullControlBenefits = FreeGangs.Server.Prison.HasFullControl(gangName)
    
    return {
        control = control,
        benefits = benefits,
        jailedMemberCount = #jailedMembers,
        hasJailedMembers = #jailedMembers > 0,
        hasFullControl = hasFullControl,
        fullControlBenefits = fullControlBenefits,
        allGangControl = FreeGangs.Server.Prison.GetAllControl(),
    }
end

---Get leaderboard of prison control
---@return table leaderboard
function FreeGangs.Server.Prison.GetLeaderboard()
    local leaderboard = {}
    
    for gangName, influence in pairs(PrisonInfluence) do
        local gang = FreeGangs.Server.Gangs[gangName]
        if gang and influence > 0 then
            table.insert(leaderboard, {
                gangName = gangName,
                label = gang.label,
                color = gang.color,
                influence = influence,
            })
        end
    end
    
    -- Sort by influence descending
    table.sort(leaderboard, function(a, b)
        return a.influence > b.influence
    end)
    
    return leaderboard
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize prison module
function FreeGangs.Server.Prison.Initialize()
    -- Load prison influence from database
    local influenceData = MySQL.query.await('SELECT gang_name, influence FROM freegangs_prison_influence')
    if influenceData then
        for _, row in ipairs(influenceData) do
            PrisonInfluence[row.gang_name] = row.influence
        end
    end
    
    -- Load jailed members
    local jailedData = MySQL.query.await([[
        SELECT citizenid, gang_name FROM freegangs_jailed_members
        WHERE released_at IS NULL
    ]])
    if jailedData then
        for _, row in ipairs(jailedData) do
            if not JailedMembers[row.gang_name] then
                JailedMembers[row.gang_name] = {}
            end
            table.insert(JailedMembers[row.gang_name], row.citizenid)
        end
    end
    
    if FreeGangs.Debug then
        print('[FREE-GANGS] Prison module initialized')
        print('[FREE-GANGS] - Loaded influence for ' .. FreeGangs.Utils.TableLength(PrisonInfluence) .. ' gangs')
        print('[FREE-GANGS] - Loaded ' .. FreeGangs.Utils.TableLength(JailedMembers) .. ' gangs with jailed members')
    end
end

---Save prison data to database
function FreeGangs.Server.Prison.SaveToDatabase()
    for gangName, influence in pairs(PrisonInfluence) do
        MySQL.query('INSERT INTO freegangs_prison_influence (gang_name, influence) VALUES (?, ?) ON DUPLICATE KEY UPDATE influence = ?', {
            gangName, influence, influence
        })
    end
end

-- ============================================================================
-- EVENT HANDLERS (Integration with jail scripts)
-- ============================================================================

-- Hook into jail events (server admins should connect their jail script)
-- Example: qb-prison, rcore_prison, etc.

---Event: Player was jailed
---@param citizenid string
---@param jailTime number
RegisterNetEvent('free-gangs:server:playerJailed', function(citizenid, jailTime)
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if membership then
        FreeGangs.Server.Prison.RegisterJailedMember(citizenid, membership.gang_name, jailTime)
    end
end)

---Event: Player was released from jail
---@param citizenid string
RegisterNetEvent('free-gangs:server:playerReleased', function(citizenid)
    -- Find which gang they're in and unregister
    for gangName, members in pairs(JailedMembers) do
        for i, id in ipairs(members) do
            if id == citizenid then
                FreeGangs.Server.Prison.UnregisterJailedMember(citizenid, gangName)
                return
            end
        end
    end
end)

---Event: Player escaped from prison
---@param citizenid string
RegisterNetEvent('free-gangs:server:playerEscaped', function(citizenid)
    FreeGangs.Server.Prison.CompleteEscape(citizenid)
end)

return FreeGangs.Server.Prison
