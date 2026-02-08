--[[
    FREE-GANGS: Shared Enumerations and Constants
    
    This file defines all constants, enums, and shared values used across
    both client and server. Loaded before config to ensure availability.
]]

FreeGangs = FreeGangs or {}

-- ============================================================================
-- ARCHETYPES
-- ============================================================================

---@enum ArchetypeType
FreeGangs.Archetypes = {
    STREET = 'street',
    MC = 'mc',
    CARTEL = 'cartel',
    CRIME_FAMILY = 'crime_family',
}

---@type table<string, {label: string, description: string}>
FreeGangs.ArchetypeLabels = {
    [FreeGangs.Archetypes.STREET] = {
        label = 'Street Gang',
        description = 'Traditional street-level criminal organization focused on territory control and drug operations.',
    },
    [FreeGangs.Archetypes.MC] = {
        label = 'Motorcycle Club',
        description = 'Outlaw motorcycle club with brotherhood culture and vehicle-focused operations.',
    },
    [FreeGangs.Archetypes.CARTEL] = {
        label = 'Drug Cartel',
        description = 'International drug trafficking organization with supplier networks and distribution corridors.',
    },
    [FreeGangs.Archetypes.CRIME_FAMILY] = {
        label = 'Crime Family',
        description = 'Traditional organized crime family focused on high-value operations and political influence.',
    },
}

-- ============================================================================
-- DEFAULT RANK STRUCTURES PER ARCHETYPE
-- ============================================================================

---@type table<string, table<number, {name: string, isBoss: boolean, isOfficer: boolean}>>
FreeGangs.DefaultRanks = {
    [FreeGangs.Archetypes.STREET] = {
        [0] = { name = 'Youngin', isBoss = false, isOfficer = false },
        [1] = { name = 'Soldier', isBoss = false, isOfficer = false },
        [2] = { name = 'Lieutenant', isBoss = false, isOfficer = true },
        [3] = { name = 'OG', isBoss = false, isOfficer = true },
        [4] = { name = 'Warlord', isBoss = false, isOfficer = true },
        [5] = { name = 'Shot Caller', isBoss = true, isOfficer = true },
    },
    [FreeGangs.Archetypes.MC] = {
        [0] = { name = 'Prospect', isBoss = false, isOfficer = false },
        [1] = { name = 'Patched Member', isBoss = false, isOfficer = false },
        [2] = { name = 'Road Captain', isBoss = false, isOfficer = true },
        [3] = { name = 'Sergeant at Arms', isBoss = false, isOfficer = true },
        [4] = { name = 'Vice President', isBoss = false, isOfficer = true },
        [5] = { name = 'President', isBoss = true, isOfficer = true },
    },
    [FreeGangs.Archetypes.CARTEL] = {
        [0] = { name = 'Street Dealer', isBoss = false, isOfficer = false },
        [1] = { name = 'Halcon', isBoss = false, isOfficer = false },
        [2] = { name = 'Sicario', isBoss = false, isOfficer = true },
        [3] = { name = 'Lieutenant', isBoss = false, isOfficer = true },
        [4] = { name = 'Plaza Boss', isBoss = false, isOfficer = true },
        [5] = { name = 'El Jefe', isBoss = true, isOfficer = true },
    },
    [FreeGangs.Archetypes.CRIME_FAMILY] = {
        [0] = { name = 'Associate', isBoss = false, isOfficer = false },
        [1] = { name = 'Soldier', isBoss = false, isOfficer = false },
        [2] = { name = 'Capo', isBoss = false, isOfficer = true },
        [3] = { name = 'Consigliere', isBoss = false, isOfficer = true },
        [4] = { name = 'Underboss', isBoss = false, isOfficer = true },
        [5] = { name = 'Don', isBoss = true, isOfficer = true },
    },
}

-- ============================================================================
-- REPUTATION LEVELS
-- ============================================================================

