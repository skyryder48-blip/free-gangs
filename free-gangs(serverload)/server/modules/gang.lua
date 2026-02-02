--[[
    FREE-GANGS: Gang Management Module
    
    Handles gang CRUD operations, creation, deletion, and configuration.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Gang = {}

-- ============================================================================
-- GANG CREATION
-- ============================================================================

---Create a new gang
---@param data table Gang creation data
---@param founderSource number The source of the founding player
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Gang.Create(data, founderSource)
    -- Validate required fields
    if not data.name or not data.label then
        return false, 'Gang name and label are required'
    end
    
    -- Sanitize and validate name
    local gangName = FreeGangs.Utils.Slugify(data.name)
    if #gangName < 2 or #gangName > 50 then
        return false, 'Gang name must be between 2 and 50 characters'
    end
    
    -- Check if gang already exists
    if FreeGangs.Server.Gangs[gangName] then
        return false, 'A gang with this name already exists'
    end
    
    -- Validate archetype
    local archetype = data.archetype or FreeGangs.Archetypes.STREET
    if not FreeGangs.ArchetypeLabels[archetype] then
        archetype = FreeGangs.Archetypes.STREET
    end
    
    -- Get founder info
    local citizenid = FreeGangs.Bridge.GetCitizenId(founderSource)
    if not citizenid then
        return false, 'Unable to identify founding player'
    end
    
    -- Check if founder is already in a gang
    local existingMembership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if existingMembership then
        return false, 'You are already in a gang'
    end
    
    -- Check creation cooldown
    local onCooldown, remaining = FreeGangs.Server.IsOnCooldown(founderSource, 'gang_create')
    if onCooldown then
        return false, 'You must wait ' .. FreeGangs.Utils.FormatDuration(remaining * 1000) .. ' before creating another gang'
    end
    
    -- Check required items (if configured)
    local config = FreeGangs.Config.General
    if config.GangCreationItems and #config.GangCreationItems > 0 then
        for _, required in pairs(config.GangCreationItems) do
            if required.item == 'money' then
                if FreeGangs.Bridge.GetMoney(founderSource, 'cash') < required.amount then
                    return false, 'You need ' .. FreeGangs.Utils.FormatMoney(required.amount) .. ' to create a gang'
                end
            else
                if not FreeGangs.Bridge.HasItem(founderSource, required.item, required.amount) then
                    return false, 'You need ' .. required.amount .. 'x ' .. required.item .. ' to create a gang'
                end
            end
        end
        
        -- Remove required items
        for _, required in pairs(config.GangCreationItems) do
            if required.item == 'money' then
                FreeGangs.Bridge.RemoveMoney(founderSource, required.amount, 'cash', 'Gang creation: ' .. data.label)
            else
                FreeGangs.Bridge.RemoveItem(founderSource, required.item, required.amount)
            end
        end
    end
    
    -- Create gang data
    local gangData = {
        name = gangName,
        label = data.label,
        archetype = archetype,
        color = data.color or '#FFFFFF',
        logo = data.logo,
        treasury = 0,
        war_chest = 0,
        master_rep = 0,
        master_level = 1,
        trap_spot = data.trap_spot,
        settings = data.settings or {},
        created_at = os.time(),
    }
    
    -- Insert into database
    local insertId = FreeGangs.Server.DB.CreateGang(gangData)
    if not insertId then
        return false, 'Failed to create gang in database'
    end
    
    gangData.id = insertId
    
    -- Create default ranks
    FreeGangs.Server.DB.CreateDefaultRanks(gangName, archetype)
    
    -- Add to cache
    FreeGangs.Server.Gangs[gangName] = gangData
    
    -- Register with QBox
    FreeGangs.Server.RegisterGangWithQBox(gangData)
    
    -- Add founder as boss
    local defaultRanks = FreeGangs.GetDefaultRanks(archetype)
    local bossRank = 5 -- Highest rank
    local bossRankName = defaultRanks[bossRank].name
    
    FreeGangs.Server.Member.Add(citizenid, gangName, bossRank, bossRankName)
    
    -- Set creation cooldown
    FreeGangs.Server.SetCooldown(founderSource, 'gang_create', config.GangCreationCooldown)
    
    -- Sync to GlobalState
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    -- Log creation
    FreeGangs.Server.DB.Log(gangName, citizenid, 'gang_created', FreeGangs.LogCategories.SYSTEM, {
        founder = citizenid,
        archetype = archetype,
    })
    
    -- Send Discord webhook
    FreeGangs.Server.SendDiscordWebhook('Gang Created', string.format(
        '**%s** has been established as a %s\nFounder: %s',
        data.label,
        FreeGangs.ArchetypeLabels[archetype].label,
        FreeGangs.Bridge.GetPlayerName(founderSource)
    ), 3066993) -- Green color
    
    -- Notify founder
    FreeGangs.Bridge.Notify(founderSource, string.format(FreeGangs.Config.Messages.GangCreated, data.label), 'success')
    
    return true, gangName
end

-- ============================================================================
-- GANG DELETION
-- ============================================================================

---Delete a gang
---@param gangName string
---@param reason string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Gang.Delete(gangName, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then
        return false, 'Gang not found'
    end
    
    -- Get all members before deletion
    local members = FreeGangs.Server.DB.GetGangMembers(gangName)
    
    -- Remove all members from QBox gang
    for _, member in pairs(members) do
        FreeGangs.Bridge.RemovePlayerFromGang(member.citizenid, gangName)
    end
    
    -- Delete related data (cascading should handle most, but be explicit)
    MySQL.query('DELETE FROM freegangs_members WHERE gang_name = ?', { gangName })
    MySQL.query('DELETE FROM freegangs_ranks WHERE gang_name = ?', { gangName })
    MySQL.query('DELETE FROM freegangs_graffiti WHERE gang_name = ?', { gangName })
    MySQL.query('DELETE FROM freegangs_bribes WHERE gang_name = ?', { gangName })
    MySQL.query('DELETE FROM freegangs_protection WHERE gang_name = ?', { gangName })
    MySQL.query('DELETE FROM freegangs_stashes WHERE gang_name = ?', { gangName })
    
    -- Delete from database
    FreeGangs.Server.DB.DeleteGang(gangName)
    
    -- Remove from cache
    FreeGangs.Server.Cache.RemoveGang(gangName)
    
    -- Clear heat records
    for key, heat in pairs(FreeGangs.Server.Heat) do
        if heat.gang_a == gangName or heat.gang_b == gangName then
            FreeGangs.Server.Heat[key] = nil
        end
    end
    
    -- Clear territory influence
    for zoneName, territory in pairs(FreeGangs.Server.Territories) do
        if territory.influence and territory.influence[gangName] then
            territory.influence[gangName] = nil
            FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
        end
    end
    
    -- Log deletion
    FreeGangs.Server.DB.Log(gangName, nil, 'gang_deleted', FreeGangs.LogCategories.ADMIN, {
        reason = reason,
        memberCount = #members,
    })
    
    -- Send Discord webhook
    FreeGangs.Server.SendDiscordWebhook('Gang Disbanded', string.format(
        '**%s** has been disbanded\nReason: %s\nMembers affected: %d',
        gang.label,
        reason or 'Not specified',
        #members
    ), 15158332) -- Red color
    
    -- Notify affected players
    for _, member in pairs(members) do
        local player = FreeGangs.Bridge.GetPlayerByCitizenId(member.citizenid)
        if player then
            FreeGangs.Bridge.Notify(player.PlayerData.source, string.format(FreeGangs.Config.Messages.GangDeleted, gang.label), 'error')
        end
    end
    
    return true
end

-- ============================================================================
-- GANG UPDATES
-- ============================================================================

---Update gang settings
---@param gangName string
---@param settings table
---@return boolean
function FreeGangs.Server.Gang.UpdateSettings(gangName, settings)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    gang.settings = FreeGangs.Utils.MergeTables(gang.settings or {}, settings)
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    return true
end

---Update gang color
---@param gangName string
---@param color string Hex color code
---@return boolean
function FreeGangs.Server.Gang.UpdateColor(gangName, color)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    if not FreeGangs.Utils.ValidateHexColor(color) then
        return false
    end
    
    gang.color = color
    FreeGangs.Server.DB.UpdateGang(gangName, { color = color })
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    return true
end

---Update gang label
---@param gangName string
---@param label string
---@return boolean
function FreeGangs.Server.Gang.UpdateLabel(gangName, label)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    if #label < 2 or #label > 100 then
        return false
    end
    
    gang.label = label
    FreeGangs.Server.DB.UpdateGang(gangName, { label = label })
    FreeGangs.Server.Cache.SyncGang(gangName)
    
    return true
end

---Update gang logo
---@param gangName string
---@param logo string Logo URL or path
---@return boolean
function FreeGangs.Server.Gang.UpdateLogo(gangName, logo)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false end
    
    gang.logo = logo
    FreeGangs.Server.DB.UpdateGang(gangName, { logo = logo })
    
    return true
end

-- ============================================================================
-- TREASURY MANAGEMENT
-- ============================================================================

---Deposit money into gang treasury
---@param gangName string
---@param source number Player source
---@param amount number
---@param reason string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Gang.DepositTreasury(gangName, source, amount, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    amount = math.floor(amount)
    if amount <= 0 then
        return false, 'Invalid amount'
    end
    
    -- Check player has enough money
    if FreeGangs.Bridge.GetMoney(source, 'cash') < amount then
        return false, 'Insufficient funds'
    end
    
    -- Remove from player
    if not FreeGangs.Bridge.RemoveMoney(source, amount, 'cash', 'Gang treasury deposit') then
        return false, 'Failed to remove money'
    end
    
    -- Add to treasury
    gang.treasury = (gang.treasury or 0) + amount
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'treasury_deposit', FreeGangs.LogCategories.ACTIVITY, {
        amount = amount,
        reason = reason,
        newBalance = gang.treasury,
    })
    
    return true
end

---Withdraw money from gang treasury
---@param gangName string
---@param source number Player source
---@param amount number
---@param reason string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Gang.WithdrawTreasury(gangName, source, amount, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    amount = math.floor(amount)
    if amount <= 0 then
        return false, 'Invalid amount'
    end
    
    -- Check treasury balance
    if (gang.treasury or 0) < amount then
        return false, 'Insufficient treasury funds'
    end
    
    -- Remove from treasury
    gang.treasury = gang.treasury - amount
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Add to player
    FreeGangs.Bridge.AddMoney(source, amount, 'cash', 'Gang treasury withdrawal')
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'treasury_withdrawal', FreeGangs.LogCategories.ACTIVITY, {
        amount = amount,
        reason = reason,
        newBalance = gang.treasury,
    })
    
    return true
end

---Deposit money into war chest
---@param gangName string
---@param source number Player source
---@param amount number
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Gang.DepositWarChest(gangName, source, amount)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return false, 'Gang not found' end
    
    amount = math.floor(amount)
    if amount <= 0 then
        return false, 'Invalid amount'
    end
    
    -- Check player has enough money
    if FreeGangs.Bridge.GetMoney(source, 'cash') < amount then
        return false, 'Insufficient funds'
    end
    
    -- Remove from player
    if not FreeGangs.Bridge.RemoveMoney(source, amount, 'cash', 'War chest deposit') then
        return false, 'Failed to remove money'
    end
    
    -- Add to war chest
    gang.war_chest = (gang.war_chest or 0) + amount
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
    
    -- Log
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    FreeGangs.Server.DB.Log(gangName, citizenid, 'warchest_deposit', FreeGangs.LogCategories.ACTIVITY, {
        amount = amount,
        newBalance = gang.war_chest,
    })
    
    return true
end

-- ============================================================================
-- GANG QUERIES
-- ============================================================================

---Get gang data for client
---@param gangName string
---@return table|nil
function FreeGangs.Server.Gang.GetClientData(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return nil end
    
    local memberCount = FreeGangs.Server.DB.GetMemberCount(gangName)
    local territories = FreeGangs.Server.GetGangTerritories(gangName)
    local territoryCount = FreeGangs.Utils.TableLength(territories)
    
    return {
        name = gang.name,
        label = gang.label,
        archetype = gang.archetype,
        archetypeLabel = FreeGangs.ArchetypeLabels[gang.archetype].label,
        color = gang.color,
        logo = gang.logo,
        treasury = gang.treasury,
        war_chest = gang.war_chest,
        master_rep = gang.master_rep,
        master_level = gang.master_level,
        levelName = FreeGangs.ReputationLevels[gang.master_level].name,
        memberCount = memberCount,
        territoryCount = territoryCount,
        maxTerritories = FreeGangs.GetMaxTerritories(gang.master_level),
        created_at = gang.created_at,
    }
end

---Get all gangs for admin panel
---@return table
function FreeGangs.Server.Gang.GetAllForAdmin()
    local gangs = {}
    
    for gangName, gang in pairs(FreeGangs.Server.Gangs) do
        gangs[#gangs + 1] = FreeGangs.Server.Gang.GetClientData(gangName)
    end
    
    -- Sort by master_rep descending
    table.sort(gangs, function(a, b)
        return a.master_rep > b.master_rep
    end)
    
    return gangs
end

-- ============================================================================
-- GANG RANK MANAGEMENT
-- ============================================================================

---Get all ranks for a gang
---@param gangName string
---@return table
function FreeGangs.Server.Gang.GetRanks(gangName)
    return FreeGangs.Server.DB.GetGangRanks(gangName)
end

---Update a rank name
---@param gangName string
---@param rankLevel number
---@param name string
---@return boolean
function FreeGangs.Server.Gang.UpdateRankName(gangName, rankLevel, name)
    if not FreeGangs.Server.Gangs[gangName] then
        return false
    end
    
    FreeGangs.Server.DB.UpdateRankName(gangName, rankLevel, name)
    
    -- Update QBox gang definition
    FreeGangs.Server.RegisterGangWithQBox(FreeGangs.Server.Gangs[gangName])
    
    return true
end

---Update rank permissions
---@param gangName string
---@param rankLevel number
---@param permissions table
---@return boolean
function FreeGangs.Server.Gang.UpdateRankPermissions(gangName, rankLevel, permissions)
    if not FreeGangs.Server.Gangs[gangName] then
        return false
    end
    
    FreeGangs.Server.DB.UpdateRankPermissions(gangName, rankLevel, permissions)
    return true
end

return FreeGangs.Server.Gang
