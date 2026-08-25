CREATE TABLE IF NOT EXISTS portops_activity (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, event_name VARCHAR(96) NOT NULL,
 entity_id VARCHAR(128) NULL, payload_json JSON NOT NULL, created_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), KEY idx_portops_activity_entity (entity_id, id)
);
CREATE TABLE IF NOT EXISTS portops_audit (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, actor_id VARCHAR(128) NOT NULL,
 action_name VARCHAR(96) NOT NULL, entity_id VARCHAR(128) NULL, details_json JSON NOT NULL,
 created_at BIGINT UNSIGNED NOT NULL, PRIMARY KEY (id), KEY idx_portops_audit_entity (entity_id, id)
);
