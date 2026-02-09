--[[
    FREE-GANGS: Shared Utility Functions
    
    Common utility functions used by both client and server.
    Loaded after enums.lua to ensure FreeGangs table exists.
]]

FreeGangs.Utils = {}

-- ============================================================================
-- TABLE UTILITIES
-- ============================================================================

---Deep copy a table
---@param orig table
---@return table
function FreeGangs.Utils.DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for key, value in next, orig, nil do
            copy[FreeGangs.Utils.DeepCopy(key)] = FreeGangs.Utils.DeepCopy(value)
        end
        setmetatable(copy, FreeGangs.Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

---Shallow copy a table
---@param orig table
---@return table
function FreeGangs.Utils.ShallowCopy(orig)
    local copy = {}
    for key, value in pairs(orig) do
        copy[key] = value
    end
    return copy
end

---Merge two tables (second table overwrites first)
---@param t1 table
---@param t2 table
---@return table
function FreeGangs.Utils.MergeTables(t1, t2)
    local result = FreeGangs.Utils.DeepCopy(t1)
    for key, value in pairs(t2) do
        if type(value) == 'table' and type(result[key]) == 'table' then
            result[key] = FreeGangs.Utils.MergeTables(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

---Check if a table contains a value
---@param tbl table
---@param value any
---@return boolean
function FreeGangs.Utils.TableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

---Get table length (works for non-sequential tables)
---@param tbl table
---@return number
function FreeGangs.Utils.TableLength(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

---Get keys from a table
---@param tbl table
---@return table
function FreeGangs.Utils.TableKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    return keys
end

---Get values from a table
---@param tbl table
---@return table
function FreeGangs.Utils.TableValues(tbl)
    local values = {}
    for _, value in pairs(tbl) do
        values[#values + 1] = value
    end
    return values
end

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

---Convert string to title case
---@param str string
---@return string
function FreeGangs.Utils.TitleCase(str)
    return str:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

---Trim whitespace from string
---@param str string
---@return string
function FreeGangs.Utils.Trim(str)
    return str:match("^%s*(.-)%s*$")
end

---Split string by delimiter
---@param str string
---@param delimiter string
---@return table
function FreeGangs.Utils.Split(str, delimiter)
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    for match in str:gmatch(pattern) do
        result[#result + 1] = match
    end
    return result
end

---Sanitize string for database/display (remove special characters)
---@param str string
---@return string
function FreeGangs.Utils.Sanitize(str)
    return str:gsub("[^%w%s%-_]", "")
end

---Generate a slug from a string (lowercase, underscores)
---@param str string
---@return string
function FreeGangs.Utils.Slugify(str)
    return str:lower():gsub("%s+", "_"):gsub("[^%w_]", "")
end

---Format number with commas (e.g., 1000000 -> 1,000,000)
---@param num number
---@return string
function FreeGangs.Utils.FormatNumber(num)
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

---Format money with $ and commas
---@param amount number
---@return string
function FreeGangs.Utils.FormatMoney(amount)
    return "$" .. FreeGangs.Utils.FormatNumber(amount)
end

-- ============================================================================
-- ID GENERATION
-- ============================================================================

---Generate a unique string ID with a given prefix
---@param prefix string|nil
---@return string
function FreeGangs.Utils.GenerateId(prefix)
    prefix = prefix or 'id'
    local time = os.time()
    local random = math.random(100000, 999999)
    return string.format('%s_%d_%d', prefix, time, random)
end

-- ============================================================================
-- MATH UTILITIES
-- ============================================================================

---Clamp a value between min and max
---@param value number
---@param min number
---@param max number
---@return number
function FreeGangs.Utils.Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

---Round a number to specified decimal places
---@param num number
---@param decimals number
---@return number
function FreeGangs.Utils.Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

---Linear interpolation
---@param a number
---@param b number
---@param t number (0-1)
---@return number
function FreeGangs.Utils.Lerp(a, b, t)
    return a + (b - a) * FreeGangs.Utils.Clamp(t, 0, 1)
end

---Calculate percentage
---@param value number
---@param total number
---@return number
function FreeGangs.Utils.Percentage(value, total)
    if total == 0 then return 0 end
    return (value / total) * 100
end

---Random number with optional seed
---@param min number
---@param max number
---@return number
function FreeGangs.Utils.Random(min, max)
    return math.random(min, max)
end

---Random float between min and max
---@param min number
---@param max number
---@return number
function FreeGangs.Utils.RandomFloat(min, max)
    return min + math.random() * (max - min)
end

-- ============================================================================
-- TIME UTILITIES
-- ============================================================================

if IsDuplicityVersion() then
    -- SERVER SIDE: os library is available
    ---Get current timestamp in seconds
    ---@return number
    function FreeGangs.Utils.GetTimestamp()
        return os.time()
    end

    ---Format timestamp to readable date
    ---@param timestamp number
    ---@param format string|nil
    ---@return string
    function FreeGangs.Utils.FormatTime(timestamp, format)
        format = format or "%Y-%m-%d %H:%M:%S"
        return os.date(format, timestamp)
    end
else
    -- CLIENT SIDE: os library is NOT available in FiveM client
    local _timeSync = { offset = 0, synced = false }

    ---Sync client time with server Unix time (call once during init)
    ---@param serverTime number Unix timestamp from server
    function FreeGangs.Utils.SyncServerTime(serverTime)
        _timeSync.offset = serverTime - (GetGameTimer() / 1000)
        _timeSync.synced = true
    end

    ---Get current timestamp in seconds (synced with server)
    ---@return number
    function FreeGangs.Utils.GetTimestamp()
        return math.floor(GetGameTimer() / 1000 + _timeSync.offset)
    end

    ---Convert Unix timestamp to date components (pure Lua, no os dependency)
    ---@param timestamp number
    ---@return table {year, month, day, hour, min, sec}
    local function unixToDate(timestamp)
        timestamp = math.floor(timestamp or 0)
        local days = math.floor(timestamp / 86400)
        local remaining = timestamp % 86400

        local hours = math.floor(remaining / 3600)
        remaining = remaining % 3600
        local minutes = math.floor(remaining / 60)
        local seconds = remaining % 60

        local year = 1970
        while true do
            local daysInYear = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 366 or 365
            if days < daysInYear then break end
            days = days - daysInYear
            year = year + 1
        end

        local isLeap = (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0))
        local daysInMonth = {31, isLeap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
        local month = 1
        while month <= 12 and days >= daysInMonth[month] do
            days = days - daysInMonth[month]
            month = month + 1
        end

        return {
            year = year, month = month, day = days + 1,
            hour = hours, min = minutes, sec = seconds,
        }
    end

    ---Format timestamp to readable date (pure Lua implementation)
    ---@param timestamp number
    ---@param format string|nil
    ---@return string
    function FreeGangs.Utils.FormatTime(timestamp, format)
        format = format or "%Y-%m-%d %H:%M:%S"
        local d = unixToDate(timestamp)
        local result = format
        result = result:gsub('%%Y', string.format('%04d', d.year))
        result = result:gsub('%%m', string.format('%02d', d.month))
        result = result:gsub('%%d', string.format('%02d', d.day))
        result = result:gsub('%%H', string.format('%02d', d.hour))
        result = result:gsub('%%M', string.format('%02d', d.min))
        result = result:gsub('%%S', string.format('%02d', d.sec))
        return result
    end
end

---Parse MySQL datetime string to Unix timestamp
---@param dateStr string MySQL datetime (e.g., "2025-01-15 14:30:00")
---@return number|nil Unix timestamp
function FreeGangs.Utils.ParseTimestamp(dateStr)
    if not dateStr or type(dateStr) ~= 'string' then return nil end

    -- Handle numeric timestamps passed as strings
    local num = tonumber(dateStr)
    if num then return num end

    -- Parse MySQL datetime format: YYYY-MM-DD HH:MM:SS
    local year, month, day, hour, min, sec = dateStr:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
    if not year then return nil end

    if IsDuplicityVersion() then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec),
        })
    end

    -- Client-side fallback: approximate calculation
    -- This is less precise but functional for cooldown checks
    local y = tonumber(year)
    local m = tonumber(month)
    local d = tonumber(day)
    local h = tonumber(hour)
    local mn = tonumber(min)
    local s = tonumber(sec)

    -- Days from year
    local days = 0
    for i = 1970, y - 1 do
        days = days + ((i % 4 == 0 and (i % 100 ~= 0 or i % 400 == 0)) and 366 or 365)
    end

    -- Days from month
    local isLeap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
    local daysInMonth = {31, isLeap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    for i = 1, m - 1 do
        days = days + daysInMonth[i]
    end
    days = days + d - 1

    return days * 86400 + h * 3600 + mn * 60 + s
end

---Get time difference in human readable format
---@param timestamp number
---@return string
function FreeGangs.Utils.TimeAgo(timestamp)
    local diff = FreeGangs.Utils.GetTimestamp() - timestamp

    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. (mins == 1 and " minute ago" or " minutes ago")
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. (hours == 1 and " hour ago" or " hours ago")
    elseif diff < 604800 then
        local days = math.floor(diff / 86400)
        return days .. (days == 1 and " day ago" or " days ago")
    else
        local weeks = math.floor(diff / 604800)
        return weeks .. (weeks == 1 and " week ago" or " weeks ago")
    end
end

---Convert milliseconds to formatted time string
---@param ms number
---@return string
function FreeGangs.Utils.FormatDuration(ms)
    local seconds = math.floor(ms / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)

    seconds = seconds % 60
    minutes = minutes % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    else
        return string.format("%d:%02d", minutes, seconds)
    end
end

---Calculate time until a future timestamp
---@param futureTimestamp number
---@return number seconds remaining (0 if past)
function FreeGangs.Utils.TimeUntil(futureTimestamp)
    local diff = futureTimestamp - FreeGangs.Utils.GetTimestamp()
    return diff > 0 and diff or 0
end

-- ============================================================================
-- REPUTATION & LEVEL UTILITIES
-- ============================================================================

---Get reputation level from points
---@param rep number
---@return number level
function FreeGangs.Utils.GetReputationLevel(rep)
    local level = 1
    for lvl, data in pairs(FreeGangs.ReputationLevels) do
        if rep >= data.repRequired and lvl > level then
            level = lvl
        end
    end
    return level
end

---Get reputation level info
---@param level number
---@return table|nil
function FreeGangs.Utils.GetReputationLevelInfo(level)
    return FreeGangs.ReputationLevels[level]
end

---Calculate progress to next level
---@param currentRep number
---@return number progress (0-100)
function FreeGangs.Utils.GetLevelProgress(currentRep)
    local currentLevel = FreeGangs.Utils.GetReputationLevel(currentRep)
    local nextLevel = currentLevel + 1
    
    if nextLevel > 10 then
        return 100 -- Max level
    end
    
    local currentLevelRep = FreeGangs.ReputationLevels[currentLevel].repRequired
    local nextLevelRep = FreeGangs.ReputationLevels[nextLevel].repRequired
    local repInLevel = currentRep - currentLevelRep
    local repNeeded = nextLevelRep - currentLevelRep
    
    return FreeGangs.Utils.Round((repInLevel / repNeeded) * 100, 1)
end

---Check if gang has unlocked a feature based on level
---@param level number
---@param feature string
---@return boolean
function FreeGangs.Utils.HasUnlock(level, feature)
    for lvl = 1, level do
        local levelData = FreeGangs.ReputationLevels[lvl]
        if levelData and levelData.unlocks then
            if FreeGangs.Utils.TableContains(levelData.unlocks, feature) then
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- HEAT & RIVALRY UTILITIES
-- ============================================================================

---Get heat stage from heat level
---@param heat number
---@return string stage
function FreeGangs.Utils.GetHeatStage(heat)
    heat = FreeGangs.Utils.Clamp(heat, 0, 100)
    
    for stage, data in pairs(FreeGangs.HeatStageThresholds) do
        if heat >= data.minHeat and heat <= data.maxHeat then
            return stage
        end
    end
    
    return FreeGangs.HeatStages.NEUTRAL
end

---Get heat stage info
---@param stage string
---@return table|nil
function FreeGangs.Utils.GetHeatStageInfo(stage)
    return FreeGangs.HeatStageThresholds[stage]
end

---Check if heat stage has a specific effect
---@param stage string
---@param effect string
---@return boolean
function FreeGangs.Utils.HasHeatEffect(stage, effect)
    local stageInfo = FreeGangs.HeatStageThresholds[stage]
    if stageInfo and stageInfo.effects then
        return FreeGangs.Utils.TableContains(stageInfo.effects, effect)
    end
    return false
end

-- ============================================================================
-- ZONE CONTROL UTILITIES
-- ============================================================================

---Get zone control tier from percentage
---@param control number (0-100)
---@return number tier
function FreeGangs.Utils.GetZoneControlTier(control)
    control = FreeGangs.Utils.Clamp(control, 0, 100)
    
    for tier, data in pairs(FreeGangs.ZoneControlTiers) do
        if control >= data.minControl and control <= data.maxControl then
            return tier
        end
    end
    
    return 1
end

---Get zone control tier info
---@param tier number
---@return table|nil
function FreeGangs.Utils.GetZoneControlTierInfo(tier)
    return FreeGangs.ZoneControlTiers[tier]
end

---Calculate drug profit modifier based on zone control
---@param control number
---@return number modifier (e.g., 0.20 for +20%)
function FreeGangs.Utils.GetDrugProfitModifier(control)
    local tier = FreeGangs.Utils.GetZoneControlTier(control)
    local tierInfo = FreeGangs.ZoneControlTiers[tier]
    return tierInfo and tierInfo.drugProfit or 0
end

---Check if gang can collect protection in zone
---@param control number
---@return boolean
function FreeGangs.Utils.CanCollectProtection(control)
    local tier = FreeGangs.Utils.GetZoneControlTier(control)
    local tierInfo = FreeGangs.ZoneControlTiers[tier]
    return tierInfo and tierInfo.canCollectProtection or false
end

-- ============================================================================
-- ARCHETYPE UTILITIES
-- ============================================================================

---Get archetype info
---@param archetype string
---@return table|nil
function FreeGangs.Utils.GetArchetypeInfo(archetype)
    return FreeGangs.ArchetypeLabels[archetype]
end

---Get default ranks for archetype
---@param archetype string
---@return table|nil
function FreeGangs.Utils.GetDefaultRanks(archetype)
    return FreeGangs.DefaultRanks[archetype]
end

---Get archetype passive bonuses
---@param archetype string
---@return table|nil
function FreeGangs.Utils.GetArchetypePassives(archetype)
    return FreeGangs.ArchetypePassiveBonuses[archetype]
end

---Get archetype tier activity
---@param archetype string
---@param tier number
---@return table|nil
function FreeGangs.Utils.GetArchetypeTierActivity(archetype, tier)
    local activities = FreeGangs.ArchetypeTierActivities[archetype]
    return activities and activities[tier] or nil
end

---Check if archetype has unlocked tier activity
---@param archetype string
---@param tier number
---@param masterLevel number
---@return boolean
function FreeGangs.Utils.HasTierActivity(archetype, tier, masterLevel)
    local activity = FreeGangs.Utils.GetArchetypeTierActivity(archetype, tier)
    return activity and masterLevel >= activity.minLevel or false
end

-- ============================================================================
-- PERMISSION UTILITIES
-- ============================================================================

---Get default permissions for rank level
---@param rankLevel number
---@return table
function FreeGangs.Utils.GetDefaultPermissions(rankLevel)
    local permissions = FreeGangs.DefaultRankPermissions[tostring(rankLevel)]
    return permissions and FreeGangs.Utils.DeepCopy(permissions) or {}
end

---Check if a permission is granted
---@param permissions table
---@param permission string
---@return boolean
function FreeGangs.Utils.HasPermission(permissions, permission)
    return permissions and permissions[permission] == true or false
end

---Merge rank permissions with personal overrides
---@param basePermissions table
---@param overrides table
---@return table
function FreeGangs.Utils.MergePermissions(basePermissions, overrides)
    local result = FreeGangs.Utils.DeepCopy(basePermissions)
    for permission, value in pairs(overrides or {}) do
        result[permission] = value
    end
    return result
end

-- ============================================================================
-- BRIBE UTILITIES
-- ============================================================================

---Get bribe contact info
---@param contactType string
---@return table|nil
function FreeGangs.Utils.GetBribeContactInfo(contactType)
    return FreeGangs.BribeContactInfo[contactType]
end

---Check if gang level can access bribe contact
---@param contactType string
---@param masterLevel number
---@return boolean
function FreeGangs.Utils.CanAccessBribeContact(contactType, masterLevel)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    return contactInfo and masterLevel >= contactInfo.minLevel or false
end

---Calculate bribe weekly cost with modifiers
---@param contactType string
---@param archetype string
---@param heatLevel number
---@return number
function FreeGangs.Utils.CalculateBribeCost(contactType, archetype, heatLevel)
    local contactInfo = FreeGangs.BribeContactInfo[contactType]
    if not contactInfo or contactInfo.weeklyCost == 0 then
        return contactInfo and contactInfo.perUseCost or 0
    end
    
    local baseCost = contactInfo.weeklyCost
    local modifier = 1.0
    
    -- Crime Family discount
    if archetype == FreeGangs.Archetypes.CRIME_FAMILY then
        local passives = FreeGangs.ArchetypePassiveBonuses[archetype]
        modifier = modifier - (passives.bribeEffectiveness or 0)
    end
    
    -- Heat increases cost
    if heatLevel >= 90 then
        modifier = modifier + 1.0 -- +100%
    end
    
    return math.floor(baseCost * modifier)
end

-- ============================================================================
-- ACTIVITY POINT UTILITIES
-- ============================================================================

---Get activity point values
---@param activity string
---@return table|nil
function FreeGangs.Utils.GetActivityPoints(activity)
    return FreeGangs.ActivityPoints[activity]
end

---Calculate activity points with archetype bonuses
---@param activity string
---@param archetype string
---@return table {masterRep: number, zoneInfluence: number, heat: number}
function FreeGangs.Utils.CalculateActivityPoints(activity, archetype)
    local basePoints = FreeGangs.ActivityPoints[activity]
    if not basePoints then
        return { masterRep = 0, zoneInfluence = 0, heat = 0 }
    end
    
    local result = FreeGangs.Utils.DeepCopy(basePoints)
    local passives = FreeGangs.ArchetypePassiveBonuses[archetype]
    
    if passives then
        -- Apply archetype bonuses (use math.ceil to ensure bonuses always have effect)
        if activity == FreeGangs.Activities.DRUG_SALE and passives.drugProfit > 0 then
            result.masterRep = math.ceil(result.masterRep * (1 + passives.drugProfit))
        end
        
        if activity == FreeGangs.Activities.GRAFFITI and passives.graffitiLoyalty > 0 then
            result.zoneInfluence = math.floor(result.zoneInfluence * (1 + passives.graffitiLoyalty))
        end
        
        if activity == FreeGangs.Activities.PROTECTION_COLLECT and passives.protectionIncome > 0 then
            result.masterRep = math.floor(result.masterRep * (1 + passives.protectionIncome))
        end
    end
    
    return result
end

-- ============================================================================
-- VECTOR UTILITIES (FiveM specific)
-- ============================================================================

---Calculate distance between two points
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return number
function FreeGangs.Utils.GetDistance(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Calculate 2D distance (ignoring Z)
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function FreeGangs.Utils.GetDistance2D(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

---Check if coords are within radius
---@param coords1 vector3|table
---@param coords2 vector3|table
---@param radius number
---@return boolean
function FreeGangs.Utils.IsWithinRadius(coords1, coords2, radius)
    local x1, y1, z1 = coords1.x or coords1[1], coords1.y or coords1[2], coords1.z or coords1[3]
    local x2, y2, z2 = coords2.x or coords2[1], coords2.y or coords2[2], coords2.z or coords2[3]
    return FreeGangs.Utils.GetDistance(x1, y1, z1, x2, y2, z2) <= radius
end

-- ============================================================================
-- VALIDATION UTILITIES
-- ============================================================================

---Validate gang name format
---@param name string
---@return boolean, string|nil error message
function FreeGangs.Utils.ValidateGangName(name)
    if not name or type(name) ~= 'string' then
        return false, 'Gang name must be a string'
    end
    
    name = FreeGangs.Utils.Trim(name)
    
    if #name < 2 then
        return false, 'Gang name must be at least 2 characters'
    end
    
    if #name > 50 then
        return false, 'Gang name must be 50 characters or less'
    end
    
    if not name:match("^[%w%s%-_]+$") then
        return false, 'Gang name can only contain letters, numbers, spaces, hyphens, and underscores'
    end
    
    return true
end

---Validate color hex code
---@param color string
---@return boolean
function FreeGangs.Utils.ValidateHexColor(color)
    if not color or type(color) ~= 'string' then
        return false
    end
    return color:match("^#%x%x%x%x%x%x$") ~= nil
end

---Validate archetype
---@param archetype string
---@return boolean
function FreeGangs.Utils.ValidateArchetype(archetype)
    for _, validType in pairs(FreeGangs.Archetypes) do
        if archetype == validType then
            return true
        end
    end
    return false
end

-- ============================================================================
-- GANG PAIR UTILITIES (for heat tracking)
-- ============================================================================

---Get ordered gang pair (alphabetically) for consistent heat tracking
---@param gang1 string
---@param gang2 string
---@return string gangA, string gangB
function FreeGangs.Utils.GetOrderedGangPair(gang1, gang2)
    if gang1 < gang2 then
        return gang1, gang2
    else
        return gang2, gang1
    end
end

-- ============================================================================
-- DEBUG UTILITIES
-- ============================================================================

---Print table for debugging
---@param tbl table
---@param indent number|nil
function FreeGangs.Utils.PrintTable(tbl, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    
    for key, value in pairs(tbl) do
        if type(value) == 'table' then
            print(prefix .. tostring(key) .. ":")
            FreeGangs.Utils.PrintTable(value, indent + 1)
        else
            print(prefix .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

---Log with resource name prefix
---@param ... any
function FreeGangs.Utils.Log(...)
    print('[free-gangs]', ...)
end

---Debug log (only if debug mode enabled)
---@param ... any
function FreeGangs.Utils.Debug(...)
    if FreeGangs.Config and FreeGangs.Config.Debug then
        print('[free-gangs:debug]', ...)
    end
end

return FreeGangs.Utils
