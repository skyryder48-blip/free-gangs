--[[
    FREE-GANGS: Archetype Configuration
    
    Extended configuration for archetype-specific mechanics including
    tier activities, passive bonuses, and special features.
]]

FreeGangs = FreeGangs or {}
FreeGangs.Config = FreeGangs.Config or {}

-- ============================================================================
-- ARCHETYPE TIER REQUIREMENTS
-- ============================================================================

FreeGangs.Config.ArchetypeTiers = {
    -- Master level required for each tier
    [1] = 4,  -- Tier 1 unlocks at level 4 (Respected)
    [2] = 6,  -- Tier 2 unlocks at level 6 (Feared)
    [3] = 8,  -- Tier 3 unlocks at level 8 (Legendary)
}

-- ============================================================================
-- STREET GANG EXTENDED SETTINGS
-- ============================================================================

FreeGangs.Config.StreetGang = {
    -- Main Corner (Tier 1)
    MainCorner = {
        -- Bonus reputation per drug sale in main corner
        BonusRepPerSale = 5,
        -- Maximum main corners per gang
        MaxCorners = 1,
        -- Minimum zone control to set as main corner
        MinZoneControl = 25,
        -- Radius around zone center for bonus (in game units)
        BonusRadius = 100.0,
        -- Visual marker settings
        Marker = {
            enabled = true,
            type = 1, -- Cylinder
            color = { r = 0, g = 255, b = 0, a = 100 },
            size = { x = 2.0, y = 2.0, z = 1.0 },
        },
    },
    
    -- Block Party (Tier 2)
    BlockParty = {
        -- Loyalty multiplier during event
        LoyaltyMultiplier = 2.0,
        -- Duration in seconds (1 hour)
        Duration = 3600,
        -- Cooldown in seconds (24 hours)
        Cooldown = 86400,
        -- Minimum members online to start
        MinMembersOnline = 3,
        -- Zone control requirement
        MinZoneControl = 51,
        -- Notification radius for non-gang members (they can see the party)
        NotificationRadius = 200.0,
        -- Ambient effects
        Effects = {
            music = true,
            particles = true,
            npcs = true, -- Spawn party NPCs
        },
    },
    
    -- Drive-By Contracts (Tier 3)
    -- Target NPCs in opposing gang territories
    -- Time-based mission with influence gain/loss mechanics
    DriveByContracts = {
        -- Base payout range
        MinPayout = 5000,
        MaxPayout = 15000,
        -- Reputation bonus on completion
        RepBonus = 50,
        -- Territory influence gained on success
        InfluenceGain = 5,
        -- Heat generated with target gang
        HeatGenerated = 25,
        -- Time limit in minutes
        TimeLimitMinutes = 15,
        -- Cooldown in seconds (2 hours)
        Cooldown = 7200,
        -- Maximum active contracts per gang (now 1 at a time)
        MaxActiveContracts = 1,
        -- Target NPC configuration
        Targets = {
            -- Models for target NPCs in enemy territory
            models = {
                'a_m_y_mexthug_01',
                'g_m_y_ballasout_01',
                'g_m_y_famfor_01',
                'g_m_y_lost_01',
                'g_m_y_salvaboss_01',
            },
            -- Escort chance (target has bodyguards)
            escortChance = 0.30,
            -- Number of escorts when spawned
            minEscorts = 1,
            maxEscorts = 3,
        },
        -- Failure penalties
        FailurePenalty = {
            repLoss = 25,
            influenceLoss = 3, -- Lost ground in target territory
            cooldownMultiplier = 1.5, -- Extended cooldown on failure
        },
    },
}

-- ============================================================================
-- MC EXTENDED SETTINGS
-- ============================================================================

