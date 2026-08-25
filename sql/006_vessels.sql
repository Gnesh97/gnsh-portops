CREATE TABLE IF NOT EXISTS portops_vessels (
 id VARCHAR(64) NOT NULL, name VARCHAR(128) NOT NULL, imo VARCHAR(32) NULL,
 vessel_type VARCHAR(32) NULL, metadata_json JSON NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1,
 created_at BIGINT UNSIGNED NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), UNIQUE KEY uq_portops_vessels_imo (imo)
);
CREATE TABLE IF NOT EXISTS portops_vessel_calls (
 id VARCHAR(64) NOT NULL, vessel_id VARCHAR(64) NOT NULL, voyage VARCHAR(64) NULL,
 status VARCHAR(32) NOT NULL, berth_id VARCHAR(64) NULL, eta BIGINT NULL, etd BIGINT NULL,
 version INT UNSIGNED NOT NULL DEFAULT 1, metadata_json JSON NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_vessel_calls_status (status)
);