---@type table<number, {name: string, repRequired: number, maxTerritories: number, unlocks: table}>
FreeGangs.ReputationLevels = {
    [1] = {
        name = 'Startup Crew',
        repRequired = 0,
        maxTerritories = 1,
        unlocks = { 'basic_features', 'trap_spot' },
    },
    [2] = {
        name = 'Known',
        repRequired = 500,
        maxTerritories = 2,
        unlocks = { 'beat_cop_bribe' },
    },
    [3] = {
        name = 'Established',
        repRequired = 1500,
        maxTerritories = 3,
        unlocks = { 'dispatcher_bribe', 'stash_upgrade_1' },
    },
    [4] = {
        name = 'Respected',
        repRequired = 3500,
        maxTerritories = 4,
        unlocks = { 'detective_bribe', 'archetype_tier_1' },
    },
    [5] = {
        name = 'Notorious',
        repRequired = 6000,
        maxTerritories = 5,
        unlocks = { 'judge_bribe', 'customs_bribe', 'income_bonus_10', 'smuggle_missions' },
    },
    [6] = {
        name = 'Feared',
        repRequired = 10000,
        maxTerritories = 6,
        unlocks = { 'prison_guard_bribe', 'archetype_tier_2' },
    },
    [7] = {
        name = 'Infamous',
        repRequired = 15000,
        maxTerritories = 7,
        unlocks = { 'city_official_bribe', 'war_collateral_increase' },
    },
    [8] = {
        name = 'Legendary',
        repRequired = 22000,
        maxTerritories = 8,
        unlocks = { 'archetype_tier_3', 'income_bonus_20' },
    },
    [9] = {
        name = 'Empire',
        repRequired = 30000,
        maxTerritories = 10,
        unlocks = { 'reduced_bribe_costs', 'rival_intel_reports' },
    },
    [10] = {
        name = 'Untouchable',
        repRequired = 50000,
        maxTerritories = -1, -- Unlimited
        unlocks = { 'archetype_ultimate', 'legacy_bonuses' },
    },
}

-- ============================================================================
-- ZONE TYPES
-- ============================================================================

---@enum ZoneType
FreeGangs.ZoneTypes = {
    RESIDENTIAL = 'residential',
    COMMERCIAL = 'commercial',
    INDUSTRIAL = 'industrial',
    STRATEGIC = 'strategic',
    PRISON = 'prison',
}

---@type table<string, {label: string, icon: string, protectionMultiplier: number}>
FreeGangs.ZoneTypeInfo = {
    [FreeGangs.ZoneTypes.RESIDENTIAL] = {
        label = 'Residential',
        icon = 'house',
        protectionMultiplier = 1.0,
    },
    [FreeGangs.ZoneTypes.COMMERCIAL] = {
        label = 'Commercial',
        icon = 'store',
        protectionMultiplier = 1.5,
    },
    [FreeGangs.ZoneTypes.INDUSTRIAL] = {
        label = 'Industrial',
        icon = 'industry',
        protectionMultiplier = 1.2,
    },
    [FreeGangs.ZoneTypes.STRATEGIC] = {
        label = 'Strategic',
        icon = 'map-pin',
        protectionMultiplier = 2.0,
    },
    [FreeGangs.ZoneTypes.PRISON] = {
        label = 'Prison',
        icon = 'handcuffs',
        protectionMultiplier = 0.5,
    },
}

-- ============================================================================
-- HEAT & RIVALRY STAGES
-- ============================================================================

---@enum HeatStage
FreeGangs.HeatStages = {
    NEUTRAL = 'neutral',
    TENSION = 'tension',
    COLD_WAR = 'cold_war',
    RIVALRY = 'rivalry',
    WAR_READY = 'war_ready',
}

---@type table<string, {minHeat: number, maxHeat: number, label: string, color: string, effects: table}>
FreeGangs.HeatStageThresholds = {
    [FreeGangs.HeatStages.NEUTRAL] = {
        minHeat = 0,
        maxHeat = 29,
        label = 'Neutral',
        color = '#4CAF50',
        effects = {},
    },
    [FreeGangs.HeatStages.TENSION] = {
        minHeat = 30,
        maxHeat = 49,
        label = 'Tension',
        color = '#FFEB3B',
        effects = { 'ui_heat_indicator' },
    },
    [FreeGangs.HeatStages.COLD_WAR] = {
        minHeat = 50,
        maxHeat = 74,
        label = 'Cold War',
        color = '#FF9800',
        effects = { 'ui_heat_indicator', 'territory_warnings' },
    },
    [FreeGangs.HeatStages.RIVALRY] = {
        minHeat = 75,
        maxHeat = 89,
        label = 'Rivalry',
        color = '#F44336',
        effects = { 'ui_heat_indicator', 'territory_warnings', 'profit_reduction', 'protection_stopped' },
    },
    [FreeGangs.HeatStages.WAR_READY] = {
        minHeat = 90,
        maxHeat = 100,
        label = 'War Ready',
        color = '#9C27B0',
        effects = { 'ui_heat_indicator', 'territory_warnings', 'profit_reduction', 'protection_stopped', 'war_available' },
    },
}

-- ============================================================================
-- WAR STATUSES
-- ============================================================================

