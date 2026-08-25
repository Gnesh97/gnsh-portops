CREATE TABLE IF NOT EXISTS portops_equipment (
 id VARCHAR(64) NOT NULL, equipment_type VARCHAR(64) NOT NULL, state VARCHAR(32) NOT NULL,
 operator_id VARCHAR(128) NULL, move_id VARCHAR(64) NULL, fault_reason VARCHAR(255) NULL,
 metadata_json JSON NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_equipment_state (equipment_type, state)
);