FreeGangs.Config.MC = {
    -- Prospect Runs (Tier 1)
    -- Item delivery missions with ambush risks
    -- Required items, destination delivery, loot table rewards
    ProspectRuns = {
        -- Time limit in minutes
        TimeLimitMinutes = 20,
        -- Cooldown per prospect (seconds)
        Cooldown = 3600, -- 1 hour
        -- Requires motorcycle
        RequiresBike = true,
        -- Bike models that count
        ValidBikeModels = {
            'bagger', 'daemon', 'daemon2', 'diablous', 'diablous2',
            'double', 'hexer', 'innovation', 'nightblade', 'ratbike',
            'sanctus', 'wolfsbane', 'zombiea', 'zombieb', 'avarus',
            'chimera', 'cliffhanger', 'esskey', 'faggio', 'faggio2',
            'faggio3', 'gargoyle', 'hakuchou', 'hakuchou2', 'manchez',
            'nemesis', 'pcj', 'ruffian', 'sovereign', 'thrust',
            'vader', 'vindicator', 'vortex', 'defiler', 'lectro',
            'bf400', 'carbonrs', 'enduro', 'sanchez', 'sanchez2',
        },
        -- Items that can be required for delivery
        DeliveryItems = {
            { name = 'weed_bag', label = 'Weed Bag', minCount = 5, maxCount = 15, weight = 1 },
            { name = 'coke_brick', label = 'Cocaine Brick', minCount = 2, maxCount = 5, weight = 0.7 },
            { name = 'meth_bag', label = 'Meth Bag', minCount = 3, maxCount = 8, weight = 0.6 },
            { name = 'pistol_ammo', label = 'Pistol Ammo', minCount = 50, maxCount = 100, weight = 0.5 },
            { name = 'weapon_pistol', label = 'Pistol', minCount = 1, maxCount = 2, weight = 0.3 },
        },
        MinDeliveryItems = 1,
        MaxDeliveryItems = 3,
        -- Destination ambush/doublecross (DECREASES with gang rep)
        DestinationAmbushChance = 0.25, -- 25% base chance
        -- Route ambush by NPC bikers
        RouteAmbush = {
            SpawnChance = 0.40, -- 40% chance of route ambush
            BaseNPCCount = 2,   -- Starting NPCs (INCREASES with gang rep)
            MaxNPCCount = 6,    -- Maximum NPCs
            NPCModels = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03' },
            Vehicles = { 'daemon', 'hexer', 'zombieb' },
        },
        -- Reputation rewards
        RepGain = 15,
        -- Territory influence gains
        TrapSpotInfluenceGain = 3,
        DestinationInfluenceGain = 5,
        -- Failure penalty
        FailureRepLoss = 10,
        -- Loot table for rewards
        LootTable = {
            { type = 'money', amount = { min = 500, max = 2000 }, chance = 1.0 },
            { type = 'item', name = 'lockpick', label = 'Lockpick', count = { min = 1, max = 3 }, chance = 0.3 },
            { type = 'item', name = 'radio', label = 'Radio', count = { min = 1, max = 1 }, chance = 0.2 },
        },
        -- Default destinations if no territories
        DefaultDestinations = {
            { name = 'sandy_shores', label = 'Sandy Shores', coords = vector3(1960.0, 3740.0, 32.0) },
            { name = 'paleto_bay', label = 'Paleto Bay', coords = vector3(-224.0, 6218.0, 31.0) },
        },
    },
    
    -- Club Runs (Tier 2)
    -- Scaled-up version of prospect runs requiring 4+ members
    -- Larger item requirements, more NPCs, higher rewards
    ClubRuns = {
        -- Minimum members required
        MinMembers = 4,
        -- Time limit in minutes
        TimeLimitMinutes = 20,
        -- Cooldown in seconds (4 hours)
        Cooldown = 14400,
        -- Scaled-up delivery items (more quantity)
        DeliveryItems = {
            { name = 'weed_bag', label = 'Weed Bag', minCount = 20, maxCount = 50, weight = 1 },
            { name = 'coke_brick', label = 'Cocaine Brick', minCount = 5, maxCount = 15, weight = 0.8 },
            { name = 'meth_bag', label = 'Meth Bag', minCount = 10, maxCount = 25, weight = 0.7 },
            { name = 'pistol_ammo', label = 'Pistol Ammo', minCount = 200, maxCount = 500, weight = 0.6 },
            { name = 'weapon_pistol', label = 'Pistol', minCount = 3, maxCount = 8, weight = 0.4 },
            { name = 'weapon_smg', label = 'SMG', minCount = 1, maxCount = 3, weight = 0.2 },
        },
        MinDeliveryItems = 3,
        MaxDeliveryItems = 5,
        -- Higher destination ambush chance (starts higher, decreases with rep)
        DestinationAmbushChance = 0.40,
        -- MORE intense route ambush
        RouteAmbush = {
            SpawnChance = 0.60,
            BaseNPCCount = 4,
            MaxNPCCount = 10,
            NPCModels = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03' },
            Vehicles = { 'daemon', 'hexer', 'zombieb', 'nightblade' },
        },
        -- Higher rewards
        RepGain = 50,
        DestinationInfluenceGain = 10,
        FailureRepLoss = 30,
        -- Better loot table
        LootTable = {
            { type = 'money', amount = { min = 2000, max = 8000 }, chance = 1.0 },
            { type = 'item', name = 'lockpick', label = 'Lockpick', count = { min = 2, max = 5 }, chance = 0.5 },
            { type = 'item', name = 'radio', label = 'Radio', count = { min = 1, max = 2 }, chance = 0.4 },
            { type = 'item', name = 'weapon_pistol', label = 'Pistol', count = { min = 1, max = 1 }, chance = 0.2 },
        },
    },
    
    -- Territory Ride (Tier 3)
    -- Patrol-style activity affecting ALL territories (owned AND opposition)
    -- Requires 3+ members in proximity, all on motorcycles
    -- More members = increased influence gain
    TerritoryRide = {
        -- Minimum members required to activate and maintain benefits
        MinMembers = 3,
        -- Proximity radius - all riders must stay within this distance of leader
        ProximityRadius = 50.0,
        -- Base influence per zone visited
        BaseInfluencePerZone = 3,
        -- Opposition zone multiplier (intimidation factor)
        OppositionZoneMultiplier = 1.5,
        -- Time between zone influence gains (prevents rapid back-and-forth)
        ZoneEntryGap = 60, -- 1 minute
        -- Minimum zones to visit for completion bonus
        MinZonesForBonus = 5,
        -- Reputation bonus for completing ride with enough zones
        CompletionRepBonus = 50,
        -- Cooldown in seconds (6 hours)
        Cooldown = 21600,
        -- Member count bonus multipliers (more riders = more influence)
        MemberBonus = {
            ['3'] = 1.0,  -- 3 members: base (100%)
            ['4'] = 1.25, -- 4 members: +25%
            ['5'] = 1.50, -- 5 members: +50%
            ['6'] = 1.75, -- 6 members: +75%
            ['7'] = 2.0,  -- 7+ members: +100% (double)
        },
    },
}

