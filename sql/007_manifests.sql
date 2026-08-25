CREATE TABLE IF NOT EXISTS portops_manifests (
 id VARCHAR(64) NOT NULL, vessel_call_id VARCHAR(64) NULL, direction VARCHAR(16) NOT NULL,
 status VARCHAR(32) NOT NULL, items_json JSON NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1,
 created_at BIGINT UNSIGNED NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_manifests_call (vessel_call_id)
);
