--[[
    FREE-GANGS: Heat System Module
    
    Handles inter-gang heat (tension/rivalry) tracking, escalation stages,
    heat decay, and integration with war declaration requirements.
    
    Heat represents the tension level between two gangs, ranging from 0-100.
    Higher heat unlocks war declaration and applies negative effects.
]]

-- Ensure module namespace exists
FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Heat = {}

-- ============================================================================
-- LOCAL CONSTANTS
-- ============================================================================

local HEAT_MIN = 0
local HEAT_MAX = 100

-- ============================================================================
-- HEAT KEY GENERATION
-- ============================================================================

---Generate a unique heat key for a gang pair
---@param gangA string
---@param gangB string
---@return string key
local function GetHeatKey(gangA, gangB)
    -- Always order alphabetically for consistent keys
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    return gangA .. '_' .. gangB
end

---Parse a heat key back to gang names
---@param key string
---@return string gangA, string gangB
local function ParseHeatKey(key)
    local parts = FreeGangs.Utils.Split(key, '_')
    return parts[1], parts[2]
end

-- ============================================================================
-- HEAT DATA MANAGEMENT
-- ============================================================================

---Get heat data from cache or create new
---@param gangA string
---@param gangB string
---@return table heatData
local function GetOrCreateHeatData(gangA, gangB)
    local key = GetHeatKey(gangA, gangB)
    
    if FreeGangs.Server.Heat[key] then
        return FreeGangs.Server.Heat[key]
    end
    
    -- Create new heat record
    local orderedA, orderedB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    local newHeat = {
        gang_a = orderedA,
        gang_b = orderedB,
        heat_level = 0,
        stage = FreeGangs.HeatStages.NEUTRAL,
        last_incident = nil,
        last_decay = os.time(),
    }
    
    FreeGangs.Server.Heat[key] = newHeat
    return newHeat
end

---Save heat data to database (through cache system)
---@param gangA string
---@param gangB string
local function MarkHeatDirty(gangA, gangB)
    local key = GetHeatKey(gangA, gangB)
    FreeGangs.Server.Cache.MarkDirty('heat', key)
end

-- ============================================================================
-- CORE HEAT FUNCTIONS
-- ============================================================================

---Add heat between two gangs
---@param gangA string First gang name
---@param gangB string Second gang name
---@param amount number Heat points to add
---@param reason string|nil Reason for heat increase
---@return number newHeat The new heat level
---@return string|nil stageChange If stage changed, the new stage name
function FreeGangs.Server.Heat.Add(gangA, gangB, amount, reason)
    -- Validate gangs exist
    if not FreeGangs.Server.Gangs[gangA] or not FreeGangs.Server.Gangs[gangB] then
        FreeGangs.Utils.Debug('Heat.Add: Invalid gang(s)', gangA, gangB)
        return 0, nil
    end
    
    -- Can't have heat with yourself
    if gangA == gangB then
        return 0, nil
    end
    
    local heatData = GetOrCreateHeatData(gangA, gangB)
    local oldHeat = heatData.heat_level
    local oldStage = heatData.stage
    
    -- Calculate new heat (clamped)
    local newHeat = FreeGangs.Utils.Clamp(oldHeat + amount, HEAT_MIN, HEAT_MAX)
    local newStage = FreeGangs.Utils.GetHeatStage(newHeat)
    
    -- Update heat data
    heatData.heat_level = newHeat
    heatData.stage = newStage
    heatData.last_incident = os.time()
    
    -- Mark dirty for database persistence
    MarkHeatDirty(gangA, gangB)
    
    -- Upsert to database immediately for persistence
    FreeGangs.Server.DB.UpsertHeat(gangA, gangB, newHeat, newStage)
    
    -- Log the heat change
    FreeGangs.Server.DB.Log(gangA, nil, 'heat_added', FreeGangs.LogCategories.WAR, {
        target_gang = gangB,
        amount = amount,
        old_heat = oldHeat,
        new_heat = newHeat,
        reason = reason,
    })
    
    -- Check for stage change
    local stageChanged = oldStage ~= newStage
    if stageChanged then
        FreeGangs.Server.Heat.OnStageChange(gangA, gangB, oldStage, newStage)
    end
    
    -- Notify clients of heat change
    FreeGangs.Server.Heat.SyncToClients(gangA, gangB)
    
    FreeGangs.Utils.Debug(string.format(
        'Heat added: %s <-> %s: %d -> %d (stage: %s)',
        gangA, gangB, oldHeat, newHeat, newStage
    ))
    
    return newHeat, stageChanged and newStage or nil
