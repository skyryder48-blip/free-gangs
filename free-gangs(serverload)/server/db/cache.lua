--[[
    FREE-GANGS: Server-Side Cache System
    
    Write-behind caching layer for high-frequency database operations.
    Reduces database load by batching updates and flushing periodically.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Cache = {}

-- Dirty tracking for write-behind pattern
local dirtyGangs = {}
local dirtyTerritories = {}
local dirtyHeat = {}
local dirtyBribes = {}
local dirtyProtection = {}
local dirtyPrison = {}

-- Last flush timestamp
local lastFlush = 0

-- ============================================================================
-- DIRTY TRACKING
-- ============================================================================

---Mark an entity as dirty (needs database update)
---@param entityType string 'gang' | 'territory' | 'heat' | 'bribe' | 'protection'
---@param key string The entity identifier
function FreeGangs.Server.Cache.MarkDirty(entityType, key)
    if entityType == 'gang' then
        dirtyGangs[key] = true
    elseif entityType == 'territory' then
        dirtyTerritories[key] = true
    elseif entityType == 'heat' then
        dirtyHeat[key] = true
    elseif entityType == 'bribe' then
        dirtyBribes[key] = true
    elseif entityType == 'protection' then
        dirtyProtection[key] = true
    elseif entityType == 'prison_influence' then
        dirtyPrison[key] = true
    end
end

---Check if an entity is dirty
---@param entityType string
---@param key string
---@return boolean
function FreeGangs.Server.Cache.IsDirty(entityType, key)
    if entityType == 'gang' then
        return dirtyGangs[key] == true
    elseif entityType == 'territory' then
        return dirtyTerritories[key] == true
    elseif entityType == 'heat' then
        return dirtyHeat[key] == true
    elseif entityType == 'bribe' then
        return dirtyBribes[key] == true
    elseif entityType == 'protection' then
        return dirtyProtection[key] == true
    elseif entityType == 'prison_influence' then
        return dirtyPrison[key] == true
    end
    return false
end

-- ============================================================================
-- FLUSH OPERATIONS
-- ============================================================================

---Flush all dirty gang data to database
local function FlushGangs()
    if not next(dirtyGangs) then return 0 end
    
    local queries = {}
    local count = 0
    
    for gangName, _ in pairs(dirtyGangs) do
        local gang = FreeGangs.Server.Gangs[gangName]
        if gang then
            queries[#queries + 1] = {
                [[
                    UPDATE freegangs_gangs 
                    SET treasury = ?, war_chest = ?, master_rep = ?, master_level = ?, settings = ?
                    WHERE name = ?
                ]],
                {
                    gang.treasury or 0,
                    gang.war_chest or 0,
                    gang.master_rep or 0,
                    gang.master_level or 1,
                    json.encode(gang.settings or {}),
                    gangName
                }
            }
            count = count + 1
        end
    end
    
    if #queries > 0 then
        MySQL.transaction(queries, function(success)
            if success then
                FreeGangs.Utils.Debug('Flushed ' .. count .. ' gang records')
            else
                FreeGangs.Utils.Log('ERROR: Failed to flush gang cache')
            end
        end)
    end
    
    dirtyGangs = {}
    return count
end

---Flush all dirty territory data to database
local function FlushTerritories()
    if not next(dirtyTerritories) then return 0 end
    
    local queries = {}
    local count = 0
    
    for zoneName, _ in pairs(dirtyTerritories) do
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory then
            queries[#queries + 1] = {
                [[
                    UPDATE freegangs_territories 
                    SET influence = ?, last_flip = ?, cooldown_until = ?
                    WHERE name = ?
                ]],
                {
                    json.encode(territory.influence or {}),
                    territory.lastFlip,
                    territory.cooldownUntil,
                    zoneName
                }
            }
            count = count + 1
        end
    end
    
    if #queries > 0 then
        MySQL.transaction(queries, function(success)
            if success then
                FreeGangs.Utils.Debug('Flushed ' .. count .. ' territory records')
            else
                FreeGangs.Utils.Log('ERROR: Failed to flush territory cache')
            end
        end)
    end
    
    dirtyTerritories = {}
    return count
end

---Flush all dirty heat data to database
local function FlushHeat()
    if not next(dirtyHeat) then return 0 end
    
    local queries = {}
    local count = 0
    
    for key, _ in pairs(dirtyHeat) do
        local heatData = FreeGangs.Server.Heat[key]
        if heatData then
            queries[#queries + 1] = {
                [[
                    UPDATE freegangs_heat 
                    SET heat_level = ?, stage = ?, last_decay = CURRENT_TIMESTAMP
                    WHERE gang_a = ? AND gang_b = ?
                ]],
                {
                    heatData.heat_level,
                    heatData.stage,
                    heatData.gang_a,
                    heatData.gang_b
                }
            }
            count = count + 1
        end
    end
    
    if #queries > 0 then
        MySQL.transaction(queries, function(success)
            if success then
                FreeGangs.Utils.Debug('Flushed ' .. count .. ' heat records')
            else
                FreeGangs.Utils.Log('ERROR: Failed to flush heat cache')
            end
        end)
    end
    
    dirtyHeat = {}
    return count
end

---Flush all dirty bribe data to database
local function FlushBribes()
    if not next(dirtyBribes) then return 0 end
    
    local queries = {}
    local count = 0
    
    for key, _ in pairs(dirtyBribes) do
        -- Key format: gangName_contactType
        local parts = {}
        for part in string.gmatch(key, "[^_]+") do
            parts[#parts + 1] = part
        end
        
        if #parts >= 2 then
            local gangName = parts[1]
            local contactType = parts[2]
            
            local bribeData = FreeGangs.Server.Bribes[gangName] and FreeGangs.Server.Bribes[gangName][contactType]
            if bribeData then
                queries[#queries + 1] = {
                    [[
                        UPDATE freegangs_bribes 
                        SET missed_payments = ?, status = ?, metadata = ?
                        WHERE gang_name = ? AND contact_type = ?
                    ]],
                    {
                        bribeData.missed_payments or 0,
                        bribeData.status,
                        json.encode(bribeData.metadata or {}),
                        gangName,
                        contactType
                    }
                }
                count = count + 1
            end
        end
    end
    
    if #queries > 0 then
        MySQL.transaction(queries, function(success)
            if success then
                FreeGangs.Utils.Debug('Flushed ' .. count .. ' bribe records')
            else
                FreeGangs.Utils.Log('ERROR: Failed to flush bribe cache')
            end
        end)
    end
    
    dirtyBribes = {}
    return count
end

---Flush all dirty prison influence data to database
local function FlushPrison()
    if not next(dirtyPrison) then return 0 end

    local count = 0
    for gangName, _ in pairs(dirtyPrison) do
        local prisonData = FreeGangs.Server.Prison and FreeGangs.Server.Prison.GetControlLevel and FreeGangs.Server.Prison.GetControlLevel(gangName)
        if prisonData then
            local query = [[
                INSERT INTO freegangs_prison_influence (gang_name, influence, last_updated)
                VALUES (?, ?, NOW())
                ON DUPLICATE KEY UPDATE influence = VALUES(influence), last_updated = NOW()
            ]]
            MySQL.update.await(query, { gangName, prisonData })
            count = count + 1
        end
    end

    dirtyPrison = {}
    return count
end

---Main flush function - flushes all dirty data
---@param force boolean|nil Force immediate synchronous flush
function FreeGangs.Server.Cache.Flush(force)
    local currentTime = os.time()
    
    -- Prevent too frequent flushes unless forced
    if not force and (currentTime - lastFlush) < 5 then
        return
    end
    
    lastFlush = currentTime
    
    local totalFlushed = 0
    totalFlushed = totalFlushed + FlushGangs()
    totalFlushed = totalFlushed + FlushTerritories()
    totalFlushed = totalFlushed + FlushHeat()
    totalFlushed = totalFlushed + FlushBribes()
    totalFlushed = totalFlushed + FlushPrison()

    if totalFlushed > 0 then
        FreeGangs.Utils.Debug('Cache flush complete: ' .. totalFlushed .. ' total records')
    end
end

-- ============================================================================
-- CACHE STATISTICS
-- ============================================================================

---Get cache statistics
---@return table
function FreeGangs.Server.Cache.GetStats()
    return {
        dirtyGangs = FreeGangs.Utils.TableLength(dirtyGangs),
        dirtyTerritories = FreeGangs.Utils.TableLength(dirtyTerritories),
        dirtyHeat = FreeGangs.Utils.TableLength(dirtyHeat),
        dirtyBribes = FreeGangs.Utils.TableLength(dirtyBribes),
        lastFlush = lastFlush,
        cachedGangs = FreeGangs.Utils.TableLength(FreeGangs.Server.Gangs),
        cachedTerritories = FreeGangs.Utils.TableLength(FreeGangs.Server.Territories),
        cachedHeat = FreeGangs.Utils.TableLength(FreeGangs.Server.Heat),
    }
end

-- ============================================================================
-- GANG CACHE OPERATIONS
-- ============================================================================

---Get gang from cache (or load from DB)
---@param gangName string
---@return table|nil
function FreeGangs.Server.Cache.GetGang(gangName)
    -- Check memory cache first
    if FreeGangs.Server.Gangs[gangName] then
        return FreeGangs.Server.Gangs[gangName]
    end
    
    -- Load from database
    local gang = FreeGangs.Server.DB.GetGang(gangName)
    if gang then
        FreeGangs.Server.Gangs[gangName] = gang
    end
    
    return gang
end

---Update gang in cache
---@param gangName string
---@param data table Partial data to update
function FreeGangs.Server.Cache.UpdateGang(gangName, data)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then return end
    
    for key, value in pairs(data) do
        gang[key] = value
    end
    
    FreeGangs.Server.Cache.MarkDirty('gang', gangName)
end

---Add gang to cache
---@param gang table
function FreeGangs.Server.Cache.AddGang(gang)
    FreeGangs.Server.Gangs[gang.name] = gang
end

---Remove gang from cache
---@param gangName string
function FreeGangs.Server.Cache.RemoveGang(gangName)
    FreeGangs.Server.Gangs[gangName] = nil
    dirtyGangs[gangName] = nil
end

-- ============================================================================
-- TERRITORY CACHE OPERATIONS
-- ============================================================================

---Get territory from cache
---@param zoneName string
---@return table|nil
function FreeGangs.Server.Cache.GetTerritory(zoneName)
    if FreeGangs.Server.Territories[zoneName] then
        return FreeGangs.Server.Territories[zoneName]
    end
    
    local territory = FreeGangs.Server.DB.GetTerritory(zoneName)
    if territory then
        FreeGangs.Server.Territories[zoneName] = territory
    end
    
    return territory
end

---Update territory influence
---@param zoneName string
---@param gangName string
---@param influence number
function FreeGangs.Server.Cache.UpdateTerritoryInfluence(zoneName, gangName, influence)
    local territory = FreeGangs.Server.Territories[zoneName]
    if not territory then return end
    
    territory.influence = territory.influence or {}
    territory.influence[gangName] = influence
    
    -- Clean up zero values
    if influence <= 0 then
        territory.influence[gangName] = nil
    end
    
    FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
end

---Set territory cooldown
---@param zoneName string
---@param cooldownUntil number|nil timestamp
function FreeGangs.Server.Cache.SetTerritoryCooldown(zoneName, cooldownUntil)
    local territory = FreeGangs.Server.Territories[zoneName]
    if not territory then return end
    
    territory.cooldownUntil = cooldownUntil
    territory.lastFlip = os.time()
    
    FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
end

-- ============================================================================
-- HEAT CACHE OPERATIONS
-- ============================================================================

---Get heat between gangs
---@param gangA string
---@param gangB string
---@return table|nil
function FreeGangs.Server.Cache.GetHeat(gangA, gangB)
    gangA, gangB = FreeGangs.OrderGangPair(gangA, gangB)
    local key = gangA .. '_' .. gangB
    
    if FreeGangs.Server.Heat[key] then
        return FreeGangs.Server.Heat[key]
    end
    
    local heat = FreeGangs.Server.DB.GetHeat(gangA, gangB)
    if heat then
        FreeGangs.Server.Heat[key] = heat
    end
    
    return heat
end

---Update heat between gangs
---@param gangA string
---@param gangB string
---@param heatLevel number
---@param stage string|nil
function FreeGangs.Server.Cache.UpdateHeat(gangA, gangB, heatLevel, stage)
    gangA, gangB = FreeGangs.OrderGangPair(gangA, gangB)
    local key = gangA .. '_' .. gangB
    
    local heatData = FreeGangs.Server.Heat[key]
    if not heatData then
        -- Create new heat record
        heatData = {
            gang_a = gangA,
            gang_b = gangB,
            heat_level = heatLevel,
            stage = stage or FreeGangs.GetHeatStage(heatLevel),
            last_incident = os.time(),
        }
        FreeGangs.Server.Heat[key] = heatData
        
        -- Insert into database
        FreeGangs.Server.DB.UpsertHeat(gangA, gangB, heatLevel, heatData.stage)
    else
        heatData.heat_level = heatLevel
        heatData.stage = stage or FreeGangs.GetHeatStage(heatLevel)
        heatData.last_incident = os.time()
        
        FreeGangs.Server.Cache.MarkDirty('heat', key)
    end
    
    return heatData
end

-- ============================================================================
-- BRIBE CACHE OPERATIONS
-- ============================================================================

---Get gang's bribes
---@param gangName string
---@return table
function FreeGangs.Server.Cache.GetGangBribes(gangName)
    return FreeGangs.Server.Bribes[gangName] or {}
end

---Get specific bribe
---@param gangName string
---@param contactType string
---@return table|nil
function FreeGangs.Server.Cache.GetBribe(gangName, contactType)
    if FreeGangs.Server.Bribes[gangName] then
        return FreeGangs.Server.Bribes[gangName][contactType]
    end
    return nil
end

---Add bribe to cache
---@param gangName string
---@param bribe table
function FreeGangs.Server.Cache.AddBribe(gangName, bribe)
    if not FreeGangs.Server.Bribes[gangName] then
        FreeGangs.Server.Bribes[gangName] = {}
    end
    FreeGangs.Server.Bribes[gangName][bribe.contact_type] = bribe
end

---Update bribe in cache
---@param gangName string
---@param contactType string
---@param data table Partial data
function FreeGangs.Server.Cache.UpdateBribe(gangName, contactType, data)
    if not FreeGangs.Server.Bribes[gangName] or not FreeGangs.Server.Bribes[gangName][contactType] then
        return
    end
    
    local bribe = FreeGangs.Server.Bribes[gangName][contactType]
    for key, value in pairs(data) do
        bribe[key] = value
    end
    
    FreeGangs.Server.Cache.MarkDirty('bribe', gangName .. '_' .. contactType)
end

---Remove bribe from cache
---@param gangName string
---@param contactType string
function FreeGangs.Server.Cache.RemoveBribe(gangName, contactType)
    if FreeGangs.Server.Bribes[gangName] then
        FreeGangs.Server.Bribes[gangName][contactType] = nil
    end
end

-- ============================================================================
-- GLOBAL STATE SYNC
-- ============================================================================

---Sync territory data to all clients via GlobalState
---@param zoneName string
function FreeGangs.Server.Cache.SyncTerritory(zoneName)
    local territory = FreeGangs.Server.Territories[zoneName]
    if territory then
        GlobalState['territory:' .. zoneName] = {
            name = territory.name,
            label = territory.label,
            influence = territory.influence,
            cooldown_until = territory.cooldown_until,
        }
    end
end

---Sync gang data to GlobalState
---@param gangName string
function FreeGangs.Server.Cache.SyncGang(gangName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if gang then
        GlobalState['gang:' .. gangName] = {
            name = gang.name,
            label = gang.label,
            color = gang.color,
            archetype = gang.archetype,
            master_level = gang.master_level,
        }
    end
end

---Sync all data to GlobalState (called on startup)
function FreeGangs.Server.Cache.SyncAll()
    -- Sync territories
    for zoneName, _ in pairs(FreeGangs.Server.Territories) do
        FreeGangs.Server.Cache.SyncTerritory(zoneName)
    end
    
    -- Sync gangs
    for gangName, _ in pairs(FreeGangs.Server.Gangs) do
        FreeGangs.Server.Cache.SyncGang(gangName)
    end
    
    FreeGangs.Utils.Log('GlobalState synchronized')
end

return FreeGangs.Server.Cache
