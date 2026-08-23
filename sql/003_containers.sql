CREATE TABLE IF NOT EXISTS portops_containers (
    id VARCHAR(64) NOT NULL,
    container_number VARCHAR(11) NOT NULL,
    iso_type VARCHAR(8) NOT NULL,
    cargo_json JSON NOT NULL,
    logistics_json JSON NOT NULL,
    vessel_call_id VARCHAR(64) NULL,
    manifest_id VARCHAR(64) NULL,
    status VARCHAR(32) NOT NULL,
    location_json JSON NULL,
    customs_json JSON NOT NULL,
    condition_score DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    seal_status VARCHAR(16) NOT NULL DEFAULT 'INTACT',
    version INT UNSIGNED NOT NULL DEFAULT 1,
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_portops_containers_number (container_number),
    KEY idx_portops_containers_status (status),
    KEY idx_portops_containers_iso_status (iso_type, status),
    KEY idx_portops_containers_updated (updated_at)
);

CREATE TABLE IF NOT EXISTS portops_container_activity (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    container_id VARCHAR(64) NOT NULL,
    event_name VARCHAR(64) NOT NULL,
    from_status VARCHAR(32) NULL,
    to_status VARCHAR(32) NULL,
    payload_json JSON NOT NULL,
    version INT UNSIGNED NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY idx_portops_container_activity_container (container_id, id),
    KEY idx_portops_container_activity_event (event_name, created_at)
);
