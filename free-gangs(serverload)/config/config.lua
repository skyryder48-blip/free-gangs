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
    -- Keys must match the reason strings passed to AddGangReputation
    Multipliers = {
        drug_sale = 1.0,
        mugging = 1.0,
        pickpocket = 1.0,
        graffiti = 1.0,
        graffiti_remove = 1.0,
        protection_collection = 1.0,
        zone_capture = 1.0,
        war_victory = 1.0,
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
        Mugging = 10,
        Pickpocket = 0, -- 10 on failure
        PickpocketFail = 10,
        Graffiti = 5,
        RivalKill = 20,
        ProtectionCollect = 12,
        ProtectionRobbery = 30,
    },
    
    -- Stage-differentiated decay multipliers (applied to GangDecayRate per tick)
    -- Higher stages decay slower (stickier beef), lower stages fade faster
    -- Overall ~15hr from 90→0 preserved
    StageDecayMultipliers = {
        war_ready = 0.4,    -- War-level beef: very persistent
        rivalry = 0.5,      -- Deep rivalries: slow to cool
        cold_war = 0.9,     -- Simmering conflict: near-baseline
        tension = 1.3,      -- Mild tension: fades moderately fast
        neutral = 1.8,      -- Trace beef: clears quickly
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
    MinHeatForWar = 85,
    
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

        -- Loot ranges (standard NPCs)
        MinCash = 1,
        MaxCash = 200,

        -- Loot table (items that can be dropped from standard NPCs)
        LootTable = {
            { item = 'phone', chance = 15, min = 1, max = 1 },
            { item = 'wallet', chance = 25, min = 1, max = 1 },
            { item = 'rolex', chance = 5, min = 1, max = 1 },
            { item = 'goldchain', chance = 8, min = 1, max = 1 },
        },

        -- Required weapon types (must have one equipped)
        RequiredWeapons = { 'pistol', 'smg' },

        -- Maximum distance to target NPC (auto-trigger range)
        MaxDistance = 5.0,

        -- Distance at which mugging cancels during progress
        CancelDistance = 8.0,

        -- NPC cooldown after being mugged (in seconds)
        NPCCooldown = 86400, -- 24 hours

        -- ================================================================
        -- NPC RESISTANCE SYSTEM
        -- ================================================================
        -- NPCs can fight back based on their ped model category.
        -- Higher risk NPCs drop better loot but may attack the player.

        Resistance = {
            -- Enable/disable resistance system
            Enabled = true,

            -- Base resistance chance for standard civilian NPCs (0-100)
            BaseResistChance = 5,

            -- Duration of NPC fight-back combat (ms) before they flee
            FightBackDuration = 8000,

            -- Categories: each has a resist chance, cash multiplier, and a loot table override
            Categories = {
                -- Armed civilian NPCs (security guards, bikers, etc.)
                armed = {
                    resistChance = 60, -- 60% chance to fight back
                    cashMultiplier = 2.0, -- 2x cash on success
                    lootTable = {
                        { item = 'phone', chance = 20, min = 1, max = 1 },
                        { item = 'wallet', chance = 30, min = 1, max = 1 },
                        { item = 'rolex', chance = 12, min = 1, max = 1 },
                        { item = 'goldchain', chance = 15, min = 1, max = 1 },
                    },
                },
                -- Gang member NPCs
                gang = {
                    resistChance = 75, -- 75% chance to fight back
                    cashMultiplier = 2.5, -- 2.5x cash on success
                    lootTable = {
                        { item = 'phone', chance = 15, min = 1, max = 1 },
                        { item = 'wallet', chance = 35, min = 1, max = 1 },
                        { item = 'rolex', chance = 8, min = 1, max = 1 },
                        { item = 'goldchain', chance = 20, min = 1, max = 1 },
                        { item = 'lockpick', chance = 10, min = 1, max = 1 },
                    },
                },
                -- Wealthy/business NPCs (suits, downtown pedestrians)
                wealthy = {
                    resistChance = 15, -- Low fight-back chance
                    cashMultiplier = 3.0, -- 3x cash on success
                    lootTable = {
                        { item = 'phone', chance = 30, min = 1, max = 1 },
                        { item = 'wallet', chance = 40, min = 1, max = 1 },
                        { item = 'rolex', chance = 20, min = 1, max = 1 },
                        { item = 'goldchain', chance = 25, min = 1, max = 1 },
                    },
                },
            },

            -- Ped models classified as "armed" (security guards, bouncers, bikers)
            ArmedPedModels = {
                's_m_m_security_01',
                's_m_m_bouncer_01',
                's_m_m_armoured_01',
                's_m_m_armoured_02',
                'g_m_y_lost_01',
                'g_m_y_lost_02',
                'g_m_y_lost_03',
                's_m_y_ranger_01',
                'a_m_m_hillbilly_01',
                'a_m_m_hillbilly_02',
            },

            -- Ped models classified as "gang" (street gangs, bikers, dealers)
            GangPedModels = {
                'g_m_y_famca_01',
                'g_f_y_families_01',
                'g_m_y_famdnf_01',
                'g_m_y_famfor_01',
                'g_m_y_ballaorig_01',
                'g_m_y_ballasout_01',
                'g_m_y_ballaeast_01',
                'g_m_y_salvaboss_01',
                'g_m_y_salvagoon_01',
                'g_m_y_salvagoon_02',
                'g_m_y_salvagoon_03',
                'g_m_y_mexgoon_01',
                'g_m_y_mexgoon_02',
                'g_m_y_mexgoon_03',
                'g_m_y_strpunk_01',
                'g_m_y_strpunk_02',
                'g_m_y_korean_01',
                'g_m_y_korean_02',
                'g_m_y_korlieut_01',
                'g_m_m_chicold_01',
                'g_m_m_chigoon_01',
                'g_m_m_chigoon_02',
            },

            -- Ped models classified as "wealthy" (business people, rich NPCs)
            WealthyPedModels = {
                'a_m_y_business_01',
                'a_m_y_business_02',
                'a_m_y_business_03',
                'a_f_y_business_01',
                'a_f_y_business_02',
                'a_f_y_business_03',
                'a_f_y_business_04',
                'a_m_m_business_01',
                'a_f_m_business_02',
                'a_m_y_bevhills_01',
                'a_m_y_bevhills_02',
                'a_f_y_bevhills_01',
                'a_f_y_bevhills_02',
                'a_f_y_bevhills_03',
                'a_f_y_bevhills_04',
                'a_m_m_bevhills_01',
                'a_m_m_bevhills_02',
                'a_f_m_bevhills_01',
                'a_f_m_bevhills_02',
                'u_m_y_downtown_01',
                'a_m_y_vinewood_01',
                'a_f_y_vinewood_01',
            },
        },
    },
    
    -- Pickpocketing
    Pickpocket = {
        -- Cooldown between pickpockets per player (in seconds)
        PlayerCooldown = 120, -- 2 minutes

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

        -- Per-roll NPC detection chance (escalates each roll)
        -- NOTE: When SkillCheck is enabled, these are used as fallback only
        DetectionChanceBase = 10, -- 10% on first roll
        DetectionChancePerRoll = 10, -- +10% per subsequent roll (roll 2 = 20%, roll 3 = 30%)

        -- ================================================================
        -- SKILL CHECK MINI-GAME (replaces pure RNG detection)
        -- ================================================================
        -- Uses ox_lib's lib.skillCheck for player-agency-based detection.
        -- Failing the skill check = detected by NPC. Passing = safe roll.

        SkillCheck = {
            -- Enable/disable skill check (falls back to RNG detection if false)
            Enabled = true,

            -- Difficulty per roll (ox_lib skillCheck difficulty strings)
            -- Options: 'easy', 'medium', 'hard'
            -- Escalates per roll for increasing tension
            DifficultyPerRoll = {
                [1] = 'easy',    -- Roll 1: easy
                [2] = 'medium',  -- Roll 2: medium
                [3] = 'hard',    -- Roll 3: hard
            },

            -- Speed multiplier per roll (higher = faster, harder)
            -- 1.0 = normal speed, 1.5 = 50% faster, etc.
            SpeedPerRoll = {
                [1] = 1.0,  -- Normal speed
                [2] = 1.2,  -- 20% faster
                [3] = 1.5,  -- 50% faster
            },

            -- Number of skill check inputs per roll
            -- More inputs = harder to complete without mistake
            InputsPerRoll = {
                [1] = 1,  -- Single input
                [2] = 2,  -- Two inputs
                [3] = 3,  -- Three inputs
            },
        },
    },
    
    -- Drug Sales
    DrugSales = {
        -- Time restrictions (in-game hours)
        AllowedStartHour = 16, -- 4 PM
        AllowedEndHour = 7, -- 7 AM (next day)
        
        -- Minimum time between sales to same NPC
        NPCSaleCooldown = 30, -- seconds

        -- Player cooldown between drug sales (short, allows rapid transactions)
        PlayerCooldown = 15, -- seconds

        -- Maximum interaction distance for drug sales
        MaxDistance = 3.0,

        -- NPC block duration after any transaction (effectively permanent per session)
        NPCBlockDuration = 999999, -- ~11.5 days, NPC despawns well before this

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

        -- Per-drug pricing (minPrice to maxPrice range per unit)
        Drugs = {
            weed_brick  = { basePrice = 40,  minPrice = 25,  maxPrice = 55 },
            coke_brick  = { basePrice = 120, minPrice = 90,  maxPrice = 160 },
            meth        = { basePrice = 100, minPrice = 75,  maxPrice = 135 },
            crack       = { basePrice = 80,  minPrice = 55,  maxPrice = 110 },
            heroin      = { basePrice = 130, minPrice = 95,  maxPrice = 170 },
            oxy         = { basePrice = 70,  minPrice = 50,  maxPrice = 95 },
            lsd         = { basePrice = 60,  minPrice = 40,  maxPrice = 85 },
            ecstasy     = { basePrice = 55,  minPrice = 35,  maxPrice = 80 },
        },

        -- Ped models that always deny sales and alert police
        -- Law enforcement, emergency services, military, security
        BlacklistedPedModels = {
            -- Police
            's_m_y_cop_01',
            's_f_y_cop_01',
            's_m_y_hwaycop_01',
            's_m_y_sheriff_01',
            's_f_y_sheriff_01',
            's_m_y_ranger_01',
            's_m_y_swat_01',
            'csb_cop',
            -- Federal
            's_m_m_ciasec_01',
            's_m_m_fibsec_01',
            's_m_m_fiboffice_01',
            's_m_m_fiboffice_02',
            'csb_agent',
            -- Military
            's_m_y_marine_01',
            's_m_y_marine_02',
            's_m_y_marine_03',
            's_m_m_marine_01',
            's_m_m_marine_02',
            's_m_y_armymech_01',
            's_m_y_pilot_01',
            -- Emergency services
            's_m_y_fireman_01',
            's_m_m_paramedic_01',
            -- Prison
            's_m_m_prisguard_01',
            -- Security
            's_m_m_security_01',
            's_m_m_bouncer_01',
            's_m_m_armoured_01',
            's_m_m_armoured_02',
            's_m_y_blackops_01',
            's_m_y_blackops_02',
            's_m_y_blackops_03',
        },

        -- Wanted level applied when trying to sell to a blacklisted ped
        BlacklistedPedWantedLevel = 2,

        -- ================================================================
        -- DYNAMIC DRUG MARKET (supply & demand pricing)
        -- ================================================================
        -- Tracks global sale volume per zone per drug type.
        -- Prices adjust based on supply saturation in each zone.

        DynamicMarket = {
            -- Enable/disable dynamic market pricing
            Enabled = true,

            -- Time window for tracking sales volume (seconds)
            -- Sales within this window count toward saturation
            TrackingWindow = 3600, -- 1 hour

            -- Sales threshold per zone per drug before prices start dropping
            -- Below this = normal prices. Above = supply penalty kicks in.
            SaturationThreshold = 15,

            -- Price reduction per sale above threshold (percentage)
            -- e.g. 0.03 = -3% per excess sale
            SupplyPenaltyRate = 0.03,

            -- Minimum price multiplier from oversupply (floor)
            MinSupplyMultiplier = 0.50, -- Prices can drop to 50% at most

            -- Bonus for underserved zones (no sales in tracking window)
            -- Applied as a price multiplier when a zone has 0 recent sales of this drug
            UndersupplyBonus = 1.25, -- +25% price in virgin zones

            -- Drug drought events (server-controlled temporary price spikes)
            Drought = {
                -- Enable random drought events
                Enabled = true,

                -- Chance per hour that a drought event triggers (0-100)
                ChancePerHour = 8, -- 8% chance per hour

                -- Duration of drought event (seconds)
                MinDuration = 1800, -- 30 minutes
                MaxDuration = 5400, -- 90 minutes

                -- Price multiplier during drought for the affected drug
                PriceMultiplier = 2.0, -- 2x price

                -- Maximum simultaneous droughts
                MaxActive = 1,
            },
        },
    },
    
    -- Graffiti (DUI + Scaleform image projection system)
    -- Requires: generic_texture_renderer_gfx community resource
    Graffiti = {
        -- Required item to spray
        RequiredItem = 'spray_can',
        ConsumeItem = true,

        -- Spray duration in milliseconds
        SprayDuration = 5000,

        -- Animation
        Animation = {
            dict = 'switch@franklin@lamar_tagging_wall',
            anim = 'lamar_tagging_wall_loop_lamar',
        },

        -- Maximum sprays per player per cycle
        MaxSpraysPerCycle = 6,
        CycleDurationHours = 6,

        -- Removal
        RemovalItem = 'cleaning_kit',
        RemovalDuration = 8000,

        -- Rendering
        RenderDistance = 100.0,    -- Distance to load/unload DUI instances
        MaxVisibleTags = 20,      -- Maximum simultaneous DUI instances per client
        DuiResolution = 512,      -- DUI texture resolution (512 = good balance)

        -- Tag dimensions (world units / meters)
        DefaultScale = 1.0,
        MinScale = 0.3,
        MaxScale = 3.0,
        DefaultWidth = 1.2,       -- Default tag width
        DefaultHeight = 1.2,      -- Default tag height

        -- Wall offset (meters from surface to prevent z-fighting)
        WallOffset = 0.03,

        -- Zone limits
        MaxPerZone = 20,
        MinDistance = 5.0,        -- Minimum distance between tags

        -- Auto-decay (set DecayDays = 0 to disable)
        DecayEnabled = false,
        DecayDays = 0,            -- Days until auto-removal (0 = never)

        -- Heat/rep values for graffiti activities
        SprayHeat = 5,            -- Player heat for spraying
        RemovalHeat = 0,          -- Player heat for removing rival tag
        RemovalLoyaltyLoss = 15,  -- Zone loyalty lost by tag owner on removal
        RemovalRepDamage = 10,    -- Rep damage to tag owner gang on removal

        -- Default graffiti images (used when gang has no custom images)
        -- Place PNG/JPG/SVG files in html/images/graffiti/ and reference here
        -- Use nui://free-gangs/html/images/graffiti/filename.png format
        DefaultImages = {
            -- Add your default graffiti images here:
            -- 'nui://free-gangs/html/images/graffiti/tag_01.png',
            -- 'nui://free-gangs/html/images/graffiti/tag_02.png',
        },

        -- Per-gang image overrides (gang_name -> image list)
        -- Gang leaders can also set custom images via gang settings
        GangImages = {
            -- ['ballas'] = {
            --     'nui://free-gangs/html/images/graffiti/ballas_01.png',
            -- },
        },
    },
    
    -- Protection Racket
    Protection = {
        -- Collection interval in real-world hours
        CollectionIntervalHours = 4,

        -- Base payout range (randomized on registration)
        BasePayoutMin = 200,
        BasePayoutMax = 800,

        -- Distance checks
        CollectionDistance = 10.0,       -- Must be within this distance to collect
        RegistrationDistance = 5.0,      -- Must be within this distance to register/takeover

        -- Min zone control to register or collect (percentage, 0-100)
        MinControlForProtection = 51,

        -- ====================================================================
        -- INTIMIDATION SYSTEM (Business Registration)
        -- ====================================================================
        Intimidation = {
            Duration = 8000,                -- Progress bar duration (ms)

            -- Base success chance before modifiers (0-100)
            BaseSuccessChance = 50,

            -- Zone control bonus: +ControlBonus% per % of control above MinControlForProtection
            -- e.g. at 70% control with 51% min: (70-51) * 0.8 = +15.2%
            ControlBonus = 0.8,

            -- Penalty when the business is already extorted by another gang
            -- Flat % reduction - the owner is already afraid of someone else
            AlreadyExtortedPenalty = 25,

            -- Heat penalty: -HeatPenaltyPerPoint% per heat point between your gang
            -- and the gang currently protecting this business
            HeatPenaltyPerPoint = 0.3,

            -- Contestation penalty: -ContestationPenalty% per % of zone controlled
            -- by rival gangs (total opposition influence in the zone)
            ContestationPenalty = 0.2,

            -- Cooldown after a failed attempt (seconds) per business
            FailCooldown = 1800,            -- 30 minutes

            -- Heat generated on failed intimidation attempt
            FailHeat = 5,

            -- Animation for intimidation scene
            Animation = {
                dict = 'anim@gang_intimidation',
                anim = 'place_cash_on_counter',
                -- Fallback if above doesn't load
                fallbackDict = 'mp_common',
                fallbackAnim = 'givetake1_a',
            },

            -- NPC owner reaction animations
            OwnerReactions = {
                scared = { dict = 'missminuteman_1ig_2', anim = 'handsup_base', duration = 3000 },
                resistant = { dict = 'gestures@m@standing@casual', anim = 'gesture_head_no', duration = 2000 },
                compliant = { dict = 'mp_common', anim = 'givetake1_b', duration = 2000 },
            },
        },

        -- ====================================================================
        -- COLLECTION SYSTEM (Physical Pickup)
        -- ====================================================================
        Collection = {
            -- Animation when collecting from NPC business (has a ped)
            NpcAnimation = {
                dict = 'mp_common',
                anim = 'givetake1_a',
                duration = 3000,
                flag = 49,
            },

            -- Animation when collecting from player-owned business (no ped)
            TargetAnimation = {
                dict = 'anim@heists@ornate_bank@grab_cash_heels',
                anim = 'grab',
                -- Fallback if above doesn't load
                fallbackDict = 'mp_common',
                fallbackAnim = 'givetake1_a',
                duration = 2500,
                flag = 49,
            },
        },

        -- ====================================================================
        -- PROTECTION ROBBERY SYSTEM
        -- ====================================================================
        -- Gangs with 30%+ zone control can rob a rival's protection payout
        -- without taking over the business. Generates major inter-gang heat.
        Robbery = {
            Enabled = true,

            -- Minimum zone control required to rob a rival's protection (%)
            MinControlForRobbery = 30,

            -- Base success chance before modifiers (0-100)
            BaseSuccessChance = 45,

            -- Zone control bonus: +ControlBonus% per % above MinControlForRobbery
            ControlBonus = 0.6,

            -- Penalty per heat point between gangs (makes repeated robberies harder)
            HeatPenaltyPerPoint = 0.2,

            -- Percentage of the business's base payout stolen on success (0.0-1.0)
            PayoutPercent = 0.75,

            -- Inter-gang heat generated on successful robbery
            HeatGenerated = 35,

            -- Inter-gang heat generated even on failed robbery attempt
            FailHeatGenerated = 15,

            -- Cooldown per business after robbery attempt (success or fail, seconds)
            CooldownPerBusiness = 3600, -- 1 hour

            -- Global player cooldown between robbery attempts (seconds)
            PlayerCooldown = 900, -- 15 minutes

            -- Duration of robbery progress bar (ms)
            Duration = 10000,

            -- Animation for robbery scene
            Animation = {
                dict = 'anim@heists@ornate_bank@grab_cash_heels',
                anim = 'grab',
                fallbackDict = 'mp_common',
                fallbackAnim = 'givetake1_a',
                duration = 10000,
                flag = 49,
            },
        },

        -- ====================================================================
        -- RIVAL TAKEOVER SYSTEM
        -- ====================================================================
        Takeover = {
            Enabled = true,

            -- Additional success penalty vs initial registration (-% flat)
            -- Taking over is harder than fresh registration
            SuccessPenalty = 15,

            -- Heat generated between gangs on successful takeover
            HeatGenerated = 20,

            -- Cooldown before a business can be taken over again (seconds)
            CooldownAfterTakeover = 7200,   -- 2 hours

            -- Duration of takeover progress bar (ms)
            Duration = 12000,

            -- Animation for takeover scene
            Animation = {
                dict = 'anim@heists@ornate_bank@thermal_charge',
                anim = 'thermal_charge',
                fallbackDict = 'mp_missheist_countrybank@aim',
                fallbackAnim = 'aim_loop',
                duration = 12000,
                flag = 49,
            },
        },

        -- ====================================================================
        -- BUSINESS REGISTRY
        -- Defines all extortable locations with coords, zone, and NPC info.
        -- type: 'npc_shop' (has owner ped) or 'player_business' (target only)
        -- pedModel: ped hash/name for NPC shops, nil for player businesses
        -- ====================================================================
        Businesses = {
            -- Grove Street area
            { id = '247_grove', label = '24/7 Grove St', zone = 'grove_street',
              coords = vector3(25.7, -1347.3, 29.5), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },
            { id = 'barber_grove', label = 'Davis Barber', zone = 'grove_street',
              coords = vector3(-32.9, -1453.7, 30.5), pedModel = 's_m_m_hairdresser_01', type = 'npc_shop' },

            -- Davis Courts
            { id = '247_davis', label = '24/7 Davis', zone = 'davis_courts',
              coords = vector3(73.2, -1961.5, 21.3), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Strawberry
            { id = 'liquor_strawberry', label = 'Rob\'s Liquor Strawberry', zone = 'strawberry',
              coords = vector3(288.3, -1854.7, 26.7), pedModel = 's_m_y_ammucity_01', type = 'npc_shop' },

            -- Rancho
            { id = '247_rancho', label = '24/7 Rancho', zone = 'rancho',
              coords = vector3(460.9, -1851.2, 27.9), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Chamberlain Hills
            { id = 'laundromat_chamberlain', label = 'Chamberlain Laundromat', zone = 'chamberlain_hills',
              coords = vector3(-155.0, -1665.4, 33.0), pedModel = nil, type = 'player_business' },

            -- Vespucci Beach
            { id = 'tattoo_vespucci', label = 'Vespucci Tattoo', zone = 'vespucci_beach',
              coords = vector3(-1153.8, -1426.8, 4.9), pedModel = 's_m_m_tattooartist_01', type = 'npc_shop' },
            { id = 'barber_vespucci', label = 'Beach Barber', zone = 'vespucci_beach',
              coords = vector3(-1282.6, -1116.8, 6.9), pedModel = 's_m_m_hairdresser_01', type = 'npc_shop' },

            -- Vinewood Boulevard
            { id = 'tattoo_vinewood', label = 'Vinewood Tattoo', zone = 'vinewood_boulevard',
              coords = vector3(322.1, 180.4, 103.6), pedModel = 's_m_m_tattooartist_01', type = 'npc_shop' },

            -- Downtown LS
            { id = 'store_downtown', label = 'Downtown Convenience', zone = 'downtown_los_santos',
              coords = vector3(143.5, -757.8, 45.2), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Little Seoul
            { id = 'seoul_laundry', label = 'Seoul Dry Cleaning', zone = 'little_seoul',
              coords = vector3(-715.3, -910.2, 19.2), pedModel = nil, type = 'player_business' },

            -- La Mesa
            { id = '247_lamesa', label = '24/7 La Mesa', zone = 'la_mesa',
              coords = vector3(712.5, -975.6, 24.3), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Mirror Park
            { id = 'store_mirror', label = 'Mirror Park Store', zone = 'mirror_park',
              coords = vector3(1087.4, -450.3, 67.2), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Del Perro
            { id = 'pier_arcade', label = 'Del Perro Pier Arcade', zone = 'del_perro',
              coords = vector3(-1748.1, -1193.5, 13.0), pedModel = nil, type = 'player_business' },

            -- Rockford Hills
            { id = 'boutique_rockford', label = 'Rockford Boutique', zone = 'rockford_hills',
              coords = vector3(-848.3, -98.5, 38.0), pedModel = 's_f_y_shop_mid', type = 'npc_shop' },

            -- Sandy Shores
            { id = '247_sandy', label = '24/7 Sandy Shores', zone = 'sandy_shores',
              coords = vector3(1960.2, 3815.8, 32.2), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },

            -- Paleto Bay
            { id = 'store_paleto', label = 'Paleto General Store', zone = 'paleto_bay',
              coords = vector3(-169.4, 6378.5, 31.5), pedModel = 's_m_m_storemanager_01', type = 'npc_shop' },
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

    -- Decay settings
    DecayAmount = 1,                     -- Base influence decay per cycle
    DecayIntervalHours = 1,              -- Hours between decay cycles
    PassiveInfluencePerMember = 0.5,     -- Influence gained per jailed member per cycle

    -- Contraband
    ContrabandExpiryHours = 24,          -- Hours before unclaimed contraband expires

    -- Escape
    EscapeCooldownMs = 3600000,          -- Cooldown between escape attempts (ms)

    -- Escape mission settings (client-side)
    EscapeMission = {
        TimerSeconds = 900,              -- 15 minutes to complete escape
        ExtractionRadius = 15.0,         -- Radius of extraction zone
        SafehouseRadius = 25.0,          -- Radius of safehouse arrival zone
        BreakoutDurationMs = 15000,      -- Progress bar duration for breakout
        WantedLevel = 3,                 -- Wanted level during escape
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
    DrugSaleSuccess = 'Sold %dx %s for %s',
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
