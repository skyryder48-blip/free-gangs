--[[
    FREE-GANGS: Client Prison Module

    Handles client-side prison operations including:
    - Prison control overview and benefit display
    - Jailed member management
    - Smuggle mission initiation
    - Contraband delivery and claiming
    - Complete escape flow with extraction, breakout, and getaway phases
    - Prison leaderboard display
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Prison = FreeGangs.Client.Prison or {}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local activeMission = nil  -- Track active escape/smuggle mission state

-- Benefit label mappings for display
local benefitLabels = {
    prison_guard_access = 'Prison Guard Access',
    free_contraband     = 'Free Contraband Delivery',
    free_prison_bribes  = 'Free Prison Bribes',
    reduced_escape_cost = 'Reduced Escape Cost',
}

-- ============================================================================
-- PRISON OVERVIEW MENU
-- ============================================================================

---Open the main prison operations menu
function FreeGangs.Client.Prison.OpenMenu()
    -- Fetch prison data from server
    local prisonData = lib.callback.await('free-gangs:callback:getPrisonData', false)
    local controlLevel = lib.callback.await('free-gangs:callback:getPrisonControl', false) or 0

    local options = {}

    -- Control level display with color coding
    local controlColor = controlLevel >= 75 and 'green'
        or (controlLevel >= 50 and 'yellow'
        or (controlLevel >= 25 and 'orange'
        or 'red'))

    table.insert(options, {
        title = 'Prison Control: ' .. math.floor(controlLevel) .. '%',
        icon = 'building-shield',
        iconColor = controlColor,
        progress = controlLevel,
        colorScheme = controlColor,
        metadata = FreeGangs.Client.Prison.GetBenefitMetadata(controlLevel),
    })

    -- Jailed members section
    local jailedCount = prisonData and prisonData.jailedMemberCount or 0
    table.insert(options, {
        title = 'Jailed Members',
        icon = 'handcuffs',
        description = jailedCount > 0
            and (jailedCount .. ' member' .. (jailedCount > 1 and 's' or '') .. ' in prison')
            or 'No members currently jailed',
        onSelect = FreeGangs.Client.Prison.ShowJailedMembers,
    })

    -- Smuggle missions
    table.insert(options, {
        title = 'Smuggle Mission',
        icon = 'truck-fast',
        description = 'Run contraband into the prison',
        onSelect = FreeGangs.Client.Prison.StartSmuggleMission,
    })

    -- Contraband delivery
    table.insert(options, {
        title = 'Deliver Contraband',
        icon = 'box',
        description = 'Send items to a jailed member',
        onSelect = FreeGangs.Client.Prison.OpenContrabandDelivery,
    })

    -- Claim contraband (for jailed players)
    table.insert(options, {
        title = 'Claim Contraband',
        icon = 'hand-holding-box',
        description = 'Pick up smuggled items',
        onSelect = FreeGangs.Client.Prison.ClaimContraband,
    })

    -- Help escape
    table.insert(options, {
        title = 'Help Escape',
        icon = 'person-running',
        description = 'Break a member out of prison',
        onSelect = FreeGangs.Client.Prison.InitiateEscape,
    })

    -- Leaderboard
    table.insert(options, {
        title = 'Prison Leaderboard',
        icon = 'ranking-star',
        description = 'View gang prison control rankings',
        onSelect = FreeGangs.Client.Prison.ShowLeaderboard,
    })

    lib.registerContext({
        id = 'freegangs_prison',
        title = 'Prison Operations',
        menu = 'freegangs_main',
        options = options,
    })

    lib.showContext('freegangs_prison')
end

-- ============================================================================
-- BENEFIT METADATA
-- ============================================================================

---Build metadata entries showing unlocked/locked benefits based on control level
---@param controlLevel number Current prison control percentage (0-100)
---@return table metadata Array of metadata entries for the context menu
function FreeGangs.Client.Prison.GetBenefitMetadata(controlLevel)
    local metadata = {}
    local config = FreeGangs.Config.Prison.ControlBenefits

    -- Collect and sort thresholds so display order is consistent
    local thresholds = {}
    for threshold, _ in pairs(config) do
        table.insert(thresholds, threshold)
    end
    table.sort(thresholds)

    for _, threshold in ipairs(thresholds) do
        local benefits = config[threshold]
        local unlocked = controlLevel >= threshold

        for _, benefit in ipairs(benefits) do
            local label = benefitLabels[benefit] or benefit:gsub('_', ' '):gsub('^%l', string.upper)
            local status = unlocked and 'Unlocked' or ('Requires ' .. threshold .. '%')

            table.insert(metadata, {
                label = label,
                value = status,
            })
        end
    end

    return metadata
end

-- ============================================================================
-- JAILED MEMBERS
-- ============================================================================

---Show a context menu listing all jailed gang members
function FreeGangs.Client.Prison.ShowJailedMembers()
    local jailedMembers = lib.callback.await('free-gangs:callback:getJailedMembers', false)

    if not jailedMembers or #jailedMembers == 0 then
        lib.notify({
            title = 'Prison',
            description = 'No gang members currently jailed',
            type = 'inform',
            duration = 5000,
            icon = 'handcuffs',
        })
        return
    end

    local options = {}

    for _, member in ipairs(jailedMembers) do
        table.insert(options, {
            title = member.name,
            icon = 'user-lock',
            description = 'Citizen ID: ' .. member.citizenid,
            metadata = {
                { label = 'Status', value = 'Incarcerated' },
            },
        })
    end

    lib.registerContext({
        id = 'freegangs_prison_jailed',
        title = 'Jailed Members',
        menu = 'freegangs_prison',
        options = options,
    })

    lib.showContext('freegangs_prison_jailed')
end

-- ============================================================================
-- SMUGGLE MISSIONS
-- ============================================================================

---Initiate a smuggle mission with risk level selection
function FreeGangs.Client.Prison.StartSmuggleMission()
    -- Get risk level configuration
    local riskConfig = FreeGangs.Config.PrisonActivities
        and FreeGangs.Config.PrisonActivities.SmuggleMissions
        and FreeGangs.Config.PrisonActivities.SmuggleMissions.riskLevels
        or {
            low    = { payoutMult = 1.0, detectionChance = 0.10 },
            medium = { payoutMult = 1.5, detectionChance = 0.25 },
            high   = { payoutMult = 2.0, detectionChance = 0.40 },
        }

    -- Build risk level selection options
    local riskOptions = {}
    for levelName, data in pairs(riskConfig) do
        riskOptions[#riskOptions + 1] = {
            value = levelName,
            label = levelName:gsub('^%l', string.upper)
                .. ' (x' .. data.payoutMult .. ' payout, '
                .. math.floor(data.detectionChance * 100) .. '% detection)',
        }
    end

    -- Sort for consistent ordering: low, medium, high
    table.sort(riskOptions, function(a, b)
        local order = { low = 1, medium = 2, high = 3 }
        return (order[a.value] or 99) < (order[b.value] or 99)
    end)

    local input = lib.inputDialog('Smuggle Mission', {
        {
            type = 'select',
            label = 'Risk Level',
            options = riskOptions,
            required = true,
        },
    })

    if not input then return end

    local selectedRisk = input[1]

    -- Confirm before starting
    local confirm = lib.alertDialog({
        header = 'Confirm Smuggle Mission',
        content = string.format(
            '**Risk Level:** %s\n**Payout Multiplier:** x%.1f\n**Detection Chance:** %d%%\n\nAre you sure you want to proceed?',
            selectedRisk:gsub('^%l', string.upper),
            riskConfig[selectedRisk].payoutMult,
            math.floor(riskConfig[selectedRisk].detectionChance * 100)
        ),
        centered = true,
        cancel = true,
    })

    if confirm ~= 'confirm' then return end

    -- Call server to start mission with selected risk level
    local result = lib.callback.await('free-gangs:callback:startSmuggleMission', false, selectedRisk)

    if result and result.success and result.missionData then
        -- Launch in-world smuggle run
        FreeGangs.Client.Prison.StartSmuggleRun(result.missionData)
    else
        lib.notify({
            title = 'Smuggle Mission Failed',
            description = result and result.message or 'Unable to start smuggle mission',
            type = 'error',
            duration = 5000,
            icon = 'circle-exclamation',
        })
    end
end

-- ============================================================================
-- SMUGGLE MISSION: IN-WORLD RUN
-- ============================================================================

---Launch the in-world smuggle run after server confirms the mission
---@param missionData table Mission details from server
function FreeGangs.Client.Prison.StartSmuggleRun(missionData)
    if activeMission then
        lib.notify({
            title = 'Smuggle Mission',
            description = 'A mission is already in progress',
            type = 'warning',
            duration = 5000,
        })
        return
    end

    -- Set mission state
    activeMission = {
        type = 'smuggle',
        missionId = missionData.missionId,
        missionType = missionData.missionType,
        riskLevel = missionData.riskLevel,
        payout = missionData.payout,
        phase = 'delivery',
        startTime = GetGameTimer(),
    }

    -- Show mission brief
    lib.notify({
        title = 'Smuggle Mission Active',
        description = string.format(
            'Type: %s | Risk: %s | Payout: $%s',
            (missionData.missionType or 'unknown'):gsub('^%l', string.upper),
            (missionData.riskLevel or 'unknown'):gsub('^%l', string.upper),
            missionData.payout or '???'
        ),
        type = 'success',
        duration = 10000,
        icon = 'truck-fast',
    })

    if missionData.targetName then
        lib.notify({
            title = 'Delivery Target',
            description = 'Deliver to: ' .. missionData.targetName,
            type = 'inform',
            duration = 8000,
            icon = 'user',
        })
    end

    -- Pick a random smuggle drop point near prison
    local smugglePoints = FreeGangs.Client.Prison.GetSmugglePoints()
    local dropPoint = smugglePoints[math.random(#smugglePoints)]

    -- Set waypoint to drop point
    SetNewWaypoint(dropPoint.x, dropPoint.y)

    lib.notify({
        title = 'Smuggle Mission',
        description = 'Head to the drop-off point!',
        type = 'warning',
        duration = 8000,
        icon = 'location-dot',
    })

    -- Create delivery zone
    local deliveryZone = lib.zones.sphere({
        coords = dropPoint,
        radius = 10.0,
        debug = FreeGangs.Config.Debug or (FreeGangs.Config.General and FreeGangs.Config.General.Debug),
        inside = function()
            if activeMission and activeMission.phase == 'delivery' then
                DrawMarker(
                    1,                                          -- cylinder
                    dropPoint.x, dropPoint.y, dropPoint.z - 1.0,
                    0, 0, 0,
                    0, 0, 0,
                    8.0, 8.0, 1.0,
                    255, 200, 0, 120,                           -- yellow RGBA
                    false, false, 2, false, nil, nil, false
                )
            end
        end,
        onEnter = function()
            if activeMission and activeMission.phase == 'delivery' then
                FreeGangs.Client.Prison.DoSmuggleDropoff()
            end
        end,
    })

    activeMission.deliveryZone = deliveryZone

    -- Mission timer (10 minutes)
    CreateThread(function()
        local timerMs = 600000
        local startTime = GetGameTimer()
        local warningShown = false

        while activeMission and activeMission.type == 'smuggle' do
            local elapsed = GetGameTimer() - startTime

            -- 2-minute warning
            if not warningShown and elapsed >= (timerMs - 120000) then
                warningShown = true
                lib.notify({
                    title = 'Smuggle Mission',
                    description = '2 minutes remaining!',
                    type = 'warning',
                    duration = 5000,
                    icon = 'clock',
                })
            end

            -- Time expired
            if elapsed >= timerMs then
                if activeMission and activeMission.type == 'smuggle' then
                    FreeGangs.Client.Prison.FailSmuggle('Time expired')
                end
                return
            end

            Wait(1000)
        end
    end)
end

---Perform the contraband drop-off at the delivery zone
function FreeGangs.Client.Prison.DoSmuggleDropoff()
    if not activeMission or activeMission.phase ~= 'delivery' then return end

    activeMission.phase = 'dropoff'

    lib.notify({
        title = 'Smuggle Mission',
        description = 'Dropping off contraband... stay still!',
        type = 'warning',
        duration = 5000,
        icon = 'box',
    })

    local success = lib.progressBar({
        duration = 10000,
        label = 'Dropping off contraband...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'anim@heists@box_carry@',
            clip = 'idle',
        },
    })

    if not success then
        FreeGangs.Client.Prison.FailSmuggle('Drop-off cancelled')
        return
    end

    -- Tell server we completed the drop (server handles detection roll)
    local result = lib.callback.await('free-gangs:callback:completeSmuggleMission', false, true, false)

    if result then
        lib.notify({
            title = 'Smuggle Mission',
            description = 'Drop-off complete! Check your payment.',
            type = 'success',
            duration = 8000,
            icon = 'circle-check',
        })
    end

    FreeGangs.Client.Prison.CleanupMission()
end

---Fail the smuggle mission with a reason
---@param reason string
function FreeGangs.Client.Prison.FailSmuggle(reason)
    if not activeMission then return end

    -- Notify server of failure
    lib.callback.await('free-gangs:callback:completeSmuggleMission', false, false, false)

    lib.notify({
        title = 'Smuggle Mission Failed',
        description = reason or 'The smuggle mission has failed',
        type = 'error',
        duration = 8000,
        icon = 'circle-xmark',
    })

    FreeGangs.Client.Prison.CleanupMission()
end

-- ============================================================================
-- CONTRABAND DELIVERY
-- ============================================================================

---Open the contraband delivery interface to send items to a jailed member
function FreeGangs.Client.Prison.OpenContrabandDelivery()
    -- Get jailed members
    local jailedMembers = lib.callback.await('free-gangs:callback:getJailedMembers', false)

    if not jailedMembers or #jailedMembers == 0 then
        lib.notify({
            title = 'Contraband',
            description = 'No gang members currently jailed to deliver to',
            type = 'inform',
            duration = 5000,
            icon = 'box',
        })
        return
    end

    -- Build member selection options
    local memberOptions = {}
    for _, member in ipairs(jailedMembers) do
        memberOptions[#memberOptions + 1] = {
            value = member.citizenid,
            label = member.name,
        }
    end

    -- Build item list from allowed contraband items
    local guardBribes = FreeGangs.Config.PrisonActivities
        and FreeGangs.Config.PrisonActivities.GuardBribes
        and FreeGangs.Config.PrisonActivities.GuardBribes.services
        and FreeGangs.Config.PrisonActivities.GuardBribes.services.contraband
    local smuggleMissions = FreeGangs.Config.PrisonActivities
        and FreeGangs.Config.PrisonActivities.SmuggleMissions

    -- Gather possible item names from config or fall back to common items
    local possibleItems = {}
    if smuggleMissions and smuggleMissions.types then
        for _, typeData in pairs(smuggleMissions.types) do
            if typeData.items then
                for _, itemName in ipairs(typeData.items) do
                    possibleItems[itemName] = true
                end
            end
        end
    end

    -- Fallback items if config yields nothing
    if not next(possibleItems) then
        possibleItems = {
            phone = true,
            radio = true,
            lockpick = true,
            bandage = true,
            sandwich = true,
            water = true,
        }
    end

    -- Check player inventory for available items
    local availableItems = {}
    for itemName, _ in pairs(possibleItems) do
        local count = exports.ox_inventory:Search('count', itemName)
        if count and count > 0 then
            availableItems[#availableItems + 1] = {
                value = itemName,
                label = itemName:gsub('_', ' '):gsub('^%l', string.upper) .. ' (x' .. count .. ')',
            }
        end
    end

    if #availableItems == 0 then
        lib.notify({
            title = 'Contraband',
            description = 'You don\'t have any items that can be smuggled',
            type = 'inform',
            duration = 5000,
            icon = 'box',
        })
        return
    end

    -- Show input dialog
    local input = lib.inputDialog('Deliver Contraband', {
        {
            type = 'select',
            label = 'Recipient',
            options = memberOptions,
            required = true,
        },
        {
            type = 'select',
            label = 'Item',
            options = availableItems,
            required = true,
        },
        {
            type = 'number',
            label = 'Amount',
            default = 1,
            min = 1,
            max = 10,
            required = true,
        },
    })

    if not input then return end

    local targetCitizenId = input[1]
    local selectedItem = input[2]
    local amount = input[3]

    -- Verify player still has enough
    local currentCount = exports.ox_inventory:Search('count', selectedItem)
    if not currentCount or currentCount < amount then
        lib.notify({
            title = 'Contraband',
            description = 'You don\'t have enough of that item',
            type = 'error',
            duration = 5000,
        })
        return
    end

    -- Build items table for server
    local items = {
        { name = selectedItem, count = amount },
    }

    -- Send to server
    local result = lib.callback.await('free-gangs:callback:deliverContraband', false, targetCitizenId, items)

    if result and result.success then
        lib.notify({
            title = 'Contraband Delivered',
            description = result.message or 'Items have been smuggled in successfully',
            type = 'success',
            duration = 5000,
            icon = 'box',
        })
    else
        lib.notify({
            title = 'Delivery Failed',
            description = result and result.message or 'Unable to deliver contraband',
            type = 'error',
            duration = 5000,
            icon = 'circle-exclamation',
        })
    end
end

-- ============================================================================
-- CLAIM CONTRABAND
-- ============================================================================

---Claim contraband that has been smuggled in for the player
function FreeGangs.Client.Prison.ClaimContraband()
    local result = lib.callback.await('free-gangs:callback:claimContraband', false)

    if result and result.success and result.items and #result.items > 0 then
        -- Build description of received items
        local itemDescriptions = {}
        for _, item in ipairs(result.items) do
            local label = item.name:gsub('_', ' '):gsub('^%l', string.upper)
            local count = item.count or 1
            table.insert(itemDescriptions, label .. ' x' .. count)
        end

        lib.notify({
            title = 'Contraband Collected',
            description = 'Received: ' .. table.concat(itemDescriptions, ', '),
            type = 'success',
            duration = 8000,
            icon = 'hand-holding-box',
        })
    else
        lib.notify({
            title = 'Contraband',
            description = 'No contraband available for pickup',
            type = 'inform',
            duration = 5000,
            icon = 'hand-holding-box',
        })
    end
end

-- ============================================================================
-- ESCAPE FLOW
-- ============================================================================

---Initiate a complete prison escape mission
function FreeGangs.Client.Prison.InitiateEscape()
    -- Check if a mission is already active
    if activeMission then
        lib.notify({
            title = 'Prison Break',
            description = 'A mission is already in progress',
            type = 'warning',
            duration = 5000,
            icon = 'person-running',
        })
        return
    end

    -- -----------------------------------------------------------------------
    -- 1. SELECTION PHASE
    -- -----------------------------------------------------------------------

    -- Get jailed members
    local jailedMembers = lib.callback.await('free-gangs:callback:getJailedMembers', false)

    if not jailedMembers or #jailedMembers == 0 then
        lib.notify({
            title = 'Prison Break',
            description = 'No gang members currently jailed',
            type = 'inform',
            duration = 5000,
            icon = 'person-running',
        })
        return
    end

    -- Build member selection options
    local memberOptions = {}
    for _, member in ipairs(jailedMembers) do
        memberOptions[#memberOptions + 1] = {
            value = member.citizenid,
            label = member.name,
        }
    end

    -- Show selection dialog
    local input = lib.inputDialog('Prison Break - Select Target', {
        {
            type = 'select',
            label = 'Member to Break Out',
            options = memberOptions,
            required = true,
        },
    })

    if not input then return end

    local targetCitizenId = input[1]

    -- Find the target name for display
    local targetName = 'Unknown'
    for _, member in ipairs(jailedMembers) do
        if member.citizenid == targetCitizenId then
            targetName = member.name
            break
        end
    end

    -- Get potential cost reduction info
    local jailReduction = lib.callback.await('free-gangs:callback:getJailTimeReduction', false) or 0
    local hasBenefit = lib.callback.await('free-gangs:callback:hasPrisonBenefit', false, 'reduced_escape_cost')
    local costNote = hasBenefit and 'Reduced escape cost active' or 'Standard escape cost'

    -- Show confirmation dialog
    local confirm = lib.alertDialog({
        header = 'Confirm Prison Break',
        content = string.format(
            '**Target:** %s\n**Cost Note:** %s\n\nThis will initiate a full prison breakout mission. '
            .. 'You will need to reach the extraction point, perform the breakout, and then escape to a safehouse.\n\n'
            .. 'Are you ready?',
            targetName,
            costNote
        ),
        centered = true,
        cancel = true,
    })

    if confirm ~= 'confirm' then return end

    -- -----------------------------------------------------------------------
    -- 2. SERVER VALIDATION
    -- -----------------------------------------------------------------------

    local result = lib.callback.await('free-gangs:callback:helpEscape', false, targetCitizenId)

    if not result or not result.success then
        lib.notify({
            title = 'Prison Break Failed',
            description = result and result.message or 'Unable to initiate prison break',
            type = 'error',
            duration = 5000,
            icon = 'circle-exclamation',
        })
        return
    end

    -- -----------------------------------------------------------------------
    -- 3. MISSION PHASE - Extraction
    -- -----------------------------------------------------------------------

    -- Set mission state
    activeMission = {
        type = 'escape',
        targetCitizenId = targetCitizenId,
        targetName = targetName,
        startTime = GetGameTimer(),
        phase = 'extraction',
    }

    -- Get extraction point (nearest smuggle point)
    local smugglePoints = FreeGangs.Client.Prison.GetSmugglePoints()
    local extractionPoint = smugglePoints[1] or vector3(1830.0, 2620.0, 45.0)

    -- Find the closest smuggle point to the player
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closestDist = math.huge

    for _, point in ipairs(smugglePoints) do
        local dist = #(playerCoords - point)
        if dist < closestDist then
            closestDist = dist
            extractionPoint = point
        end
    end

    -- Set waypoint to extraction point
    SetNewWaypoint(extractionPoint.x, extractionPoint.y)

    -- Notify player
    lib.notify({
        title = 'Prison Break',
        description = 'Head to the extraction point!',
        type = 'warning',
        duration = 10000,
        icon = 'person-running',
    })

    -- Get escape config values
    local escapeConfig = FreeGangs.Config.Prison.EscapeMission or {}
    local timerMs = (escapeConfig.TimerSeconds or 900) * 1000

    -- Create extraction zone
    local extractionZone = lib.zones.sphere({
        coords = extractionPoint,
        radius = escapeConfig.ExtractionRadius or 15.0,
        debug = FreeGangs.Config.Debug or (FreeGangs.Config.General and FreeGangs.Config.General.Debug),
        inside = function()
            if activeMission and activeMission.phase == 'extraction' then
                -- Draw marker at extraction point
                DrawMarker(
                    1,                                          -- type (cylinder)
                    extractionPoint.x, extractionPoint.y, extractionPoint.z - 1.0,
                    0, 0, 0,                                    -- direction
                    0, 0, 0,                                    -- rotation
                    10.0, 10.0, 1.0,                            -- scale
                    255, 100, 0, 100,                           -- RGBA
                    false, false, 2, false, nil, nil, false
                )
            end
        end,
        onEnter = function()
            if activeMission and activeMission.phase == 'extraction' then
                FreeGangs.Client.Prison.DoBreakout()
            end
        end,
    })

    -- Store zone reference for cleanup
    activeMission.extractionZone = extractionZone

    -- Mission timer thread
    CreateThread(function()
        local startTime = GetGameTimer()
        local warningShown = false

        while activeMission and activeMission.type == 'escape' do
            local elapsed = GetGameTimer() - startTime

            -- Show 2-minute warning
            if not warningShown and elapsed >= (timerMs - 120000) then
                warningShown = true
                lib.notify({
                    title = 'Prison Break',
                    description = '2 minutes remaining!',
                    type = 'warning',
                    duration = 5000,
                    icon = 'clock',
                })
            end

            -- Time expired
            if elapsed >= timerMs then
                if activeMission and activeMission.type == 'escape' then
                    FreeGangs.Client.Prison.FailEscape('Time expired')
                end
                return
            end

            Wait(1000)
        end
    end)
end

---Perform the breakout sequence at the extraction zone
function FreeGangs.Client.Prison.DoBreakout()
    if not activeMission or activeMission.phase ~= 'extraction' then return end

    activeMission.phase = 'breakout'

    local escapeConfig = FreeGangs.Config.Prison.EscapeMission or {}

    -- Notify player
    lib.notify({
        title = 'Prison Break',
        description = 'Starting breakout... stay still!',
        type = 'warning',
        duration = 5000,
        icon = 'unlock',
    })

    -- Run breakout progress bar
    local success = lib.progressBar({
        duration = escapeConfig.BreakoutDurationMs or 15000,
        label = 'Staging prison breakout...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'mp_arresting',
            clip = 'a_uncuff',
        },
    })

    if not success then
        FreeGangs.Client.Prison.FailEscape('Breakout cancelled')
        return
    end

    -- Remove extraction zone now that breakout is done
    if activeMission.extractionZone then
        activeMission.extractionZone:remove()
        activeMission.extractionZone = nil
    end

    -- Apply wanted level
    local wantedLevel = escapeConfig.WantedLevel or 3
    SetPlayerWantedLevel(PlayerId(), wantedLevel, false)
    SetPlayerWantedLevelNow(PlayerId(), false)

    -- Transition to getaway phase
    activeMission.phase = 'getaway'

    -- Determine safehouse location (gang HQ or predefined fallback)
    local safehouse = FreeGangs.Client.GangHQ
        or (FreeGangs.Client.PlayerGang and FreeGangs.Client.PlayerGang.hqCoords)
        or vector3(1604.25, 3570.84, 37.78)

    -- If safehouse is a vector4, convert to vector3 for waypoint
    local safeX = safehouse.x or 0.0
    local safeY = safehouse.y or 0.0

    -- Set waypoint to safehouse
    SetNewWaypoint(safeX, safeY)

    lib.notify({
        title = 'Breakout Successful!',
        description = 'Get to the safehouse! Lose the heat!',
        type = 'success',
        duration = 10000,
        icon = 'person-running',
    })

    -- Create safehouse arrival zone
    local safehouseZone = lib.zones.sphere({
        coords = vector3(safeX, safeY, safehouse.z or 0.0),
        radius = escapeConfig.SafehouseRadius or 25.0,
        debug = FreeGangs.Config.Debug or (FreeGangs.Config.General and FreeGangs.Config.General.Debug),
        inside = function()
            if activeMission and activeMission.phase == 'getaway' then
                -- Draw safehouse marker
                DrawMarker(
                    1,
                    safeX, safeY, (safehouse.z or 0.0) - 1.0,
                    0, 0, 0,
                    0, 0, 0,
                    20.0, 20.0, 1.0,
                    0, 255, 100, 100,
                    false, false, 2, false, nil, nil, false
                )
            end
        end,
        onEnter = function()
            if activeMission and activeMission.phase == 'getaway' then
                FreeGangs.Client.Prison.CompleteEscape()
            end
        end,
    })

    activeMission.safehouseZone = safehouseZone
end

---Successfully complete the escape mission
function FreeGangs.Client.Prison.CompleteEscape()
    if not activeMission then return end

    -- Clear wanted level
    ClearPlayerWantedLevel(PlayerId())

    -- Notify server of successful escape
    lib.callback.await('free-gangs:callback:completeEscape', false, true)

    lib.notify({
        title = 'Prison Break Complete!',
        description = (activeMission.targetName or 'Your member') .. ' has been freed!',
        type = 'success',
        duration = 10000,
        icon = 'circle-check',
    })

    -- Clean up all mission state
    FreeGangs.Client.Prison.CleanupMission()
end

---Fail the escape mission with a reason
---@param reason string The reason the escape failed
function FreeGangs.Client.Prison.FailEscape(reason)
    if not activeMission then return end

    -- Notify server of failure
    lib.callback.await('free-gangs:callback:completeEscape', false, false)

    lib.notify({
        title = 'Prison Break Failed',
        description = reason or 'The escape attempt has failed',
        type = 'error',
        duration = 8000,
        icon = 'circle-xmark',
    })

    -- Clean up all mission state
    FreeGangs.Client.Prison.CleanupMission()
end

---Clean up all active mission state and zones
function FreeGangs.Client.Prison.CleanupMission()
    if not activeMission then return end

    -- Remove extraction zone
    if activeMission.extractionZone then
        activeMission.extractionZone:remove()
        activeMission.extractionZone = nil
    end

    -- Remove safehouse zone
    if activeMission.safehouseZone then
        activeMission.safehouseZone:remove()
        activeMission.safehouseZone = nil
    end

    -- Remove delivery zone
    if activeMission.deliveryZone then
        activeMission.deliveryZone:remove()
        activeMission.deliveryZone = nil
    end

    -- Clear waypoint
    SetWaypointOff()

    -- Reset wanted level
    ClearPlayerWantedLevel(PlayerId())

    -- Clear mission state
    activeMission = nil

    FreeGangs.Utils.Debug('Prison mission cleaned up')
end

-- ============================================================================
-- LEADERBOARD
-- ============================================================================

---Show the prison control leaderboard
function FreeGangs.Client.Prison.ShowLeaderboard()
    local leaderboard = lib.callback.await('free-gangs:callback:getPrisonLeaderboard', false)

    if not leaderboard or #leaderboard == 0 then
        lib.notify({
            title = 'Leaderboard',
            description = 'No gangs have prison control yet',
            type = 'inform',
            duration = 5000,
            icon = 'ranking-star',
        })
        return
    end

    local options = {}
    local playerGangName = FreeGangs.Client.PlayerGang and FreeGangs.Client.PlayerGang.name

    for rank, entry in ipairs(leaderboard) do
        -- Determine trend icon based on influence level
        local trendIcon
        local trendDescription
        if entry.influence >= 75 then
            trendIcon = 'arrow-up'
            trendDescription = 'Dominant'
        elseif entry.influence >= 50 then
            trendIcon = 'arrow-trend-up'
            trendDescription = 'Strong'
        elseif entry.influence >= 25 then
            trendIcon = 'minus'
            trendDescription = 'Moderate'
        else
            trendIcon = 'arrow-trend-down'
            trendDescription = 'Low'
        end

        -- Count active benefits for this influence level
        local benefitCount = 0
        local config = FreeGangs.Config.Prison.ControlBenefits
        for threshold, benefits in pairs(config) do
            if entry.influence >= threshold then
                benefitCount = benefitCount + #benefits
            end
        end

        -- Highlight the player's own gang
        local isPlayerGang = entry.gangName == playerGangName
        local titlePrefix = '#' .. rank .. ' '
        local gangLabel = entry.label or entry.gangName

        table.insert(options, {
            title = titlePrefix .. gangLabel .. (isPlayerGang and ' (You)' or ''),
            icon = trendIcon,
            iconColor = isPlayerGang and 'green' or nil,
            description = string.format('%.1f%% control | %s', entry.influence, trendDescription),
            progress = entry.influence,
            colorScheme = entry.influence >= 50 and 'green' or (entry.influence >= 25 and 'yellow' or 'red'),
            metadata = {
                { label = 'Control', value = string.format('%.1f%%', entry.influence) },
                { label = 'Status', value = trendDescription },
                { label = 'Benefits Active', value = tostring(benefitCount) },
            },
        })
    end

    lib.registerContext({
        id = 'freegangs_prison_leaderboard',
        title = 'Prison Control Leaderboard',
        menu = 'freegangs_prison',
        options = options,
    })

    lib.showContext('freegangs_prison_leaderboard')
end

-- ============================================================================
-- UTILITY
-- ============================================================================

---Get smuggle point coordinates from territory config
---@return table Array of vector3 smuggle points
function FreeGangs.Client.Prison.GetSmugglePoints()
    -- Try to get from territory config
    local zoneName = FreeGangs.Config.Prison.ZoneName or 'bolingbroke'
    local territories = FreeGangs.Config.Territories

    if territories and territories[zoneName] then
        local zone = territories[zoneName]
        -- Check settings sub-table first (territory config structure)
        if zone.settings and zone.settings.smugglePoints then
            return zone.settings.smugglePoints
        end
        -- Check direct smugglePoints
        if zone.smugglePoints then
            return zone.smugglePoints
        end
    end

    -- Try runtime territory data
    local zone = FreeGangs.Territories and FreeGangs.Territories[zoneName]
    if zone and zone.smugglePoints then
        return zone.smugglePoints
    end

    -- Fallback coordinates near Bolingbroke Penitentiary
    return {
        vector3(1805.5, 2620.2, 46.0),
        vector3(1890.2, 2550.5, 46.0),
    }
end

---Check if a prison escape mission is currently active
---@return boolean
function FreeGangs.Client.Prison.IsMissionActive()
    return activeMission ~= nil
end

---Get the current mission phase
---@return string|nil phase
function FreeGangs.Client.Prison.GetMissionPhase()
    return activeMission and activeMission.phase or nil
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Contraband ready notification for jailed players
RegisterNetEvent('free-gangs:client:contrabandReady', function()
    lib.notify({
        title = 'Contraband Ready',
        description = 'Your smuggled goods are ready for pickup',
        type = 'inform',
        duration = 10000,
        icon = 'box',
    })
end)

-- Escape initiated notification
RegisterNetEvent('free-gangs:client:escapeInitiated', function(data)
    lib.notify({
        title = 'Prison Break',
        description = 'An escape attempt has been initiated!',
        type = 'warning',
        duration = 15000,
        icon = 'unlock',
    })
end)

-- Smuggle mission data from server (notification for other gang members)
RegisterNetEvent('free-gangs:client:startSmuggleMission', function(data)
    if not data then return end

    -- Skip if this player already has an active mission (they initiated it)
    if activeMission then return end

    lib.notify({
        title = 'Gang Smuggle Mission',
        description = 'A smuggle mission has been started by a gang member',
        type = 'inform',
        duration = 5000,
        icon = 'truck-fast',
    })
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if activeMission then
        FreeGangs.Client.Prison.CleanupMission()
    end
end)

return FreeGangs.Client.Prison
