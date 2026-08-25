CREATE TABLE IF NOT EXISTS portops_yard_slots (
    slot_id VARCHAR(64) PRIMARY KEY, yard_id VARCHAR(64) NOT NULL, block_id VARCHAR(32) NOT NULL,
    bay INT NOT NULL, row_index INT NOT NULL, tier INT NOT NULL, zone_tag VARCHAR(32) NOT NULL,
    transform_json JSON NOT NULL, iso_types_json JSON NOT NULL, state VARCHAR(16) NOT NULL DEFAULT 'AVAILABLE',
    reservation_owner VARCHAR(128) NULL, reservation_expires_at BIGINT NULL, occupant_id VARCHAR(64) NULL,
    version INT NOT NULL DEFAULT 1, updated_at BIGINT NOT NULL,
    KEY idx_portops_yard_slots_zone (yard_id, block_id, zone_tag, state)
);
