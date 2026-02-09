--[[
    FREE-GANGS: Server Graffiti Module
    
    Handles graffiti/tagging system on the server:
    - Spray validation and persistence
    - Tag removal mechanics
    - Zone loyalty effects
    - Cycle limits (max sprays per time period)
    
    Tags persist to database and sync to all clients.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Graffiti = {}

-- ============================================================================
-- LOCAL CACHES
-- ============================================================================

-- Track spray counts per player per cycle
local playerSprayCounts = {}

-- Cache for loaded graffiti (id -> data)
local graffitiCache = {}

-- Cycle duration (6 hours in seconds)
local CYCLE_DURATION = 6 * 60 * 60

-- Maximum sprays per cycle
local MAX_SPRAYS_PER_CYCLE = 6

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Load all graffiti from database into cache
function FreeGangs.Server.Graffiti.LoadAll()
    local result = MySQL.query.await([[
        SELECT 
            id, gang_name, zone_name, coords, rotation, image, created_by, created_at, expires_at
        FROM freegangs_graffiti
        WHERE expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP
    ]])
    
    graffitiCache = {}
    for _, row in pairs(result or {}) do
        row.coords = row.coords and json.decode(row.coords) or {}
        row.rotation = row.rotation and json.decode(row.rotation) or { x = 0, y = 0, z = 0 }
        graffitiCache[row.id] = row
    end
    
    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(graffitiCache) .. ' graffiti tags')
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get current cycle timestamp (start of current 6-hour period)
---@return number timestamp
local function GetCurrentCycleStart()
    local now = FreeGangs.Utils.GetTimestamp()
    return now - (now % CYCLE_DURATION)
end

---Get player's spray count for current cycle
---@param citizenid string
---@return number count
local function GetPlayerSprayCount(citizenid)
    local cycleStart = GetCurrentCycleStart()
    
    local data = playerSprayCounts[citizenid]
    if not data or data.cycleStart ~= cycleStart then
        -- Query database for sprays in current cycle
        local count = MySQL.scalar.await([[
            SELECT COUNT(*) FROM freegangs_graffiti
            WHERE created_by = ? AND created_at >= FROM_UNIXTIME(?)
        ]], { citizenid, cycleStart }) or 0
        
        playerSprayCounts[citizenid] = {
            cycleStart = cycleStart,
            count = count,
        }
    end
    
    return playerSprayCounts[citizenid].count
end

---Increment player's spray count
---@param citizenid string
local function IncrementPlayerSprayCount(citizenid)
    local cycleStart = GetCurrentCycleStart()
    
    if not playerSprayCounts[citizenid] or playerSprayCounts[citizenid].cycleStart ~= cycleStart then
        playerSprayCounts[citizenid] = {
            cycleStart = cycleStart,
            count = 0,
        }
    end
    
    playerSprayCounts[citizenid].count = playerSprayCounts[citizenid].count + 1
end

---Check if coords are too close to existing tag
---@param coords table {x, y, z}
---@param minDistance number
---@return boolean tooClose
---@return table|nil nearbyTag
local function IsTooCloseToExistingTag(coords, minDistance)
    minDistance = minDistance or 5.0
    
    for id, tag in pairs(graffitiCache) do
        if tag.coords and tag.coords.x then
            local distance = math.sqrt(
                (coords.x - tag.coords.x)^2 + 
                (coords.y - tag.coords.y)^2 + 
                (coords.z - tag.coords.z)^2
            )
            if distance < minDistance then
                return true, tag
            end
        end
    end
    
    return false, nil
end

---Get zone name from coordinates
---@param coords table {x, y, z}
---@return string|nil zoneName
local function GetZoneFromCoords(coords)
    for zoneName, territory in pairs(FreeGangs.Server.Territories) do
        if territory.coords then
            local zoneCoords = territory.coords
            local distance = math.sqrt(
                (coords.x - zoneCoords.x)^2 + 
                (coords.y - zoneCoords.y)^2
            )
            
            if territory.radius and distance <= territory.radius then
                return zoneName
            elseif territory.size then
                -- Box zone check
                local halfX = (territory.size.x or 100) / 2
                local halfY = (territory.size.y or 100) / 2
                
                if math.abs(coords.x - zoneCoords.x) <= halfX and 
                   math.abs(coords.y - zoneCoords.y) <= halfY then
                    return zoneName
                end
            end
        end
    end
    
    return nil
end

---Count tags in a zone for a gang
---@param zoneName string
---@param gangName string
---@return number count
local function GetZoneTagCount(zoneName, gangName)
    local count = 0
    
    for _, tag in pairs(graffitiCache) do
        if tag.zone_name == zoneName and tag.gang_name == gangName then
            count = count + 1
        end
    end
    
    return count
end

---Get all tags in a zone
---@param zoneName string
---@return table tags
local function GetZoneTags(zoneName)
    local tags = {}
    
    for id, tag in pairs(graffitiCache) do
        if tag.zone_name == zoneName then
            tags[#tags + 1] = tag
        end
    end
    
    return tags
end

-- ============================================================================
-- SPRAY GRAFFITI
-- ============================================================================

---Spray a new graffiti tag
---@param source number Player source
---@param coords table {x, y, z}
---@param rotation table {x, y, z}
---@param image string|nil Custom image reference
---@return boolean success
---@return string message
---@return table|nil tagData
function FreeGangs.Server.Graffiti.Spray(source, coords, rotation, image)
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Check gang membership
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end
    
    -- Check for spray can item
    local sprayCanItem = FreeGangs.Config.Activities.Graffiti and
                         FreeGangs.Config.Activities.Graffiti.RequiredItem or 'spray_can'
    if not FreeGangs.Bridge.HasItem(source, sprayCanItem, 1) then
        return false, FreeGangs.L('activities', 'graffiti_no_spray'), nil
    end
    
    -- Check cycle limit
    local sprayCount = GetPlayerSprayCount(citizenid)
    local maxSprays = FreeGangs.Config.Activities.Graffiti and
                      FreeGangs.Config.Activities.Graffiti.MaxSpraysPerCycle or MAX_SPRAYS_PER_CYCLE
    if sprayCount >= maxSprays then
        return false, FreeGangs.L('activities', 'graffiti_max_reached'), nil
    end
    
    -- Get zone
    local zoneName = GetZoneFromCoords(coords)
    
    -- Check zone tag limit
    if zoneName then
        local maxZoneTags = FreeGangs.Config.Activities.Graffiti and 
                           FreeGangs.Config.Activities.Graffiti.MaxPerZone or 20
        local zoneTagCount = GetZoneTagCount(zoneName, gangData.gang.name)
        if zoneTagCount >= maxZoneTags then
            return false, FreeGangs.L('activities', 'graffiti_max_zone'), nil
        end
    end
    
    -- Check if too close to existing tag
    local minDistance = FreeGangs.Config.Activities.Graffiti and 
                        FreeGangs.Config.Activities.Graffiti.MinDistance or 5.0
    local tooClose, nearbyTag = IsTooCloseToExistingTag(coords, minDistance)
    
    if tooClose and nearbyTag then
        -- If nearby tag belongs to rival, this is a tag-over (remove theirs, add ours)
        if nearbyTag.gang_name ~= gangData.gang.name then
            -- Remove rival tag
            local removeSuccess = FreeGangs.Server.Graffiti.Remove(source, nearbyTag.id, true)
            if not removeSuccess then
                return false, 'Failed to remove rival tag', nil
            end
        else
            -- Can't spray too close to own tag
            return false, 'Too close to existing tag', nil
        end
    end
    
    -- Consume spray can
    if not FreeGangs.Bridge.RemoveItem(source, sprayCanItem, 1) then
        return false, FreeGangs.L('errors', 'generic'), nil
    end
    
    -- Create tag in database
    rotation = rotation or { x = 0, y = 0, z = 0 }
    
    local tagId = MySQL.insert.await([[
        INSERT INTO freegangs_graffiti (gang_name, zone_name, coords, rotation, image, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        gangData.gang.name,
        zoneName,
        json.encode(coords),
        json.encode(rotation),
        image,
        citizenid,
    })
    
    if not tagId then
        -- Refund spray can
        FreeGangs.Bridge.AddItem(source, sprayCanItem, 1)
        return false, FreeGangs.L('errors', 'server_error'), nil
    end
    
    -- Create tag data
    local tagData = {
        id = tagId,
        gang_name = gangData.gang.name,
        zone_name = zoneName,
        coords = coords,
        rotation = rotation,
        image = image,
        created_by = citizenid,
        created_at = FreeGangs.Utils.GetTimestamp(),
    }
    
    -- Add to cache
    graffitiCache[tagId] = tagData
    
    -- Increment spray count
    IncrementPlayerSprayCount(citizenid)
    
    -- Get activity points
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.GRAFFITI]
    
    -- Add reputation
    local repAmount = activityPoints.masterRep
    
    -- Apply archetype bonus (Street Gang gets +25% graffiti loyalty)
    local loyaltyAmount = activityPoints.zoneInfluence
    if gangData.gang.archetype == FreeGangs.Archetypes.STREET then
        loyaltyAmount = math.floor(loyaltyAmount * (1 + FreeGangs.ArchetypePassiveBonuses[FreeGangs.Archetypes.STREET].graffitiLoyalty))
    end
    
    FreeGangs.Server.AddGangReputation(gangData.gang.name, repAmount, citizenid, 'graffiti')
    
    -- Add zone influence if in territory
    if zoneName then
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory then
            territory.influence = territory.influence or {}
            territory.influence[gangData.gang.name] = math.min(100, 
                (territory.influence[gangData.gang.name] or 0) + loyaltyAmount
            )
            FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
            
            -- Update GlobalState for clients
            GlobalState['territory:' .. zoneName] = {
                influence = territory.influence,
                updated = FreeGangs.Utils.GetTimestamp(),
            }
        end
    end
    
    -- Add heat
    local heatAmount = activityPoints.heat
    FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)
    
    -- Notify all clients to spawn the tag
    TriggerClientEvent(FreeGangs.Events.Client.ADD_GRAFFITI, -1, tagData)
    
    -- Log activity
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'graffiti_spray', FreeGangs.LogCategories.ACTIVITY, {
        tag_id = tagId,
        zone = zoneName,
        coords = coords,
    })
    
    return true, FreeGangs.L('activities', 'graffiti_sprayed', loyaltyAmount), {
        tag = tagData,
        rep = repAmount,
        loyalty = loyaltyAmount,
        heat = heatAmount,
    }
end

-- ============================================================================
-- REMOVE GRAFFITI
-- ============================================================================

---Remove a graffiti tag
---@param source number Player source
---@param tagId number Tag ID to remove
---@param isTagOver boolean|nil Whether this is a tag-over (automatic removal)
---@return boolean success
---@return string message
---@return table|nil result
function FreeGangs.Server.Graffiti.Remove(source, tagId, isTagOver)
    -- Validate player
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end
    
    -- Get tag data
    local tagData = graffitiCache[tagId]
    if not tagData then
        return false, 'Tag not found', nil
    end
    
    -- Get player's gang data
    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    
    -- If not a tag-over, require cleaning item
    if not isTagOver then
        local cleanerItem = FreeGangs.Config.Activities.Graffiti and
                           FreeGangs.Config.Activities.Graffiti.RemovalItem or 'cleaning_kit'
        if not FreeGangs.Bridge.HasItem(source, cleanerItem, 1) then
            return false, 'You need a cleaning kit to remove this tag', nil
        end

        -- Consume cleaner (check return value)
        if not FreeGangs.Bridge.RemoveItem(source, cleanerItem, 1) then
            return false, FreeGangs.L('errors', 'generic'), nil
        end
    end
    
    -- Determine removal type
    local isOwnTag = gangData and tagData.gang_name == gangData.gang.name
    local isRivalRemoval = gangData and tagData.gang_name ~= gangData.gang.name
    local isCivilian = not gangData
    
    -- Remove from database
    MySQL.query.await('DELETE FROM freegangs_graffiti WHERE id = ?', { tagId })
    
    -- Remove from cache
    graffitiCache[tagId] = nil
    
    -- Process effects based on removal type
    local tagOwnerGang = tagData.gang_name
    local zoneName = tagData.zone_name
    
    if zoneName then
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory and territory.influence then
            -- Remove loyalty from tag owner
            local loyaltyLoss = 15
            territory.influence[tagOwnerGang] = math.max(0, 
                (territory.influence[tagOwnerGang] or 0) - loyaltyLoss
            )
            FreeGangs.Server.Cache.MarkDirty('territory', zoneName)
            
            -- Update GlobalState
            GlobalState['territory:' .. zoneName] = {
                influence = territory.influence,
                updated = FreeGangs.Utils.GetTimestamp(),
            }
        end
    end
    
    -- Handle rival removal bonus
    local result = {
        removed = true,
        tagOwner = tagOwnerGang,
        zone = zoneName,
    }
    
    if isRivalRemoval and gangData then
        -- Award rep to remover
        local removeRepBonus = FreeGangs.ActivityPoints[FreeGangs.Activities.GRAFFITI_REMOVE].masterRep
        FreeGangs.Server.AddGangReputation(gangData.gang.name, removeRepBonus, citizenid, 'graffiti_remove')
        result.repGained = removeRepBonus
        
        -- Damage owner gang rep
        local ownerGang = FreeGangs.Server.Gangs[tagOwnerGang]
        if ownerGang then
            FreeGangs.Server.SetGangReputation(tagOwnerGang, ownerGang.master_rep - 10, 'tag_removed')
        end
    end
    
    -- Notify all clients to remove the tag
    TriggerClientEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, -1, tagId)
    
    -- Notify tag owner's gang if online
    if isRivalRemoval or isCivilian then
        local ownerGang = FreeGangs.Server.Gangs[tagOwnerGang]
        if ownerGang then
            FreeGangs.Bridge.NotifyGang(tagOwnerGang, 
                string.format('Your tag at %s was removed!', zoneName or 'unknown location'),
                'warning'
            )
        end
    end
    
    -- Log activity
    FreeGangs.Server.DB.Log(gangData and gangData.gang.name or nil, citizenid, 'graffiti_remove', FreeGangs.LogCategories.ACTIVITY, {
        tag_id = tagId,
        tag_owner = tagOwnerGang,
        zone = zoneName,
        is_rival = isRivalRemoval,
        is_civilian = isCivilian,
    })
    
    return true, FreeGangs.L('activities', 'graffiti_removed'), result
