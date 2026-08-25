CREATE TABLE IF NOT EXISTS portops_moves (
 id VARCHAR(64) NOT NULL, move_number VARCHAR(96) NULL, idempotency_key VARCHAR(128) NULL,
 container_id VARCHAR(64) NOT NULL, from_location_json JSON NOT NULL, to_location_json JSON NOT NULL,
 status VARCHAR(32) NOT NULL, steps_json JSON NOT NULL, assignments_json JSON NOT NULL,
 reservations_json JSON NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1,
 blocked_reason VARCHAR(255) NULL, created_at BIGINT UNSIGNED NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), UNIQUE KEY uq_portops_moves_number (move_number), UNIQUE KEY uq_portops_moves_idempotency (idempotency_key),
 KEY idx_portops_moves_container (container_id,status), KEY idx_portops_moves_updated (updated_at)
);
CREATE TABLE IF NOT EXISTS portops_move_activity (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, move_id VARCHAR(64) NOT NULL, event_name VARCHAR(64) NOT NULL,
 from_status VARCHAR(32) NULL, to_status VARCHAR(32) NULL, payload_json JSON NOT NULL, version INT UNSIGNED NOT NULL,
 created_at BIGINT UNSIGNED NOT NULL, PRIMARY KEY (id), KEY idx_portops_move_activity_move (move_id,id)
);
CREATE TABLE IF NOT EXISTS portops_move_steps (
 id VARCHAR(64) NOT NULL, move_id VARCHAR(64) NOT NULL, ordinal INT UNSIGNED NOT NULL,
 kind VARCHAR(32) NOT NULL, status VARCHAR(32) NOT NULL, assignee_json JSON NOT NULL,
 reservation_json JSON NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1, metadata_json JSON NOT NULL,
 PRIMARY KEY (id), UNIQUE KEY uq_portops_move_steps_order (move_id, ordinal),
 KEY idx_portops_move_steps_status (move_id, status),
 CONSTRAINT fk_portops_move_steps_move FOREIGN KEY (move_id) REFERENCES portops_moves(id) ON DELETE CASCADE
);