---@enum WarStatus
FreeGangs.WarStatus = {
    PENDING = 'pending',
    ACTIVE = 'active',
    ATTACKER_WON = 'attacker_won',
    DEFENDER_WON = 'defender_won',
    DRAW = 'draw',
    CANCELLED = 'cancelled',
}

---@type table<string, {label: string, isActive: boolean, isConcluded: boolean}>
FreeGangs.WarStatusInfo = {
    [FreeGangs.WarStatus.PENDING] = { label = 'Pending Acceptance', isActive = false, isConcluded = false },
    [FreeGangs.WarStatus.ACTIVE] = { label = 'Active War', isActive = true, isConcluded = false },
    [FreeGangs.WarStatus.ATTACKER_WON] = { label = 'Attacker Victory', isActive = false, isConcluded = true },
    [FreeGangs.WarStatus.DEFENDER_WON] = { label = 'Defender Victory', isActive = false, isConcluded = true },
    [FreeGangs.WarStatus.DRAW] = { label = 'Draw', isActive = false, isConcluded = true },
    [FreeGangs.WarStatus.CANCELLED] = { label = 'Cancelled', isActive = false, isConcluded = true },
}

-- ============================================================================
-- BRIBE CONTACT TYPES
-- ============================================================================

---@enum BribeContactType
FreeGangs.BribeContacts = {
    BEAT_COP = 'beat_cop',
    DISPATCHER = 'dispatcher',
    DETECTIVE = 'detective',
    JUDGE = 'judge',
    CUSTOMS = 'customs',
    PRISON_GUARD = 'prison_guard',
    CITY_OFFICIAL = 'city_official',
}

---@type table<string, {label: string, minLevel: number, weeklyCost: number, perUseCost: number, icon: string, heatPerUse: number}>
FreeGangs.BribeContactInfo = {
    [FreeGangs.BribeContacts.BEAT_COP] = {
        label = 'Beat Cop',
        minLevel = 2,
        weeklyCost = 2000,
        perUseCost = 0,
        icon = 'user-police',
        heatPerUse = 3,
    },
    [FreeGangs.BribeContacts.DISPATCHER] = {
        label = 'Dispatcher',
        minLevel = 3,
        weeklyCost = 5000,
        perUseCost = 2000, -- For redirect
        icon = 'radio',
        heatPerUse = 5,
    },
    [FreeGangs.BribeContacts.DETECTIVE] = {
        label = 'Detective',
        minLevel = 4,
        weeklyCost = 8000,
        perUseCost = 0,
        icon = 'magnifying-glass',
        heatPerUse = 8,
    },
    [FreeGangs.BribeContacts.JUDGE] = {
        label = 'Judge/DA',
        minLevel = 5,
        weeklyCost = 15000,
        perUseCost = 1000, -- Per minute reduced
        icon = 'gavel',
        heatPerUse = 10,
    },
    [FreeGangs.BribeContacts.CUSTOMS] = {
        label = 'Customs Agent',
        minLevel = 5,
        weeklyCost = 0, -- Per-use only
        perUseCost = 8000,
        icon = 'plane-arrival',
        heatPerUse = 5,
    },
    [FreeGangs.BribeContacts.PRISON_GUARD] = {
        label = 'Prison Guard',
        minLevel = 6,
        weeklyCost = 3000,
        perUseCost = 2000, -- Contraband delivery
        icon = 'key',
        heatPerUse = 8,
    },
    [FreeGangs.BribeContacts.CITY_OFFICIAL] = {
        label = 'City Official',
        minLevel = 7,
        weeklyCost = 0, -- 25% of initial bribe
        perUseCost = 0,
        icon = 'landmark',
        heatPerUse = 5,
        initialBribe = 20000,
    },
}

-- ============================================================================
-- BRIBE STATUS
-- ============================================================================

---@enum BribeStatus
FreeGangs.BribeStatus = {
    ACTIVE = 'active',
    PAUSED = 'paused',
    TERMINATED = 'terminated',
}

-- ============================================================================
-- STASH TYPES
-- ============================================================================

---@enum StashType
FreeGangs.StashTypes = {
    GANG = 'gang',
    WARCHEST = 'warchest',
    PERSONAL = 'personal',
}

---@type table<string, {label: string, defaultSlots: number, defaultWeight: number}>
FreeGangs.StashTypeInfo = {
    [FreeGangs.StashTypes.GANG] = { label = 'Gang Stash', defaultSlots = 50, defaultWeight = 100000 },
    [FreeGangs.StashTypes.WARCHEST] = { label = 'War Chest', defaultSlots = 20, defaultWeight = 50000 },
    [FreeGangs.StashTypes.PERSONAL] = { label = 'Personal Locker', defaultSlots = 25, defaultWeight = 50000 },
}