end

---Remove heat between two gangs
---@param gangA string First gang name
---@param gangB string Second gang name
---@param amount number Heat points to remove
---@param reason string|nil Reason for heat decrease
---@return number newHeat The new heat level
function FreeGangs.Server.Heat.Remove(gangA, gangB, amount, reason)
    local heatData = GetOrCreateHeatData(gangA, gangB)
    local oldHeat = heatData.heat_level
    local oldStage = heatData.stage
    
    -- Calculate new heat (clamped)
    local newHeat = FreeGangs.Utils.Clamp(oldHeat - amount, HEAT_MIN, HEAT_MAX)
    local newStage = FreeGangs.Utils.GetHeatStage(newHeat)
    
    -- Update heat data
    heatData.heat_level = newHeat
    heatData.stage = newStage
    
    -- Mark dirty for database persistence
    MarkHeatDirty(gangA, gangB)
    
    -- Log if significant change
    if amount >= 10 then
        FreeGangs.Server.DB.Log(gangA, nil, 'heat_removed', FreeGangs.LogCategories.WAR, {
            target_gang = gangB,
            amount = amount,
            old_heat = oldHeat,
            new_heat = newHeat,
            reason = reason,
        })
    end
    
    -- Check for stage change
    if oldStage ~= newStage then
        FreeGangs.Server.Heat.OnStageChange(gangA, gangB, oldStage, newStage)
    end
    
    -- Sync to clients
    FreeGangs.Server.Heat.SyncToClients(gangA, gangB)
    
    return newHeat
end

---Set heat between two gangs directly
---@param gangA string First gang name
---@param gangB string Second gang name
---@param heat number Heat level to set (0-100)
---@param reason string|nil Reason for direct set
---@return number newHeat The set heat level
function FreeGangs.Server.Heat.Set(gangA, gangB, heat, reason)
    local heatData = GetOrCreateHeatData(gangA, gangB)
    local oldHeat = heatData.heat_level
    local oldStage = heatData.stage
    
    -- Clamp heat value
    local newHeat = FreeGangs.Utils.Clamp(heat, HEAT_MIN, HEAT_MAX)
    local newStage = FreeGangs.Utils.GetHeatStage(newHeat)
    
    -- Update heat data
    heatData.heat_level = newHeat
    heatData.stage = newStage
    
    if heat > 0 then
        heatData.last_incident = os.time()
    end
    
    -- Mark dirty for database persistence
    MarkHeatDirty(gangA, gangB)
    
    -- Upsert to database
    FreeGangs.Server.DB.UpsertHeat(gangA, gangB, newHeat, newStage)
    
    -- Log the change
    FreeGangs.Server.DB.Log(gangA, nil, 'heat_set', FreeGangs.LogCategories.WAR, {
        target_gang = gangB,
        old_heat = oldHeat,
        new_heat = newHeat,
        reason = reason or 'admin_set',
    })
    
    -- Check for stage change
    if oldStage ~= newStage then
        FreeGangs.Server.Heat.OnStageChange(gangA, gangB, oldStage, newStage)
    end
    
    -- Sync to clients
    FreeGangs.Server.Heat.SyncToClients(gangA, gangB)
    
    return newHeat
end

