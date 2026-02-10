-- ============================================================================
-- FREE-GANGS Database Schema
-- Version: 1.0.0
-- 
-- Run this SQL file against your MariaDB/MySQL database before starting
-- the resource. Requires OxMySQL to be properly configured.
-- ============================================================================

-- ============================================================================
-- CORE GANG DATA
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_gangs` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Internal identifier (lowercase, no spaces)',
    `label` VARCHAR(100) NOT NULL COMMENT 'Display name',
    `archetype` ENUM('street', 'mc', 'cartel', 'crime_family') NOT NULL DEFAULT 'street',
    `color` VARCHAR(7) DEFAULT '#FFFFFF' COMMENT 'Hex color code for UI',
    `logo` TEXT NULL COMMENT 'Logo URL or base64 encoded image',
    `treasury` INT UNSIGNED DEFAULT 0 COMMENT 'Main gang funds',
    `war_chest` INT UNSIGNED DEFAULT 0 COMMENT 'Funds reserved for war collateral',
    `master_rep` INT DEFAULT 0 COMMENT 'Master reputation points',
    `master_level` TINYINT UNSIGNED DEFAULT 1 COMMENT 'Current reputation level (1-10)',
    `trap_spot` JSON NULL COMMENT 'Coordinates of initial trap spot location',
    `settings` JSON DEFAULT '{}' COMMENT 'Gang-specific settings (main corner, etc.)',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX `idx_archetype` (`archetype`),
    INDEX `idx_master_level` (`master_level` DESC),
    INDEX `idx_master_rep` (`master_rep` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- GANG MEMBERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_members` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL COMMENT 'QBox citizen identifier',
    `gang_name` VARCHAR(50) NOT NULL COMMENT 'FK to freegangs_gangs.name',
    `rank` TINYINT UNSIGNED DEFAULT 0 COMMENT 'Rank level (0 = lowest)',
    `rank_name` VARCHAR(50) NULL COMMENT 'Custom rank display name',
    `permissions` JSON DEFAULT '{}' COMMENT 'Individual permission overrides',
    `personal_rep` INT DEFAULT 0 COMMENT 'Personal contribution to gang',
    `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `last_active` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY `uk_citizen_gang` (`citizenid`, `gang_name`),
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_rank` (`gang_name`, `rank` DESC),
    
    CONSTRAINT `fk_member_gang` FOREIGN KEY (`gang_name`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- GANG RANKS (Custom rank structure per gang)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_ranks` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `rank_level` TINYINT UNSIGNED NOT NULL COMMENT '0 = lowest rank',
    `name` VARCHAR(50) NOT NULL COMMENT 'Rank display name',
    `is_boss` TINYINT(1) DEFAULT 0 COMMENT 'Has full permissions',
    `is_officer` TINYINT(1) DEFAULT 0 COMMENT 'Has officer-level permissions',
    `permissions` JSON DEFAULT '{}' COMMENT 'Specific permissions for this rank',
    
    UNIQUE KEY `uk_gang_rank` (`gang_name`, `rank_level`),
    INDEX `idx_gang` (`gang_name`),
    
    CONSTRAINT `fk_rank_gang` FOREIGN KEY (`gang_name`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TERRITORIES (Zone control data)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_territories` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Internal zone identifier',
    `label` VARCHAR(100) NOT NULL COMMENT 'Display name',
    `zone_type` ENUM('residential', 'commercial', 'industrial', 'strategic', 'prison') DEFAULT 'residential',
    `coords` JSON NOT NULL COMMENT 'Zone boundary coordinates (center or poly points)',
    `radius` FLOAT NULL COMMENT 'For sphere zones',
    `size` JSON NULL COMMENT 'For box zones {x, y, z}',
    `influence` JSON DEFAULT '{}' COMMENT 'Per-gang influence percentages {"gang_name": percentage}',
    `protection_value` INT UNSIGNED DEFAULT 0 COMMENT 'Hourly protection money potential',
    `last_flip` TIMESTAMP NULL COMMENT 'Last time zone majority changed',
    `cooldown_until` TIMESTAMP NULL COMMENT 'Capture cooldown expiry',
    `settings` JSON DEFAULT '{}' COMMENT 'Zone-specific settings',
    
    INDEX `idx_zone_type` (`zone_type`),
    INDEX `idx_cooldown` (`cooldown_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- GRAFFITI (Tag persistence)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_graffiti` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `zone_name` VARCHAR(50) NULL COMMENT 'Territory where tag is placed',
    `coords` JSON NOT NULL COMMENT '{x, y, z}',
    `rotation` JSON NOT NULL COMMENT '{x, y, z} rotation',
    `image_url` VARCHAR(512) NOT NULL DEFAULT '' COMMENT 'URL of graffiti image (nui:// or https://)',
    `normal_x` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal X component',
    `normal_y` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal Y component',
    `normal_z` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal Z component',
    `scale` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Graffiti scale multiplier',
    `width` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Width in world units (meters)',
    `height` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Height in world units (meters)',
    `created_by` VARCHAR(50) NOT NULL COMMENT 'Citizenid of player who sprayed',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL COMMENT 'Optional auto-decay timestamp',

    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_zone` (`zone_name`),
    INDEX `idx_expires` (`expires_at`),

    CONSTRAINT `fk_graffiti_gang` FOREIGN KEY (`gang_name`)
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- INTER-GANG HEAT (Rivalry tracking)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_heat` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_a` VARCHAR(50) NOT NULL COMMENT 'First gang (alphabetically lower)',
    `gang_b` VARCHAR(50) NOT NULL COMMENT 'Second gang (alphabetically higher)',
    `heat_level` TINYINT UNSIGNED DEFAULT 0 COMMENT 'Current heat (0-100)',
    `stage` ENUM('neutral', 'tension', 'cold_war', 'rivalry', 'war_ready') DEFAULT 'neutral',
    `last_incident` TIMESTAMP NULL COMMENT 'Last heat-generating event',
    `last_decay` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Last heat decay tick',
    
    UNIQUE KEY `uk_gang_pair` (`gang_a`, `gang_b`),
    INDEX `idx_gang_a` (`gang_a`),
    INDEX `idx_gang_b` (`gang_b`),
    INDEX `idx_stage` (`stage`),
    
    CONSTRAINT `fk_heat_gang_a` FOREIGN KEY (`gang_a`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_heat_gang_b` FOREIGN KEY (`gang_b`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- WARS (Active and historical war records)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_wars` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `attacker` VARCHAR(50) NOT NULL COMMENT 'Gang that declared war',
    `defender` VARCHAR(50) NOT NULL COMMENT 'Target gang',
    `attacker_collateral` INT UNSIGNED DEFAULT 0 COMMENT 'Attacker stake from war chest',
    `defender_collateral` INT UNSIGNED DEFAULT 0 COMMENT 'Defender stake from war chest',
    `status` ENUM('pending', 'active', 'attacker_won', 'defender_won', 'draw', 'cancelled') DEFAULT 'pending',
    `attacker_kills` INT UNSIGNED DEFAULT 0,
    `defender_kills` INT UNSIGNED DEFAULT 0,
    `terms` JSON DEFAULT '{}' COMMENT 'War terms and conditions',
    `started_at` TIMESTAMP NULL COMMENT 'When war became active',
    `ended_at` TIMESTAMP NULL COMMENT 'When war concluded',
    `winner` VARCHAR(50) NULL COMMENT 'Winning gang name',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX `idx_attacker` (`attacker`),
    INDEX `idx_defender` (`defender`),
    INDEX `idx_status` (`status`),
    INDEX `idx_active` (`status`, `started_at`),
    
    CONSTRAINT `fk_war_attacker` FOREIGN KEY (`attacker`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_war_defender` FOREIGN KEY (`defender`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- BRIBES (Active bribe contacts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_bribes` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `contact_type` ENUM('beat_cop', 'dispatcher', 'detective', 'judge', 'customs', 'prison_guard', 'city_official') NOT NULL,
    `contact_level` TINYINT UNSIGNED DEFAULT 1 COMMENT 'Contact upgrade level',
    `established_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `last_payment` TIMESTAMP NULL,
    `next_payment` TIMESTAMP NULL,
    `missed_payments` TINYINT UNSIGNED DEFAULT 0,
    `status` ENUM('active', 'paused', 'terminated') DEFAULT 'active',
    `metadata` JSON DEFAULT '{}' COMMENT 'Contact-specific data',
    
    UNIQUE KEY `uk_gang_contact` (`gang_name`, `contact_type`),
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_status` (`status`),
    INDEX `idx_next_payment` (`next_payment`),
    
    CONSTRAINT `fk_bribe_gang` FOREIGN KEY (`gang_name`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- PROTECTION RACKETS (Business protection registration)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_protection` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `business_id` VARCHAR(100) NOT NULL COMMENT 'Unique business identifier',
    `business_label` VARCHAR(100) NULL COMMENT 'Business display name',
    `zone_name` VARCHAR(50) NULL COMMENT 'Territory zone',
    `coords` JSON NOT NULL COMMENT 'Business location',
    `payout_base` INT UNSIGNED DEFAULT 500 COMMENT 'Base protection payment',
    `business_type` VARCHAR(20) DEFAULT 'npc_shop' COMMENT 'npc_shop or player_business',
    `established_by` VARCHAR(50) NOT NULL COMMENT 'Citizenid who registered',
    `last_collection` TIMESTAMP NULL,
    `last_takeover` TIMESTAMP NULL COMMENT 'When this business was last taken over',
    `status` ENUM('active', 'suspended', 'contested') DEFAULT 'active',

    UNIQUE KEY `uk_business` (`business_id`),
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_zone` (`zone_name`),
    INDEX `idx_status` (`status`),

    CONSTRAINT `fk_protection_gang` FOREIGN KEY (`gang_name`)
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- ARMS DISTRIBUTORS (Distributor relationships)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_distributors` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `distributor_id` VARCHAR(50) NOT NULL COMMENT 'Distributor NPC identifier',
    `relationship_level` INT DEFAULT 0 COMMENT 'Trust level with distributor',
    `last_tribute` TIMESTAMP NULL COMMENT 'Last weekly tribute payment',
    `active_order` JSON NULL COMMENT 'Current pending order details',
    `order_deadline` TIMESTAMP NULL COMMENT 'When current order must be delivered',
    `status` ENUM('active', 'blocked', 'suspended') DEFAULT 'active',
    
    UNIQUE KEY `uk_gang_distributor` (`gang_name`, `distributor_id`),
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_status` (`status`),
    
    CONSTRAINT `fk_distributor_gang` FOREIGN KEY (`gang_name`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- STASHES (Gang storage locations)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_stashes` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NOT NULL,
    `stash_type` ENUM('gang', 'warchest', 'personal') NOT NULL DEFAULT 'gang',
    `stash_id` VARCHAR(100) NOT NULL COMMENT 'ox_inventory stash identifier',
    `owner_citizenid` VARCHAR(50) NULL COMMENT 'For personal stashes only',
    `coords` JSON NOT NULL COMMENT 'Stash access location',
    `slots` INT UNSIGNED DEFAULT 50,
    `max_weight` INT UNSIGNED DEFAULT 100000,
    `access_permissions` JSON DEFAULT '{}' COMMENT 'Who can access',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY `uk_stash` (`stash_id`),
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_type` (`stash_type`),
    
    CONSTRAINT `fk_stash_gang` FOREIGN KEY (`gang_name`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- ACTIVITY LOG (Audit trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_name` VARCHAR(50) NULL COMMENT 'Related gang (null for system)',
    `citizenid` VARCHAR(50) NULL COMMENT 'Player involved (null for system)',
    `action` VARCHAR(100) NOT NULL COMMENT 'Action type identifier',
    `category` ENUM('membership', 'reputation', 'territory', 'war', 'bribe', 'activity', 'admin', 'system') DEFAULT 'system',
    `details` JSON DEFAULT '{}' COMMENT 'Action-specific details',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX `idx_gang` (`gang_name`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_action` (`action`),
    INDEX `idx_category` (`category`),
    INDEX `idx_created` (`created_at` DESC),
    INDEX `idx_gang_action` (`gang_name`, `action`, `created_at` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- WAR COOLDOWNS (Track cooldowns between specific gang pairs)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_war_cooldowns` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `gang_a` VARCHAR(50) NOT NULL,
    `gang_b` VARCHAR(50) NOT NULL,
    `cooldown_until` TIMESTAMP NOT NULL,
    `reason` VARCHAR(100) NULL COMMENT 'Why cooldown exists',
    
    UNIQUE KEY `uk_cooldown_pair` (`gang_a`, `gang_b`),
    INDEX `idx_cooldown` (`cooldown_until`),
    
    CONSTRAINT `fk_cooldown_gang_a` FOREIGN KEY (`gang_a`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_cooldown_gang_b` FOREIGN KEY (`gang_b`) 
        REFERENCES `freegangs_gangs`(`name`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- PLAYER HEAT (Individual player heat tracking)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_player_heat` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `heat_points` INT DEFAULT 0,
    `last_activity` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `last_decay` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- LIFETIME CRIME STATS (Per-player crime activity tracking)
-- ============================================================================

CREATE TABLE IF NOT EXISTS `freegangs_crime_stats` (
    `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL COMMENT 'Player identifier',
    `crime_type` VARCHAR(50) NOT NULL COMMENT 'Crime type (mugging, pickpocket, drug_sale, etc.)',
    `total_count` INT UNSIGNED DEFAULT 0 COMMENT 'Lifetime count of this crime type',
    `total_cash_earned` BIGINT UNSIGNED DEFAULT 0 COMMENT 'Lifetime cash earned from this crime type',
    `last_performed` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY `uk_player_crime` (`citizenid`, `crime_type`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_crime_type` (`crime_type`),
    INDEX `idx_count` (`crime_type`, `total_count` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Additional composite indexes for common queries
CREATE INDEX IF NOT EXISTS `idx_member_activity` ON `freegangs_members` (`gang_name`, `last_active` DESC);
CREATE INDEX IF NOT EXISTS `idx_territory_influence` ON `freegangs_territories` (`zone_type`, `id`);
CREATE INDEX IF NOT EXISTS `idx_log_cleanup` ON `freegangs_logs` (`created_at`);