-- ============================================================================
-- LOG CATEGORIES
-- ============================================================================

---@enum LogCategory
FreeGangs.LogCategories = {
    MEMBERSHIP = 'membership',
    REPUTATION = 'reputation',
    TERRITORY = 'territory',
    WAR = 'war',
    BRIBE = 'bribe',
    ACTIVITY = 'activity',
    ADMIN = 'admin',
    SYSTEM = 'system',
}

-- ============================================================================
-- PERMISSION FLAGS
-- ============================================================================

---@enum Permission
FreeGangs.Permissions = {
    INVITE = 'canInvite',
    KICK = 'canKick',
    PROMOTE = 'canPromote',
    DEMOTE = 'canDemote',
    ACCESS_TREASURY = 'canAccessTreasury',
    WITHDRAW_TREASURY = 'canWithdrawTreasury',
    DEPOSIT_WARCHEST = 'canDepositWarchest',
    WITHDRAW_WARCHEST = 'canWithdrawWarchest',
    MANAGE_TERRITORY = 'canManageTerritory',
    COLLECT_PROTECTION = 'canCollectProtection',
    ACCESS_GANG_STASH = 'canAccessGangStash',
    MANAGE_RANKS = 'canManageRanks',
    DECLARE_WAR = 'canDeclareWar',
    ACCEPT_WAR = 'canAcceptWar',
    SURRENDER = 'canSurrender',
    MANAGE_BRIBES = 'canManageBribes',
    USE_BRIBES = 'canUseBribes',
    SET_MAIN_CORNER = 'canSetMainCorner', -- Street Gang specific
    START_CLUB_RUN = 'canStartClubRun', -- MC specific
    MANAGE_DISTRIBUTORS = 'canManageDistributors', -- Cartel specific
    CALL_SITDOWN = 'canCallSitdown', -- Crime Family specific
}

---@type table<string, table<string, boolean>>
FreeGangs.DefaultRankPermissions = {
    -- Rank 0: Lowest rank - very limited permissions
    ['0'] = {
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
    },
    -- Rank 1: Basic member
    ['1'] = {
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
        [FreeGangs.Permissions.USE_BRIBES] = true,
    },
    -- Rank 2: Officer level
    ['2'] = {
        [FreeGangs.Permissions.INVITE] = true,
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
        [FreeGangs.Permissions.USE_BRIBES] = true,
        [FreeGangs.Permissions.COLLECT_PROTECTION] = true,
    },
    -- Rank 3: Senior Officer
    ['3'] = {
        [FreeGangs.Permissions.INVITE] = true,
        [FreeGangs.Permissions.KICK] = true,
        [FreeGangs.Permissions.PROMOTE] = true,
        [FreeGangs.Permissions.DEMOTE] = true,
        [FreeGangs.Permissions.ACCESS_TREASURY] = true,
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
        [FreeGangs.Permissions.USE_BRIBES] = true,
        [FreeGangs.Permissions.COLLECT_PROTECTION] = true,
        [FreeGangs.Permissions.MANAGE_BRIBES] = true,
    },
    -- Rank 4: Underboss/VP level
    ['4'] = {
        [FreeGangs.Permissions.INVITE] = true,
        [FreeGangs.Permissions.KICK] = true,
        [FreeGangs.Permissions.PROMOTE] = true,
        [FreeGangs.Permissions.DEMOTE] = true,
        [FreeGangs.Permissions.ACCESS_TREASURY] = true,
        [FreeGangs.Permissions.WITHDRAW_TREASURY] = true,
        [FreeGangs.Permissions.DEPOSIT_WARCHEST] = true,
        [FreeGangs.Permissions.MANAGE_TERRITORY] = true,
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
        [FreeGangs.Permissions.USE_BRIBES] = true,
        [FreeGangs.Permissions.COLLECT_PROTECTION] = true,
        [FreeGangs.Permissions.MANAGE_BRIBES] = true,
        [FreeGangs.Permissions.ACCEPT_WAR] = true,
    },
    -- Rank 5: Boss - all permissions
    ['5'] = {
        [FreeGangs.Permissions.INVITE] = true,
        [FreeGangs.Permissions.KICK] = true,
        [FreeGangs.Permissions.PROMOTE] = true,
        [FreeGangs.Permissions.DEMOTE] = true,
        [FreeGangs.Permissions.ACCESS_TREASURY] = true,
        [FreeGangs.Permissions.WITHDRAW_TREASURY] = true,
        [FreeGangs.Permissions.DEPOSIT_WARCHEST] = true,
        [FreeGangs.Permissions.WITHDRAW_WARCHEST] = true,
        [FreeGangs.Permissions.MANAGE_TERRITORY] = true,
        [FreeGangs.Permissions.ACCESS_GANG_STASH] = true,
        [FreeGangs.Permissions.MANAGE_RANKS] = true,
        [FreeGangs.Permissions.DECLARE_WAR] = true,
        [FreeGangs.Permissions.ACCEPT_WAR] = true,
        [FreeGangs.Permissions.SURRENDER] = true,
        [FreeGangs.Permissions.USE_BRIBES] = true,
        [FreeGangs.Permissions.COLLECT_PROTECTION] = true,
        [FreeGangs.Permissions.MANAGE_BRIBES] = true,
        [FreeGangs.Permissions.SET_MAIN_CORNER] = true,
        [FreeGangs.Permissions.START_CLUB_RUN] = true,
        [FreeGangs.Permissions.MANAGE_DISTRIBUTORS] = true,
        [FreeGangs.Permissions.CALL_SITDOWN] = true,
    },
}

