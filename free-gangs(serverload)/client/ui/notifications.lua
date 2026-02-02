--[[
    FREE-GANGS: UI Notifications Module
    
    Notification wrappers for territory alerts, war alerts, reputation changes,
    heat updates, bribe reminders, and other system notifications.
    Uses ox_lib notify with themed styling.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.UI = FreeGangs.Client.UI or {}
FreeGangs.Client.UI.Notifications = {}

-- Notification queue to prevent spam
local notificationCooldowns = {}
local COOLDOWN_MS = 1000 -- Minimum ms between same notification types

-- ============================================================================
-- CORE NOTIFICATION FUNCTIONS
-- ============================================================================

---Send a styled notification
---@param data table Notification data
local function SendNotification(data)
    -- Check cooldown
    local id = data.id or data.title
    local now = GetGameTimer()
    
    if notificationCooldowns[id] and now - notificationCooldowns[id] < COOLDOWN_MS then
        return -- Skip duplicate notification
    end
    notificationCooldowns[id] = now
    
    -- Apply theme styling
    local theme = FreeGangs.Config.UI.Theme
    
    lib.notify({
        id = data.id,
        title = data.title,
        description = data.description,
        type = data.type or 'inform',
        duration = data.duration or FreeGangs.Config.UI.Notifications.DefaultDuration,
        position = data.position or FreeGangs.Config.UI.Notifications.Position,
        icon = data.icon,
        iconColor = data.iconColor or theme.AccentColor,
        iconAnimation = data.iconAnimation,
        style = {
            backgroundColor = data.backgroundColor or theme.SecondaryColor,
            color = data.textColor or theme.TextColor,
            borderRadius = '8px',
            ['.description'] = {
                color = data.descColor or '#CCCCCC',
            },
        },
    })
end

---Basic notification wrapper
---@param message string
---@param notifyType string|nil ('success', 'error', 'warning', 'inform')
---@param duration number|nil
function FreeGangs.Client.UI.Notify(message, notifyType, duration)
    SendNotification({
        title = 'Gang System',
        description = message,
        type = notifyType or 'inform',
        duration = duration,
    })
end

-- ============================================================================
-- TERRITORY NOTIFICATIONS
-- ============================================================================

---Notify about territory events
---@param zoneName string
---@param alertType string ('contested', 'captured', 'lost', 'entered', 'influence')
---@param data table|nil Additional data
function FreeGangs.Client.UI.NotifyTerritoryAlert(zoneName, alertType, data)
    data = data or {}
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    local territory = territories[zoneName]
    local zoneLabel = territory and territory.label or zoneName
    
    local notifications = {
        contested = {
            id = 'territory_contested_' .. zoneName,
            title = '⚠️ TERRITORY CONTESTED',
            description = string.format('%s is being contested by rivals!', zoneLabel),
            type = 'warning',
            duration = 10000,
            icon = 'skull-crossbones',
            iconColor = '#FF0000',
            iconAnimation = 'shake',
        },
        captured = {
            id = 'territory_captured_' .. zoneName,
            title = '🏴 TERRITORY CAPTURED',
            description = string.format('Your gang now controls %s!', zoneLabel),
            type = 'success',
            duration = 10000,
            icon = 'flag',
            iconColor = '#00FF00',
            iconAnimation = 'bounce',
        },
        lost = {
            id = 'territory_lost_' .. zoneName,
            title = '❌ TERRITORY LOST',
            description = string.format('%s has been lost to %s!', zoneLabel, data.newOwner or 'rivals'),
            type = 'error',
            duration = 10000,
            icon = 'flag',
            iconColor = '#FF0000',
            iconAnimation = 'shake',
        },
        entered = {
            id = 'territory_entered',
            title = 'Territory',
            description = string.format('Entering %s', zoneLabel),
            type = 'inform',
            duration = 3000,
            icon = 'map-marker-alt',
            iconColor = data.isOwned and '#00FF00' or (data.isRival and '#FF0000' or '#888888'),
        },
        influence = {
            id = 'territory_influence_' .. zoneName,
            title = 'Influence Changed',
            description = string.format('%s: %d%% influence', zoneLabel, data.influence or 0),
            type = 'inform',
            duration = 5000,
            icon = 'chart-line',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        },
        cooldown = {
            id = 'territory_cooldown',
            title = 'Capture Cooldown',
            description = string.format('%s is on cooldown. %s remaining.', zoneLabel, data.remaining or 'Unknown'),
            type = 'warning',
            duration = 5000,
            icon = 'clock',
            iconColor = '#FFAA00',
        },
    }
    
    local notifData = notifications[alertType]
    if notifData then
        SendNotification(notifData)
    end
end

-- ============================================================================
-- WAR NOTIFICATIONS
-- ============================================================================

---Notify about war events
---@param alertType string ('declared', 'started', 'ended', 'kill', 'death', 'surrender')
---@param data table Additional data
function FreeGangs.Client.UI.NotifyWarAlert(alertType, data)
    data = data or {}
    
    local notifications = {
        declared = {
            id = 'war_declared',
            title = '⚔️ WAR DECLARED!',
            description = string.format('%s has declared war on your gang!', data.enemyGang or 'Unknown'),
            type = 'error',
            duration = 15000,
            icon = 'crosshairs',
            iconColor = '#FF0000',
            iconAnimation = 'shake',
        },
        started = {
            id = 'war_started',
            title = '🔥 WAR BEGUN!',
            description = string.format('War with %s is now active!', data.enemyGang or 'Unknown'),
            type = 'warning',
            duration = 15000,
            icon = 'fire',
            iconColor = '#FF4400',
            iconAnimation = 'bounce',
        },
        ended = {
            id = 'war_ended',
            title = data.won and '🏆 VICTORY!' or '💀 DEFEAT',
            description = string.format('War with %s has ended. %s', 
                data.enemyGang or 'Unknown',
                data.won and 'You won!' or 'You lost.'),
            type = data.won and 'success' or 'error',
            duration = 15000,
            icon = data.won and 'trophy' or 'skull',
            iconColor = data.won and '#FFD700' or '#666666',
        },
        kill = {
            id = 'war_kill',
            title = '💀 Enemy Eliminated',
            description = string.format('Score: %d - %d', data.ourKills or 0, data.theirKills or 0),
            type = 'success',
            duration = 5000,
            icon = 'crosshairs',
            iconColor = '#00FF00',
        },
        death = {
            id = 'war_death',
            title = '☠️ Gang Member Killed',
            description = string.format('Score: %d - %d', data.ourKills or 0, data.theirKills or 0),
            type = 'error',
            duration = 5000,
            icon = 'skull',
            iconColor = '#FF0000',
        },
        surrender = {
            id = 'war_surrender',
            title = '🏳️ Enemy Surrendered!',
            description = string.format('%s has surrendered! Your gang wins!', data.enemyGang or 'Unknown'),
            type = 'success',
            duration = 15000,
            icon = 'flag',
            iconColor = '#FFFFFF',
        },
        peace = {
            id = 'war_peace',
            title = '🤝 Peace Declared',
            description = string.format('Mutual peace with %s. Collateral returned.', data.enemyGang or 'Unknown'),
            type = 'success',
            duration = 10000,
            icon = 'handshake',
            iconColor = '#00FF00',
        },
    }
    
    local notifData = notifications[alertType]
    if notifData then
        SendNotification(notifData)
    end
end

-- ============================================================================
-- REPUTATION NOTIFICATIONS
-- ============================================================================

---Notify about reputation changes
---@param amount number (positive or negative)
---@param newLevel number|nil If level changed
---@param reason string|nil Reason for change
function FreeGangs.Client.UI.NotifyRepChange(amount, newLevel, reason)
    local isGain = amount > 0
    
    -- Basic rep change notification
    SendNotification({
        id = 'rep_change',
        title = isGain and '⬆️ Reputation Gained' or '⬇️ Reputation Lost',
        description = string.format('%s%d reputation%s', 
            isGain and '+' or '', 
            amount,
            reason and (' (' .. reason .. ')') or ''),
        type = isGain and 'success' or 'warning',
        duration = 3000,
        icon = 'star',
        iconColor = isGain and '#00FF00' or '#FF4444',
    })
    
    -- Level up/down notification
    if newLevel then
        local levelInfo = FreeGangs.ReputationLevels[newLevel]
        local isLevelUp = isGain
        
        SendNotification({
            id = 'rep_level_change',
            title = isLevelUp and '🎉 LEVEL UP!' or '📉 Level Down',
            description = string.format('Gang is now Level %d: %s', newLevel, levelInfo and levelInfo.name or 'Unknown'),
            type = isLevelUp and 'success' or 'error',
            duration = 10000,
            icon = isLevelUp and 'crown' or 'arrow-down',
            iconColor = isLevelUp and '#FFD700' or '#FF4444',
            iconAnimation = isLevelUp and 'bounce' or nil,
        })
        
        -- Show new unlocks on level up
        if isLevelUp and levelInfo and levelInfo.unlocks and #levelInfo.unlocks > 0 then
            Wait(500) -- Small delay for dramatic effect
            SendNotification({
                id = 'rep_unlocks',
                title = '🔓 New Unlocks!',
                description = table.concat(levelInfo.unlocks, ', '),
                type = 'inform',
                duration = 8000,
                icon = 'unlock',
                iconColor = FreeGangs.Config.UI.Theme.AccentColor,
            })
        end
    end
end

-- ============================================================================
-- HEAT NOTIFICATIONS
-- ============================================================================

---Notify about heat level changes
---@param otherGang string
---@param stage string Heat stage
---@param heatLevel number
function FreeGangs.Client.UI.NotifyHeatChange(otherGang, stage, heatLevel)
    local stageInfo = FreeGangs.HeatStageThresholds[stage]
    if not stageInfo then return end
    
    local notifications = {
        [FreeGangs.HeatStages.TENSION] = {
            id = 'heat_tension',
            title = '🌡️ Tension Rising',
            description = string.format('Relations with %s are becoming tense (%d heat)', otherGang, heatLevel),
            type = 'warning',
            icon = 'thermometer-half',
            iconColor = '#FFFF00',
        },
        [FreeGangs.HeatStages.COLD_WAR] = {
            id = 'heat_cold_war',
            title = '❄️ Cold War',
            description = string.format('Cold war status with %s (%d heat)', otherGang, heatLevel),
            type = 'warning',
            icon = 'snowflake',
            iconColor = '#00FFFF',
        },
        [FreeGangs.HeatStages.RIVALRY] = {
            id = 'heat_rivalry',
            title = '🔥 RIVALRY!',
            description = string.format('Full rivalry with %s! Drug profits reduced. (%d heat)', otherGang, heatLevel),
            type = 'error',
            icon = 'fire',
            iconColor = '#FF4400',
            iconAnimation = 'shake',
        },
        [FreeGangs.HeatStages.WAR_READY] = {
            id = 'heat_war_ready',
            title = '⚔️ WAR READY!',
            description = string.format('%s - War can now be declared! (%d heat)', otherGang, heatLevel),
            type = 'error',
            duration = 10000,
            icon = 'crosshairs',
            iconColor = '#FF0000',
            iconAnimation = 'bounce',
        },
    }
    
    local notifData = notifications[stage]
    if notifData then
        SendNotification(notifData)
    end
end

-- ============================================================================
-- BRIBE NOTIFICATIONS
-- ============================================================================

---Notify about bribe events
---@param alertType string ('established', 'due', 'paid', 'missed', 'terminated', 'used')
---@param contactType string
---@param data table|nil
function FreeGangs.Client.UI.NotifyBribe(alertType, contactType, data)
    data = data or {}
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local contactLabel = contactInfo and contactInfo.label or contactType
    
    local notifications = {
        established = {
            id = 'bribe_established_' .. contactType,
            title = '🤝 Contact Established',
            description = string.format('%s is now on your payroll', contactLabel),
            type = 'success',
            duration = 8000,
            icon = contactInfo and contactInfo.icon or 'user-secret',
            iconColor = '#00FF00',
        },
        due = {
            id = 'bribe_due_' .. contactType,
            title = '💰 Payment Due',
            description = string.format('%s payment due within %d hours', contactLabel, data.hoursRemaining or 24),
            type = 'warning',
            duration = 10000,
            icon = 'clock',
            iconColor = '#FFAA00',
            iconAnimation = 'bounce',
        },
        paid = {
            id = 'bribe_paid_' .. contactType,
            title = '✅ Payment Made',
            description = string.format('%s has been paid', contactLabel),
            type = 'success',
            duration = 5000,
            icon = 'check-circle',
            iconColor = '#00FF00',
        },
        missed = {
            id = 'bribe_missed_' .. contactType,
            title = '⚠️ Payment Missed!',
            description = string.format('Missed payment to %s! Effects paused, costs increased.', contactLabel),
            type = 'error',
            duration = 10000,
            icon = 'exclamation-triangle',
            iconColor = '#FF4444',
            iconAnimation = 'shake',
        },
        terminated = {
            id = 'bribe_terminated_' .. contactType,
            title = '❌ Contact Lost',
            description = string.format('%s relationship terminated', contactLabel),
            type = 'error',
            duration = 8000,
            icon = 'user-times',
            iconColor = '#FF0000',
        },
        used = {
            id = 'bribe_used_' .. contactType,
            title = '✨ Contact Ability Used',
            description = data.abilityName or 'Ability activated',
            type = 'success',
            duration = 5000,
            icon = 'magic',
            iconColor = FreeGangs.Config.UI.Theme.AccentColor,
        },
    }
    
    local notifData = notifications[alertType]
    if notifData then
        SendNotification(notifData)
    end
end

-- ============================================================================
-- ACTIVITY NOTIFICATIONS
-- ============================================================================

---Notify about criminal activities
---@param activityType string
---@param success boolean
---@param data table|nil
function FreeGangs.Client.UI.NotifyActivity(activityType, success, data)
    data = data or {}
    
    local notifications = {
        mugging = {
            success = {
                title = '💰 Mugging Successful',
                description = data.reward and ('Got ' .. FreeGangs.Utils.FormatMoney(data.reward)) or 'Target robbed!',
                type = 'success',
                icon = 'mask',
                iconColor = '#00FF00',
            },
            fail = {
                title = '❌ Mugging Failed',
                description = data.reason or 'The target got away!',
                type = 'error',
                icon = 'times-circle',
                iconColor = '#FF0000',
            },
        },
        pickpocket = {
            success = {
                title = '🖐️ Pickpocket Successful',
                description = data.reward and ('Stole ' .. FreeGangs.Utils.FormatMoney(data.reward)) or 'Got something!',
                type = 'success',
                icon = 'hand-paper',
                iconColor = '#00FF00',
            },
            fail = {
                title = '👁️ Spotted!',
                description = 'You were caught pickpocketing!',
                type = 'error',
                icon = 'eye',
                iconColor = '#FF0000',
                iconAnimation = 'shake',
            },
        },
        drug_sale = {
            success = {
                title = '💊 Drug Sale',
                description = data.reward and ('Sold for ' .. FreeGangs.Utils.FormatMoney(data.reward)) or 'Deal complete!',
                type = 'success',
                icon = 'cannabis',
                iconColor = '#00FF00',
            },
            fail = {
                title = '❌ Deal Failed',
                description = data.reason or 'Customer rejected the deal',
                type = 'error',
                icon = 'times',
                iconColor = '#FF0000',
            },
        },
        graffiti = {
            success = {
                title = '🎨 Tag Sprayed',
                description = string.format('+%d zone influence', data.loyalty or 10),
                type = 'success',
                icon = 'spray-can',
                iconColor = '#FF00FF',
            },
            fail = {
                title = '❌ Spray Failed',
                description = data.reason or 'Could not spray tag',
                type = 'error',
                icon = 'ban',
                iconColor = '#FF0000',
            },
        },
        protection = {
            success = {
                title = '💵 Protection Collected',
                description = data.reward and ('Got ' .. FreeGangs.Utils.FormatMoney(data.reward)) or 'Payment received!',
                type = 'success',
                icon = 'shield-alt',
                iconColor = '#00FF00',
            },
            fail = {
                title = '❌ Collection Failed',
                description = data.reason or 'Could not collect protection',
                type = 'error',
                icon = 'shield-alt',
                iconColor = '#FF0000',
            },
        },
    }
    
    local activityNotifs = notifications[activityType]
    if activityNotifs then
        local notifData = success and activityNotifs.success or activityNotifs.fail
        if notifData then
            notifData.id = activityType .. (success and '_success' or '_fail')
            notifData.duration = notifData.duration or 5000
            SendNotification(notifData)
        end
    end
end

-- ============================================================================
-- MEMBER NOTIFICATIONS
-- ============================================================================

---Notify about member events
---@param alertType string ('joined', 'left', 'kicked', 'promoted', 'demoted')
---@param memberName string
---@param data table|nil
function FreeGangs.Client.UI.NotifyMember(alertType, memberName, data)
    data = data or {}
    
    local notifications = {
        joined = {
            id = 'member_joined',
            title = '👤 New Member',
            description = string.format('%s has joined the gang', memberName),
            type = 'success',
            icon = 'user-plus',
            iconColor = '#00FF00',
        },
        left = {
            id = 'member_left',
            title = '👤 Member Left',
            description = string.format('%s has left the gang', memberName),
            type = 'warning',
            icon = 'user-minus',
            iconColor = '#FFAA00',
        },
        kicked = {
            id = 'member_kicked',
            title = '👢 Member Kicked',
            description = string.format('%s has been kicked from the gang', memberName),
            type = 'error',
            icon = 'user-times',
            iconColor = '#FF0000',
        },
        promoted = {
            id = 'member_promoted',
            title = '⬆️ Member Promoted',
            description = string.format('%s promoted to %s', memberName, data.newRank or 'higher rank'),
            type = 'success',
            icon = 'arrow-up',
            iconColor = '#00FF00',
        },
        demoted = {
            id = 'member_demoted',
            title = '⬇️ Member Demoted',
            description = string.format('%s demoted to %s', memberName, data.newRank or 'lower rank'),
            type = 'warning',
            icon = 'arrow-down',
            iconColor = '#FFAA00',
        },
        death = {
            id = 'member_death',
            title = '💀 Gang Member Down',
            description = string.format('%s was killed', memberName),
            type = 'error',
            icon = 'skull',
            iconColor = '#FF0000',
        },
    }
    
    local notifData = notifications[alertType]
    if notifData then
        SendNotification(notifData)
    end
end

-- ============================================================================
-- GENERAL SYSTEM NOTIFICATIONS
-- ============================================================================

---Show cooldown notification
---@param action string
---@param remainingMs number
function FreeGangs.Client.UI.NotifyCooldown(action, remainingMs)
    SendNotification({
        id = 'cooldown_' .. action,
        title = '⏳ On Cooldown',
        description = string.format('%s available in %s', action, FreeGangs.Utils.FormatDuration(remainingMs)),
        type = 'warning',
        duration = 3000,
        icon = 'clock',
        iconColor = '#FFAA00',
    })
end

---Show error notification
---@param message string
function FreeGangs.Client.UI.NotifyError(message)
    SendNotification({
        id = 'error',
        title = '❌ Error',
        description = message,
        type = 'error',
        duration = 5000,
        icon = 'exclamation-circle',
        iconColor = '#FF0000',
    })
end

---Show success notification
---@param message string
function FreeGangs.Client.UI.NotifySuccess(message)
    SendNotification({
        id = 'success',
        title = '✅ Success',
        description = message,
        type = 'success',
        duration = 5000,
        icon = 'check-circle',
        iconColor = '#00FF00',
    })
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Handle territory alert from server
RegisterNetEvent(FreeGangs.Events.Client.TERRITORY_ALERT, function(zoneName, alertType, data)
    FreeGangs.Client.UI.NotifyTerritoryAlert(zoneName, alertType, data)
end)

-- Handle war alert from server
RegisterNetEvent(FreeGangs.Events.Client.WAR_ALERT, function(alertType, data)
    FreeGangs.Client.UI.NotifyWarAlert(alertType, data)
end)

-- Handle bribe due reminder from server
RegisterNetEvent(FreeGangs.Events.Client.BRIBE_DUE, function(contactType, hoursRemaining)
    FreeGangs.Client.UI.NotifyBribe('due', contactType, { hoursRemaining = hoursRemaining })
end)

-- Handle heat update from server
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_HEAT, function(otherGang, stage, heatLevel)
    FreeGangs.Client.UI.NotifyHeatChange(otherGang, stage, heatLevel)
end)

-- Handle general notification from server
RegisterNetEvent(FreeGangs.Events.Client.NOTIFY, function(message, notifyType, duration)
    FreeGangs.Client.UI.Notify(message, notifyType, duration)
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General.Debug then
    RegisterCommand('fg_notify', function(_, args)
        local notifyType = args[1] or 'inform'
        local message = args[2] or 'Test notification'
        FreeGangs.Client.UI.Notify(message, notifyType)
    end, false)
    
    RegisterCommand('fg_notify_territory', function(_, args)
        local alertType = args[1] or 'contested'
        FreeGangs.Client.UI.NotifyTerritoryAlert('test_zone', alertType, { newOwner = 'Test Gang' })
    end, false)
    
    RegisterCommand('fg_notify_war', function(_, args)
        local alertType = args[1] or 'declared'
        FreeGangs.Client.UI.NotifyWarAlert(alertType, { enemyGang = 'Test Gang', won = true })
    end, false)
end

return FreeGangs.Client.UI.Notifications
