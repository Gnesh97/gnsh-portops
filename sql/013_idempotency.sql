CREATE TABLE IF NOT EXISTS portops_idempotency_keys (
 scope_name VARCHAR(64) NOT NULL, idempotency_key VARCHAR(128) NOT NULL,
 response_json JSON NOT NULL, expires_at BIGINT UNSIGNED NOT NULL, created_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (scope_name, idempotency_key), KEY idx_portops_idempotency_expiry (expires_at)
);