-- ============================================================================
-- ACTIVITY TYPES
-- ============================================================================

---@enum ActivityType
FreeGangs.Activities = {
    DRUG_SALE = 'drug_sale',
    MUGGING = 'mugging',
    PICKPOCKET = 'pickpocket',
    GRAFFITI = 'graffiti',
    GRAFFITI_REMOVE = 'graffiti_remove',
    PROTECTION_COLLECT = 'protection_collect',
    ZONE_PRESENCE = 'zone_presence',
    RIVAL_KILL = 'rival_kill',
    BRIBE_USE = 'bribe_use',
    WAR_VICTORY = 'war_victory',
    WAR_DEFEAT = 'war_defeat',
    ZONE_CAPTURE = 'zone_capture',
    ZONE_LOST = 'zone_lost',
    MEMBER_DEATH = 'member_death',
    DEATH_IN_TERRITORY = 'death_in_territory',
    BRIBE_ESTABLISHED = 'bribe_established',
    BRIBE_FAILED = 'bribe_failed',
    BRIBE_MISSED = 'bribe_missed',
}

-- ============================================================================
-- REPUTATION POINT VALUES
-- ============================================================================

---@type table<string, {masterRep: number, zoneInfluence: number, heat: number}>
FreeGangs.ActivityPoints = {
    [FreeGangs.Activities.DRUG_SALE] = {
        masterRep = 1,
        zoneInfluence = 0.2,
        heat = 1,
    },
    [FreeGangs.Activities.MUGGING] = {
        masterRep = 5,
        zoneInfluence = 10,
        heat = 22,
    },
    [FreeGangs.Activities.PICKPOCKET] = {
        masterRep = 0,
        zoneInfluence = 1,
        heat = 0, -- 10 on failure
    },
    [FreeGangs.Activities.GRAFFITI] = {
        masterRep = 5,
        zoneInfluence = 10,
        heat = 5,
    },
    [FreeGangs.Activities.GRAFFITI_REMOVE] = {
        masterRep = 5,
        zoneInfluence = 0, -- Removes rival influence instead
        heat = 0,
    },
    [FreeGangs.Activities.PROTECTION_COLLECT] = {
        masterRep = 15,
        zoneInfluence = 20,
        heat = 12,
    },
    [FreeGangs.Activities.ZONE_PRESENCE] = {
        masterRep = 0,
        zoneInfluence = 15, -- Per 30 minutes
        heat = 0,
    },
    [FreeGangs.Activities.RIVAL_KILL] = {
        masterRep = 10,
        zoneInfluence = 0,
        heat = 20,
    },
    [FreeGangs.Activities.BRIBE_USE] = {
        masterRep = 0,
        zoneInfluence = 0,
        heat = 0, -- Varies by contact type
    },
    [FreeGangs.Activities.WAR_VICTORY] = {
        masterRep = 150,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.WAR_DEFEAT] = {
        masterRep = -150,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.ZONE_CAPTURE] = {
        masterRep = 50,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.ZONE_LOST] = {
        masterRep = -200,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.MEMBER_DEATH] = {
        masterRep = -10,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.DEATH_IN_TERRITORY] = {
        masterRep = -20, -- Additional to member death
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.BRIBE_ESTABLISHED] = {
        masterRep = 25,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.BRIBE_FAILED] = {
        masterRep = -20,
        zoneInfluence = 0,
        heat = 0,
    },
    [FreeGangs.Activities.BRIBE_MISSED] = {
        masterRep = -50,
        zoneInfluence = 0,
        heat = 0,
    },
}

