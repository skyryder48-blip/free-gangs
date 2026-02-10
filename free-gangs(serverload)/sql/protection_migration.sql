-- ============================================================================
-- Protection Racket Migration
-- Adds business_type and last_takeover columns for enhanced protection system
-- Run this ONCE on existing databases that already have freegangs_protection
-- ============================================================================

ALTER TABLE `freegangs_protection`
    ADD COLUMN IF NOT EXISTS `business_type` VARCHAR(20) DEFAULT 'npc_shop'
        COMMENT 'npc_shop or player_business' AFTER `payout_base`,
    ADD COLUMN IF NOT EXISTS `last_takeover` TIMESTAMP NULL
        COMMENT 'When this business was last taken over' AFTER `last_collection`;
