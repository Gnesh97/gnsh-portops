CREATE TABLE IF NOT EXISTS portops_customs_cases (
 id VARCHAR(64) NOT NULL, container_id VARCHAR(64) NOT NULL, status VARCHAR(32) NOT NULL,
 risk_score DECIMAL(6,3) NOT NULL DEFAULT 0, reasons_json JSON NOT NULL, details_json JSON NOT NULL,
 officer_id VARCHAR(128) NULL, version INT UNSIGNED NOT NULL DEFAULT 1,
 created_at BIGINT UNSIGNED NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_customs_container (container_id, status)
);
