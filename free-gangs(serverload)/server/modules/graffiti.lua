--[[
    FREE-GANGS: Server Graffiti Module

    Handles graffiti/tagging system on the server:
    - Spray validation with anti-cheat timing
    - Coordinate validation (player proximity)
    - Tag removal mechanics with zone loyalty effects
    - Cycle limits (max sprays per time period)
    - DUI image URL validation
    - Surface normal + scale persistence

    Tags persist to database and sync to all clients via events.
    Rendering uses DUI + Scaleform (client-side).
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

-- ============================================================================
-- CONFIG HELPERS
-- ============================================================================

local function GetGraffitiConfig()
    return FreeGangs.Config.Activities and FreeGangs.Config.Activities.Graffiti or {}
end

local function GetCycleDuration()
    local cfg = GetGraffitiConfig()
    return (cfg.CycleDurationHours or 6) * 3600
end

local function GetMaxSpraysPerCycle()
    local cfg = GetGraffitiConfig()
    return cfg.MaxSpraysPerCycle or 6
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Load all graffiti from database into cache
function FreeGangs.Server.Graffiti.LoadAll()
    local result = MySQL.query.await([[
        SELECT
            id, gang_name, zone_name, coords, rotation,
            image_url, normal_x, normal_y, normal_z,
            scale, width, height,
            created_by, created_at, expires_at
        FROM freegangs_graffiti
        WHERE expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP
    ]])

    graffitiCache = {}
    for _, row in pairs(result or {}) do
        row.coords = row.coords and json.decode(row.coords) or {}
        row.rotation = row.rotation and json.decode(row.rotation) or { x = 0, y = 0, z = 0 }
        row.normal_x = row.normal_x or 0.0
        row.normal_y = row.normal_y or 0.0
        row.normal_z = row.normal_z or 0.0
        row.scale = row.scale or 1.0
        row.width = row.width or 1.0
        row.height = row.height or 1.0
        row.image_url = row.image_url or ''
        graffitiCache[row.id] = row
    end

    FreeGangs.Utils.Log('Loaded ' .. FreeGangs.Utils.TableLength(graffitiCache) .. ' graffiti tags')
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Get current cycle timestamp (start of current cycle period)
---@return number timestamp
local function GetCurrentCycleStart()
    local now = FreeGangs.Utils.GetTimestamp()
    return now - (now % GetCycleDuration())
end

---Get player's spray count for current cycle
---@param citizenid string
---@return number count
local function GetPlayerSprayCount(citizenid)
    local cycleStart = GetCurrentCycleStart()
    local data = playerSprayCounts[citizenid]

    if not data or data.cycleStart ~= cycleStart then
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
        playerSprayCounts[citizenid] = { cycleStart = cycleStart, count = 0 }
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

    for _, tag in pairs(graffitiCache) do
        if tag.coords and tag.coords.x then
            local dx = coords.x - tag.coords.x
            local dy = coords.y - tag.coords.y
            local dz = coords.z - tag.coords.z
            local distSq = dx * dx + dy * dy + dz * dz
            if distSq < minDistance * minDistance then
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

            if territory.radius then
                local dx = coords.x - zoneCoords.x
                local dy = coords.y - zoneCoords.y
                if dx * dx + dy * dy <= territory.radius * territory.radius then
                    return zoneName
                end
            elseif territory.size then
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

---Validate that an image URL is allowed
---@param imageUrl string
---@param gangName string
---@return boolean valid
local function IsValidImageUrl(imageUrl, gangName)
    if not imageUrl or imageUrl == '' then return true end

    local cfg = GetGraffitiConfig()

    -- Check gang-specific images
    local gangImages = cfg.GangImages and cfg.GangImages[gangName]
    if gangImages then
        for _, url in pairs(gangImages) do
            if url == imageUrl then return true end
        end
    end

    -- Check default images
    if cfg.DefaultImages then
        for _, url in pairs(cfg.DefaultImages) do
            if url == imageUrl then return true end
        end
    end

    -- Check gang settings in DB (custom images set by gang leaders)
    local gangData = FreeGangs.Server.Gangs[gangName]
    if gangData and gangData.settings then
        local settings = type(gangData.settings) == 'string' and json.decode(gangData.settings) or gangData.settings
        if settings and settings.graffiti_images then
            for _, url in pairs(settings.graffiti_images) do
                if url == imageUrl then return true end
            end
        end
    end

    -- Allow nui:// URLs from this resource (local images)
    local resourceName = GetCurrentResourceName()
    if imageUrl:find('^nui://' .. resourceName .. '/') then
        return true
    end
    if imageUrl:find('^https://cfx%-nui%-' .. resourceName .. '/') then
        return true
    end

    return false
end

---Validate spray coordinates are near the player
---@param source number
---@param coords table {x, y, z}
---@return boolean valid
local function ValidateSprayCoords(source, coords)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local pedCoords = GetEntityCoords(ped)
    local dx = coords.x - pedCoords.x
    local dy = coords.y - pedCoords.y
    local dz = coords.z - pedCoords.z
    local distSq = dx * dx + dy * dy + dz * dz

    -- Allow up to 5 meters from player (generous for raycast offset)
    return distSq <= 25.0
end

-- ============================================================================
-- SPRAY GRAFFITI
-- ============================================================================

---Spray a new graffiti tag
---@param source number Player source
---@param sprayData table { coords, normal, image_url, scale, width, height }
---@return boolean success
---@return string message
---@return table|nil tagData
function FreeGangs.Server.Graffiti.Spray(source, sprayData)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    if not gangData then
        return false, FreeGangs.L('gangs', 'not_in_gang'), nil
    end

    local cfg = GetGraffitiConfig()
    local coords = sprayData.coords
    local normal = sprayData.normal or { x = 0, y = 1, z = 0 }
    local imageUrl = sprayData.image_url or ''
    local scale = math.max(cfg.MinScale or 0.3, math.min(cfg.MaxScale or 3.0, tonumber(sprayData.scale) or (cfg.DefaultScale or 1.0)))
    local width = tonumber(sprayData.width) or (cfg.DefaultWidth or 1.2)
    local height = tonumber(sprayData.height) or (cfg.DefaultHeight or 1.2)

    -- Validate coords exist and are near player
    if not coords or not coords.x or not coords.y or not coords.z then
        return false, 'Invalid coordinates', nil
    end
    if not ValidateSprayCoords(source, coords) then
        return false, 'Too far from spray location', nil
    end

    -- Validate image URL
    if not IsValidImageUrl(imageUrl, gangData.gang.name) then
        return false, 'Invalid image', nil
    end

    -- Check for spray can item
    local sprayCanItem = cfg.RequiredItem or 'spray_can'
    if not FreeGangs.Bridge.HasItem(source, sprayCanItem, 1) then
        return false, FreeGangs.L('activities', 'graffiti_no_spray'), nil
    end

    -- Check cycle limit
    local sprayCount = GetPlayerSprayCount(citizenid)
    if sprayCount >= GetMaxSpraysPerCycle() then
        return false, FreeGangs.L('activities', 'graffiti_max_reached'), nil
    end

    -- Get zone
    local zoneName = GetZoneFromCoords(coords)

    -- Check zone tag limit
    if zoneName then
        local maxZoneTags = cfg.MaxPerZone or 20
        local zoneTagCount = GetZoneTagCount(zoneName, gangData.gang.name)
        if zoneTagCount >= maxZoneTags then
            return false, FreeGangs.L('activities', 'graffiti_max_zone'), nil
        end
    end

    -- Check proximity to existing tags
    local minDistance = cfg.MinDistance or 5.0
    local tooClose, nearbyTag = IsTooCloseToExistingTag(coords, minDistance)

    if tooClose and nearbyTag then
        if nearbyTag.gang_name ~= gangData.gang.name then
            -- Tag-over: remove rival tag first
            local removeSuccess = FreeGangs.Server.Graffiti.Remove(source, nearbyTag.id, true)
            if not removeSuccess then
                return false, 'Failed to remove rival tag', nil
            end
        else
            return false, 'Too close to existing tag', nil
        end
    end

    -- Consume spray can (atomic: consume first, refund on failure)
    if cfg.ConsumeItem ~= false then
        if not FreeGangs.Bridge.RemoveItem(source, sprayCanItem, 1) then
            return false, FreeGangs.L('errors', 'generic'), nil
        end
    end

    -- Calculate rotation from surface normal
    local nx = tonumber(normal.x) or 0.0
    local ny = tonumber(normal.y) or 0.0
    local nz = tonumber(normal.z) or 0.0
    local heading = math.deg(math.atan2(ny, nx))
    local rotation = { x = 0.0, y = 0.0, z = heading }

    -- Calculate expiry
    local expiresAtUnix = nil
    if cfg.DecayEnabled and cfg.DecayDays and cfg.DecayDays > 0 then
        local now = FreeGangs.Utils.GetTimestamp()
        expiresAtUnix = now + (cfg.DecayDays * 86400)
    end

    -- Insert into database (use FROM_UNIXTIME for expires_at, or NULL if no decay)
    local tagId
    if expiresAtUnix then
        tagId = MySQL.insert.await([[
            INSERT INTO freegangs_graffiti
                (gang_name, zone_name, coords, rotation, image_url, normal_x, normal_y, normal_z, scale, width, height, created_by, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))
        ]], {
            gangData.gang.name, zoneName, json.encode(coords), json.encode(rotation),
            imageUrl, nx, ny, nz, scale, width, height, citizenid, expiresAtUnix,
        })
    else
        tagId = MySQL.insert.await([[
            INSERT INTO freegangs_graffiti
                (gang_name, zone_name, coords, rotation, image_url, normal_x, normal_y, normal_z, scale, width, height, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            gangData.gang.name, zoneName, json.encode(coords), json.encode(rotation),
            imageUrl, nx, ny, nz, scale, width, height, citizenid,
        })
    end

    if not tagId then
        -- Refund spray can
        if cfg.ConsumeItem ~= false then
            FreeGangs.Bridge.AddItem(source, sprayCanItem, 1)
        end
        return false, FreeGangs.L('errors', 'server_error'), nil
    end

    -- Build tag data for cache and client sync
    local tagData = {
        id = tagId,
        gang_name = gangData.gang.name,
        zone_name = zoneName,
        coords = coords,
        rotation = rotation,
        image_url = imageUrl,
        normal_x = nx,
        normal_y = ny,
        normal_z = nz,
        scale = scale,
        width = width,
        height = height,
        created_by = citizenid,
        created_at = FreeGangs.Utils.GetTimestamp(),
    }

    graffitiCache[tagId] = tagData
    IncrementPlayerSprayCount(citizenid)

    -- Activity rewards
    local activityPoints = FreeGangs.ActivityPoints[FreeGangs.Activities.GRAFFITI]
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

            GlobalState['territory:' .. zoneName] = {
                influence = territory.influence,
                updated = FreeGangs.Utils.GetTimestamp(),
            }
        end
    end

    -- Add player heat
    local heatAmount = cfg.SprayHeat or activityPoints.heat
    FreeGangs.Server.AddPlayerHeat(citizenid, heatAmount)

    -- Notify all clients
    TriggerClientEvent(FreeGangs.Events.Client.ADD_GRAFFITI, -1, tagData)

    -- Log activity
    FreeGangs.Server.DB.Log(gangData.gang.name, citizenid, 'graffiti_spray', FreeGangs.LogCategories.ACTIVITY, {
        tag_id = tagId,
        zone = zoneName,
        coords = coords,
        image_url = imageUrl,
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
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then
        return false, FreeGangs.L('errors', 'not_loaded'), nil
    end

    local tagData = graffitiCache[tagId]
    if not tagData then
        return false, 'Tag not found', nil
    end

    local gangData = FreeGangs.Server.GetPlayerGangData(source)
    local cfg = GetGraffitiConfig()

    -- If not a tag-over, require cleaning item
    if not isTagOver then
        local cleanerItem = cfg.RemovalItem or 'cleaning_kit'
        if not FreeGangs.Bridge.HasItem(source, cleanerItem, 1) then
            return false, 'You need a cleaning kit to remove this tag', nil
        end

        if not FreeGangs.Bridge.RemoveItem(source, cleanerItem, 1) then
            return false, FreeGangs.L('errors', 'generic'), nil
        end
    end

    local isOwnTag = gangData and tagData.gang_name == gangData.gang.name
    local isRivalRemoval = gangData and tagData.gang_name ~= gangData.gang.name

    -- Remove from database
    MySQL.query.await('DELETE FROM freegangs_graffiti WHERE id = ?', { tagId })
    graffitiCache[tagId] = nil

    -- Zone loyalty effects
    local tagOwnerGang = tagData.gang_name
    local zoneName = tagData.zone_name

    if zoneName then
        local territory = FreeGangs.Server.Territories[zoneName]
        if territory and territory.influence then
            local loyaltyLoss = cfg.RemovalLoyaltyLoss or 15
            territory.influence[tagOwnerGang] = math.max(0,
                (territory.influence[tagOwnerGang] or 0) - loyaltyLoss
            )
            FreeGangs.Server.Cache.MarkDirty('territory', zoneName)

            GlobalState['territory:' .. zoneName] = {
                influence = territory.influence,
                updated = FreeGangs.Utils.GetTimestamp(),
            }
        end
    end

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
        local repDamage = cfg.RemovalRepDamage or 10
        local ownerGang = FreeGangs.Server.Gangs[tagOwnerGang]
        if ownerGang then
            FreeGangs.Server.SetGangReputation(tagOwnerGang, ownerGang.master_rep - repDamage, 'tag_removed')
        end

        -- Add heat for removing rival tag
        local removalHeat = cfg.RemovalHeat or 0
        if removalHeat > 0 then
            FreeGangs.Server.AddPlayerHeat(citizenid, removalHeat)
        end
    end

    -- Notify all clients
    TriggerClientEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, -1, tagId)

    -- Notify tag owner's gang
    if isRivalRemoval or (not gangData) then
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
    local radiusSq = radius * radius
    local nearby = {}

    for _, tag in pairs(graffitiCache) do
        if tag.coords and tag.coords.x then
            local dx = coords.x - tag.coords.x
            local dy = coords.y - tag.coords.y
            local dz = coords.z - tag.coords.z
            if (dx * dx + dy * dy + dz * dz) <= radiusSq then
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
    local tags = {}
    for _, tag in pairs(graffitiCache) do
        if tag.zone_name == zoneName then
            tags[#tags + 1] = tag
        end
    end
    return tags
end

---Get gang's graffiti
---@param gangName string
---@return table tags
function FreeGangs.Server.Graffiti.GetGangTags(gangName)
    local tags = {}
    for _, tag in pairs(graffitiCache) do
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
    for _, tag in pairs(graffitiCache) do
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

---Get available graffiti images for a gang
---@param gangName string
---@return table images
function FreeGangs.Server.Graffiti.GetGangImages(gangName)
    local cfg = GetGraffitiConfig()
    local images = {}

    -- Gang-specific config images
    if cfg.GangImages and cfg.GangImages[gangName] then
        for _, url in pairs(cfg.GangImages[gangName]) do
            images[#images + 1] = url
        end
    end

    -- Gang settings from DB
    local gangData = FreeGangs.Server.Gangs[gangName]
    if gangData and gangData.settings then
        local settings = type(gangData.settings) == 'string' and json.decode(gangData.settings) or gangData.settings
        if settings and settings.graffiti_images then
            for _, url in pairs(settings.graffiti_images) do
                images[#images + 1] = url
            end
        end
    end

    -- Fallback to defaults if gang has no custom images
    if #images == 0 and cfg.DefaultImages then
        for _, url in pairs(cfg.DefaultImages) do
            images[#images + 1] = url
        end
    end

    return images
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

    MySQL.query('DELETE FROM freegangs_graffiti WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP')

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