---Get heat level between two gangs
---@param gangA string First gang name
---@param gangB string Second gang name
---@return number heat The current heat level
function FreeGangs.Server.Heat.Get(gangA, gangB)
    local key = GetHeatKey(gangA, gangB)
    local heatData = FreeGangs.Server.Heat[key]
    
    if heatData then
        return heatData.heat_level
    end
    
    return 0
end

---Get heat stage between two gangs
---@param gangA string First gang name
---@param gangB string Second gang name
---@return string stage The current heat stage
function FreeGangs.Server.Heat.GetStage(gangA, gangB)
    local key = GetHeatKey(gangA, gangB)
    local heatData = FreeGangs.Server.Heat[key]
    
    if heatData then
        return heatData.stage
    end
    
    return FreeGangs.HeatStages.NEUTRAL
end

---Get full heat data between two gangs
---@param gangA string First gang name
---@param gangB string Second gang name
---@return table|nil heatData
function FreeGangs.Server.Heat.GetData(gangA, gangB)
    local key = GetHeatKey(gangA, gangB)
    return FreeGangs.Server.Heat[key]
end

---Get all heat records for a specific gang
---@param gangName string
---@return table heatRecords Array of heat data
function FreeGangs.Server.Heat.GetGangHeat(gangName)
    local records = {}
    
    for key, data in pairs(FreeGangs.Server.Heat) do
        if data.gang_a == gangName or data.gang_b == gangName then
            local otherGang = data.gang_a == gangName and data.gang_b or data.gang_a
            records[#records + 1] = {
                gang = otherGang,
                heat_level = data.heat_level,
                stage = data.stage,
                last_incident = data.last_incident,
            }
        end
    end
    
    -- Sort by heat level descending
    table.sort(records, function(a, b)
        return a.heat_level > b.heat_level
    end)
    
    return records
end

