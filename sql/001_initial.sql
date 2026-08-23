CREATE TABLE IF NOT EXISTS portops_schema_version (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    version INT UNSIGNED NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS portops_cranes (
    crane_id VARCHAR(64) NOT NULL PRIMARY KEY,
    profile_version INT UNSIGNED NOT NULL,
    mode VARCHAR(32) NOT NULL,
    canonical_version BIGINT UNSIGNED NOT NULL DEFAULT 0,
    recovery_required TINYINT(1) NOT NULL DEFAULT 0,
    updated_at BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS portops_crane_sessions (
    session_id VARCHAR(128) NOT NULL PRIMARY KEY,
    crane_id VARCHAR(64) NOT NULL,
    source_id VARCHAR(64) NOT NULL,
    operator_id VARCHAR(128) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    expires_at BIGINT NOT NULL,
    created_at BIGINT NOT NULL,
    invalidated_at BIGINT NULL,
    invalidated_reason VARCHAR(64) NULL
);