end

-- ============================================================================
-- QUERY FUNCTIONS
-- ============================================================================

---Get nearby graffiti tags
---@param coords table {x, y, z}
---@param radius number
---@return table tags
function FreeGangs.Server.Graffiti.GetNearby(coords, radius)
    radius = radius or 100.0
    local nearby = {}
    
    for id, tag in pairs(graffitiCache) do
        if tag.coords and tag.coords.x then
            local distance = math.sqrt(
                (coords.x - tag.coords.x)^2 + 
                (coords.y - tag.coords.y)^2 + 
                (coords.z - tag.coords.z)^2
            )
            if distance <= radius then
                nearby[#nearby + 1] = tag
            end
        end
    end
    
    return nearby
end

---Get all graffiti in a zone
---@param zoneName string
---@return table tags
function FreeGangs.Server.Graffiti.GetZoneTags(zoneName)
    return GetZoneTags(zoneName)
end

---Get gang's graffiti
---@param gangName string
---@return table tags
function FreeGangs.Server.Graffiti.GetGangTags(gangName)
    local tags = {}
    
    for id, tag in pairs(graffitiCache) do
        if tag.gang_name == gangName then
            tags[#tags + 1] = tag
        end
    end
    
    return tags
end

---Get all graffiti (for admin or full map load)
---@return table tags
function FreeGangs.Server.Graffiti.GetAll()
    local tags = {}
    
    for id, tag in pairs(graffitiCache) do
        tags[#tags + 1] = tag
    end
    
    return tags
end

---Get single tag by ID
---@param tagId number
---@return table|nil tag
function FreeGangs.Server.Graffiti.GetById(tagId)
    return graffitiCache[tagId]
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

---Clean up expired graffiti
function FreeGangs.Server.Graffiti.CleanupExpired()
    local result = MySQL.query.await([[
        SELECT id FROM freegangs_graffiti WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP
    ]])
    
    if not result or #result == 0 then return end
    
    local removedIds = {}
    for _, row in pairs(result) do
        graffitiCache[row.id] = nil
        removedIds[#removedIds + 1] = row.id
    end
    
    -- Delete from database
    MySQL.query('DELETE FROM freegangs_graffiti WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP')
    
    -- Notify clients
    for _, id in pairs(removedIds) do
        TriggerClientEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, -1, id)
    end
    
    if #removedIds > 0 then
        FreeGangs.Utils.Log('Cleaned up ' .. #removedIds .. ' expired graffiti tags')
    end
end

---Clean up spray count cache
local function CleanupSprayCounts()
    local currentCycle = GetCurrentCycleStart()
    
    for citizenid, data in pairs(playerSprayCounts) do
        if data.cycleStart ~= currentCycle then
            playerSprayCounts[citizenid] = nil
        end
    end
end

-- ============================================================================
-- BACKGROUND THREADS
-- ============================================================================

CreateThread(function()
    -- Load graffiti on startup
    Wait(2000) -- Wait for DB to be ready
    FreeGangs.Server.Graffiti.LoadAll()
end)

CreateThread(function()
    while true do
        Wait(3600000) -- Every hour
        FreeGangs.Server.Graffiti.CleanupExpired()
        CleanupSprayCounts()
    end
end)

return FreeGangs.Server.Graffiti
