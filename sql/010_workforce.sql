CREATE TABLE IF NOT EXISTS portops_employees (
 id VARCHAR(128) NOT NULL, name VARCHAR(128) NULL, role VARCHAR(64) NULL,
 on_duty TINYINT(1) NOT NULL DEFAULT 0, available TINYINT(1) NOT NULL DEFAULT 1,
 certifications_json JSON NOT NULL, metadata_json JSON NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_employees_role (role, on_duty, available)
);
