--[[
    FREE-GANGS: Database Queries
    
    Centralized SQL queries and database operations.
    All database interactions go through these functions.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.DB = {}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize database (create tables if needed)
function FreeGangs.Server.DB.Initialize()
    -- Tables are created via schema.sql
    -- This function handles any runtime migrations or data validation
    
    FreeGangs.Utils.Log('Database initialized')
end

-- ============================================================================
-- GANG QUERIES
-- ============================================================================

---Get all gangs from database
---@return table
function FreeGangs.Server.DB.GetAllGangs()
    local result = MySQL.query.await([[
        SELECT 
            id, name, label, archetype, color, logo,
            treasury, war_chest, master_rep, master_level,
            trap_spot, settings, created_at
        FROM freegangs_gangs
    ]])
    
    local gangs = {}
    for _, row in pairs(result or {}) do
        row.trap_spot = row.trap_spot and json.decode(row.trap_spot) or nil
        row.settings = row.settings and json.decode(row.settings) or {}
        gangs[#gangs + 1] = row
    end
    
    return gangs
end

---Get a specific gang
---@param gangName string
---@return table|nil
function FreeGangs.Server.DB.GetGang(gangName)
    local result = MySQL.single.await([[
        SELECT 
            id, name, label, archetype, color, logo,
            treasury, war_chest, master_rep, master_level,
            trap_spot, settings, created_at
        FROM freegangs_gangs
        WHERE name = ?
    ]], { gangName })
    
    if result then
        result.trap_spot = result.trap_spot and json.decode(result.trap_spot) or nil
        result.settings = result.settings and json.decode(result.settings) or {}
    end
    
    return result
end

---Create a new gang
---@param data table
---@return number|nil insertId
function FreeGangs.Server.DB.CreateGang(data)
    local result = MySQL.insert.await([[
        INSERT INTO freegangs_gangs 
        (name, label, archetype, color, logo, trap_spot, settings)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.label,
        data.archetype or 'street',
        data.color or '#FFFFFF',
        data.logo,
        data.trap_spot and json.encode(data.trap_spot) or nil,
        json.encode(data.settings or {}),
    })
    
    return result
end

---Update gang data
---@param gangName string
---@param data table
function FreeGangs.Server.DB.UpdateGang(gangName, data)
    local sets = {}
    local values = {}
    
    if data.label then
        sets[#sets + 1] = 'label = ?'
        values[#values + 1] = data.label
    end
    
    if data.color then
        sets[#sets + 1] = 'color = ?'
        values[#values + 1] = data.color
    end
    
    if data.logo then
        sets[#sets + 1] = 'logo = ?'
        values[#values + 1] = data.logo
    end
    
    if data.treasury ~= nil then
        sets[#sets + 1] = 'treasury = ?'
        values[#values + 1] = data.treasury
    end
    
    if data.war_chest ~= nil then
        sets[#sets + 1] = 'war_chest = ?'
        values[#values + 1] = data.war_chest
    end
    
    if data.master_rep ~= nil then
        sets[#sets + 1] = 'master_rep = ?'
        values[#values + 1] = data.master_rep
    end
    
    if data.master_level ~= nil then
        sets[#sets + 1] = 'master_level = ?'
        values[#values + 1] = data.master_level
    end
    
    if data.settings then
        sets[#sets + 1] = 'settings = ?'
        values[#values + 1] = json.encode(data.settings)
    end
    
    if #sets == 0 then return end
    
    values[#values + 1] = gangName
    
    MySQL.update.await(
        'UPDATE freegangs_gangs SET ' .. table.concat(sets, ', ') .. ' WHERE name = ?',
        values
    )
end

---Delete a gang
---@param gangName string
function FreeGangs.Server.DB.DeleteGang(gangName)
    MySQL.query.await('DELETE FROM freegangs_gangs WHERE name = ?', { gangName })
end

-- ============================================================================
-- MEMBER QUERIES
-- ============================================================================

---Get all members of a gang
---@param gangName string
---@return table
function FreeGangs.Server.DB.GetGangMembers(gangName)
    local result = MySQL.query.await([[
        SELECT 
            id, citizenid, gang_name, rank, rank_name,
            permissions, personal_rep, joined_at, last_active
        FROM freegangs_members
        WHERE gang_name = ?
        ORDER BY rank DESC, joined_at ASC
    ]], { gangName })
    
    local members = {}
    for _, row in pairs(result or {}) do
        row.permissions = row.permissions and json.decode(row.permissions) or {}
        members[#members + 1] = row
    end
    
    return members
end

---Get player's membership
---@param citizenid string
---@return table|nil
function FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    local result = MySQL.single.await([[
        SELECT 
            id, citizenid, gang_name, rank, rank_name,
            permissions, personal_rep, joined_at, last_active
        FROM freegangs_members
        WHERE citizenid = ?
    ]], { citizenid })
    
    if result then
        result.permissions = result.permissions and json.decode(result.permissions) or {}
    end
    
    return result
end

---Add a member to a gang
---@param citizenid string
---@param gangName string
---@param rank number
---@param rankName string|nil
---@return number|nil insertId
function FreeGangs.Server.DB.AddMember(citizenid, gangName, rank, rankName)
    return MySQL.insert.await([[
        INSERT INTO freegangs_members (citizenid, gang_name, rank, rank_name)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE 
            gang_name = VALUES(gang_name),
            rank = VALUES(rank),
            rank_name = VALUES(rank_name),
            last_active = CURRENT_TIMESTAMP
    ]], { citizenid, gangName, rank or 0, rankName })
end

---Update member rank
---@param citizenid string
---@param gangName string
---@param rank number
---@param rankName string|nil
function FreeGangs.Server.DB.UpdateMemberRank(citizenid, gangName, rank, rankName)
    MySQL.update.await([[
        UPDATE freegangs_members 
        SET rank = ?, rank_name = ?, last_active = CURRENT_TIMESTAMP
        WHERE citizenid = ? AND gang_name = ?
    ]], { rank, rankName, citizenid, gangName })
end

---Update member permissions
---@param citizenid string
---@param gangName string
---@param permissions table
function FreeGangs.Server.DB.UpdateMemberPermissions(citizenid, gangName, permissions)
    MySQL.update.await([[
        UPDATE freegangs_members 
        SET permissions = ?, last_active = CURRENT_TIMESTAMP
        WHERE citizenid = ? AND gang_name = ?
    ]], { json.encode(permissions), citizenid, gangName })
end

---Update member personal rep
---@param citizenid string
---@param gangName string
---@param personalRep number
function FreeGangs.Server.DB.UpdateMemberRep(citizenid, gangName, personalRep)
    MySQL.update.await([[
        UPDATE freegangs_members 
        SET personal_rep = ?, last_active = CURRENT_TIMESTAMP
        WHERE citizenid = ? AND gang_name = ?
    ]], { personalRep, citizenid, gangName })
end

---Remove member from gang
---@param citizenid string
---@param gangName string
function FreeGangs.Server.DB.RemoveMember(citizenid, gangName)
    MySQL.query.await([[
        DELETE FROM freegangs_members 
        WHERE citizenid = ? AND gang_name = ?
    ]], { citizenid, gangName })
end

---Get member count for a gang
---@param gangName string
---@return number
function FreeGangs.Server.DB.GetMemberCount(gangName)
    local result = MySQL.scalar.await([[
        SELECT COUNT(*) FROM freegangs_members WHERE gang_name = ?
    ]], { gangName })
    
    return result or 0
end

-- ============================================================================
-- RANK QUERIES
-- ============================================================================

---Get all ranks for a gang
---@param gangName string
---@return table
function FreeGangs.Server.DB.GetGangRanks(gangName)
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, rank_level, name, is_boss, is_officer, permissions
        FROM freegangs_ranks
        WHERE gang_name = ?
        ORDER BY rank_level ASC
    ]], { gangName })
    
    local ranks = {}
    for _, row in pairs(result or {}) do
        row.permissions = row.permissions and json.decode(row.permissions) or {}
        ranks[#ranks + 1] = row
    end
    
    return ranks
end

---Create default ranks for a gang
---@param gangName string
---@param archetype string
function FreeGangs.Server.DB.CreateDefaultRanks(gangName, archetype)
    local defaultRanks = FreeGangs.DefaultRanks[archetype] or FreeGangs.DefaultRanks[FreeGangs.Archetypes.STREET]
    
    local queries = {}
    for level, rankData in pairs(defaultRanks) do
        local permissions = FreeGangs.Utils.GetDefaultPermissions(level)
        queries[#queries + 1] = {
            [[
                INSERT INTO freegangs_ranks (gang_name, rank_level, name, is_boss, is_officer, permissions)
                VALUES (?, ?, ?, ?, ?, ?)
            ]],
            { gangName, level, rankData.name, rankData.isBoss and 1 or 0, rankData.isOfficer and 1 or 0, json.encode(permissions) }
        }
    end
    
    MySQL.transaction.await(queries)
end

---Update rank name
---@param gangName string
---@param rankLevel number
---@param name string
function FreeGangs.Server.DB.UpdateRankName(gangName, rankLevel, name)
    MySQL.update.await([[
        UPDATE freegangs_ranks SET name = ? WHERE gang_name = ? AND rank_level = ?
    ]], { name, gangName, rankLevel })
end

---Update rank permissions
---@param gangName string
---@param rankLevel number
---@param permissions table
function FreeGangs.Server.DB.UpdateRankPermissions(gangName, rankLevel, permissions)
    MySQL.update.await([[
        UPDATE freegangs_ranks SET permissions = ? WHERE gang_name = ? AND rank_level = ?
    ]], { json.encode(permissions), gangName, rankLevel })
end

-- ============================================================================
-- TERRITORY QUERIES
-- ============================================================================

---Get all territories
---@return table
function FreeGangs.Server.DB.GetAllTerritories()
    local result = MySQL.query.await([[
        SELECT 
            id, name, label, zone_type, coords, radius, size,
            influence, protection_value, last_flip, cooldown_until, settings
        FROM freegangs_territories
    ]])
    
    local territories = {}
    for _, row in pairs(result or {}) do
        row.coords = row.coords and json.decode(row.coords) or {}
        row.size = row.size and json.decode(row.size) or nil
        row.influence = row.influence and json.decode(row.influence) or {}
        row.settings = row.settings and json.decode(row.settings) or {}
        territories[#territories + 1] = row
    end
    
    return territories
end

---Get a specific territory
---@param zoneName string
---@return table|nil
function FreeGangs.Server.DB.GetTerritory(zoneName)
    local result = MySQL.single.await([[
        SELECT 
            id, name, label, zone_type, coords, radius, size,
            influence, protection_value, last_flip, cooldown_until, settings
        FROM freegangs_territories
        WHERE name = ?
    ]], { zoneName })
    
    if result then
        result.coords = result.coords and json.decode(result.coords) or {}
        result.size = result.size and json.decode(result.size) or nil
        result.influence = result.influence and json.decode(result.influence) or {}
        result.settings = result.settings and json.decode(result.settings) or {}
    end
    
    return result
end

---Update territory influence
---@param zoneName string
---@param influence table
function FreeGangs.Server.DB.UpdateTerritoryInfluence(zoneName, influence)
    MySQL.update.await([[
        UPDATE freegangs_territories SET influence = ? WHERE name = ?
    ]], { json.encode(influence), zoneName })
end

---Set territory cooldown
---@param zoneName string
---@param cooldownUntil number timestamp
function FreeGangs.Server.DB.SetTerritoryCooldown(zoneName, cooldownUntil)
    MySQL.update.await([[
        UPDATE freegangs_territories SET cooldown_until = FROM_UNIXTIME(?), last_flip = CURRENT_TIMESTAMP WHERE name = ?
    ]], { cooldownUntil, zoneName })
end

---Create a territory
---@param data table
---@return number|nil
function FreeGangs.Server.DB.CreateTerritory(data)
    return MySQL.insert.await([[
        INSERT INTO freegangs_territories (name, label, zone_type, coords, radius, size, protection_value, settings)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.label,
        data.zone_type or 'residential',
        json.encode(data.coords),
        data.radius,
        data.size and json.encode(data.size) or nil,
        data.protection_value or 0,
        json.encode(data.settings or {}),
    })
end

-- ============================================================================
-- GRAFFITI QUERIES (DUI rendering system)
-- Primary graffiti operations use the in-memory cache in server/modules/graffiti.lua.
-- These DB functions are available for direct queries if needed.
-- ============================================================================

---Create graffiti (with DUI rendering columns)
---@param data table
---@return number|nil
function FreeGangs.Server.DB.CreateGraffiti(data)
    return MySQL.insert.await([[
        INSERT INTO freegangs_graffiti
            (gang_name, zone_name, coords, rotation, image_url, normal_x, normal_y, normal_z, scale, width, height, created_by, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.gang_name,
        data.zone_name,
        json.encode(data.coords),
        json.encode(data.rotation),
        data.image_url or '',
        data.normal_x or 0.0,
        data.normal_y or 0.0,
        data.normal_z or 0.0,
        data.scale or 1.0,
        data.width or 1.0,
        data.height or 1.0,
        data.created_by,
        data.expires_at,
    })
end

---Delete graffiti
---@param graffitiId number
function FreeGangs.Server.DB.DeleteGraffiti(graffitiId)
    MySQL.query.await('DELETE FROM freegangs_graffiti WHERE id = ?', { graffitiId })
end

-- ============================================================================
-- HEAT QUERIES
-- ============================================================================

---Get all heat data
---@return table
function FreeGangs.Server.DB.GetAllHeat()
    local result = MySQL.query.await([[
        SELECT id, gang_a, gang_b, heat_level, stage,
               UNIX_TIMESTAMP(last_incident) as last_incident,
               UNIX_TIMESTAMP(last_decay) as last_decay
        FROM freegangs_heat
    ]])

    return result or {}
end

---Get heat between two gangs
---@param gangA string
---@param gangB string
---@return table|nil
function FreeGangs.Server.DB.GetHeat(gangA, gangB)
    -- Ensure consistent ordering
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)

    return MySQL.single.await([[
        SELECT id, gang_a, gang_b, heat_level, stage,
               UNIX_TIMESTAMP(last_incident) as last_incident,
               UNIX_TIMESTAMP(last_decay) as last_decay
        FROM freegangs_heat
        WHERE gang_a = ? AND gang_b = ?
    ]], { gangA, gangB })
end

---Create or update heat
---@param gangA string
---@param gangB string
---@param heatLevel number
---@param stage string
function FreeGangs.Server.DB.UpsertHeat(gangA, gangB, heatLevel, stage)
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    
    MySQL.query.await([[
        INSERT INTO freegangs_heat (gang_a, gang_b, heat_level, stage, last_incident)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE 
            heat_level = VALUES(heat_level),
            stage = VALUES(stage),
            last_incident = VALUES(last_incident)
    ]], { gangA, gangB, heatLevel, stage })
end

---Update heat level
---@param gangA string
---@param gangB string
---@param heatLevel number
---@param stage string
function FreeGangs.Server.DB.UpdateHeat(gangA, gangB, heatLevel, stage)
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    
    MySQL.update.await([[
        UPDATE freegangs_heat 
        SET heat_level = ?, stage = ?, last_decay = CURRENT_TIMESTAMP
        WHERE gang_a = ? AND gang_b = ?
    ]], { heatLevel, stage, gangA, gangB })
end

-- ============================================================================
-- WAR QUERIES
-- ============================================================================

---Get active wars
---@return table
function FreeGangs.Server.DB.GetActiveWars()
    local result = MySQL.query.await([[
        SELECT 
            id, attacker, defender, attacker_collateral, defender_collateral,
            status, attacker_kills, defender_kills, terms, started_at, ended_at, winner
        FROM freegangs_wars
        WHERE status IN ('pending', 'active')
    ]])
    
    local wars = {}
    for _, row in pairs(result or {}) do
        row.terms = row.terms and json.decode(row.terms) or {}
        wars[#wars + 1] = row
    end
    
    return wars
end

---Get wars involving a gang
---@param gangName string
---@return table
function FreeGangs.Server.DB.GetGangWars(gangName)
    local result = MySQL.query.await([[
        SELECT 
            id, attacker, defender, attacker_collateral, defender_collateral,
            status, attacker_kills, defender_kills, terms, started_at, ended_at, winner
        FROM freegangs_wars
        WHERE attacker = ? OR defender = ?
        ORDER BY created_at DESC
        LIMIT 20
    ]], { gangName, gangName })
    
    local wars = {}
    for _, row in pairs(result or {}) do
        row.terms = row.terms and json.decode(row.terms) or {}
        wars[#wars + 1] = row
    end
    
    return wars
end

---Create a war declaration
---@param data table
---@return number|nil
function FreeGangs.Server.DB.CreateWar(data)
    return MySQL.insert.await([[
        INSERT INTO freegangs_wars (attacker, defender, attacker_collateral, terms)
        VALUES (?, ?, ?, ?)
    ]], {
        data.attacker,
        data.defender,
        data.attacker_collateral,
        json.encode(data.terms or {}),
    })
end

---Update war status
---@param warId number
---@param status string
---@param winner string|nil
function FreeGangs.Server.DB.UpdateWarStatus(warId, status, winner)
    if FreeGangs.WarStatusInfo[status] and FreeGangs.WarStatusInfo[status].isConcluded then
        MySQL.update.await([[
            UPDATE freegangs_wars 
            SET status = ?, winner = ?, ended_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ]], { status, winner, warId })
    else
        MySQL.update.await([[
            UPDATE freegangs_wars SET status = ? WHERE id = ?
        ]], { status, warId })
    end
end

---Accept war (set defender collateral and activate)
---@param warId number
---@param defenderCollateral number
function FreeGangs.Server.DB.AcceptWar(warId, defenderCollateral)
    MySQL.update.await([[
        UPDATE freegangs_wars 
        SET defender_collateral = ?, status = 'active', started_at = CURRENT_TIMESTAMP
        WHERE id = ?
    ]], { defenderCollateral, warId })
end

---Increment kill count
---@param warId number
---@param isAttacker boolean
function FreeGangs.Server.DB.IncrementWarKills(warId, isAttacker)
    local column = isAttacker and 'attacker_kills' or 'defender_kills'
    MySQL.update.await(
        'UPDATE freegangs_wars SET ' .. column .. ' = ' .. column .. ' + 1 WHERE id = ?',
        { warId }
    )
end

---Check war cooldown
---@param gangA string
---@param gangB string
---@return boolean hasCooldown
---@return number|nil cooldownUntil
function FreeGangs.Server.DB.CheckWarCooldown(gangA, gangB)
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    
    local result = MySQL.single.await([[
        SELECT cooldown_until FROM freegangs_war_cooldowns
        WHERE gang_a = ? AND gang_b = ? AND cooldown_until > CURRENT_TIMESTAMP
    ]], { gangA, gangB })
    
    if result then
        return true, result.cooldown_until
    end
    return false, nil
end

---Set war cooldown
---@param gangA string
---@param gangB string
---@param cooldownUntil number timestamp
---@param reason string|nil
function FreeGangs.Server.DB.SetWarCooldown(gangA, gangB, cooldownUntil, reason)
    gangA, gangB = FreeGangs.Utils.GetOrderedGangPair(gangA, gangB)
    
    MySQL.query.await([[
        INSERT INTO freegangs_war_cooldowns (gang_a, gang_b, cooldown_until, reason)
        VALUES (?, ?, FROM_UNIXTIME(?), ?)
        ON DUPLICATE KEY UPDATE cooldown_until = VALUES(cooldown_until), reason = VALUES(reason)
    ]], { gangA, gangB, cooldownUntil, reason })
end

-- ============================================================================
-- BRIBE QUERIES
-- ============================================================================

---Get all active bribes
---@return table
function FreeGangs.Server.DB.GetAllActiveBribes()
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, contact_type, contact_level,
            established_at, last_payment, next_payment, missed_payments, status, metadata
        FROM freegangs_bribes
        WHERE status = 'active'
    ]])
    
    local bribes = {}
    for _, row in pairs(result or {}) do
        row.metadata = row.metadata and json.decode(row.metadata) or {}
        bribes[#bribes + 1] = row
    end
    
    return bribes
end

---Get gang's bribes
---@param gangName string
---@return table
function FreeGangs.Server.DB.GetGangBribes(gangName)
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, contact_type, contact_level,
            established_at, last_payment, next_payment, missed_payments, status, metadata
        FROM freegangs_bribes
        WHERE gang_name = ?
    ]], { gangName })
    
    local bribes = {}
    for _, row in pairs(result or {}) do
        row.metadata = row.metadata and json.decode(row.metadata) or {}
        bribes[#bribes + 1] = row
    end
    
    return bribes
end

---Create a bribe contact
---@param data table
---@return number|nil
function FreeGangs.Server.DB.CreateBribe(data)
    return MySQL.insert.await([[
        INSERT INTO freegangs_bribes (gang_name, contact_type, contact_level, next_payment, metadata)
        VALUES (?, ?, ?, FROM_UNIXTIME(?), ?)
    ]], {
        data.gang_name,
        data.contact_type,
        data.contact_level or 1,
        data.next_payment,
        json.encode(data.metadata or {}),
    })
end

---Update bribe payment
---@param gangName string
---@param contactType string
---@param nextPayment number timestamp
function FreeGangs.Server.DB.UpdateBribePayment(gangName, contactType, nextPayment)
    MySQL.update.await([[
        UPDATE freegangs_bribes 
        SET last_payment = CURRENT_TIMESTAMP, next_payment = FROM_UNIXTIME(?), missed_payments = 0
        WHERE gang_name = ? AND contact_type = ?
    ]], { nextPayment, gangName, contactType })
end

---Increment missed payments
---@param gangName string
---@param contactType string
---@param newStatus string|nil
function FreeGangs.Server.DB.IncrementMissedPayments(gangName, contactType, newStatus)
    if newStatus then
        MySQL.update.await([[
            UPDATE freegangs_bribes 
            SET missed_payments = missed_payments + 1, status = ?
            WHERE gang_name = ? AND contact_type = ?
        ]], { newStatus, gangName, contactType })
    else
        MySQL.update.await([[
            UPDATE freegangs_bribes 
            SET missed_payments = missed_payments + 1
            WHERE gang_name = ? AND contact_type = ?
        ]], { gangName, contactType })
    end
end

---Terminate bribe contact
---@param gangName string
---@param contactType string
function FreeGangs.Server.DB.TerminateBribe(gangName, contactType)
    MySQL.update.await([[
        UPDATE freegangs_bribes SET status = 'terminated' WHERE gang_name = ? AND contact_type = ?
    ]], { gangName, contactType })
end

-- ============================================================================
-- PROTECTION QUERIES
-- ============================================================================

---Get gang's protection rackets
---@param gangName string
---@return table
function FreeGangs.Server.DB.GetGangProtection(gangName)
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, business_id, business_label, zone_name, coords,
            payout_base, established_by, last_collection, status
        FROM freegangs_protection
        WHERE gang_name = ? AND status = 'active'
    ]], { gangName })
    
    local protection = {}
    for _, row in pairs(result or {}) do
        row.coords = row.coords and json.decode(row.coords) or {}
        protection[#protection + 1] = row
    end
    
    return protection
end

---Get protection in zone
---@param zoneName string
---@return table
function FreeGangs.Server.DB.GetZoneProtection(zoneName)
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, business_id, business_label, zone_name, coords,
            payout_base, established_by, last_collection, status
        FROM freegangs_protection
        WHERE zone_name = ?
    ]], { zoneName })
    
    local protection = {}
    for _, row in pairs(result or {}) do
        row.coords = row.coords and json.decode(row.coords) or {}
        protection[#protection + 1] = row
    end
    
    return protection
end

---Register protection
---@param data table
---@return number|nil
function FreeGangs.Server.DB.RegisterProtection(data)
    return MySQL.insert.await([[
        INSERT INTO freegangs_protection (gang_name, business_id, business_label, zone_name, coords, payout_base, established_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE gang_name = VALUES(gang_name), status = 'active'
    ]], {
        data.gang_name,
        data.business_id,
        data.business_label,
        data.zone_name,
        json.encode(data.coords),
        data.payout_base,
        data.established_by,
    })
end

---Update protection collection
---@param businessId string
function FreeGangs.Server.DB.UpdateProtectionCollection(businessId)
    MySQL.update.await([[
        UPDATE freegangs_protection SET last_collection = CURRENT_TIMESTAMP WHERE business_id = ?
    ]], { businessId })
end

-- ============================================================================
-- LOGGING
-- ============================================================================

---Log an action
---@param gangName string|nil
---@param citizenid string|nil
---@param action string
---@param category string
---@param details table|nil
function FreeGangs.Server.DB.Log(gangName, citizenid, action, category, details)
    MySQL.insert([[
        INSERT INTO freegangs_logs (gang_name, citizenid, action, category, details)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        gangName,
        citizenid,
        action,
        category,
        json.encode(details or {}),
    })
end

---Get logs for a gang
---@param gangName string
---@param limit number|nil
---@return table
function FreeGangs.Server.DB.GetGangLogs(gangName, limit)
    limit = limit or 100
    
    local result = MySQL.query.await([[
        SELECT id, gang_name, citizenid, action, category, details, created_at
        FROM freegangs_logs
        WHERE gang_name = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { gangName, limit })
    
    local logs = {}
    for _, row in pairs(result or {}) do
        row.details = row.details and json.decode(row.details) or {}
        logs[#logs + 1] = row
    end
    
    return logs
end

---Cleanup old logs
---@param daysOld number
function FreeGangs.Server.DB.CleanupLogs(daysOld)
    MySQL.query([[
        DELETE FROM freegangs_logs WHERE created_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)
    ]], { daysOld })
end

return FreeGangs.Server.DB