-- ============================================================================
-- CARTEL EXTENDED SETTINGS
-- ============================================================================

FreeGangs.Config.Cartel = {
    -- Halcon Network (Tier 1)
    HalconNetwork = {
        -- Minimum zone control for alerts
        MinZoneControl = 25,
        -- Alert cooldown per player entering (seconds)
        AlertCooldown = 60,
        -- Alert types
        AlertTypes = {
            rival = true,   -- Alert when rival gang members enter
            police = true,  -- Alert when police enter
            unknown = true, -- Alert when non-gang armed players enter
        },
        -- Police job names to detect
        PoliceJobs = { 'police', 'bcso', 'sheriff', 'statepolice', 'leo', 'fbi', 'doj' },
        -- Notification settings
        Notification = {
            duration = 5000,
            sound = true,
            blip = true,
            blipDuration = 30, -- seconds
        },
        -- Intelligence quality by zone control
        IntelQuality = {
            [25] = 'basic',    -- Just "someone entered"
            [50] = 'detailed', -- Player count
            [75] = 'full',     -- Player names, gang affiliation
        },
    },
    
    -- Convoy Protection (Tier 2)
    -- Item delivery mission - similar to MC prospect runs
    -- NO route ambush - only destination doublecross risk
    -- Synced to all online gang members when activated
    ConvoyProtection = {
        -- Time limit in minutes
        TimeLimitMinutes = 20,
        -- Cooldown in seconds (3 hours)
        Cooldown = 10800,
        -- Items required for delivery (Cartel deals in larger quantities)
        DeliveryItems = {
            { name = 'coke_brick', label = 'Cocaine Brick', minCount = 10, maxCount = 30, weight = 1 },
            { name = 'heroin_pack', label = 'Heroin Package', minCount = 5, maxCount = 20, weight = 0.8 },
            { name = 'meth_bag', label = 'Meth Bag', minCount = 10, maxCount = 25, weight = 0.7 },
            { name = 'dirty_money', label = 'Dirty Money', minCount = 50000, maxCount = 150000, weight = 0.6 },
            { name = 'weapon_carbinerifle', label = 'Carbine Rifle', minCount = 2, maxCount = 5, weight = 0.4 },
            { name = 'weapon_smg', label = 'SMG', minCount = 3, maxCount = 8, weight = 0.5 },
        },
        MinDeliveryItems = 2,
        MaxDeliveryItems = 4,
        -- Destination ambush/doublecross chance (DECREASES with gang rep)
        -- NO route ambush for Cartel convoys
        DestinationAmbushChance = 0.30,
        -- Rewards
        RepGain = 40,
        DestinationInfluenceGain = 8,
        FailureRepLoss = 25,
        -- Loot table
        LootTable = {
            { type = 'money', amount = { min = 5000, max = 15000 }, chance = 1.0 },
            { type = 'item', name = 'coke_brick', label = 'Cocaine Brick', count = { min = 1, max = 3 }, chance = 0.4 },
            { type = 'item', name = 'weapon_pistol', label = 'Pistol', count = { min = 1, max = 1 }, chance = 0.3 },
        },
        -- Default destinations
        DefaultDestinations = {
            { name = 'port', label = 'Los Santos Port', coords = vector3(1148.0, -3065.0, 5.0) },
            { name = 'airport', label = 'LS Airport Cargo', coords = vector3(-1025.0, -2757.0, 13.0) },
        },
    },
    
    -- Exclusive Suppliers (Tier 3)
    ExclusiveSuppliers = {
        -- Only Cartels and Crime Families can access
        AccessibleArchetypes = { 'cartel', 'crime_family' },
        -- Supplier types available
        SupplierTypes = {
            drugs = {
                enabled = true,
                discountPercent = 0.25, -- 25% discount
                exclusiveItems = { 'cocaine_brick', 'meth_brick', 'heroin_brick' },
            },
            arms = {
                enabled = true,
                discountPercent = 0.20, -- 20% discount
                exclusiveItems = { 'weapon_carbinerifle_mk2', 'weapon_assaultrifle_mk2' },
            },
        },
        -- Supplier relationship affects pricing
        RelationshipLevels = {
            [1] = { discount = 0.00, exclusiveAccess = false },
            [3] = { discount = 0.10, exclusiveAccess = false },
            [5] = { discount = 0.20, exclusiveAccess = true },
            [7] = { discount = 0.30, exclusiveAccess = true },
            [10] = { discount = 0.40, exclusiveAccess = true, bulkOrders = true },
        },
    },
    
    -- Plaza System
    PlazaSystem = {
        -- Minimum zones for plaza benefits (not necessarily connected)
        MinZones = 3,
        -- Minimum control per zone to count
        MinControlPerZone = 51,
        -- Plaza benefits
        Benefits = {
            bulkDiscount = 0.15,      -- 15% bulk pricing
            distributionBonus = 0.10, -- 10% more from distribution
            supplierRelationship = 0.05, -- +5% relationship gain
        },
    },
}

