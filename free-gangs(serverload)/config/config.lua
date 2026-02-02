--[[
    FREE-GANGS: Main Configuration File
    
    This file contains all configurable settings for the gang system.
    Modify these values to customize the system for your server.
    
    IMPORTANT: After making changes, restart the resource for them to take effect.
]]

FreeGangs.Config = {}

-- ============================================================================
-- GENERAL SETTINGS
-- ============================================================================

FreeGangs.Config.General = {
    -- Debug mode (enables verbose logging)
    Debug = false,
    
    -- Language/locale file to use
    Locale = 'en',
    
    -- Required item to access gang UI (set to nil for no item requirement)
    TabletItem = 'tablet',
    
    -- Discord webhook for admin notifications (leave empty to disable)
    DiscordWebhook = '',
    
    -- Maximum members per gang (0 = unlimited)
    MaxMembersPerGang = 50,
    
    -- Minimum founding members required to create a gang
    MinFoundingMembers = 3,
    
    -- Items required to create a gang (set to empty table {} for no requirements)
    GangCreationItems = {
        { item = 'money', amount = 25000 },
        { item = 'tablet', amount = 1 },
    },
    
    -- Cooldown between creating new gangs (in seconds, per player)
    GangCreationCooldown = 86400, -- 24 hours
}

-- ============================================================================
-- REPUTATION SETTINGS
-- ============================================================================

