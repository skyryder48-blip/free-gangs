--[[
    FREE-GANGS: Client-Side Cache
    
    Manages client-side cached state for quick access.
    Syncs with server via events and GlobalState.
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Cache = {}

-- Internal cache storage
local cache = {}

-- ============================================================================
-- BASIC CACHE OPERATIONS
-- ============================================================================

---Set a value in cache
---@param key string
---@param value any
function FreeGangs.Client.Cache.Set(key, value)
    cache[key] = value
end

---Get a value from cache
---@param key string
---@return any
function FreeGangs.Client.Cache.Get(key)
    return cache[key]
end

---Remove a value from cache
---@param key string
function FreeGangs.Client.Cache.Remove(key)
    cache[key] = nil
end

---Check if key exists in cache
---@param key string
---@return boolean
function FreeGangs.Client.Cache.Has(key)
    return cache[key] ~= nil
end

---Clear entire cache
function FreeGangs.Client.Cache.Clear()
    cache = {}
end

-- ============================================================================
-- CONVENIENCE GETTERS
-- ============================================================================

---Get player's gang data
---@return table|nil
function FreeGangs.Client.Cache.GetPlayerGang()
    return cache.playerGang
end

---Get player's membership data
---@return table|nil
function FreeGangs.Client.Cache.GetMembership()
    local gang = cache.playerGang
    return gang and gang.membership or nil
end

---Check if player is in a gang
---@return boolean
function FreeGangs.Client.Cache.IsInGang()
    return cache.playerGang ~= nil
end

---Get player's gang name
---@return string|nil
function FreeGangs.Client.Cache.GetGangName()
    local gang = cache.playerGang
    return gang and gang.name or nil
end

---Get player's rank
---@return number
function FreeGangs.Client.Cache.GetRank()
    local membership = FreeGangs.Client.Cache.GetMembership()
    return membership and membership.rank or 0
end

---Check if player is gang boss
---@return boolean
function FreeGangs.Client.Cache.IsBoss()
    local membership = FreeGangs.Client.Cache.GetMembership()
    return membership and membership.isBoss or false
end

---Check if player is officer+
---@return boolean
function FreeGangs.Client.Cache.IsOfficer()
    local membership = FreeGangs.Client.Cache.GetMembership()
    if not membership then return false end
    return membership.isOfficer or membership.isBoss or membership.rank >= 2
end

---Get all territories
---@return table
function FreeGangs.Client.Cache.GetTerritories()
    return cache.territories or {}
end

---Get specific territory
---@param zoneName string
---@return table|nil
function FreeGangs.Client.Cache.GetTerritory(zoneName)
    local territories = cache.territories or {}
    return territories[zoneName]
end

---Get current zone
---@return table|nil {name: string, data: table, enteredAt: number}
function FreeGangs.Client.Cache.GetCurrentZone()
    return FreeGangs.Client.CurrentZone
end

---Check if in any territory
---@return boolean
function FreeGangs.Client.Cache.IsInTerritory()
    return FreeGangs.Client.CurrentZone ~= nil
end

---Get gang's archetype
---@return string|nil
function FreeGangs.Client.Cache.GetArchetype()
    local gang = cache.playerGang
    return gang and gang.archetype or nil
end

---Get gang's master level
---@return number
function FreeGangs.Client.Cache.GetMasterLevel()
    local gang = cache.playerGang
    return gang and gang.master_level or 1
end

---Get gang's master rep
---@return number
function FreeGangs.Client.Cache.GetMasterRep()
    local gang = cache.playerGang
    return gang and gang.master_rep or 0
end

-- ============================================================================
-- COOLDOWN TRACKING
-- ============================================================================

local cooldowns = {}

---Set a local cooldown
---@param key string
---@param durationMs number Duration in milliseconds
function FreeGangs.Client.Cache.SetCooldown(key, durationMs)
    cooldowns[key] = GetGameTimer() + durationMs
end

---Check if on cooldown
---@param key string
---@return boolean onCooldown
---@return number remainingMs
function FreeGangs.Client.Cache.IsOnCooldown(key)
    local expiry = cooldowns[key]
    if not expiry then
        return false, 0
    end
    
    local remaining = expiry - GetGameTimer()
    if remaining > 0 then
        return true, remaining
    end
    
    cooldowns[key] = nil
    return false, 0
end

---Get cooldown remaining formatted
---@param key string
---@return string
function FreeGangs.Client.Cache.GetCooldownRemaining(key)
    local _, remaining = FreeGangs.Client.Cache.IsOnCooldown(key)
    return FreeGangs.Utils.FormatDuration(remaining)
end

-- ============================================================================
-- ACTIVITY TRACKING
-- ============================================================================

local activityCounts = {}
local activityResetTime = {}

---Track an activity (for diminishing returns)
---@param activityType string
function FreeGangs.Client.Cache.TrackActivity(activityType)
    local now = GetGameTimer()
    
    -- Reset if hour has passed
    if activityResetTime[activityType] and now > activityResetTime[activityType] then
        activityCounts[activityType] = 0
    end
    
    activityCounts[activityType] = (activityCounts[activityType] or 0) + 1
    activityResetTime[activityType] = now + 3600000 -- 1 hour
end

---Get activity count this hour
---@param activityType string
---@return number
function FreeGangs.Client.Cache.GetActivityCount(activityType)
    local now = GetGameTimer()
    
    if activityResetTime[activityType] and now > activityResetTime[activityType] then
        activityCounts[activityType] = 0
    end
    
    return activityCounts[activityType] or 0
end

-- ============================================================================
-- HEAT TRACKING (Local display)
-- ============================================================================

local heatData = {}

---Update heat data for a gang pair
---@param otherGang string
---@param level number
---@param stage string
function FreeGangs.Client.Cache.UpdateHeat(otherGang, level, stage)
    heatData[otherGang] = {
        level = level,
        stage = stage,
        lastUpdate = GetGameTimer(),
    }
end

---Get heat with specific gang
---@param otherGang string
---@return table|nil {level: number, stage: string}
function FreeGangs.Client.Cache.GetHeat(otherGang)
    return heatData[otherGang]
end

---Get all heat data
---@return table
function FreeGangs.Client.Cache.GetAllHeat()
    return heatData
end

-- ============================================================================
-- BRIBE TRACKING
-- ============================================================================

local bribes = {}

---Update bribe data
---@param contactType string
---@param data table
function FreeGangs.Client.Cache.UpdateBribe(contactType, data)
    bribes[contactType] = data
end

---Get bribe data
---@param contactType string
---@return table|nil
function FreeGangs.Client.Cache.GetBribe(contactType)
    return bribes[contactType]
end

---Get all active bribes
---@return table
function FreeGangs.Client.Cache.GetAllBribes()
    return bribes
end

---Check if bribe contact is active
---@param contactType string
---@return boolean
function FreeGangs.Client.Cache.HasBribe(contactType)
    local bribe = bribes[contactType]
    return bribe and bribe.status == 'active'
end

-- ============================================================================
-- WAR TRACKING
-- ============================================================================

local activeWars = {}

---Update war data
---@param warId number
---@param data table
function FreeGangs.Client.Cache.UpdateWar(warId, data)
    activeWars[warId] = data
end

---Remove war data
---@param warId number
function FreeGangs.Client.Cache.RemoveWar(warId)
    activeWars[warId] = nil
end

---Get all active wars
---@return table
function FreeGangs.Client.Cache.GetActiveWars()
    return activeWars
end

---Check if at war with specific gang
---@param gangName string
---@return boolean, table|nil warData
function FreeGangs.Client.Cache.IsAtWarWith(gangName)
    for _, war in pairs(activeWars) do
        if war.status == 'active' then
            if war.attacker == gangName or war.defender == gangName then
                return true, war
            end
        end
    end
    return false, nil
end

-- ============================================================================
-- DEBUG
-- ============================================================================

---Get cache debug info
---@return table
function FreeGangs.Client.Cache.GetDebugInfo()
    return {
        playerGang = cache.playerGang ~= nil,
        territoriesCount = FreeGangs.Utils.TableLength(cache.territories or {}),
        cooldownsCount = FreeGangs.Utils.TableLength(cooldowns),
        heatCount = FreeGangs.Utils.TableLength(heatData),
        bribesCount = FreeGangs.Utils.TableLength(bribes),
        activeWarsCount = FreeGangs.Utils.TableLength(activeWars),
        sprayCount = FreeGangs.Client.Cache.GetSprayCount(),
    }
end

return FreeGangs.Client.Cache
