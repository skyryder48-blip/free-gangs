-- ============================================================================
-- FREE-GANGS Graffiti Migration
-- Run this against your database to upgrade the graffiti table for DUI rendering.
-- Safe to run multiple times (uses ADD COLUMN IF NOT EXISTS).
-- ============================================================================

ALTER TABLE `freegangs_graffiti`
    ADD COLUMN IF NOT EXISTS `image_url` VARCHAR(512) NOT NULL DEFAULT '' COMMENT 'URL of graffiti image (nui:// or https://)' AFTER `rotation`,
    ADD COLUMN IF NOT EXISTS `normal_x` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal X component' AFTER `image_url`,
    ADD COLUMN IF NOT EXISTS `normal_y` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal Y component' AFTER `normal_x`,
    ADD COLUMN IF NOT EXISTS `normal_z` FLOAT NOT NULL DEFAULT 0.0 COMMENT 'Surface normal Z component' AFTER `normal_y`,
    ADD COLUMN IF NOT EXISTS `scale` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Graffiti scale multiplier' AFTER `normal_z`,
    ADD COLUMN IF NOT EXISTS `width` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Width in world units (meters)' AFTER `scale`,
    ADD COLUMN IF NOT EXISTS `height` FLOAT NOT NULL DEFAULT 1.0 COMMENT 'Height in world units (meters)' AFTER `width`;