-- ============================================================================
-- CRIME FAMILY EXTENDED SETTINGS
-- ============================================================================

FreeGangs.Config.CrimeFamily = {
    -- Business Extortion Bonus (Tier 1) - PASSIVE BONUS
    -- Crime families get enhanced rep and payout from business extortions
    -- This is automatically applied to all extortion activities
    BusinessExtortion = {
        -- Reputation multiplier for extortion activities
        RepMultiplier = 1.50, -- +50% rep from extortions
        -- Payout multiplier for extortion activities
        PayoutMultiplier = 1.25, -- +25% payout from extortions
        -- Description for UI
        Description = 'Business extortions grant 50% more reputation and 25% higher payouts',
    },
    
    -- High-Value Contracts (Tier 2)
    HighValueContracts = {
        -- Reputation multiplier for heists
        HeistRepMultiplier = 1.5,
        -- Exclusive heist access
        ExclusiveHeists = {
            enabled = true,
            -- List of heist script events to hook into
            heistHooks = {
                -- Format: { eventName = 'event:name', repMultiplier = 1.5 }
                -- Server admins should configure their heist scripts here
            },
        },
        -- Contract types
        ContractTypes = {
            jewelry = { payout = { min = 15000, max = 35000 }, rep = 75 },
            bank = { payout = { min = 25000, max = 50000 }, rep = 100 },
            art = { payout = { min = 20000, max = 40000 }, rep = 85 },
            casino = { payout = { min = 50000, max = 100000 }, rep = 150 },
        },
        -- Cooldown between contracts (seconds)
        ContractCooldown = 14400, -- 4 hours
    },
    
    -- Political Immunity (Tier 3)
    PoliticalImmunity = {
        -- Bribe cost reduction
        BribeCostReduction = 0.40, -- 40%
        -- Bribe effect enhancement
        BribeEffectBonus = 0.25, -- +25%
        -- Access all bribes regardless of zone control
        IgnoreZoneRequirements = true,
        -- Reduced heat from bribe usage
        HeatReduction = 0.50, -- 50% less heat
        -- Additional benefits
        Benefits = {
            -- Reduced sentence time even without judge bribe
            baseSentenceReduction = 0.15, -- 15%
            -- Faster bribe establishment
            establishmentSpeedBonus = 0.30, -- 30% faster
            -- Lower chance of bribe failure
            failureChanceReduction = 0.20, -- 20% lower
        },
    },
    
    -- City Official Maintenance (Crime Family special)
    CityOfficialMaintenance = {
        -- Reduced maintenance cost
        MaintenancePercent = 0.10, -- 10% instead of 25%
        -- Kickback multiplier
        KickbackMultiplier = 2.5,
        -- Kickback range
        KickbackRange = { min = 5000, max = 20000 },
    },
}