-- ============================================================================
-- ZONE CONTROL TIERS
-- ============================================================================

---@type table<number, {minControl: number, maxControl: number, drugProfit: number, canCollectProtection: boolean, protectionMultiplier: number, bribeAccess: boolean}>
FreeGangs.ZoneControlTiers = {
    [1] = {
        minControl = 0,
        maxControl = 5,
        drugProfit = -0.20, -- -20%
        canCollectProtection = false,
        protectionMultiplier = 0,
        bribeAccess = false,
    },
    [2] = {
        minControl = 6,
        maxControl = 10,
        drugProfit = -0.15, -- -15%
        canCollectProtection = false,
        protectionMultiplier = 0,
        bribeAccess = false,
    },
    [3] = {
        minControl = 11,
        maxControl = 24,
        drugProfit = 0, -- Base
        canCollectProtection = false,
        protectionMultiplier = 0,
        bribeAccess = false,
    },
    [4] = {
        minControl = 25,
        maxControl = 50,
        drugProfit = 0.05, -- +5%
        canCollectProtection = false,
        protectionMultiplier = 0.5,
        bribeAccess = true, -- Level 1 bribes
    },
    [5] = {
        minControl = 51,
        maxControl = 79,
        drugProfit = 0.10, -- +10%
        canCollectProtection = true,
        protectionMultiplier = 1.0,
        bribeAccess = true,
    },
    [6] = {
        minControl = 80,
        maxControl = 100,
        drugProfit = 0.15, -- +15%
        canCollectProtection = true,
        protectionMultiplier = 2.0, -- 2x protection payouts
        bribeAccess = true,
        discountBribes = true,
        reducedHeat = true,
        increasedHeatDecay = true,
    },
}

-- ============================================================================
-- ARCHETYPE PASSIVE BONUSES
-- ============================================================================

---@type table<string, {drugProfit: number, vehicleIncome: number, supplierRelationship: number, protectionIncome: number, graffitiLoyalty: number, convoyPayout: number, productionEfficiency: number, bribeEffectiveness: number}>
FreeGangs.ArchetypePassiveBonuses = {
    [FreeGangs.Archetypes.STREET] = {
        drugProfit = 0.20, -- +20% corner drug sales
        graffitiLoyalty = 0.25, -- +25% graffiti loyalty points
        vehicleIncome = 0,
        supplierRelationship = 0,
        protectionIncome = 0,
        convoyPayout = 0,
        productionEfficiency = 0,
        bribeEffectiveness = 0,
    },
    [FreeGangs.Archetypes.MC] = {
        vehicleIncome = 0.15, -- +15% vehicle-related income
        convoyPayout = 0.20, -- +20% convoy mission payouts
        drugProfit = 0,
        graffitiLoyalty = 0,
        supplierRelationship = 0,
        protectionIncome = 0,
        productionEfficiency = 0,
        bribeEffectiveness = 0,
    },
    [FreeGangs.Archetypes.CARTEL] = {
        supplierRelationship = 0.30, -- +30% supplier relationship gain
        productionEfficiency = 0.25, -- +25% drug production efficiency
        drugProfit = 0,
        graffitiLoyalty = 0,
        vehicleIncome = 0,
        protectionIncome = 0,
        convoyPayout = 0,
        bribeEffectiveness = 0,
    },
    [FreeGangs.Archetypes.CRIME_FAMILY] = {
        protectionIncome = 0.25, -- +25% protection racket income
        bribeEffectiveness = 0.20, -- +20% bribe effectiveness (reduced costs)
        drugProfit = 0,
        graffitiLoyalty = 0,
        vehicleIncome = 0,
        supplierRelationship = 0,
        convoyPayout = 0,
        productionEfficiency = 0,
    },
}

-- ============================================================================
-- ARCHETYPE TIER ACTIVITIES
-- ============================================================================