FreeGangs.Config.Reputation = {
    -- Base decay amount per tick
    DecayAmount = 10,
    
    -- Decay interval in real-world hours
    DecayIntervalHours = 6,
    
    -- Additional decay if gang has 0 territory influence for this many hours
    InactivityDecayHours = 48,
    InactivityDecayAmount = 50,
    
    -- Minimum reputation (can't go below this)
    MinReputation = 0,
    
    -- Point multipliers (adjust to speed up or slow down progression)
    Multipliers = {
        DrugSale = 1.0,
        Mugging = 1.0,
        Graffiti = 1.0,
        Protection = 1.0,
        ZoneCapture = 1.0,
        WarVictory = 1.0,
    },
    
    -- Diminishing returns settings for drug sales
    DiminishingReturns = {
        Enabled = true,
        -- After this many sales per hour, points start reducing
        SalesThreshold = 20,
        -- Minimum multiplier (e.g., 0.2 = 20% of normal points)
        MinMultiplier = 0.2,
        -- How quickly returns diminish (higher = faster diminishing)
        DecayRate = 0.05,
    },
}

-- ============================================================================
-- TERRITORY SETTINGS
-- ============================================================================

FreeGangs.Config.Territory = {
    -- Influence decay per tick (percentage)
    DecayPercentage = 2.0,
    
    -- Decay interval in real-world hours
    DecayIntervalHours = 4,
    
    -- Minimum influence percentage to receive any benefits
    MinInfluenceForBenefits = 10,
    
    -- Majority threshold to "own" a zone
    MajorityThreshold = 51,
    
    -- Cooldown after zone flip before it can flip again (in seconds)
    CaptureCooldownSeconds = 7200, -- 2 hours
    
    -- Presence tick interval (how often presence loyalty is awarded)
    PresenceTickMinutes = 30,
    
    -- Loyalty points per presence tick
    PresenceLoyaltyPoints = 15,
    
    -- Must leave zone for this many minutes before earning presence again
    PresenceResetMinutes = 30,
    
    -- Zone visualization settings
    Visuals = {
        -- Show zone blips on map
        ShowBlips = true,
        
        -- Show 3D markers at zone centers
        ShowMarkers = false,
        
        -- Blip sprite for territories
        BlipSprite = 310,
        
        -- Blip scale
        BlipScale = 0.8,
    },
}

-- ============================================================================
-- HEAT SETTINGS
-- ============================================================================

FreeGangs.Config.Heat = {
    -- Individual heat decay (points per real-world minutes)
    IndividualDecayRate = 1,
    IndividualDecayMinutes = 5,
    
    -- Gang heat decay (points per real-world minutes)
    GangDecayRate = 1,
    GangDecayMinutes = 10,
    
    -- Maximum heat level
    MaxHeat = 100,
    
    -- Heat point values (override enums if needed)
    Points = {
        DrugSale = 1,
        Mugging = 22,
        Pickpocket = 0, -- 10 on failure
        PickpocketFail = 10,
        Graffiti = 5,
        RivalKill = 20,
        ProtectionCollect = 12,
    },
    
    -- Rivalry (Stage 3) effects
    Rivalry = {
        -- Drug profit reduction in contested zones
        ProfitReduction = 0.70, -- 70% reduction
        
        -- Protection collections stopped entirely
        ProtectionStopped = true,
    },
    
    -- Bribe payment frequency changes based on heat
    BribeHeatThresholds = {
        -- At 50+ heat: payment every 5 days instead of 7
        { heat = 50, intervalDays = 5 },
        -- At 75+ heat: payment every 3 days
        { heat = 75, intervalDays = 3 },
        -- At 90+ heat: double cost
        { heat = 90, costMultiplier = 2.0 },
    },
}

-- ============================================================================
-- WAR SETTINGS
-- ============================================================================

FreeGangs.Config.War = {
    -- Minimum heat required to declare war
    MinHeatForWar = 90,
    
    -- Collateral limits
    MinCollateral = 5000,
    MaxCollateral = 100000,
    
    -- Cooldown after war ends before declaring on same gang (in hours)
    SameGangCooldownHours = 48,
    
    -- How long a war declaration stays pending before auto-cancel (in hours)
    PendingTimeoutHours = 24,
    
    -- War chest settings
    WarChest = {
        -- Minimum balance to declare war
        MinBalanceForWar = 5000,
    },
}

-- ============================================================================
-- CRIMINAL ACTIVITY SETTINGS
-- ============================================================================

FreeGangs.Config.Activities = {
    -- Mugging
    Mugging = {
        -- Cooldown between muggings (in seconds)
        PlayerCooldown = 300, -- 5 minutes
        
        -- Loot ranges
        MinCash = 1,
        MaxCash = 200,
        
        -- Loot table (items that can be dropped)
        LootTable = {
            { item = 'phone', chance = 15, min = 1, max = 1 },
            { item = 'wallet', chance = 25, min = 1, max = 1 },
            { item = 'rolex', chance = 5, min = 1, max = 1 },
            { item = 'goldchain', chance = 8, min = 1, max = 1 },
        },
        
        -- Required weapon types (must have one equipped)
        RequiredWeapons = { 'pistol', 'smg' },
        
        -- Maximum distance to target NPC
        MaxDistance = 5.0,
    },
    
    -- Pickpocketing
    Pickpocket = {
        -- Number of loot rolls per successful pickpocket
        LootRolls = 3,
        
        -- Maximum distance to maintain during progress bar
        MaxDistance = 2.0,
        
        -- Loot table (same format as mugging)
        LootTable = {
            { item = 'money', chance = 80, min = 5, max = 50 },
            { item = 'phone', chance = 10, min = 1, max = 1 },
            { item = 'wallet', chance = 15, min = 1, max = 1 },
        },
        
        -- Cooldown before can attempt on same NPC again (even after failure)
        NPCCooldown = 1800, -- 30 minutes
    },
    
    -- Drug Sales
    DrugSales = {
        -- Time restrictions (in-game hours)
        AllowedStartHour = 16, -- 4 PM
        AllowedEndHour = 7, -- 7 AM (next day)
        
        -- Minimum time between sales to same NPC
        NPCSaleCooldown = 30, -- seconds
        
        -- Success chance modifiers
        SuccessChance = {
            Base = 0.60, -- 60%
            OwnTerritory = 0.20, -- +20% in own territory
            RivalTerritory = -0.30, -- -30% in rival territory
        },
        
        -- Price multiplier for controlled territory
        TerritoryPriceBonus = 0.15, -- +15%
        
        -- Drug types that can be sold
        SellableDrugs = {
            'weed_brick',
            'coke_brick',
            'meth',
            'crack',
            'heroin',
            'oxy',
            'lsd',
            'ecstasy',
        },
    },
    
    -- Graffiti
    Graffiti = {
        -- Required item to spray
        RequiredItem = 'spray_can',
        
        -- Item consumed on spray
        ConsumeItem = true,
        
        -- Spray duration in milliseconds
        SprayDuration = 5000,
        
        -- Animation
        Animation = {
            dict = 'switch@franklin@lamar_tagging_wall',
            anim = 'lamar_tagging_wall_loop_lamar',
        },
        
        -- Maximum sprays per player per 6 hours
        MaxSpraysPerCycle = 6,
        CycleDurationHours = 6,
        
        -- Required item to remove graffiti
        RemovalItem = 'cleaning_kit',
        
        -- Removal duration in milliseconds
        RemovalDuration = 8000,
        
        -- Auto-decay settings (set to 0 to disable)
        AutoDecayDays = 0, -- Tags persist until removed or server restart
        
        -- Persist through server restarts (database storage)
        PersistThroughRestart = true,
        
        -- Graffiti visibility distance
        RenderDistance = 100.0,
        
        -- Maximum graffiti per zone
        MaxPerZone = 20,
    },
    
    -- Protection Racket
    Protection = {
        -- Collection interval in real-world hours
        CollectionIntervalHours = 4,
        
        -- Base payout range
        BasePayoutMin = 200,
        BasePayoutMax = 800,
        
        -- Risk of robbery while carrying collection money
        RobberyVulnerability = true,
        
        -- Contested zone payout reduction (per 5% of opposition control)
        ContestedReduction = 0.05, -- -5% per 5% opposition
        
        -- Businesses that can be extorted (identifiers)
        ExtortableBusinesses = {
            '247supermarket',
            'ltdgasoline',
            'robsliquor',
            'binco',
            'suburban',
            'ponsonbys',
            'ammunation',
            'tattoo',
            'barber',
        },
    },
}

-- ============================================================================
-- BRIBE SETTINGS
-- ============================================================================

FreeGangs.Config.Bribes = {
    -- Discovery settings
    Discovery = {
        -- Only officers+ can identify contacts
        MinRankForDiscovery = 2,
        
        -- Contact spawn hours (24-hour format)
        SpawnStartHour = 18, -- 6 PM
        SpawnEndHour = 2, -- 2 AM
    },
    
    -- Approach settings
    Approach = {
        -- Cooldown after failed approach (in hours)
        FailCooldownHours = 6,
        
        -- Reputation loss on failed approach
        FailRepLoss = 20,
        
        -- Time window to provide bribe after successful approach (in minutes)
        BribeWindowMinutes = 10,
        
        -- Reputation loss if bribe window expires
        TimeoutRepLoss = 25,
        
        -- Cooldown after timeout (in hours)
        TimeoutCooldownHours = 24,
    },
    
    -- Maintenance settings
    Maintenance = {
        -- Payment due notification hours before deadline
        NotificationHours = 24,
        
        -- First missed payment penalty
        FirstMissedPenalty = {
            effectsPaused = true,
            costIncrease = 0.50, -- +50%
        },
        
        -- Second missed payment penalty
        SecondMissedPenalty = {
            contactTerminated = true,
            cooldownHours = 48,
            repLoss = 30,
        },
    },
    
    -- Contact-specific settings
    Contacts = {
        -- Beat Cop
        [FreeGangs.BribeContacts.BEAT_COP] = {
            effect = 'Block dispatch for nonviolent crimes in zones >50% control',
        },
        
        -- Dispatcher
        [FreeGangs.BribeContacts.DISPATCHER] = {
            level1Effect = 'All dispatch delayed 60 seconds in zones >50% control',
            level2Effect = 'Redirect police to false location',
            redirectCost = 2000,
            redirectCooldown = 600, -- 10 minutes
        },
        
        -- Detective
        [FreeGangs.BribeContacts.DETECTIVE] = {
            meetingCooldown = 7200, -- 2 hours
            lootTable = {
                { item = 'weapon_pistol', chance = 20, min = 1, max = 1 },
                { item = 'ammo-9', chance = 50, min = 20, max = 50 },
                { item = 'armor', chance = 30, min = 1, max = 1 },
                { item = 'radio', chance = 25, min = 1, max = 1 },
                { item = 'weed_brick', chance = 15, min = 1, max = 3 },
                { item = 'markedbills', chance = 40, min = 1000, max = 5000 },
            },
        },
        
        -- Judge/DA
        [FreeGangs.BribeContacts.JUDGE] = {
            passiveSentenceReduction = 0.30, -- -30%
            reduceSentenceCostPerMin = 1000,
            minSentenceMinutes = 5,
            immediateReleaseCost = 100000,
            releaseCooldown = 300, -- 5 minutes
        },
        
        -- Customs Agent
        [FreeGangs.BribeContacts.CUSTOMS] = {
            -- Discount by master level
            discounts = {
                [5] = 0.15, -- 15% at level 5
                [7] = 0.25, -- 25% at level 7
                [9] = 0.40, -- 40% at level 9
            },
        },
        
        -- Prison Guard
        [FreeGangs.BribeContacts.PRISON_GUARD] = {
            contrabandCost = 2000,
            contrabandCooldown = 3600, -- 1 hour
            helpEscapeCost = 30000,
            helpEscapeCooldown = 600, -- 10 minutes
            -- Prison control bonuses
            controlBonuses = {
                [50] = { freeContraband = true },
                [75] = { reducedEscapeCost = 10000 },
            },
        },
        
        -- City Official
        [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
            initialBribe = 20000,
            maintenancePercent = 0.25, -- 25% of initial
            kickbackInterval = 7200, -- 2 hours (seconds)
            kickbackRanges = {
                [FreeGangs.Archetypes.STREET] = { min = 2000, max = 8000, multiplier = 1.0 },
                [FreeGangs.Archetypes.MC] = { min = 2000, max = 8000, multiplier = 2.0 },
                [FreeGangs.Archetypes.CARTEL] = { min = 2000, max = 8000, multiplier = 2.5 },
                [FreeGangs.Archetypes.CRIME_FAMILY] = { min = 2000, max = 8000, multiplier = 2.5 },
            },
        },
    },
}

-- ============================================================================
-- ARMS TRAFFICKING SETTINGS
-- ============================================================================

FreeGangs.Config.ArmsTrafficking = {
    -- Minimum master level to access distribution network
    DistributionMinLevel = 5,
    
    -- Minimum master level for acquisition missions (Cartel/Crime Family only)
    AcquisitionMinLevel = 8,
    
    -- Weekly tribute to distributor
    WeeklyTribute = 5000,
    
    -- Missed tribute penalty
    MissedTributePenalty = 0.50, -- +50% to unlock again
    
    -- Order settings
    Orders = {
        -- Minimum time to complete order (seconds)
        MinDeliveryTime = 300, -- 5 minutes
        
        -- Maximum time to complete order (seconds)
        MaxDeliveryTime = 1800, -- 30 minutes
        
        -- Ambush chance base percentage
        AmbushChance = 0.15, -- 15%
        
        -- Ambush chance reduction per relationship level
        AmbushReductionPerLevel = 0.02, -- -2% per level
    },
    
    -- Relationship settings
    Relationship = {
        -- Points needed per level
        PointsPerLevel = 100,
        
        -- Max relationship level
        MaxLevel = 10,
        
        -- Points earned per successful delivery
        PointsPerDelivery = 10,
        
        -- Points lost per failed delivery
        PointsLostPerFail = 25,
    },
}

-- ============================================================================
-- STASH SETTINGS
-- ============================================================================

FreeGangs.Config.Stash = {
    -- Base stash settings
    GangStash = {
        BaseSlots = 50,
        BaseWeight = 100000,
        -- Additional slots per master level
        SlotsPerLevel = 10,
    },
    
    WarChest = {
        Slots = 20,
        Weight = 50000,
    },
    
    PersonalLocker = {
        Slots = 25,
        Weight = 50000,
    },
    
    -- Allow leaders to move stash locations
    AllowStashRelocation = true,
    
    -- Cooldown between stash relocations (in hours)
    RelocationCooldownHours = 24,
}

-- ============================================================================
-- UI SETTINGS
-- ============================================================================

FreeGangs.Config.UI = {
    -- Theme settings (Godfather-inspired)
    Theme = {
        PrimaryColor = '#8B0000', -- Dark red
        SecondaryColor = '#1a1a1a', -- Near black
        AccentColor = '#D4AF37', -- Gold
        TextColor = '#FFFFFF',
        FontFamily = 'Cinzel', -- Elegant serif font
    },
    
    -- Notification settings
    Notifications = {
        Position = 'top-right',
        DefaultDuration = 5000, -- ms
    },
    
    -- Gang menu keybind (set to nil to disable keybind)
    MenuKeybind = 'F6',
    
    -- Show territory info on HUD when in zone
    ShowTerritoryHUD = true,
}

-- ============================================================================
-- PRISON ZONE SETTINGS
-- ============================================================================

FreeGangs.Config.Prison = {
    -- Zone name identifier
    ZoneName = 'bolingbroke',
    
    -- Control thresholds for benefits
    ControlBenefits = {
        [30] = { 'prison_guard_access' },
        [50] = { 'free_contraband' },
        [51] = { 'free_prison_bribes' },
        [75] = { 'reduced_escape_cost' },
    },
    
    -- Smuggle mission settings
    SmuggleMissions = {
        -- Must have a member jailed to unlock
        RequireJailedMember = true,
        
        -- Payout range
        MinPayout = 2000,
        MaxPayout = 8000,
        
        -- Cooldown between missions (seconds)
        Cooldown = 1800, -- 30 minutes
    },
}

-- ============================================================================
-- ARCHETYPE-SPECIFIC SETTINGS
-- ============================================================================

FreeGangs.Config.ArchetypeSettings = {
    -- Street Gang: Main Corner
    [FreeGangs.Archetypes.STREET] = {
        MainCorner = {
            -- Bonus rep per sale in main corner zone
            BonusRepPerSale = 5,
            -- Only one main corner per gang
            MaxMainCorners = 1,
        },
        BlockParty = {
            -- Loyalty multiplier during event
            LoyaltyMultiplier = 2.0,
            -- Duration in seconds
            Duration = 3600, -- 1 hour
            -- Cooldown in seconds
            Cooldown = 86400, -- 24 hours
        },
        DriveByContracts = {
            -- Contract payout range
            MinPayout = 5000,
            MaxPayout = 15000,
            -- Rep bonus
            RepBonus = 50,
            -- Cooldown in seconds
            Cooldown = 7200, -- 2 hours
        },
    },
    
    -- MC: Club activities
    [FreeGangs.Archetypes.MC] = {
        ProspectRuns = {
            -- Passive income range per run
            MinIncome = 500,
            MaxIncome = 2000,
            -- Interception chance
            InterceptionChance = 0.20, -- 20%
            -- Run duration in minutes
            Duration = 30,
        },
        ClubRuns = {
            -- Minimum members required
            MinMembers = 4,
            -- Payout per member
            PayoutPerMember = 2500,
            -- Bonus for full club (10+ members)
            FullClubBonus = 0.25, -- +25%
            -- Cooldown in seconds
            Cooldown = 14400, -- 4 hours
        },
        TerritoryRide = {
            -- Loyalty bonus per zone passed
            LoyaltyPerZone = 5,
            -- Minimum zones to visit for bonus
            MinZones = 3,
            -- Cooldown in seconds
            Cooldown = 21600, -- 6 hours
        },
    },
    
    -- Cartel: Network activities
    [FreeGangs.Archetypes.CARTEL] = {
        HalconNetwork = {
            -- Minimum zone control for alerts
            MinZoneControl = 25,
            -- Alert cooldown per player (seconds)
            AlertCooldown = 60,
        },
        ConvoyProtection = {
            -- Base payout
            BasePayout = 10000,
            -- Bonus for zero casualties
            NoCasualtyBonus = 0.50, -- +50%
            -- Cooldown in seconds
            Cooldown = 10800, -- 3 hours
        },
        PlazaSystem = {
            -- Minimum zones for plaza benefits
            MinZones = 3,
            -- Bulk pricing discount
            BulkDiscount = 0.15, -- 15%
        },
    },
    
    -- Crime Family: Business activities
    [FreeGangs.Archetypes.CRIME_FAMILY] = {
        TributeNetwork = {
            -- Percentage cut from NPC sales in controlled zones
            TributeCut = 0.05, -- 5%
        },
        HighValueContracts = {
            -- Rep multiplier for heists
            HeistRepMultiplier = 1.5,
        },
        PoliticalImmunity = {
            -- Bribe cost reduction
            BribeCostReduction = 0.40, -- 40%
            -- Bribe effect enhancement
            BribeEffectBonus = 0.25, -- +25%
            -- Access all bribes regardless of zone control
            IgnoreZoneRequirements = true,
        },
        CityOfficialMaintenance = {
            -- Reduced maintenance for Crime Families
            MaintenancePercent = 0.10, -- 10% instead of 25%
        },
    },
}

-- ============================================================================
-- NOTIFICATION MESSAGES
-- ============================================================================

FreeGangs.Config.Messages = {
    -- Gang management
    GangCreated = 'Your gang %s has been established!',
    GangDeleted = 'Gang %s has been disbanded.',
    MemberJoined = '%s has joined the gang.',
    MemberLeft = '%s has left the gang.',
    MemberKicked = '%s has been kicked from the gang.',
    MemberPromoted = '%s has been promoted to %s.',
    MemberDemoted = '%s has been demoted to %s.',
    
    -- Reputation
    RepGained = '+%d reputation',
    RepLost = '-%d reputation',
    LevelUp = 'Gang reached Level %d: %s!',
    LevelDown = 'Gang dropped to Level %d: %s.',
    
    -- Territory
    TerritoryEntered = 'Entering %s territory',
    TerritoryExited = 'Leaving %s territory',
    ZoneCaptured = 'Your gang now controls %s!',
    ZoneLost = 'Your gang has lost control of %s!',
    ZoneContested = '%s is being contested by rivals!',
    
    -- Heat & War
    HeatIncreased = 'Heat with %s increased to %d',
    StageChanged = 'Relations with %s escalated to %s',
    WarDeclared = '%s has declared war on your gang!',
    WarAccepted = 'War with %s has begun!',
    WarEnded = 'War with %s has ended. %s',
    
    -- Activities
    MuggingSuccess = 'Mugging successful! Got %s',
    PickpocketSuccess = 'Pickpocket successful!',
    PickpocketFail = 'Pickpocket failed! You\'ve been spotted!',
    DrugSaleSuccess = 'Sold %s for %s',
    DrugSaleFail = 'Customer rejected the deal.',
    GraffitiSprayed = 'Tag sprayed! +%d zone influence',
    GraffitiRemoved = 'Rival tag removed!',
    ProtectionCollected = 'Collected %s in protection money',
    
    -- Bribes
    BribeEstablished = '%s is now on your payroll.',
    BribeFailed = 'The contact rejected your approach.',
    BribeDue = 'Payment due to %s within 24 hours.',
    BribeMissed = '%s contact has been lost due to missed payment.',
    BribeUsed = 'Bribe ability activated.',
    
    -- Errors
    NotInGang = 'You are not in a gang.',
    NoPermission = 'You don\'t have permission to do this.',
    InsufficientFunds = 'Insufficient funds.',
    OnCooldown = 'This action is on cooldown. %s remaining.',
    InvalidTarget = 'Invalid target.',
    TooFarAway = 'You are too far away.',
}

-- ============================================================================
-- ADMIN SETTINGS
-- ============================================================================

FreeGangs.Config.Admin = {
    -- Ace permission required for admin commands
    AcePermission = 'freegangs.admin',
    
    -- Log retention (days, 0 = keep forever)
    LogRetentionDays = 30,
    
    -- Discord webhook for admin alerts
    AdminAlertWebhook = '',
    
    -- Events that trigger admin alerts
    AlertEvents = {
        'gang_created',
        'gang_deleted',
        'war_declared',
        'war_ended',
        'suspicious_activity',
    },
}

-- Make config globally accessible
FreeGangs.Debug = FreeGangs.Config.General.Debug

return FreeGangs.Config