-- ============================================================================
-- PRISON ACTIVITY SETTINGS
-- ============================================================================

FreeGangs.Config.PrisonActivities = {
    -- Tier 1: Smuggle Missions (Level 5+)
    SmuggleMissions = {
        minLevel = 5,
        -- Requires a member to be jailed
        requireJailedMember = true,
        -- Payout range
        payout = { min = 2000, max = 8000 },
        -- Rep reward
        repReward = 30,
        -- Cooldown in seconds
        cooldown = 1800, -- 30 minutes
        -- Mission types
        types = {
            contraband = { weight = 40, items = { 'phone', 'radio', 'lockpick' } },
            drugs = { weight = 35, items = { 'weed_bag', 'coke_bag', 'meth_bag' } },
            weapons = { weight = 25, items = { 'weapon_switchblade', 'weapon_knuckle' } },
        },
        -- Risk levels affect payout and detection
        riskLevels = {
            low = { payoutMult = 1.0, detectionChance = 0.10 },
            medium = { payoutMult = 1.5, detectionChance = 0.25 },
            high = { payoutMult = 2.0, detectionChance = 0.40 },
        },
    },
    
    -- Tier 2: Guard Bribes (Level 6+)
    GuardBribes = {
        minLevel = 6,
        -- Base cost for guard contact
        baseCost = 3000,
        -- Services available
        services = {
            contraband = {
                cost = 2000,
                cooldown = 3600, -- 1 hour
                -- Free at 50%+ prison control
            },
            protection = {
                cost = 5000,
                duration = 86400, -- 24 hours
                -- Jailed member takes less damage
            },
            information = {
                cost = 1000,
                -- Get info on other jailed players
            },
            helpEscape = {
                cost = 30000,
                cooldown = 600, -- 10 minutes
                -- Reduced cost at 75%+ control
            },
        },
    },
    
    -- Tier 3: Prison Control (Level 8+, 51%+ control)
    PrisonControl = {
        minLevel = 8,
        minControl = 51,
        -- Benefits at this level
        benefits = {
            freeBribes = true,           -- No cost for prison guard bribes
            reducedEscapeCost = 10000,   -- Escape cost reduced from $30k
            priorityContraband = true,   -- Faster delivery, better items
            jailReduction = 0.20,        -- 20% jail time reduction for members
        },
    },
}

-- ============================================================================
-- ARCHETYPE ACTIVITY COOLDOWNS (GLOBAL CACHE)
-- ============================================================================

FreeGangs.Config.ActivityCooldowns = {
    -- Street Gang
    main_corner_set = 3600,      -- 1 hour between changes
    block_party = 86400,         -- 24 hours
    driveby_contract = 7200,     -- 2 hours
    
    -- MC
    prospect_run = 3600,         -- 1 hour per prospect
    club_run = 14400,            -- 4 hours
    territory_ride = 21600,      -- 6 hours
    
    -- Cartel
    halcon_alert = 60,           -- Per-player alert cooldown
    convoy_protection = 10800,   -- 3 hours
    supplier_access = 7200,      -- 2 hours
    
    -- Crime Family
    tribute_collection = 3600,   -- 1 hour
    high_value_contract = 14400, -- 4 hours
    
    -- Prison
    smuggle_mission = 1800,      -- 30 minutes
    guard_bribe = 3600,          -- 1 hour
}

-- ============================================================================
-- ARCHETYPE SWITCHING
-- ============================================================================

FreeGangs.Config.ArchetypeSwitching = {
    -- Allow gangs to change archetype
    enabled = false,
    -- Cooldown in days
    cooldownDays = 30,
    -- Cost to switch
    cost = 50000,
    -- Rep penalty (percentage)
    repPenalty = 0.10, -- 10% rep loss
    -- Requires boss approval
    requiresBoss = true,
    -- Minimum gang age in days
    minimumGangAge = 7,
}

return FreeGangs.Config
