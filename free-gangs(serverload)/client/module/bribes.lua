--[[
    FREE-GANGS: Client Bribes Module
    
    Handles client-side bribery operations including contact spawning/despawning,
    NPC identification, ox_target interactions, and ability usage menus.
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Bribes = {}

-- Local state
local spawnedPeds = {} -- { [contactType] = { ped = pedHandle, coords = vec4, ... } }
local identifiedContacts = {} -- Contacts the player can see
local nearbyContacts = {} -- Contacts in range for identification

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize the bribes module
function FreeGangs.Client.Bribes.Initialize()
    FreeGangs.Utils.Debug('Initializing bribes module...')
    
    -- Request initial spawned contacts from server
    FreeGangs.Client.Bribes.RequestSpawnedContacts()
    
    -- Start identification thread
    FreeGangs.Client.Bribes.StartIdentificationThread()
    
    FreeGangs.Utils.Debug('Bribes module initialized')
end

---Request currently spawned contacts from server
function FreeGangs.Client.Bribes.RequestSpawnedContacts()
    local contacts = lib.callback.await('freegangs:getSpawnedContacts', false)
    
    if contacts then
        for contactType, data in pairs(contacts) do
            FreeGangs.Client.Bribes.OnContactSpawned(contactType, data)
        end
    end
end

-- ============================================================================
-- CONTACT SPAWNING/DESPAWNING
-- ============================================================================

---Handle server notification of contact spawn
---@param contactType string
---@param data table Contact spawn data
function FreeGangs.Client.Bribes.OnContactSpawned(contactType, data)
    if not data or not data.coords then return end
    
    -- Store contact data
    nearbyContacts[contactType] = {
        coords = data.coords,
        pedModel = data.pedModel,
        scenario = data.scenario,
        label = data.label,
        despawnAt = data.despawnAt,
    }
    
    FreeGangs.Utils.Debug('Contact available: ' .. contactType .. ' at ' .. data.label)
end

---Handle server notification of contact despawn
---@param contactType string
function FreeGangs.Client.Bribes.OnContactDespawned(contactType)
    -- Remove from nearby
    nearbyContacts[contactType] = nil
    identifiedContacts[contactType] = nil
    
    -- Despawn ped if exists
    if spawnedPeds[contactType] then
        FreeGangs.Client.Bribes.DespawnContactPed(contactType)
    end
    
    FreeGangs.Utils.Debug('Contact despawned: ' .. contactType)
end

---Spawn the actual NPC ped for a contact
---@param contactType string
function FreeGangs.Client.Bribes.SpawnContactPed(contactType)
    local data = nearbyContacts[contactType]
    if not data or spawnedPeds[contactType] then return end
    
    local coords = data.coords
    local modelHash = joaat(data.pedModel)
    
    -- Request model
    lib.requestModel(modelHash, 5000)
    
    -- Create ped
    local ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    
    if not DoesEntityExist(ped) then
        FreeGangs.Utils.Debug('Failed to spawn ' .. contactType .. ' ped')
        return
    end
    
    -- Configure ped
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanBeTargetted(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    
    -- Apply scenario if specified
    if data.scenario then
        TaskStartScenarioInPlace(ped, data.scenario, 0, true)
    end
    
    -- Store reference
    spawnedPeds[contactType] = {
        ped = ped,
        coords = coords,
        networkId = nil, -- Local ped, no network
    }
    
    -- Add ox_target if identified
    if identifiedContacts[contactType] then
        FreeGangs.Client.Bribes.AddContactTarget(contactType)
    end
    
    -- Set model as no longer needed
    SetModelAsNoLongerNeeded(modelHash)
    
    FreeGangs.Utils.Debug('Spawned ' .. contactType .. ' ped')
end

---Despawn a contact NPC ped
---@param contactType string
function FreeGangs.Client.Bribes.DespawnContactPed(contactType)
    local spawn = spawnedPeds[contactType]
    if not spawn then return end
    
    -- Remove ox_target
    FreeGangs.Client.Bribes.RemoveContactTarget(contactType)
    
    -- Delete ped
    if DoesEntityExist(spawn.ped) then
        DeletePed(spawn.ped)
    end
    
    spawnedPeds[contactType] = nil
    
    FreeGangs.Utils.Debug('Despawned ' .. contactType .. ' ped')
end

-- ============================================================================
-- CONTACT IDENTIFICATION
-- ============================================================================

---Start the identification thread
function FreeGangs.Client.Bribes.StartIdentificationThread()
    CreateThread(function()
        while true do
            Wait(1000) -- Check every second
            
            local playerGang = FreeGangs.Client.PlayerGang
            if playerGang then
                FreeGangs.Client.Bribes.UpdateContactVisibility(playerGang)
            end
        end
    end)
end

---Update which contacts are visible to the player
---@param playerGang table
function FreeGangs.Client.Bribes.UpdateContactVisibility(playerGang)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local gangLevel = playerGang.master_level or 1
    local spawnDistSq = 100.0 * 100.0 -- 100 unit spawn range
    local despawnDistSq = FreeGangs.Config.BribeContacts.SpawnSettings.despawnDistanceSq
    
    for contactType, data in pairs(nearbyContacts) do
        local contactInfo = FreeGangs.BribeContactInfo[contactType]
        if not contactInfo then goto continue end
        
        local coords = data.coords
        local distSq = #(playerCoords - vector3(coords.x, coords.y, coords.z))^2
        
        -- Check if player can see this contact type
        local canIdentify = gangLevel >= contactInfo.minLevel
        
        if canIdentify then
            -- Player can identify this contact
            if not identifiedContacts[contactType] then
                identifiedContacts[contactType] = true
                
                -- Add target to existing ped if spawned
                if spawnedPeds[contactType] then
                    FreeGangs.Client.Bribes.AddContactTarget(contactType)
                end
            end
        else
            -- Player cannot identify - remove if was identified
            if identifiedContacts[contactType] then
                identifiedContacts[contactType] = nil
                
                if spawnedPeds[contactType] then
                    FreeGangs.Client.Bribes.RemoveContactTarget(contactType)
                end
            end
        end
        
        -- Handle spawning/despawning based on distance
        if distSq < spawnDistSq then
            -- Close enough to spawn
            if not spawnedPeds[contactType] then
                FreeGangs.Client.Bribes.SpawnContactPed(contactType)
            end
        elseif distSq > despawnDistSq then
            -- Too far, despawn
            if spawnedPeds[contactType] then
                FreeGangs.Client.Bribes.DespawnContactPed(contactType)
            end
        end
        
        ::continue::
    end
end

---Check if player can identify a specific contact
---@param contactType string
---@return boolean
function FreeGangs.Client.Bribes.CanIdentifyContact(contactType)
    return identifiedContacts[contactType] == true
end

-- ============================================================================
-- OX_TARGET INTEGRATION
-- ============================================================================

---Add ox_target options to a contact
---@param contactType string
function FreeGangs.Client.Bribes.AddContactTarget(contactType)
    local spawn = spawnedPeds[contactType]
    if not spawn or not DoesEntityExist(spawn.ped) then return end
    
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local visualTells = FreeGangs.Config.BribeContacts.VisualTells[contactType]
    
    -- Check if gang already has this contact
    local hasContact = FreeGangs.Client.Bribes.GangHasContact(contactType)
    
    local options = {}
    
    if hasContact then
        -- Already have contact - show ability menu
        options[#options + 1] = {
            name = 'freegangs_bribe_' .. contactType .. '_abilities',
            icon = contactInfo.icon or 'user-secret',
            label = 'Use Contact',
            onSelect = function()
                FreeGangs.Client.Bribes.ShowAbilityMenu(contactType)
            end,
        }
        
        -- Payment option
        options[#options + 1] = {
            name = 'freegangs_bribe_' .. contactType .. '_pay',
            icon = 'dollar-sign',
            label = 'Make Payment',
            onSelect = function()
                FreeGangs.Client.Bribes.MakePayment(contactType)
            end,
        }
    else
        -- Don't have contact - show approach option
        options[#options + 1] = {
            name = 'freegangs_bribe_' .. contactType .. '_approach',
            icon = 'handshake',
            label = 'Approach (' .. contactInfo.label .. ')',
            onSelect = function()
                FreeGangs.Client.Bribes.ApproachContact(contactType)
            end,
        }
    end
    
    -- Add info option
    options[#options + 1] = {
        name = 'freegangs_bribe_' .. contactType .. '_info',
        icon = 'circle-info',
        label = visualTells and visualTells.description or 'Suspicious Individual',
        onSelect = function()
            FreeGangs.Client.Bribes.ShowContactInfo(contactType)
        end,
    }
    
    exports.ox_target:addLocalEntity(spawn.ped, options)
end

---Remove ox_target options from a contact
---@param contactType string
function FreeGangs.Client.Bribes.RemoveContactTarget(contactType)
    local spawn = spawnedPeds[contactType]
    if not spawn then return end
    
    exports.ox_target:removeLocalEntity(spawn.ped, {
        'freegangs_bribe_' .. contactType .. '_approach',
        'freegangs_bribe_' .. contactType .. '_abilities',
        'freegangs_bribe_' .. contactType .. '_pay',
        'freegangs_bribe_' .. contactType .. '_info',
    })
end

-- ============================================================================
-- CONTACT INTERACTION
-- ============================================================================

---Approach a contact to establish a bribe
---@param contactType string
function FreeGangs.Client.Bribes.ApproachContact(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local dialogue = FreeGangs.Config.BribeContacts.DialogueOptions
    
    -- Show initial dialogue
    local confirm = lib.alertDialog({
        header = dialogue.initial.title,
        content = dialogue.initial.description .. '\n\n**Contact:** ' .. contactInfo.label .. '\n**Weekly Cost:** ' .. FreeGangs.Utils.FormatMoney(contactInfo.weeklyCost),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    -- Play approach animation
    local playerPed = PlayerPedId()
    lib.requestAnimDict('anim@heists@ornate_bank@chat_manager')
    
    TaskPlayAnim(playerPed, 'anim@heists@ornate_bank@chat_manager', 'intro', 8.0, -8.0, 3000, 49, 0, false, false, false)
    
    -- Show progress bar
    local success = lib.progressBar({
        duration = 3000,
        label = 'Approaching contact...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
    })
    
    ClearPedTasks(playerPed)
    
    if not success then return end
    
    -- Send approach request to server
    local result, err = lib.callback.await('freegangs:bribes:approach', false, contactType)
    
    if result then
        -- Success - show bribe requirements
        FreeGangs.Client.Bribes.ShowEstablishDialog(contactType)
    else
        -- Failed
        lib.notify({
            title = 'Approach Failed',
            description = err or 'The contact rejected your approach.',
            type = 'error',
        })
    end
end

---Show the establish bribe dialog
---@param contactType string
function FreeGangs.Client.Bribes.ShowEstablishDialog(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local dialogue = FreeGangs.Config.BribeContacts.DialogueOptions
    
    local cost = contactInfo.weeklyCost
    if contactInfo.initialBribe then
        cost = contactInfo.initialBribe
    end
    
    local confirm = lib.alertDialog({
        header = dialogue.offer_response.success.title,
        content = string.format(
            dialogue.establish_confirm.description,
            FreeGangs.Utils.FormatMoney(cost),
            '7 days'
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then
        lib.notify({
            title = 'Bribe Window',
            description = 'You have 10 minutes to accept the offer.',
            type = 'warning',
        })
        return
    end
    
    -- Send establish request to server
    local result, err = lib.callback.await('freegangs:bribes:establish', false, contactType)
    
    if result then
        lib.notify({
            title = 'Contact Established',
            description = contactInfo.label .. ' is now on your payroll.',
            type = 'success',
        })
        
        -- Refresh target options
        if spawnedPeds[contactType] then
            FreeGangs.Client.Bribes.RemoveContactTarget(contactType)
            FreeGangs.Client.Bribes.AddContactTarget(contactType)
        end
    else
        lib.notify({
            title = 'Failed',
            description = err or 'Could not establish contact.',
            type = 'error',
        })
    end
end

---Make a payment to a contact
---@param contactType string
function FreeGangs.Client.Bribes.MakePayment(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    
    -- Get payment info from server
    local paymentInfo = lib.callback.await('freegangs:bribes:getPaymentInfo', false, contactType)
    
    if not paymentInfo then
        lib.notify({
            title = 'Error',
            description = 'Could not get payment information.',
            type = 'error',
        })
        return
    end
    
    local confirm = lib.alertDialog({
        header = 'Make Payment',
        content = string.format(
            '**Contact:** %s\n**Amount Due:** %s\n**Next Due:** %s',
            contactInfo.label,
            FreeGangs.Utils.FormatMoney(paymentInfo.amount),
            paymentInfo.nextDue or 'In 7 days'
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    -- Show progress
    local success = lib.progressBar({
        duration = 2000,
        label = 'Processing payment...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            car = true,
            move = true,
        },
    })
    
    if not success then return end
    
    -- Send payment request
    local result, err = lib.callback.await('freegangs:bribes:makePayment', false, contactType)
    
    if result then
        lib.notify({
            title = 'Payment Made',
            description = 'Payment to ' .. contactInfo.label .. ' processed.',
            type = 'success',
        })
    else
        lib.notify({
            title = 'Payment Failed',
            description = err or 'Could not process payment.',
            type = 'error',
        })
    end
end

---Show contact info dialog
---@param contactType string
function FreeGangs.Client.Bribes.ShowContactInfo(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local visualTells = FreeGangs.Config.BribeContacts.VisualTells[contactType]
    local abilities = FreeGangs.Config.BribeContacts.Abilities[contactType]
    
    local content = '**Type:** ' .. contactInfo.label .. '\n'
    content = content .. '**Required Level:** ' .. contactInfo.minLevel .. '\n'
    content = content .. '**Weekly Cost:** ' .. FreeGangs.Utils.FormatMoney(contactInfo.weeklyCost) .. '\n\n'
    
    if visualTells then
        content = content .. '**Description:**\n' .. visualTells.description .. '\n\n'
    end
    
    if abilities then
        content = content .. '**Abilities:**\n'
        if abilities.passive then
            content = content .. '• Passive: ' .. abilities.passive.description .. '\n'
        end
        if abilities.active then
            content = content .. '• Active: ' .. abilities.active.description .. '\n'
        end
    end
    
    lib.alertDialog({
        header = contactInfo.label .. ' Info',
        content = content,
        centered = true,
    })
end

-- ============================================================================
-- ABILITY MENUS
-- ============================================================================

---Show the ability menu for a contact
---@param contactType string
function FreeGangs.Client.Bribes.ShowAbilityMenu(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    local abilities = FreeGangs.Config.BribeContacts.Abilities[contactType]
    
    if not abilities then
        lib.notify({
            title = 'No Abilities',
            description = 'This contact has no usable abilities.',
            type = 'inform',
        })
        return
    end
    
    local options = {}
    
    -- Add passive info if exists
    if abilities.passive then
        options[#options + 1] = {
            title = 'Passive: ' .. abilities.passive.name:gsub('_', ' '):gsub('^%l', string.upper),
            description = abilities.passive.description,
            icon = 'shield-halved',
            disabled = true,
        }
    end
    
    -- Add active abilities
    if abilities.active then
        if abilities.active.options then
            -- Multi-option ability (Judge, Prison Guard)
            for optionName, optionData in pairs(abilities.active.options) do
                local cost = optionData.cost or optionData.costPerMinute
                options[#options + 1] = {
                    title = optionName:gsub('_', ' '):gsub('^%l', string.upper),
                    description = (cost and cost > 0) and ('Cost: ' .. FreeGangs.Utils.FormatMoney(cost)) or 'Variable cost',
                    icon = 'bolt',
                    onSelect = function()
                        FreeGangs.Client.Bribes.UseAbility(contactType, optionName)
                    end,
                }
            end
        else
            -- Single ability
            options[#options + 1] = {
                title = abilities.active.name:gsub('_', ' '):gsub('^%l', string.upper),
                description = abilities.active.description .. (abilities.active.cost and abilities.active.cost > 0 and (' (Cost: ' .. FreeGangs.Utils.FormatMoney(abilities.active.cost) .. ')') or ''),
                icon = 'bolt',
                onSelect = function()
                    FreeGangs.Client.Bribes.UseAbility(contactType, abilities.active.name)
                end,
            }
        end
    end
    
    lib.registerContext({
        id = 'freegangs_bribe_abilities_' .. contactType,
        title = contactInfo.label .. ' Abilities',
        options = options,
    })
    
    lib.showContext('freegangs_bribe_abilities_' .. contactType)
end

---Use a bribe ability
---@param contactType string
---@param abilityName string
function FreeGangs.Client.Bribes.UseAbility(contactType, abilityName)
    local params = {}
    
    -- Handle special cases that need additional input
    if contactType == FreeGangs.BribeContacts.JUDGE then
        if abilityName == 'reduce_sentence' or abilityName == 'release' or abilityName == 'immediate_release' then
            params = FreeGangs.Client.Bribes.GetJailTargetInput()
            if not params then return end
        end
    elseif contactType == FreeGangs.BribeContacts.PRISON_GUARD then
        if abilityName == 'contraband' or abilityName == 'contraband_delivery' then
            params = FreeGangs.Client.Bribes.GetContrabandInput()
            if not params then return end
        elseif abilityName == 'escape' or abilityName == 'help_escape' then
            params = FreeGangs.Client.Bribes.GetJailTargetInput()
            if not params then return end
        end
    end
    
    -- Show progress
    local success = lib.progressBar({
        duration = 2000,
        label = 'Using contact...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            car = true,
            move = true,
        },
    })
    
    if not success then return end
    
    -- Send ability request to server
    local result, response = lib.callback.await('freegangs:bribes:useAbility', false, contactType, abilityName, params)
    
    if result then
        lib.notify({
            title = 'Ability Used',
            description = FreeGangs.Locale('bribes.bribe_used') or 'Contact ability activated.',
            type = 'success',
        })
    else
        lib.notify({
            title = 'Failed',
            description = response or 'Could not use ability.',
            type = 'error',
        })
    end
end

---Get jail target input for Judge/Prison abilities
---@return table|nil
function FreeGangs.Client.Bribes.GetJailTargetInput()
    -- Get list of jailed gang members
    local jailedMembers = lib.callback.await('freegangs:bribes:getJailedMembers', false)
    
    if not jailedMembers or #jailedMembers == 0 then
        lib.notify({
            title = 'No Prisoners',
            description = 'No gang members currently jailed.',
            type = 'inform',
        })
        return nil
    end
    
    local options = {}
    for _, member in pairs(jailedMembers) do
        options[#options + 1] = {
            value = member.citizenid,
            label = member.name .. ' (' .. member.timeRemaining .. ' remaining)',
        }
    end
    
    local input = lib.inputDialog('Select Prisoner', {
        {
            type = 'select',
            label = 'Gang Member',
            options = options,
            required = true,
        },
    })
    
    if not input then return nil end
    
    return {
        targetCitizenid = input[1],
    }
end

---Get contraband input for Prison Guard delivery
---@return table|nil
function FreeGangs.Client.Bribes.GetContrabandInput()
    local allowedItems = FreeGangs.Config.BribeContacts.Abilities[FreeGangs.BribeContacts.PRISON_GUARD].active.options.contraband_delivery.allowedItems
    
    -- Get player's eligible items
    local playerItems = {}
    for _, itemName in pairs(allowedItems) do
        local count = exports.ox_inventory:Search('count', itemName)
        if count and count > 0 then
            playerItems[#playerItems + 1] = {
                value = itemName,
                label = itemName .. ' (x' .. count .. ')',
            }
        end
    end
    
    if #playerItems == 0 then
        lib.notify({
            title = 'No Items',
            description = 'You don\'t have any items to smuggle.',
            type = 'inform',
        })
        return nil
    end
    
    -- Get jailed members
    local jailedMembers = lib.callback.await('freegangs:bribes:getJailedMembers', false)
    
    if not jailedMembers or #jailedMembers == 0 then
        lib.notify({
            title = 'No Prisoners',
            description = 'No gang members currently jailed.',
            type = 'inform',
        })
        return nil
    end
    
    local memberOptions = {}
    for _, member in pairs(jailedMembers) do
        memberOptions[#memberOptions + 1] = {
            value = member.citizenid,
            label = member.name,
        }
    end
    
    local input = lib.inputDialog('Contraband Delivery', {
        {
            type = 'select',
            label = 'Target Prisoner',
            options = memberOptions,
            required = true,
        },
        {
            type = 'select',
            label = 'Item to Send',
            options = playerItems,
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
    
    if not input then return nil end
    
    return {
        targetCitizenid = input[1],
        items = {
            { name = input[2], amount = input[3] },
        },
    }
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Check if the player's gang has a contact
---@param contactType string
---@return boolean
function FreeGangs.Client.Bribes.GangHasContact(contactType)
    local gangBribes = FreeGangs.Client.Cache.Get('gangBribes') or {}
    return gangBribes[contactType] ~= nil
end

---Get gang's bribe data
---@param contactType string
---@return table|nil
function FreeGangs.Client.Bribes.GetBribeData(contactType)
    local gangBribes = FreeGangs.Client.Cache.Get('gangBribes') or {}
    return gangBribes[contactType]
end

---Refresh gang's bribe data from server
function FreeGangs.Client.Bribes.RefreshBribes()
    local bribes = lib.callback.await('freegangs:bribes:getGangBribes', false)
    if bribes then
        FreeGangs.Client.Cache.Set('gangBribes', bribes)
    end
end

-- ============================================================================
-- PASSIVE EFFECT HANDLERS
-- ============================================================================

---Check if dispatch should be blocked (Beat Cop passive)
---@return boolean
function FreeGangs.Client.Bribes.ShouldBlockDispatch()
    if not FreeGangs.Client.Bribes.GangHasContact(FreeGangs.BribeContacts.BEAT_COP) then
        return false
    end
    
    -- Check zone control
    local currentZone = FreeGangs.Client.CurrentZone
    if not currentZone then return false end
    
    local playerGang = FreeGangs.Client.PlayerGang
    if not playerGang then return false end
    
    -- STUB: Check zone control (would come from Territory module)
    local control = FreeGangs.Client.Bribes.GetZoneControl(currentZone.name, playerGang.name)
    
    return control >= 50
end

---Check dispatch delay amount (Dispatcher passive)
---@return number Delay in seconds (0 if no delay)
function FreeGangs.Client.Bribes.GetDispatchDelay()
    if not FreeGangs.Client.Bribes.GangHasContact(FreeGangs.BribeContacts.DISPATCHER) then
        return 0
    end
    
    -- Check zone control
    local currentZone = FreeGangs.Client.CurrentZone
    if not currentZone then return 0 end
    
    local playerGang = FreeGangs.Client.PlayerGang
    if not playerGang then return 0 end
    
    -- STUB: Check zone control
    local control = FreeGangs.Client.Bribes.GetZoneControl(currentZone.name, playerGang.name)
    
    if control >= 50 then
        return 60 -- 60 second delay
    end
    
    return 0
end

---Get jail sentence modifier (Judge passive)
---@return number Multiplier (1.0 = no reduction)
function FreeGangs.Client.Bribes.GetSentenceModifier()
    if not FreeGangs.Client.Bribes.GangHasContact(FreeGangs.BribeContacts.JUDGE) then
        return 1.0
    end
    
    -- -30% sentence
    return 0.70
end

---Get zone control percentage (STUB)
---@param zoneName string
---@param gangName string
---@return number
function FreeGangs.Client.Bribes.GetZoneControl(zoneName, gangName)
    -- STUB: Replace with actual Territory module integration
    local territories = FreeGangs.Client.Cache.Get('territories') or {}
    local territory = territories[zoneName]
    
    if territory and territory.influence then
        return territory.influence[gangName] or 0
    end
    
    return 0
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Contact spawned
RegisterNetEvent('freegangs:client:contactSpawned', function(contactType, data)
    FreeGangs.Client.Bribes.OnContactSpawned(contactType, data)
end)

-- Contact despawned
RegisterNetEvent('freegangs:client:contactDespawned', function(contactType)
    FreeGangs.Client.Bribes.OnContactDespawned(contactType)
end)

-- Bribe data updated
RegisterNetEvent('freegangs:client:bribesUpdated', function(bribes)
    FreeGangs.Client.Cache.Set('gangBribes', bribes)
    
    -- Refresh targets for all spawned contacts
    for contactType, spawn in pairs(spawnedPeds) do
        FreeGangs.Client.Bribes.RemoveContactTarget(contactType)
        FreeGangs.Client.Bribes.AddContactTarget(contactType)
    end
end)

-- Payment reminder
RegisterNetEvent('freegangs:client:bribePaymentReminder', function(contactType, hoursRemaining)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    
    lib.notify({
        title = 'Payment Due',
        description = string.format('Payment to %s due in %d hours', contactInfo.label, math.ceil(hoursRemaining)),
        type = 'warning',
        duration = 8000,
    })
end)

-- Initialize on resource start
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        if FreeGangs.Client.Ready then
            FreeGangs.Client.Bribes.Initialize()
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        -- Despawn all peds
        for contactType, _ in pairs(spawnedPeds) do
            FreeGangs.Client.Bribes.DespawnContactPed(contactType)
        end
    end
end)

return FreeGangs.Client.Bribes
