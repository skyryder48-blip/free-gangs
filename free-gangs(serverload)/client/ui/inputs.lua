--[[
    FREE-GANGS: UI Input Dialogs Module
    
    ox_lib input dialogs for gang creation, invitations, deposits,
    war declarations, and other interactive forms.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.UI = FreeGangs.Client.UI or {}

-- ============================================================================
-- GANG CREATION
-- ============================================================================

---Show gang creation form
function FreeGangs.Client.UI.ShowGangCreation()
    -- Check if player can create
    local canCreate = lib.callback.await('free-gangs:callback:canCreateGang', false)
    if not canCreate then
        FreeGangs.Bridge.Notify('You cannot create a gang at this time', 'error')
        return
    end
    
    -- Build archetype options
    local archetypeOptions = {}
    for archetype, info in pairs(FreeGangs.ArchetypeLabels) do
        table.insert(archetypeOptions, {
            value = archetype,
            label = info.label,
        })
    end
    
    -- Build color options
    local colorOptions = {
        { value = '#FF0000', label = '🔴 Red' },
        { value = '#00FF00', label = '🟢 Green' },
        { value = '#0000FF', label = '🔵 Blue' },
        { value = '#FFFF00', label = '🟡 Yellow' },
        { value = '#FF00FF', label = '🟣 Purple' },
        { value = '#00FFFF', label = '🔵 Cyan' },
        { value = '#FFA500', label = '🟠 Orange' },
        { value = '#FFFFFF', label = '⚪ White' },
        { value = '#8B0000', label = '🟤 Dark Red' },
        { value = '#006400', label = '🌲 Dark Green' },
    }
    
    local input = lib.inputDialog(FreeGangs.L('gang', 'create_title'), {
        {
            type = 'input',
            label = FreeGangs.L('gang', 'create_name'),
            description = FreeGangs.L('gang', 'create_name_desc'),
            required = true,
            min = 2,
            max = 50,
            placeholder = 'Enter gang name...',
        },
        {
            type = 'select',
            label = FreeGangs.L('gang', 'create_archetype'),
            description = FreeGangs.L('gang', 'create_archetype_desc'),
            required = true,
            options = archetypeOptions,
        },
        {
            type = 'select',
            label = FreeGangs.L('gang', 'create_color'),
            description = FreeGangs.L('gang', 'create_color_desc'),
            options = colorOptions,
            default = '#8B0000',
        },
    })
    
    if not input then return end
    
    local gangName = input[1]
    local archetype = input[2]
    local color = input[3] or '#8B0000'
    
    -- Validate name
    if not gangName or #gangName < 2 then
        FreeGangs.Bridge.Notify(FreeGangs.L('gang', 'create_invalid_name'), 'error')
        return
    end
    
    -- Confirm creation with cost
    local config = FreeGangs.Config.General
    local costText = ''
    if config.GangCreationItems and #config.GangCreationItems > 0 then
        local costs = {}
        for _, item in ipairs(config.GangCreationItems) do
            if item.item == 'money' then
                table.insert(costs, FreeGangs.Utils.FormatMoney(item.amount))
            else
                table.insert(costs, string.format('%dx %s', item.amount, item.item))
            end
        end
        costText = '\n\nCost: ' .. table.concat(costs, ', ')
    end
    
    local confirm = lib.alertDialog({
        header = 'Confirm Gang Creation',
        content = string.format(
            'Create **%s** as a %s?%s',
            gangName,
            FreeGangs.ArchetypeLabels[archetype].label,
            costText
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    -- Send to server
    TriggerServerEvent(FreeGangs.Events.Server.CREATE_GANG, {
        name = gangName,
        label = gangName,
        archetype = archetype,
        color = color,
    })
end

-- ============================================================================
-- MEMBER MANAGEMENT
-- ============================================================================

---Show invite member input
function FreeGangs.Client.UI.ShowInviteInput()
    local input = lib.inputDialog(FreeGangs.L('menu', 'invite_member'), {
        {
            type = 'number',
            label = 'Player ID',
            description = 'Enter the server ID of the player to invite',
            required = true,
            min = 1,
            placeholder = 'Player Server ID',
        },
    })
    
    if not input then return end
    
    local playerId = tonumber(input[1])
    if not playerId then
        FreeGangs.Bridge.Notify('Invalid player ID', 'error')
        return
    end
    
    -- Send invite request
    TriggerServerEvent('free-gangs:server:invitePlayer', playerId)
end

---Confirm rank change (promote/demote)
---@param member table
---@param action string 'promote' or 'demote'
function FreeGangs.Client.UI.ConfirmRankChange(member, action)
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local currentRank = member.rank or 0
    local newRank = action == 'promote' and currentRank + 1 or currentRank - 1
    local rankInfo = FreeGangs.DefaultRanks[gangData.archetype] and 
                    FreeGangs.DefaultRanks[gangData.archetype][newRank]
    
    local newRankName = rankInfo and rankInfo.name or string.format('Rank %d', newRank)
    
    local confirm = lib.alertDialog({
        header = action == 'promote' and 'Confirm Promotion' or 'Confirm Demotion',
        content = string.format(
            '%s **%s** to **%s**?',
            action == 'promote' and 'Promote' or 'Demote',
            member.name or member.citizenid,
            newRankName
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    local event = action == 'promote' and FreeGangs.Events.Server.PROMOTE_MEMBER or FreeGangs.Events.Server.DEMOTE_MEMBER
    TriggerServerEvent(event, member.citizenid)
end

---Confirm kick member
---@param member table
function FreeGangs.Client.UI.ConfirmKickMember(member)
    local confirm = lib.alertDialog({
        header = 'Confirm Kick',
        content = string.format(
            'Are you sure you want to kick **%s** from the gang?\n\nThis action cannot be undone.',
            member.name or member.citizenid
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent(FreeGangs.Events.Server.KICK_MEMBER, member.citizenid)
end

---Confirm leaving gang
function FreeGangs.Client.UI.ConfirmLeaveGang()
    local confirm = lib.alertDialog({
        header = 'Leave Gang',
        content = 'Are you sure you want to leave your gang?\n\nYou will lose your rank and any personal reputation.',
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent(FreeGangs.Events.Server.LEAVE_GANG)
end

-- ============================================================================
-- TREASURY INPUTS
-- ============================================================================

---Show deposit input
---@param depositType string 'treasury' or 'warchest'
function FreeGangs.Client.UI.ShowDepositInput(depositType)
    local playerCash = FreeGangs.Bridge.GetMoney(nil, 'cash') or 0
    
    local input = lib.inputDialog(FreeGangs.L('treasury', 'deposit'), {
        {
            type = 'number',
            label = 'Amount',
            description = string.format('You have %s cash', FreeGangs.Utils.FormatMoney(playerCash)),
            required = true,
            min = 1,
            max = playerCash,
            placeholder = 'Enter amount...',
        },
    })
    
    if not input then return end
    
    local amount = tonumber(input[1])
    if not amount or amount <= 0 then
        FreeGangs.Bridge.Notify('Invalid amount', 'error')
        return
    end
    
    if amount > playerCash then
        FreeGangs.Bridge.Notify(FreeGangs.L('treasury', 'insufficient_funds'), 'error')
        return
    end
    
    local event = depositType == 'warchest' and FreeGangs.Events.Server.DEPOSIT_WARCHEST or FreeGangs.Events.Server.DEPOSIT_TREASURY
    TriggerServerEvent(event, amount)
end

---Show withdraw input
---@param withdrawType string 'treasury'
function FreeGangs.Client.UI.ShowWithdrawInput(withdrawType)
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local balance = gangData.treasury or 0
    
    local input = lib.inputDialog(FreeGangs.L('treasury', 'withdraw'), {
        {
            type = 'number',
            label = 'Amount',
            description = string.format('Treasury balance: %s', FreeGangs.Utils.FormatMoney(balance)),
            required = true,
            min = 1,
            max = balance,
            placeholder = 'Enter amount...',
        },
    })
    
    if not input then return end
    
    local amount = tonumber(input[1])
    if not amount or amount <= 0 then
        FreeGangs.Bridge.Notify('Invalid amount', 'error')
        return
    end
    
    if amount > balance then
        FreeGangs.Bridge.Notify(FreeGangs.L('treasury', 'insufficient_funds'), 'error')
        return
    end
    
    TriggerServerEvent(FreeGangs.Events.Server.WITHDRAW_TREASURY, amount)
end

-- ============================================================================
-- WAR DECLARATION
-- ============================================================================

---Show war declaration targets
---@param heatData table|nil
function FreeGangs.Client.UI.ShowWarDeclarationTargets(heatData)
    if not heatData then
        FreeGangs.Bridge.Notify('No rivals available for war', 'error')
        return
    end
    
    local targets = {}
    for gangName, heat in pairs(heatData) do
        if heat >= FreeGangs.Config.War.MinHeatForWar then
            table.insert(targets, {
                value = gangName,
                label = string.format('%s (%d heat)', gangName, heat),
            })
        end
    end
    
    if #targets == 0 then
        FreeGangs.Bridge.Notify(
            string.format('No gangs have enough heat (%d+ required)', FreeGangs.Config.War.MinHeatForWar),
            'error'
        )
        return
    end
    
    local gangData = FreeGangs.Client.PlayerGang
    local maxCollateral = gangData and gangData.war_chest or 0
    
    local input = lib.inputDialog(FreeGangs.L('war', 'declare_title'), {
        {
            type = 'select',
            label = FreeGangs.L('war', 'declare_target'),
            description = 'Choose the gang to declare war on',
            required = true,
            options = targets,
        },
        {
            type = 'number',
            label = FreeGangs.L('war', 'declare_collateral'),
            description = string.format(
                '%s\nWar Chest: %s | Min: %s | Max: %s',
                FreeGangs.L('war', 'declare_collateral_desc'),
                FreeGangs.Utils.FormatMoney(maxCollateral),
                FreeGangs.Utils.FormatMoney(FreeGangs.Config.War.MinCollateral),
                FreeGangs.Utils.FormatMoney(FreeGangs.Config.War.MaxCollateral)
            ),
            required = true,
            min = FreeGangs.Config.War.MinCollateral,
            max = math.min(maxCollateral, FreeGangs.Config.War.MaxCollateral),
            placeholder = 'Enter collateral amount...',
        },
    })
    
    if not input then return end
    
    local targetGang = input[1]
    local collateral = tonumber(input[2])
    
    if not targetGang or not collateral then
        FreeGangs.Bridge.Notify('Invalid war declaration', 'error')
        return
    end
    
    -- Final confirmation
    FreeGangs.Client.UI.ShowWarDeclaration(targetGang, collateral)
end

---Show war declaration confirmation
---@param targetGang string
---@param collateral number
function FreeGangs.Client.UI.ShowWarDeclaration(targetGang, collateral)
    local confirm = lib.alertDialog({
        header = '⚔️ DECLARE WAR',
        content = string.format(
            'You are about to declare war on **%s**!\n\n' ..
            '**Collateral:** %s\n' ..
            'They must match your collateral to accept.\n\n' ..
            'If they decline or don\'t respond within 24 hours, you win by forfeit.\n\n' ..
            '**This is a serious action!**',
            targetGang,
            FreeGangs.Utils.FormatMoney(collateral)
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'DECLARE WAR',
            cancel = 'Cancel',
        },
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent(FreeGangs.Events.Server.DECLARE_WAR, targetGang, collateral)
end

---Confirm surrender
---@param war table
function FreeGangs.Client.UI.ConfirmSurrender(war)
    local confirm = lib.alertDialog({
        header = '🏳️ Surrender',
        content = string.format(
            'Are you sure you want to surrender?\n\n' ..
            'Your gang will **lose** the war and forfeit your collateral of **%s**.\n\n' ..
            'This action cannot be undone!',
            FreeGangs.Utils.FormatMoney(war.collateral_amount)
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'SURRENDER',
            cancel = 'Keep Fighting',
        },
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent(FreeGangs.Events.Server.SURRENDER, war.id)
end

-- ============================================================================
-- BRIBE INPUTS
-- ============================================================================

---Show bribe payment confirmation
---@param contactType string
---@param amount number
function FreeGangs.Client.UI.ShowBribePaymentConfirm(contactType, amount)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return end
    
    local confirm = lib.alertDialog({
        header = 'Make Payment',
        content = string.format(
            'Pay **%s** to **%s** for continued services?\n\n' ..
            'This will be deducted from your gang treasury.',
            FreeGangs.Utils.FormatMoney(amount),
            contactInfo.label
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent(FreeGangs.Events.Server.PAY_BRIBE, contactType)
end

---Confirm terminating bribe contact
---@param contactType string
function FreeGangs.Client.UI.ConfirmTerminateBribe(contactType)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo then return end
    
    local confirm = lib.alertDialog({
        header = 'Terminate Contact',
        content = string.format(
            'Are you sure you want to terminate your relationship with **%s**?\n\n' ..
            'You will lose all benefits and must re-establish the contact if needed later.',
            contactInfo.label
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent('free-gangs:server:terminateBribe', contactType)
end

-- ============================================================================
-- GANG SETTINGS INPUTS
-- ============================================================================

---Show color picker
function FreeGangs.Client.UI.ShowColorPicker()
    local colorOptions = {
        { value = '#FF0000', label = '🔴 Red' },
        { value = '#00FF00', label = '🟢 Green' },
        { value = '#0000FF', label = '🔵 Blue' },
        { value = '#FFFF00', label = '🟡 Yellow' },
        { value = '#FF00FF', label = '🟣 Purple' },
        { value = '#00FFFF', label = '🔵 Cyan' },
        { value = '#FFA500', label = '🟠 Orange' },
        { value = '#FFFFFF', label = '⚪ White' },
        { value = '#8B0000', label = '🟤 Dark Red' },
        { value = '#006400', label = '🌲 Dark Green' },
        { value = '#FFD700', label = '🌟 Gold' },
        { value = '#C0C0C0', label = '⬜ Silver' },
        { value = '#000080', label = '🔵 Navy' },
        { value = '#800080', label = '💜 Purple' },
    }
    
    local input = lib.inputDialog('Change Gang Color', {
        {
            type = 'select',
            label = 'New Color',
            description = 'Choose your gang\'s new representative color',
            required = true,
            options = colorOptions,
        },
    })
    
    if not input then return end
    
    TriggerServerEvent('free-gangs:server:updateGangColor', input[1])
end

---Show rank customization
function FreeGangs.Client.UI.ShowRankCustomization()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    local defaultRanks = FreeGangs.DefaultRanks[gangData.archetype] or {}
    
    local fields = {}
    for rank = 0, 5 do
        local rankInfo = defaultRanks[rank] or { name = 'Rank ' .. rank }
        table.insert(fields, {
            type = 'input',
            label = string.format('Rank %d', rank),
            description = rank == 5 and 'Leader rank' or (rank >= 2 and 'Officer rank' or 'Member rank'),
            default = rankInfo.name,
            max = 30,
        })
    end
    
    local input = lib.inputDialog('Customize Rank Names', fields)
    
    if not input then return end
    
    local rankNames = {}
    for i, name in ipairs(input) do
        rankNames[i - 1] = name
    end
    
    TriggerServerEvent('free-gangs:server:updateRankNames', rankNames)
end

---Show leadership transfer
function FreeGangs.Client.UI.ShowLeadershipTransfer()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- Get members who can receive leadership (officers)
    local members = lib.callback.await(FreeGangs.Callbacks.GET_GANG_MEMBERS, false, gangData.name)
    if not members then return end
    
    local options = {}
    for _, member in ipairs(members) do
        if member.rank >= 2 and member.citizenid ~= FreeGangs.Bridge.GetCitizenId() then
            table.insert(options, {
                value = member.citizenid,
                label = string.format('%s (%s)', member.name or member.citizenid, member.rank_name or 'Officer'),
            })
        end
    end
    
    if #options == 0 then
        FreeGangs.Bridge.Notify('No eligible members for leadership transfer (need Rank 2+)', 'error')
        return
    end
    
    local input = lib.inputDialog('Transfer Leadership', {
        {
            type = 'select',
            label = 'New Leader',
            description = 'This will make them the gang boss and demote you',
            required = true,
            options = options,
        },
    })
    
    if not input then return end
    
    local newLeader = input[1]
    
    -- Final confirmation
    local confirm = lib.alertDialog({
        header = '⚠️ Transfer Leadership',
        content = 'Are you absolutely sure you want to transfer leadership?\n\n**You will lose your boss rank!**\n\nThis cannot be undone.',
        centered = true,
        cancel = true,
    })
    
    if confirm ~= 'confirm' then return end
    
    TriggerServerEvent('free-gangs:server:transferLeadership', newLeader)
end

---Show main corner selection (Street Gang)
function FreeGangs.Client.UI.ShowMainCornerSelection()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData or gangData.archetype ~= FreeGangs.Archetypes.STREET then return end
    
    -- Get controlled territories
    local territories = lib.callback.await(FreeGangs.Callbacks.GET_TERRITORIES, false)
    if not territories then return end
    
    local options = {}
    for zoneName, territory in pairs(territories) do
        local ourInfluence = territory.influence and territory.influence[gangData.name] or 0
        if ourInfluence >= 51 then -- Must control zone
            table.insert(options, {
                value = zoneName,
                label = territory.label or zoneName,
            })
        end
    end
    
    if #options == 0 then
        FreeGangs.Bridge.Notify('No controlled territories available (need >51% influence)', 'error')
        return
    end
    
    local input = lib.inputDialog('Set Main Corner', {
        {
            type = 'select',
            label = 'Main Corner Zone',
            description = '+5 bonus rep per drug sale in this zone',
            required = true,
            options = options,
        },
    })
    
    if not input then return end
    
    TriggerServerEvent('free-gangs:server:setMainCorner', input[1])
end

---Confirm dissolving gang
function FreeGangs.Client.UI.ConfirmDissolveGang()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return end
    
    -- First confirmation
    local confirm1 = lib.alertDialog({
        header = '⚠️ DISSOLVE GANG',
        content = string.format(
            'You are about to permanently delete **%s**!\n\n' ..
            'This will:\n' ..
            '• Remove all members\n' ..
            '• Delete all territories\n' ..
            '• Forfeit all treasury funds\n' ..
            '• Erase all reputation\n\n' ..
            '**THIS CANNOT BE UNDONE!**',
            gangData.label or gangData.name
        ),
        centered = true,
        cancel = true,
    })
    
    if confirm1 ~= 'confirm' then return end
    
    -- Type gang name to confirm
    local input = lib.inputDialog('Final Confirmation', {
        {
            type = 'input',
            label = 'Type gang name to confirm',
            description = string.format('Type "%s" exactly to confirm deletion', gangData.name),
            required = true,
        },
    })
    
    if not input then return end
    
    if input[1] ~= gangData.name then
        FreeGangs.Bridge.Notify('Gang name did not match. Dissolution cancelled.', 'error')
        return
    end
    
    TriggerServerEvent(FreeGangs.Events.Server.DELETE_GANG)
end

-- ============================================================================
-- MISC INPUTS
-- ============================================================================

---Show rival gang list
function FreeGangs.Client.UI.ShowGangList()
    local gangs = lib.callback.await(FreeGangs.Callbacks.GET_ALL_GANGS, false)
    if not gangs or #gangs == 0 then
        FreeGangs.Bridge.Notify('No active gangs in the city', 'inform')
        return
    end
    
    local options = {}
    for _, gang in ipairs(gangs) do
        local archetypeInfo = FreeGangs.ArchetypeLabels[gang.archetype] or { label = 'Unknown' }
        local levelInfo = FreeGangs.ReputationLevels[gang.master_level or 1] or { name = 'Unknown' }
        
        table.insert(options, {
            title = gang.label or gang.name,
            description = string.format('%s • Level %d: %s', archetypeInfo.label, gang.master_level or 1, levelInfo.name),
            icon = FreeGangs.Client.UI.GetArchetypeIcon(gang.archetype),
            iconColor = gang.color or '#FFFFFF',
            metadata = {
                { label = 'Members', value = tostring(gang.member_count or 0) },
                { label = 'Territories', value = tostring(gang.territory_count or 0) },
            },
        })
    end
    
    lib.registerContext({
        id = 'freegangs_gang_list',
        title = 'Active Gangs',
        menu = 'freegangs_no_gang',
        options = options,
    })
    
    lib.showContext('freegangs_gang_list')
end

---Show rivalry details
---@param otherGang string
---@param heat number
function FreeGangs.Client.UI.ShowRivalryDetails(otherGang, heat)
    local stage = FreeGangs.Client.UI.GetHeatStage(heat)
    local stageInfo = FreeGangs.HeatStageThresholds[stage]
    
    local options = {
        {
            title = 'Heat Level',
            icon = 'thermometer-full',
            iconColor = stageInfo.color,
            progress = heat,
            colorScheme = heat >= 75 and 'red' or (heat >= 50 and 'orange' or 'yellow'),
            metadata = {
                { label = 'Current', value = tostring(heat) },
                { label = 'Stage', value = stageInfo.label },
            },
        },
    }
    
    -- Stage effects
    if stageInfo.effects and #stageInfo.effects > 0 then
        table.insert(options, {
            title = 'Active Effects',
            icon = 'exclamation-circle',
            iconColor = stageInfo.color,
            description = table.concat(stageInfo.effects, ', '),
        })
    end
    
    -- Heat thresholds
    table.insert(options, {
        title = 'Stage Thresholds',
        icon = 'info-circle',
        iconColor = '#888888',
        metadata = {
            { label = 'Neutral', value = '0-29' },
            { label = 'Tension', value = '30-49' },
            { label = 'Cold War', value = '50-74' },
            { label = 'Rivalry', value = '75-89' },
            { label = 'War Ready', value = '90+' },
        },
    })
    
    lib.registerContext({
        id = 'freegangs_rivalry_detail',
        title = 'Rivalry: ' .. otherGang,
        menu = 'freegangs_wars',
        options = options,
    })
    
    lib.showContext('freegangs_rivalry_detail')
end

-- ============================================================================
-- WAR INVITATION HANDLING
-- ============================================================================

---Handle incoming war declaration
---@param warData table
RegisterNetEvent('free-gangs:client:warInvitation', function(warData)
    local alert = lib.alertDialog({
        header = '⚔️ WAR DECLARED!',
        content = string.format(
            '**%s** has declared war on your gang!\n\n' ..
            '**Their Collateral:** %s\n\n' ..
            'You must match their collateral to accept the war.\n' ..
            'If you decline or don\'t respond within 24 hours, you forfeit.\n\n' ..
            'Do you accept this declaration of war?',
            warData.attacker_gang,
            FreeGangs.Utils.FormatMoney(warData.collateral_amount)
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'ACCEPT WAR',
            cancel = 'Decline (Forfeit)',
        },
    })
    
    if alert == 'confirm' then
        TriggerServerEvent(FreeGangs.Events.Server.ACCEPT_WAR, warData.id)
    else
        TriggerServerEvent('free-gangs:server:declineWar', warData.id)
    end
end)

---Handle gang invitation
---@param inviteData table
RegisterNetEvent('free-gangs:client:gangInvitation', function(inviteData)
    local archetypeInfo = FreeGangs.ArchetypeLabels[inviteData.archetype] or { label = 'Unknown' }
    
    local alert = lib.alertDialog({
        header = 'Gang Invitation',
        content = string.format(
            '**%s** has invited you to join **%s**!\n\n' ..
            '**Type:** %s\n' ..
            '**Level:** %d\n\n' ..
            'Do you want to accept this invitation?',
            inviteData.inviter_name or 'Someone',
            inviteData.gang_label or inviteData.gang_name,
            archetypeInfo.label,
            inviteData.master_level or 1
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Join Gang',
            cancel = 'Decline',
        },
    })
    
    if alert == 'confirm' then
        TriggerServerEvent(FreeGangs.Events.Server.JOIN_GANG, inviteData.gang_name)
    end
end)

return FreeGangs.Client.UI