---Get all gangs a gang has heat with
---@param gangName string
---@return table gangs Array of gang names with non-zero heat
function FreeGangs.Server.Heat.GetRivals(gangName)
    local rivals = {}
    
    for key, data in pairs(FreeGangs.Server.Heat) do
        if data.heat_level > 0 then
            if data.gang_a == gangName then
                rivals[#rivals + 1] = data.gang_b
            elseif data.gang_b == gangName then
                rivals[#rivals + 1] = data.gang_a
            end
        end
    end
    
    return rivals
end

-- ============================================================================
-- HEAT STAGE CHANGE HANDLING
-- ============================================================================

---Handle heat stage changes (notifications, effects)
---@param gangA string
---@param gangB string
---@param oldStage string
---@param newStage string
function FreeGangs.Server.Heat.OnStageChange(gangA, gangB, oldStage, newStage)
    local gangAData = FreeGangs.Server.Gangs[gangA]
    local gangBData = FreeGangs.Server.Gangs[gangB]
    
    if not gangAData or not gangBData then return end
    
    local stageInfo = FreeGangs.HeatStageThresholds[newStage]
    local isEscalation = FreeGangs.Server.Heat.IsEscalation(oldStage, newStage)
    
    -- Determine notification type
    local notifyType = isEscalation and 'warning' or 'info'
    
    -- Build notification message
    local messageKey = isEscalation and 'StageEscalated' or 'StageDeescalated'
    local message = string.format(
        'Relations with %s have %s to: %s',
        '%s', -- Will be filled with other gang name
        isEscalation and 'escalated' or 'deescalated',
        stageInfo.label
    )
    
    -- Notify gang A about gang B
    local messageA = string.format(message:gsub('%%s', gangBData.label, 1))
    FreeGangs.Bridge.NotifyGang(gangA, messageA, notifyType)
    
    -- Notify gang B about gang A
    local messageB = string.format(message:gsub('%%s', gangAData.label, 1))
    FreeGangs.Bridge.NotifyGang(gangB, messageB, notifyType)
    
    -- Trigger client event for UI updates
    TriggerClientEvent(FreeGangs.Events.Client.UPDATE_HEAT, -1, {
        gang_a = gangA,
        gang_b = gangB,
        stage = newStage,
        stage_info = stageInfo,
    })
    
    -- Log the stage change
    FreeGangs.Server.DB.Log(gangA, nil, 'heat_stage_change', FreeGangs.LogCategories.WAR, {
        target_gang = gangB,
        old_stage = oldStage,
        new_stage = newStage,
        is_escalation = isEscalation,
    })
    
    -- Discord webhook for significant stage changes
    if newStage == FreeGangs.HeatStages.RIVALRY or newStage == FreeGangs.HeatStages.WAR_READY then
        FreeGangs.Server.SendDiscordWebhook('Heat Escalation', string.format(
            '**%s** and **%s** have reached **%s** status!',
            gangAData.label,
            gangBData.label,
            stageInfo.label
        ), 16711680) -- Red color
    end
end

---Check if stage change is an escalation
---@param oldStage string
---@param newStage string
---@return boolean
function FreeGangs.Server.Heat.IsEscalation(oldStage, newStage)
    local stageOrder = {
        [FreeGangs.HeatStages.NEUTRAL] = 1,
        [FreeGangs.HeatStages.TENSION] = 2,
        [FreeGangs.HeatStages.COLD_WAR] = 3,
        [FreeGangs.HeatStages.RIVALRY] = 4,
        [FreeGangs.HeatStages.WAR_READY] = 5,
    }
    
    return (stageOrder[newStage] or 0) > (stageOrder[oldStage] or 0)
end

-- ============================================================================
-- HEAT DECAY SYSTEM
-- ============================================================================

---Process heat decay for all gang pairs
function FreeGangs.Server.Heat.ProcessDecay()
    local currentTime = os.time()
    local gangDecayRate = FreeGangs.Config.Heat.GangDecayRate
    local gangDecayInterval = FreeGangs.Config.Heat.GangDecayMinutes * 60
    
    local decayedCount = 0
    
    for key, heatData in pairs(FreeGangs.Server.Heat) do
        -- Skip if no heat
        if heatData.heat_level <= 0 then
            goto continue
        end
        
        -- Check if enough time has passed for decay
        local lastDecay = heatData.last_decay or currentTime
        local timeSinceDecay = currentTime - lastDecay
        
        if timeSinceDecay >= gangDecayInterval then
            -- Calculate decay ticks
            local decayTicks = math.floor(timeSinceDecay / gangDecayInterval)
            local totalDecay = gangDecayRate * decayTicks
            
            local oldHeat = heatData.heat_level
            local oldStage = heatData.stage
            
            -- Apply decay
            local newHeat = math.max(0, heatData.heat_level - totalDecay)
            local newStage = FreeGangs.Utils.GetHeatStage(newHeat)
            
            -- Update data
            heatData.heat_level = newHeat
            heatData.stage = newStage
            heatData.last_decay = currentTime
            
            -- Mark dirty
            MarkHeatDirty(heatData.gang_a, heatData.gang_b)
            
            -- Check for stage change
            if oldStage ~= newStage then
                FreeGangs.Server.Heat.OnStageChange(heatData.gang_a, heatData.gang_b, oldStage, newStage)
            end
            
            decayedCount = decayedCount + 1
        end
        
        ::continue::
    end
    
    if decayedCount > 0 then
        FreeGangs.Utils.Debug('Processed heat decay for ' .. decayedCount .. ' gang pairs')
    end
end

-- ============================================================================
-- HEAT CHECKING UTILITIES
-- ============================================================================

---Check if two gangs can declare war (heat >= 90)
---@param gangA string
---@param gangB string
---@return boolean canDeclare
---@return string|nil reason If can't declare, the reason why
function FreeGangs.Server.Heat.CanDeclareWar(gangA, gangB)
    local heatLevel = FreeGangs.Server.Heat.Get(gangA, gangB)
    local minHeat = FreeGangs.Config.War.MinHeatForWar
    
    if heatLevel < minHeat then
        return false, string.format('Requires %d heat (current: %d)', minHeat, heatLevel)
    end
    
    return true, nil
end

---Check if two gangs are in a rivalry stage or higher
---@param gangA string
---@param gangB string
---@return boolean
function FreeGangs.Server.Heat.IsRivalry(gangA, gangB)
    local stage = FreeGangs.Server.Heat.GetStage(gangA, gangB)
    return stage == FreeGangs.HeatStages.RIVALRY or stage == FreeGangs.HeatStages.WAR_READY
end

---Check if heat effects apply (profit reduction, etc.)
---@param gangA string
---@param gangB string
---@param effect string
---@return boolean
function FreeGangs.Server.Heat.HasEffect(gangA, gangB, effect)
    local stage = FreeGangs.Server.Heat.GetStage(gangA, gangB)
    return FreeGangs.Utils.HasHeatEffect(stage, effect)
end

---Get the drug profit modifier based on heat with rival gangs in a zone
---@param gangName string
---@param zoneName string
---@return number modifier (1.0 = no change, 0.3 = 70% reduction)
function FreeGangs.Server.Heat.GetRivalryProfitModifier(gangName, zoneName)
    -- Check if gang has rivalry with any gang controlling this zone
    local territory = FreeGangs.Server.Territories[zoneName]
    if not territory then
        return 1.0
    end
    
    local influence = territory.influence or {}
    
    for rivalGang, percent in pairs(influence) do
        if rivalGang ~= gangName and percent > 0 then
            if FreeGangs.Server.Heat.IsRivalry(gangName, rivalGang) then
                -- Apply rivalry profit reduction
                return 1.0 - FreeGangs.Config.Heat.Rivalry.ProfitReduction
            end
        end
    end
    
    return 1.0
end

-- ============================================================================
-- CLIENT SYNCHRONIZATION
-- ============================================================================

---Sync heat data to relevant clients
---@param gangA string
---@param gangB string
function FreeGangs.Server.Heat.SyncToClients(gangA, gangB)
    local heatData = FreeGangs.Server.Heat.GetData(gangA, gangB)
    if not heatData then return end
    
    local syncData = {
        gang_a = gangA,
        gang_b = gangB,
        heat_level = heatData.heat_level,
        stage = heatData.stage,
    }
    
    -- Get online members of both gangs
    local players = FreeGangs.Bridge.GetPlayers()
    
    for source, player in pairs(players) do
        local playerGang = player.PlayerData.gang and player.PlayerData.gang.name
        if playerGang == gangA or playerGang == gangB then
            TriggerClientEvent(FreeGangs.Events.Client.UPDATE_HEAT, source, syncData)
        end
    end
end

---Send full heat state to a player
---@param source number
---@param gangName string
function FreeGangs.Server.Heat.SyncToPlayer(source, gangName)
    local heatRecords = FreeGangs.Server.Heat.GetGangHeat(gangName)
    TriggerClientEvent(FreeGangs.Events.Client.UPDATE_HEAT, source, {
        full_sync = true,
        gang = gangName,
        records = heatRecords,
    })
end

-- ============================================================================
-- HEAT FROM ACTIVITIES
-- ============================================================================

---Add heat from a specific activity type
---@param gangA string Acting gang
---@param gangB string Target/affected gang
---@param activity string Activity type from FreeGangs.Activities
---@param citizenid string|nil Player who performed the activity
function FreeGangs.Server.Heat.AddFromActivity(gangA, gangB, activity, citizenid)
    local heatConfig = FreeGangs.Config.Heat.Points
    local heatAmount = heatConfig[activity] or 0
    
    if heatAmount <= 0 then return end
    
    local reason = string.format('activity:%s', activity)
    if citizenid then
        reason = reason .. ':' .. citizenid
    end
    
    FreeGangs.Server.Heat.Add(gangA, gangB, heatAmount, reason)
end

-- ============================================================================
-- ADMIN FUNCTIONS
-- ============================================================================

---Reset heat between two gangs
---@param gangA string
---@param gangB string
---@param adminSource number|nil
function FreeGangs.Server.Heat.Reset(gangA, gangB, adminSource)
    FreeGangs.Server.Heat.Set(gangA, gangB, 0, 'admin_reset')
    
    if adminSource then
        local adminName = adminSource == 0 and 'Console' or FreeGangs.Bridge.GetPlayerName(adminSource)
        FreeGangs.Server.DB.Log(gangA, nil, 'heat_reset', FreeGangs.LogCategories.ADMIN, {
            target_gang = gangB,
            admin = adminName,
        })
    end
end

---Get all heat data (for admin panel)
---@return table allHeat
function FreeGangs.Server.Heat.GetAll()
    local allHeat = {}
    
    for key, data in pairs(FreeGangs.Server.Heat) do
        allHeat[#allHeat + 1] = {
            gang_a = data.gang_a,
            gang_b = data.gang_b,
            heat_level = data.heat_level,
            stage = data.stage,
            last_incident = data.last_incident,
        }
    end
    
    -- Sort by heat level descending
    table.sort(allHeat, function(a, b)
        return a.heat_level > b.heat_level
    end)
    
    return allHeat
end

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    -- Show heat between two gangs
    RegisterCommand('fg_heat', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local gangA = args[1]
        local gangB = args[2]
        
        if not gangA or not gangB then
            print('[free-gangs:debug] Usage: /fg_heat [gang1] [gang2]')
            return
        end
        
        local heat = FreeGangs.Server.Heat.Get(gangA, gangB)
        local stage = FreeGangs.Server.Heat.GetStage(gangA, gangB)
        
        print(string.format('[free-gangs:debug] Heat %s <-> %s: %d (%s)', gangA, gangB, heat, stage))
    end, false)
    
    -- Set heat between two gangs
    RegisterCommand('fg_setheat', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local gangA = args[1]
        local gangB = args[2]
        local amount = tonumber(args[3])
        
        if not gangA or not gangB or not amount then
            print('[free-gangs:debug] Usage: /fg_setheat [gang1] [gang2] [amount]')
            return
        end
        
        local newHeat = FreeGangs.Server.Heat.Set(gangA, gangB, amount, 'debug_command')
        print(string.format('[free-gangs:debug] Set heat %s <-> %s to %d', gangA, gangB, newHeat))
    end, false)
    
    -- Show all heat for a gang
    RegisterCommand('fg_gangheat', function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        local gangName = args[1]
        
        if not gangName then
            print('[free-gangs:debug] Usage: /fg_gangheat [gang]')
            return
        end
        
        local records = FreeGangs.Server.Heat.GetGangHeat(gangName)
        print('[free-gangs:debug] Heat records for ' .. gangName .. ':')
        
        for _, record in ipairs(records) do
            print(string.format('  %s: %d (%s)', record.gang, record.heat_level, record.stage))
        end
    end, false)
    
    -- Force heat decay
    RegisterCommand('fg_heatdecay', function(source)
        if source ~= 0 and not IsPlayerAceAllowed(source, FreeGangs.Config.Admin.AcePermission) then
            return
        end
        
        FreeGangs.Server.Heat.ProcessDecay()
        print('[free-gangs:debug] Forced heat decay cycle')
    end, false)
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('AddGangHeat', function(gangA, gangB, amount, reason)
    return FreeGangs.Server.Heat.Add(gangA, gangB, amount, reason)
end)

exports('GetGangHeat', function(gangA, gangB)
    return FreeGangs.Server.Heat.Get(gangA, gangB)
end)

exports('GetHeatStage', function(gangA, gangB)
    return FreeGangs.Server.Heat.GetStage(gangA, gangB)
end)

exports('GetRivalryStage', function(gangA, gangB)
    return FreeGangs.Server.Heat.GetStage(gangA, gangB)
end)

-- ============================================================================
-- MODULE RETURN
-- ============================================================================

FreeGangs.Utils.Log('Heat module loaded')

return FreeGangs.Server.Heat