---@type table<string, table<number, {name: string, description: string, minLevel: number}>>
FreeGangs.ArchetypeTierActivities = {
    [FreeGangs.Archetypes.STREET] = {
        [1] = {
            name = 'Main Corner',
            description = 'Designate a main corner zone. All sales in radius grant +5 rep per sale instead of +1.',
            minLevel = 4,
        },
        [2] = {
            name = 'Block Party',
            description = 'Host territory event that boosts loyalty gain by 2x for 1 hour. 24-hour cooldown.',
            minLevel = 6,
        },
        [3] = {
            name = 'Drive-By Contracts',
            description = 'Accept NPC contracts to hit rival gang targets for cash + major reputation.',
            minLevel = 8,
        },
    },
    [FreeGangs.Archetypes.MC] = {
        [1] = {
            name = 'Prospect Runs',
            description = 'Send prospects on delivery missions generating passive income. Risk of interception.',
            minLevel = 4,
        },
        [2] = {
            name = 'Club Runs',
            description = 'Organize convoy mission requiring 4+ members. Major payout on completion.',
            minLevel = 6,
        },
        [3] = {
            name = 'Territory Ride',
            description = 'Mass ride through territories grants +5 loyalty to ALL zones passed.',
            minLevel = 8,
        },
    },
    [FreeGangs.Archetypes.CARTEL] = {
        [1] = {
            name = 'Halcon Network',
            description = 'Passive alerts when rivals or police enter any controlled territory (>25%).',
            minLevel = 4,
        },
        [2] = {
            name = 'Convoy Protection',
            description = 'Escort shipment missions with bonus payout for zero casualties.',
            minLevel = 6,
        },
        [3] = {
            name = 'Exclusive Suppliers',
            description = 'ONLY Cartels/Crime Families access top-tier drug AND arms suppliers.',
            minLevel = 8,
        },
    },
    [FreeGangs.Archetypes.CRIME_FAMILY] = {
        [1] = {
            name = 'Tribute Network',
            description = '5% passive cut from all criminal NPC sales in controlled zones.',
            minLevel = 4,
        },
        [2] = {
            name = 'High-Value Contracts',
            description = 'Reputation increases tied to existing heist scripts. Exclusive heists unlocked.',
            minLevel = 6,
        },
        [3] = {
            name = 'Political Immunity',
            description = 'Access ALL bribes without zone influence requirements + enhanced effects (+25%) + reduced costs (-40%).',
            minLevel = 8,
        },
    },
}

-- ============================================================================
-- NOTIFICATION TYPES
-- ============================================================================

---@enum NotificationType
FreeGangs.NotificationTypes = {
    SUCCESS = 'success',
    ERROR = 'error',
    WARNING = 'warning',
    INFO = 'inform',
}

-- ============================================================================
-- EVENT NAMES (For consistency across client/server)
-- ============================================================================

FreeGangs.Events = {
    -- Server events
    Server = {
        -- Gang management
        CREATE_GANG = 'free-gangs:server:createGang',
        DELETE_GANG = 'free-gangs:server:deleteGang',
        JOIN_GANG = 'free-gangs:server:joinGang',
        LEAVE_GANG = 'free-gangs:server:leaveGang',
        KICK_MEMBER = 'free-gangs:server:kickMember',
        PROMOTE_MEMBER = 'free-gangs:server:promoteMember',
        DEMOTE_MEMBER = 'free-gangs:server:demoteMember',
        
        -- Reputation
        ADD_REPUTATION = 'free-gangs:server:addReputation',
        REMOVE_REPUTATION = 'free-gangs:server:removeReputation',
        
        -- Territory
        ENTER_TERRITORY = 'free-gangs:server:enterTerritory',
        EXIT_TERRITORY = 'free-gangs:server:exitTerritory',
        PRESENCE_TICK = 'free-gangs:server:presenceTick',
        UPDATE_INFLUENCE = 'free-gangs:server:updateInfluence',
        
        -- Heat & War
        ADD_HEAT = 'free-gangs:server:addHeat',
        DECLARE_WAR = 'free-gangs:server:declareWar',
        ACCEPT_WAR = 'free-gangs:server:acceptWar',
        SURRENDER = 'free-gangs:server:surrender',
        
        -- Activities
        DRUG_SALE = 'free-gangs:server:drugSale',
        MUGGING = 'free-gangs:server:mugging',
        PICKPOCKET = 'free-gangs:server:pickpocket',
        SPRAY_GRAFFITI = 'free-gangs:server:sprayGraffiti',
        REMOVE_GRAFFITI = 'free-gangs:server:removeGraffiti',
        COLLECT_PROTECTION = 'free-gangs:server:collectProtection',
        
        -- Bribes
        ESTABLISH_BRIBE = 'free-gangs:server:establishBribe',
        USE_BRIBE = 'free-gangs:server:useBribe',
        PAY_BRIBE = 'free-gangs:server:payBribe',
        
        -- Stash
        OPEN_STASH = 'free-gangs:server:openStash',
        
        -- Treasury
        DEPOSIT_TREASURY = 'free-gangs:server:depositTreasury',
        WITHDRAW_TREASURY = 'free-gangs:server:withdrawTreasury',
        DEPOSIT_WARCHEST = 'free-gangs:server:depositWarchest',
    },
    
    -- Client events
    Client = {
        -- UI Updates
        UPDATE_GANG_DATA = 'free-gangs:client:updateGangData',
        UPDATE_TERRITORY = 'free-gangs:client:updateTerritory',
        UPDATE_HEAT = 'free-gangs:client:updateHeat',
        UPDATE_WAR = 'free-gangs:client:updateWar',
        
        -- Notifications
        NOTIFY = 'free-gangs:client:notify',
        TERRITORY_ALERT = 'free-gangs:client:territoryAlert',
        WAR_ALERT = 'free-gangs:client:warAlert',
        BRIBE_DUE = 'free-gangs:client:bribeDue',
        
        -- UI Control
        OPEN_MENU = 'free-gangs:client:openMenu',
        CLOSE_MENU = 'free-gangs:client:closeMenu',
        OPEN_GANG_UI = 'free-gangs:client:openGangUI',
        
        -- Zone visuals
        SHOW_ZONE_MARKERS = 'free-gangs:client:showZoneMarkers',
        HIDE_ZONE_MARKERS = 'free-gangs:client:hideZoneMarkers',
        
        -- Graffiti
        LOAD_GRAFFITI = 'free-gangs:client:loadGraffiti',
        ADD_GRAFFITI = 'free-gangs:client:addGraffiti',
        REMOVE_GRAFFITI = 'free-gangs:client:removeGraffiti',
    },
}

