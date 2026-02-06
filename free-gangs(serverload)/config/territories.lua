--[[
    FREE-GANGS: Territory Configuration
    
    This file defines all territory zones in Los Santos.
    Zones can be sphere, box, or polygon type using ox_lib zones.
    
    Zone Types:
    - residential: Corner drug operations, recruitment, safe houses
    - commercial: Protection money, laundering, high visibility
    - industrial: Manufacturing, weapons storage, chop shops
    - strategic: Special locations with unique benefits
    - prison: Special zone with unique control benefits
    
    CUSTOMIZATION:
    - Add/remove zones as needed for your server
    - Adjust coords, sizes, and values to match your map
    - Ensure zone names are unique and lowercase with underscores
]]

FreeGangs = FreeGangs or {}
FreeGangs.Config = FreeGangs.Config or {}

-- ============================================================================
-- TERRITORY DEFINITIONS
-- ============================================================================

FreeGangs.Config.Territories = {
    -- ========================================================================
    -- SOUTH LOS SANTOS (Gang Territory)
    -- ========================================================================
    
    -- Grove Street / Davis Area
    grove_street = {
        label = 'Grove Street',
        zoneType = 'residential',
        coords = vector3(-17.5, -1438.5, 31.0),
        size = vector3(300.0, 250.0, 50.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 2, -- Green
        protectionValue = 400,
        settings = {
            spawnPoints = {
                vector4(-17.5, -1438.5, 31.1, 0.0),
                vector4(-50.2, -1468.7, 32.5, 90.0),
            },
            drugCorners = {
                vector3(-25.5, -1440.2, 31.1),
                vector3(-10.8, -1455.3, 31.1),
                vector3(-45.2, -1420.8, 31.1),
            },
        },
    },
    
    davis_courts = {
        label = 'Davis Courts',
        zoneType = 'residential',
        coords = vector3(92.0, -1944.0, 21.0),
        size = vector3(200.0, 200.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 1, -- Red
        protectionValue = 350,
        settings = {
            spawnPoints = {
                vector4(92.0, -1944.0, 21.0, 180.0),
            },
            drugCorners = {
                vector3(85.2, -1960.5, 21.0),
                vector3(110.5, -1938.2, 21.0),
            },
        },
    },
    
    strawberry = {
        label = 'Strawberry',
        zoneType = 'residential',
        coords = vector3(278.0, -1854.0, 27.0),
        size = vector3(280.0, 200.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 3, -- Blue
        protectionValue = 380,
        settings = {
            spawnPoints = {
                vector4(278.0, -1854.0, 27.0, 270.0),
            },
            drugCorners = {
                vector3(290.5, -1840.2, 27.0),
                vector3(260.8, -1870.5, 27.0),
            },
        },
    },
    
    rancho = {
        label = 'Rancho',
        zoneType = 'residential',
        coords = vector3(475.0, -1855.0, 28.0),
        size = vector3(250.0, 180.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 27, -- Purple
        protectionValue = 320,
        settings = {
            spawnPoints = {
                vector4(475.0, -1855.0, 28.0, 0.0),
            },
            drugCorners = {
                vector3(480.2, -1840.5, 28.0),
                vector3(460.8, -1870.2, 28.0),
            },
        },
    },
    
    chamberlain_hills = {
        label = 'Chamberlain Hills',
        zoneType = 'residential',
        coords = vector3(-164.0, -1664.0, 33.0),
        size = vector3(220.0, 200.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 5, -- Yellow
        protectionValue = 360,
        settings = {
            spawnPoints = {
                vector4(-164.0, -1664.0, 33.0, 45.0),
            },
            drugCorners = {
                vector3(-150.5, -1650.2, 33.0),
                vector3(-180.2, -1680.5, 33.0),
            },
        },
    },
    
    -- ========================================================================
    -- COMMERCIAL DISTRICTS
    -- ========================================================================
    
    vespucci_beach = {
        label = 'Vespucci Beach',
        zoneType = 'commercial',
        coords = vector3(-1356.0, -1119.0, 4.5),
        size = vector3(400.0, 300.0, 30.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 43, -- Orange
        protectionValue = 650,
        settings = {
            businesses = {
                { id = 'vespucci_tattoo', label = 'Vespucci Tattoo', coords = vector3(-1153.8, -1426.8, 4.9) },
                { id = 'vespucci_barber', label = 'Beach Barber', coords = vector3(-1282.6, -1116.8, 6.9) },
            },
            drugCorners = {
                vector3(-1400.5, -1100.2, 4.5),
                vector3(-1320.2, -1150.5, 4.5),
            },
        },
    },
    
    vinewood_boulevard = {
        label = 'Vinewood Boulevard',
        zoneType = 'commercial',
        coords = vector3(287.0, 180.0, 104.0),
        size = vector3(350.0, 200.0, 50.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 46, -- Pink
        protectionValue = 800,
        settings = {
            businesses = {
                { id = 'vinewood_tattoo', label = 'Vinewood Tattoo', coords = vector3(322.1, 180.4, 103.6) },
                { id = 'vinewood_barber', label = 'Celebrity Barber', coords = vector3(-278.1, 6228.5, 31.7) },
            },
            drugCorners = {
                vector3(300.5, 190.2, 104.0),
                vector3(270.2, 170.5, 104.0),
            },
        },
    },
    
    downtown_los_santos = {
        label = 'Downtown LS',
        zoneType = 'commercial',
        coords = vector3(143.0, -757.0, 45.0),
        size = vector3(300.0, 300.0, 80.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 51, -- Gold
        protectionValue = 950,
        settings = {
            businesses = {
                { id = 'downtown_bank', label = 'Maze Bank West', coords = vector3(-204.0, -861.0, 30.3) },
            },
            drugCorners = {
                vector3(150.5, -750.2, 45.0),
                vector3(130.2, -770.5, 45.0),
            },
        },
    },
    
    little_seoul = {
        label = 'Little Seoul',
        zoneType = 'commercial',
        coords = vector3(-715.0, -900.0, 19.0),
        size = vector3(280.0, 250.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 38, -- Dark Blue
        protectionValue = 720,
        settings = {
            businesses = {
                { id = 'seoul_tattoo', label = 'Seoul Ink', coords = vector3(-1153.8, -1426.8, 4.9) },
            },
            drugCorners = {
                vector3(-700.5, -890.2, 19.0),
                vector3(-730.2, -910.5, 19.0),
            },
        },
    },
    
    -- ========================================================================
    -- INDUSTRIAL ZONES
    -- ========================================================================
    
    la_mesa = {
        label = 'La Mesa',
        zoneType = 'industrial',
        coords = vector3(712.0, -988.0, 24.0),
        size = vector3(350.0, 300.0, 50.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 40, -- Brown
        protectionValue = 550,
        settings = {
            warehouseLocations = {
                vector3(700.5, -960.2, 24.0),
                vector3(730.2, -1010.5, 24.0),
            },
            drugCorners = {
                vector3(720.5, -980.2, 24.0),
            },
        },
    },
    
    elysian_island = {
        label = 'Elysian Island',
        zoneType = 'industrial',
        coords = vector3(-77.0, -2450.0, 6.0),
        size = vector3(500.0, 400.0, 30.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 4, -- White
        protectionValue = 480,
        settings = {
            warehouseLocations = {
                vector3(-50.5, -2420.2, 6.0),
                vector3(-100.2, -2480.5, 6.0),
            },
        },
    },
    
    cypress_flats = {
        label = 'Cypress Flats',
        zoneType = 'industrial',
        coords = vector3(812.0, -2200.0, 29.0),
        size = vector3(400.0, 350.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 47, -- Gray
        protectionValue = 420,
        settings = {
            warehouseLocations = {
                vector3(800.5, -2180.2, 29.0),
                vector3(830.2, -2220.5, 29.0),
            },
            drugCorners = {
                vector3(820.5, -2210.2, 29.0),
            },
        },
    },
    
    terminal = {
        label = 'Terminal',
        zoneType = 'industrial',
        coords = vector3(872.0, -3123.0, 5.0),
        size = vector3(500.0, 400.0, 30.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 20, -- Dark Green
        protectionValue = 380,
        settings = {
            warehouseLocations = {
                vector3(860.5, -3100.2, 5.0),
                vector3(890.2, -3150.5, 5.0),
            },
        },
    },
    
    -- ========================================================================
    -- STRATEGIC ZONES
    -- ========================================================================
    
    los_santos_port = {
        label = 'LS Port',
        zoneType = 'strategic',
        coords = vector3(-299.0, -2748.0, 6.0),
        size = vector3(600.0, 500.0, 40.0),
        rotation = 0,
        blipSprite = 410,
        blipColor = 3, -- Blue
        protectionValue = 1200,
        settings = {
            isStrategic = true,
            strategicType = 'port',
            benefits = {
                'smuggling_operations',
                'supplier_meetings',
                'bulk_shipments',
            },
            spawnPoints = {
                vector4(-299.0, -2748.0, 6.1, 180.0),
            },
        },
    },
    
    lsia = {
        label = 'LS International Airport',
        zoneType = 'strategic',
        coords = vector3(-1037.0, -2737.0, 20.0),
        size = vector3(800.0, 600.0, 50.0),
        rotation = 0,
        blipSprite = 90,
        blipColor = 5, -- Yellow
        protectionValue = 1500,
        settings = {
            isStrategic = true,
            strategicType = 'airport',
            benefits = {
                'cargo_theft',
                'international_connections',
                'high_value_targets',
            },
            spawnPoints = {
                vector4(-1037.0, -2737.0, 20.1, 90.0),
            },
        },
    },
    
    -- ========================================================================
    -- PRISON ZONE (Special)
    -- ========================================================================
    
    bolingbroke = {
        label = 'Bolingbroke Penitentiary',
        zoneType = 'prison',
        coords = vector3(1850.0, 2585.0, 46.0),
        size = vector3(600.0, 500.0, 100.0),
        rotation = 45,
        blipSprite = 188,
        blipColor = 1, -- Red
        protectionValue = 0, -- No standard protection
        settings = {
            isPrison = true,
            controlBenefits = {
                [30] = { 'prison_guard_access' },
                [50] = { 'free_contraband' },
                [51] = { 'free_prison_bribes' },
                [75] = { 'reduced_escape_cost' },
            },
            smugglePoints = {
                vector3(1805.5, 2620.2, 46.0),
                vector3(1890.2, 2550.5, 46.0),
            },
        },
    },
    
    -- ========================================================================
    -- SANDY SHORES / BLAINE COUNTY
    -- ========================================================================
    
    sandy_shores = {
        label = 'Sandy Shores',
        zoneType = 'residential',
        coords = vector3(1975.0, 3826.0, 32.0),
        size = vector3(400.0, 350.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 44, -- Light Brown
        protectionValue = 280,
        settings = {
            isRural = true,
            drugCorners = {
                vector3(1960.5, 3810.2, 32.0),
                vector3(1990.2, 3840.5, 32.0),
            },
        },
    },
    
    grapeseed = {
        label = 'Grapeseed',
        zoneType = 'residential',
        coords = vector3(1712.0, 4783.0, 42.0),
        size = vector3(300.0, 250.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 25, -- Forest Green
        protectionValue = 200,
        settings = {
            isRural = true,
            drugCorners = {
                vector3(1700.5, 4770.2, 42.0),
            },
        },
    },
    
    paleto_bay = {
        label = 'Paleto Bay',
        zoneType = 'commercial',
        coords = vector3(-169.0, 6378.0, 31.0),
        size = vector3(400.0, 300.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 69, -- Teal
        protectionValue = 350,
        settings = {
            isRural = true,
            businesses = {
                { id = 'paleto_store', label = 'Paleto General Store', coords = vector3(-169.4, 6378.5, 31.5) },
            },
            drugCorners = {
                vector3(-160.5, 6390.2, 31.0),
            },
        },
    },
    
    -- ========================================================================
    -- ADDITIONAL NEIGHBORHOODS
    -- ========================================================================
    
    mirror_park = {
        label = 'Mirror Park',
        zoneType = 'residential',
        coords = vector3(1087.0, -457.0, 67.0),
        size = vector3(300.0, 250.0, 50.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 26, -- Light Purple
        protectionValue = 450,
        settings = {
            drugCorners = {
                vector3(1080.5, -450.2, 67.0),
                vector3(1100.2, -470.5, 67.0),
            },
        },
    },
    
    east_vinewood = {
        label = 'East Vinewood',
        zoneType = 'residential',
        coords = vector3(277.0, 68.0, 97.0),
        size = vector3(250.0, 200.0, 40.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 48, -- Lime
        protectionValue = 520,
        settings = {
            drugCorners = {
                vector3(270.5, 60.2, 97.0),
                vector3(290.2, 80.5, 97.0),
            },
        },
    },
    
    del_perro = {
        label = 'Del Perro',
        zoneType = 'commercial',
        coords = vector3(-1582.0, -460.0, 40.0),
        size = vector3(350.0, 280.0, 50.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 37, -- Cyan
        protectionValue = 680,
        settings = {
            businesses = {
                { id = 'del_perro_pier', label = 'Del Perro Pier', coords = vector3(-1748.1, -1193.5, 13.0) },
            },
            drugCorners = {
                vector3(-1570.5, -450.2, 40.0),
                vector3(-1600.2, -470.5, 40.0),
            },
        },
    },
    
    rockford_hills = {
        label = 'Rockford Hills',
        zoneType = 'commercial',
        coords = vector3(-848.0, -98.0, 38.0),
        size = vector3(400.0, 350.0, 60.0),
        rotation = 0,
        blipSprite = 310,
        blipColor = 51, -- Gold
        protectionValue = 1100,
        settings = {
            businesses = {
                { id = 'rockford_bank', label = 'Rockford Bank', coords = vector3(-848.0, -98.0, 38.0) },
            },
            highValueArea = true,
            drugCorners = {
                vector3(-840.5, -90.2, 38.0),
            },
        },
    },
}

-- ============================================================================
-- ZONE VISUAL SETTINGS
-- ============================================================================

FreeGangs.Config.TerritoryVisuals = {
    -- Blip settings (disabled - territory should not appear on the pause map)
    Blips = {
        Enabled = false,
        DefaultSprite = 310,
        DefaultScale = 0.8,
        DefaultAlpha = 180,
        UpdateFrequency = 5000, -- ms, how often to update blip colors
    },
    
    -- Control tier colors (for map display)
    TierColors = {
        [1] = { r = 255, g = 0, b = 0, a = 100 },      -- 0-5%: Red
        [2] = { r = 255, g = 128, b = 0, a = 100 },    -- 6-10%: Orange
        [3] = { r = 255, g = 255, b = 0, a = 100 },    -- 11-24%: Yellow
        [4] = { r = 128, g = 255, b = 0, a = 100 },    -- 25-50%: Light Green
        [5] = { r = 0, g = 255, b = 0, a = 100 },      -- 51-79%: Green
        [6] = { r = 0, g = 128, b = 255, a = 100 },    -- 80-100%: Blue
    },
    
    -- HUD display settings
    HUD = {
        Enabled = true,
        Position = { x = 0.85, y = 0.80 },
        Width = 0.15,
        ShowInfluenceBar = true,
        ShowControlTier = true,
        ShowOwner = true,
    },
}

-- ============================================================================
-- ZONE TYPE CONFIGURATIONS
-- ============================================================================

FreeGangs.Config.ZoneTypeSettings = {
    [FreeGangs.ZoneTypes.RESIDENTIAL] = {
        decayModifier = 1.0,
        presenceBonus = 1.0,
        activityBonus = 1.0,
        maxBusinesses = 3,
    },
    [FreeGangs.ZoneTypes.COMMERCIAL] = {
        decayModifier = 0.8, -- Slower decay
        presenceBonus = 0.8, -- Less presence points
        activityBonus = 1.2, -- More activity points
        maxBusinesses = 8,
    },
    [FreeGangs.ZoneTypes.INDUSTRIAL] = {
        decayModifier = 0.9,
        presenceBonus = 0.9,
        activityBonus = 1.1,
        maxBusinesses = 4,
    },
    [FreeGangs.ZoneTypes.STRATEGIC] = {
        decayModifier = 0.7, -- Much slower decay
        presenceBonus = 1.5, -- High presence value
        activityBonus = 1.3,
        maxBusinesses = 2,
    },
    [FreeGangs.ZoneTypes.PRISON] = {
        decayModifier = 1.2, -- Faster decay
        presenceBonus = 2.0, -- Double presence value
        activityBonus = 0.5, -- Less activity points
        maxBusinesses = 0,
    },
}

-- ============================================================================
-- INFLUENCE POINT VALUES
-- ============================================================================

FreeGangs.Config.InfluencePoints = {
    -- Presence-based
    PresenceTick = 15,              -- Every 30 minutes in zone
    
    -- Activity-based
    DrugSale = 0.2,                 -- Per successful sale (0.2%)
    Graffiti = 10,                  -- Per tag placed
    GraffitiRemoved = -15,          -- When your tag is removed
    RivalGraffitiRemoved = 5,       -- When you remove rival tag
    BusinessCollection = 20,        -- Per protection collection
    Mugging = 10,                   -- Per successful mugging
    Pickpocket = 1,                 -- Per successful pickpocket
    
    -- Combat-based
    RivalKillInZone = 15,           -- Kill rival in this zone
    MemberDeathInZone = -10,        -- Your member dies in zone
    
    -- Zone capture
    CaptureBonus = 50,              -- Bonus when achieving majority
    CaptureLoss = -50,              -- Penalty when losing majority
}

-- ============================================================================
-- NEIGHBORING ZONES (for decay resistance bonus)
-- ============================================================================

FreeGangs.Config.NeighboringZones = {
    grove_street = { 'chamberlain_hills', 'davis_courts', 'strawberry' },
    davis_courts = { 'grove_street', 'rancho', 'strawberry' },
    strawberry = { 'grove_street', 'davis_courts', 'chamberlain_hills' },
    rancho = { 'davis_courts', 'cypress_flats', 'la_mesa' },
    chamberlain_hills = { 'grove_street', 'strawberry', 'vespucci_beach' },
    vespucci_beach = { 'chamberlain_hills', 'del_perro', 'little_seoul' },
    little_seoul = { 'vespucci_beach', 'downtown_los_santos', 'del_perro' },
    downtown_los_santos = { 'little_seoul', 'mirror_park', 'la_mesa' },
    vinewood_boulevard = { 'east_vinewood', 'mirror_park', 'rockford_hills' },
    la_mesa = { 'rancho', 'cypress_flats', 'downtown_los_santos', 'mirror_park' },
    mirror_park = { 'la_mesa', 'vinewood_boulevard', 'east_vinewood', 'downtown_los_santos' },
    east_vinewood = { 'mirror_park', 'vinewood_boulevard' },
    del_perro = { 'vespucci_beach', 'little_seoul', 'rockford_hills' },
    rockford_hills = { 'del_perro', 'vinewood_boulevard' },
    elysian_island = { 'terminal', 'los_santos_port' },
    cypress_flats = { 'rancho', 'la_mesa', 'terminal' },
    terminal = { 'elysian_island', 'cypress_flats', 'los_santos_port' },
    los_santos_port = { 'elysian_island', 'terminal' },
    lsia = { 'elysian_island', 'vespucci_beach' },
    bolingbroke = {}, -- Prison has no neighbors
    sandy_shores = { 'grapeseed' },
    grapeseed = { 'sandy_shores', 'paleto_bay' },
    paleto_bay = { 'grapeseed' },
}

return FreeGangs.Config.Territories
