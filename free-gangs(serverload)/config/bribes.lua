--[[
    FREE-GANGS: Bribery System Configuration
    
    Defines all bribe contact spawn locations, schedules, abilities,
    and related configuration values.
]]

FreeGangs.Config = FreeGangs.Config or {}
FreeGangs.Config.BribeContacts = {}

-- ============================================================================
-- CONTACT SPAWN LOCATIONS
-- ============================================================================
-- Each contact type has multiple potential spawn locations
-- NPCs will spawn at these locations during their active hours

FreeGangs.Config.BribeContacts.SpawnLocations = {
    [FreeGangs.BribeContacts.BEAT_COP] = {
        -- Spawn at various city locations (donut shops, parking lots, etc.)
        {
            coords = vector4(135.8, -1039.5, 29.3, 340.0),
            label = 'Legion Square Area',
            pedModel = 's_m_y_cop_01',
        },
        {
            coords = vector4(-1196.1, -889.5, 14.0, 35.0),
            label = 'Vespucci Beach',
            pedModel = 's_m_y_cop_01',
        },
        {
            coords = vector4(428.6, -979.5, 30.7, 0.0),
            label = 'Pillbox Hill',
            pedModel = 's_m_y_cop_01',
        },
        {
            coords = vector4(-705.6, -154.5, 37.4, 120.0),
            label = 'Rockford Hills',
            pedModel = 's_m_y_cop_01',
        },
    },
    
    [FreeGangs.BribeContacts.DISPATCHER] = {
        -- Spawn near LSPD stations but not too close
        {
            coords = vector4(428.8, -1017.6, 28.7, 5.0),
            label = 'Mission Row Area',
            pedModel = 's_f_y_dispatcher',
        },
        {
            coords = vector4(-439.8, 6019.5, 31.5, 45.0),
            label = 'Paleto Bay Area',
            pedModel = 's_f_y_dispatcher',
        },
        {
            coords = vector4(1854.8, 3687.5, 34.3, 210.0),
            label = 'Sandy Shores Area',
            pedModel = 's_m_m_911operator_01',
        },
    },
    
    [FreeGangs.BribeContacts.DETECTIVE] = {
        -- Spawn at bars, motels, secluded areas
        {
            coords = vector4(197.8, -935.2, 30.7, 145.0),
            label = 'Downtown Bar',
            pedModel = 's_m_y_cop_01',
            scenario = 'WORLD_HUMAN_SMOKING',
        },
        {
            coords = vector4(-560.8, 286.4, 82.2, 80.0),
            label = 'West Vinewood',
            pedModel = 's_m_y_cop_01',
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        {
            coords = vector4(1392.5, 3614.5, 38.9, 200.0),
            label = 'Sandy Shores Motel',
            pedModel = 's_m_y_cop_01',
            scenario = 'WORLD_HUMAN_LEANING',
        },
    },
    
    [FreeGangs.BribeContacts.JUDGE] = {
        -- Spawn near courthouse, upscale restaurants
        {
            coords = vector4(252.4, -1072.2, 29.3, 185.0),
            label = 'Courthouse Steps',
            pedModel = 's_m_m_lawyer_01',
            scenario = 'WORLD_HUMAN_SMOKING',
        },
        {
            coords = vector4(-456.5, 264.8, 83.3, 270.0),
            label = 'Vinewood Hills',
            pedModel = 's_m_m_lawyer_01',
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
    },
    
    [FreeGangs.BribeContacts.CUSTOMS] = {
        -- Spawn near docks, airport
        {
            coords = vector4(1211.8, -3117.5, 5.9, 90.0),
            label = 'Port of Los Santos',
            pedModel = 's_m_y_dockwork_01',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        {
            coords = vector4(-1020.5, -2455.5, 13.9, 130.0),
            label = 'LSIA Cargo Area',
            pedModel = 's_m_y_dockwork_01',
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
        },
    },
    
    [FreeGangs.BribeContacts.PRISON_GUARD] = {
        -- Spawn near Bolingbroke
        {
            coords = vector4(1845.7, 2604.8, 45.6, 270.0),
            label = 'Bolingbroke Entrance',
            pedModel = 's_m_m_prisguard_01',
            scenario = 'WORLD_HUMAN_GUARD_PATROL',
        },
        {
            coords = vector4(1690.3, 2565.5, 45.6, 180.0),
            label = 'Bolingbroke Side Gate',
            pedModel = 's_m_m_prisguard_01',
            scenario = 'WORLD_HUMAN_STAND_GUARD',
        },
    },
    
    [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
        -- Spawn at City Hall, upscale locations
        {
            coords = vector4(-535.5, -220.5, 37.6, 300.0),
            label = 'City Hall Steps',
            pedModel = 'a_m_m_business_01',
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
        },
        {
            coords = vector4(-74.8, -818.5, 326.2, 65.0),
            label = 'Maze Bank Tower Lobby',
            pedModel = 'a_m_m_business_01',
            scenario = 'WORLD_HUMAN_AA_SMOKE',
        },
    },
}

-- ============================================================================
-- CONTACT SPAWN SCHEDULES
-- ============================================================================
-- Defines when contacts are active (in-game hours, 24-hour format)

FreeGangs.Config.BribeContacts.Schedules = {
    [FreeGangs.BribeContacts.BEAT_COP] = {
        startHour = 18,  -- 6 PM
        endHour = 2,     -- 2 AM (next day)
        daysActive = { 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday' },
    },
    [FreeGangs.BribeContacts.DISPATCHER] = {
        startHour = 20,  -- 8 PM
        endHour = 4,     -- 4 AM
        daysActive = { 'tuesday', 'thursday', 'saturday' },
    },
    [FreeGangs.BribeContacts.DETECTIVE] = {
        startHour = 21,  -- 9 PM
        endHour = 3,     -- 3 AM
        daysActive = { 'wednesday', 'friday', 'sunday' },
    },
    [FreeGangs.BribeContacts.JUDGE] = {
        startHour = 19,  -- 7 PM
        endHour = 23,    -- 11 PM
        daysActive = { 'monday', 'friday' },
    },
    [FreeGangs.BribeContacts.CUSTOMS] = {
        startHour = 22,  -- 10 PM
        endHour = 6,     -- 6 AM
        daysActive = { 'monday', 'wednesday', 'saturday' },
    },
    [FreeGangs.BribeContacts.PRISON_GUARD] = {
        startHour = 0,   -- Midnight
        endHour = 5,     -- 5 AM
        daysActive = { 'tuesday', 'thursday', 'sunday' },
    },
    [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
        startHour = 18,  -- 6 PM
        endHour = 22,    -- 10 PM
        daysActive = { 'thursday', 'saturday' },
    },
}

-- ============================================================================
-- CONTACT VISUAL TELLS
-- ============================================================================
-- Visual indicators to help identify contacts (nervous behavior, clothing)

FreeGangs.Config.BribeContacts.VisualTells = {
    [FreeGangs.BribeContacts.BEAT_COP] = {
        description = 'Cop without partner, looking around nervously',
        clothingDetails = { 'Off-duty attire', 'Unmarked jacket' },
        behaviors = { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_IMPATIENT' },
    },
    [FreeGangs.BribeContacts.DISPATCHER] = {
        description = 'Radio operator alone outside during late hours',
        clothingDetails = { 'Civilian clothes with radio earpiece' },
        behaviors = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_SMOKING' },
    },
    [FreeGangs.BribeContacts.DETECTIVE] = {
        description = 'Plainclothes cop in bars or secluded areas after dark',
        clothingDetails = { 'Rumpled suit', 'Badge hidden' },
        behaviors = { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_LEANING' },
    },
    [FreeGangs.BribeContacts.JUDGE] = {
        description = 'Well-dressed professional near courthouse at unusual hours',
        clothingDetails = { 'Expensive suit', 'Briefcase' },
        behaviors = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_AA_SMOKE' },
    },
    [FreeGangs.BribeContacts.CUSTOMS] = {
        description = 'Dock worker with clipboard near shipping containers',
        clothingDetails = { 'Safety vest', 'Clipboard', 'Radio' },
        behaviors = { 'WORLD_HUMAN_CLIPBOARD', 'WORLD_HUMAN_STAND_MOBILE' },
    },
    [FreeGangs.BribeContacts.PRISON_GUARD] = {
        description = 'Guard alone near prison perimeter during night shift',
        clothingDetails = { 'Prison guard uniform', 'Keychain' },
        behaviors = { 'WORLD_HUMAN_GUARD_PATROL', 'WORLD_HUMAN_SMOKING' },
    },
    [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
        description = 'Nervous politician avoiding main entrances',
        clothingDetails = { 'Expensive suit', 'Gold watch', 'Briefcase' },
        behaviors = { 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_AA_SMOKE' },
    },
}

-- ============================================================================
-- CONTACT ABILITIES DETAILED
-- ============================================================================

FreeGangs.Config.BribeContacts.Abilities = {
    [FreeGangs.BribeContacts.BEAT_COP] = {
        passive = {
            name = 'dispatch_block',
            description = 'Auto-block dispatch for nonviolent crimes in zones >50% control',
            zoneControlRequired = 50,
        },
        active = nil, -- No active ability
    },
    
    [FreeGangs.BribeContacts.DISPATCHER] = {
        passive = {
            name = 'dispatch_delay',
            description = 'All dispatch delayed 60 seconds in zones >50% control',
            delaySeconds = 60,
            zoneControlRequired = 50,
        },
        active = {
            name = 'dispatch_redirect',
            description = 'Send police to false location',
            cost = 2000,
            cooldownSeconds = 600, -- 10 minutes
            requiredLevel = 5, -- Master level 5 required
            heatGenerated = 10,
        },
    },
    
    [FreeGangs.BribeContacts.DETECTIVE] = {
        passive = nil,
        active = {
            name = 'evidence_exchange',
            description = 'Meet detective for contraband exchange',
            cost = 0, -- No per-use cost, just weekly maintenance
            cooldownSeconds = 7200, -- 2 hours
            heatGenerated = 8,
            lootTable = {
                { item = 'weapon_pistol', chance = 20, min = 1, max = 1 },
                { item = 'ammo-9', chance = 50, min = 20, max = 50 },
                { item = 'armor', chance = 30, min = 1, max = 1 },
                { item = 'radio', chance = 25, min = 1, max = 1 },
                { item = 'weed_brick', chance = 15, min = 1, max = 3 },
                { item = 'markedbills', chance = 40, min = 1000, max = 5000 },
            },
        },
    },
    
    [FreeGangs.BribeContacts.JUDGE] = {
        passive = {
            name = 'sentence_reduction',
            description = '-30% jail sentences for all gang members',
            reductionPercent = 0.30,
        },
        active = {
            name = 'courthouse_visit',
            description = 'Reduce sentence or release prisoner',
            options = {
                reduce_sentence = {
                    costPerMinute = 1000,
                    minSentenceMinutes = 5,
                    heatGenerated = 10,
                },
                immediate_release = {
                    cost = 100000,
                    cooldownSeconds = 300, -- 5 minutes
                    heatGenerated = 15,
                },
            },
        },
    },
    
    [FreeGangs.BribeContacts.CUSTOMS] = {
        passive = nil,
        active = {
            name = 'arms_discount',
            description = 'Reduced cost on arms trafficking',
            -- Discount scales with master level
            discountByLevel = {
                [5] = 0.15, -- 15%
                [7] = 0.25, -- 25%
                [9] = 0.40, -- 40%
            },
            heatGenerated = 5,
        },
    },
    
    [FreeGangs.BribeContacts.PRISON_GUARD] = {
        passive = nil,
        active = {
            name = 'prison_services',
            description = 'Contraband delivery or help escape',
            options = {
                contraband_delivery = {
                    cost = 2000,
                    cooldownSeconds = 3600, -- 1 hour
                    heatGenerated = 8,
                    allowedItems = { 'weapon_switchblade', 'phone', 'radio', 'joint', 'sandwich' },
                },
                help_escape = {
                    cost = 30000,
                    cooldownSeconds = 600, -- 10 minutes
                    heatGenerated = 15,
                },
            },
            -- Prison control bonuses
            prisonControlBonuses = {
                [50] = { freeContraband = true },
                [75] = { reducedEscapeCost = 10000 },
            },
        },
    },
    
    [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
        passive = {
            name = 'kickback_payments',
            description = 'Return every 2 hours for kickback payment',
            intervalSeconds = 7200, -- 2 hours
            payoutRanges = {
                [FreeGangs.Archetypes.STREET] = { min = 2000, max = 8000, multiplier = 1.0 },
                [FreeGangs.Archetypes.MC] = { min = 2000, max = 8000, multiplier = 2.0 },
                [FreeGangs.Archetypes.CARTEL] = { min = 2000, max = 8000, multiplier = 2.5 },
                [FreeGangs.Archetypes.CRIME_FAMILY] = { min = 2000, max = 8000, multiplier = 2.5 },
            },
        },
        active = nil,
    },
}

-- ============================================================================
-- APPROACH DIALOGUE OPTIONS
-- ============================================================================

FreeGangs.Config.BribeContacts.DialogueOptions = {
    initial = {
        title = 'Approach Contact',
        description = 'This person looks like they might be open to... persuasion.',
        options = {
            { label = 'Make an offer', value = 'offer' },
            { label = 'Walk away', value = 'cancel' },
        },
    },
    
    offer_response = {
        success = {
            title = 'Interested',
            description = 'The contact seems interested in your proposal.',
            requirementText = 'They want %s to seal the deal.',
        },
        failure = {
            title = 'Rejected',
            description = 'The contact wants nothing to do with you.',
            cooldownText = 'Your gang cannot approach contacts for %s.',
        },
    },
    
    establish_confirm = {
        title = 'Establish Contact',
        description = 'Are you sure you want to establish this contact?\n\n**Weekly Cost:** %s\n**First Payment Due:** %s',
    },
}

-- ============================================================================
-- PAYMENT REMINDER SETTINGS
-- ============================================================================

FreeGangs.Config.BribeContacts.PaymentReminders = {
    -- Hours before due date to send reminder
    reminderHours = { 24, 6, 1 },
    
    -- Penalty multipliers
    penalties = {
        firstMiss = {
            costIncrease = 0.50, -- +50%
            effectsPaused = true,
        },
        secondMiss = {
            terminated = true,
            cooldownHours = 48,
            repLoss = 30,
        },
    },
}

-- ============================================================================
-- SPAWN INTERVALS
-- ============================================================================

FreeGangs.Config.BribeContacts.SpawnSettings = {
    -- How often to check/spawn contacts (in seconds)
    spawnCheckInterval = 60,
    
    -- How long a contact stays spawned (in seconds)
    contactDuration = 900, -- 15 minutes
    
    -- Maximum contacts spawned at once per type
    maxSpawnedPerType = 1,
    
    -- Distance to despawn contacts (squared for performance)
    despawnDistanceSq = 150.0 * 150.0,
    
    -- Distance player must be to see/interact with contact
    interactionDistance = 3.0,
}

return FreeGangs.Config.BribeContacts