-- ============================================================================
-- CALLBACK NAMES
-- ============================================================================

FreeGangs.Callbacks = {
    -- Gang data
    GET_GANG_DATA = 'free-gangs:callback:getGangData',
    GET_GANG_MEMBERS = 'free-gangs:callback:getGangMembers',
    GET_ALL_GANGS = 'free-gangs:callback:getAllGangs',
    GET_PLAYER_GANG = 'free-gangs:callback:getPlayerGang',
    
    -- Territory
    GET_TERRITORIES = 'free-gangs:callback:getTerritories',
    GET_TERRITORY_INFO = 'free-gangs:callback:getTerritoryInfo',
    GET_ZONE_CONTROL = 'free-gangs:callback:getZoneControl',
    
    -- Heat & War
    GET_HEAT_LEVEL = 'free-gangs:callback:getHeatLevel',
    GET_ACTIVE_WARS = 'free-gangs:callback:getActiveWars',
    GET_WAR_HISTORY = 'free-gangs:callback:getWarHistory',
    
    -- Bribes
    GET_ACTIVE_BRIBES = 'free-gangs:callback:getActiveBribes',
    GET_BRIBE_STATUS = 'free-gangs:callback:getBribeStatus',
    
    -- Activities
    CAN_PERFORM_ACTIVITY = 'free-gangs:callback:canPerformActivity',
    GET_PROTECTION_BUSINESSES = 'free-gangs:callback:getProtectionBusinesses',
    
    -- Graffiti
    GET_NEARBY_GRAFFITI = 'free-gangs:callback:getNearbyGraffiti',
    
    -- Validation
    VALIDATE_PERMISSION = 'free-gangs:callback:validatePermission',
    VALIDATE_RANK = 'free-gangs:callback:validateRank',
}

-- ============================================================================
-- EXPORTS NAMES (for documentation)
-- ============================================================================

FreeGangs.Exports = {
    -- Gang membership
    'GetPlayerGang',
    'IsInGang',
    'GetGangRank',
    'HasGangPermission',
    
    -- Reputation
    'AddMasterRep',
    'RemoveMasterRep',
    'GetMasterRep',
    'GetMasterLevel',
    
    -- Territory
    'GetZoneControl',
    'AddZoneLoyalty',
    'GetZoneOwner',
    'IsInGangTerritory',
    
    -- Heat & Conflict
    'AddGangHeat',
    'GetGangHeat',
    'AreGangsAtWar',
    'GetRivalryStage',
    
    -- Archetype
    'GetArchetype',
    'HasArchetypeAccess',
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Get default ranks for an archetype
---@param archetype string
---@return table<number, {name: string, isBoss: boolean, isOfficer: boolean}>
function FreeGangs.GetDefaultRanks(archetype)
    return FreeGangs.DefaultRanks[archetype] or FreeGangs.DefaultRanks[FreeGangs.Archetypes.STREET]
end

---Get max territories for a reputation level
---@param level number
---@return number
function FreeGangs.GetMaxTerritories(level)
    local levelData = FreeGangs.ReputationLevels[level]
    if not levelData then return 1 end
    return levelData.maxTerritories
end

return FreeGangs
