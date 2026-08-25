CREATE TABLE IF NOT EXISTS portops_gate_appointments (
 id VARCHAR(64) NOT NULL, container_id VARCHAR(64) NOT NULL, booking_ref VARCHAR(64) NULL,
 company VARCHAR(128) NULL, driver_id VARCHAR(128) NULL, window_start BIGINT NOT NULL,
 window_end BIGINT NOT NULL, status VARCHAR(32) NOT NULL, version INT UNSIGNED NOT NULL DEFAULT 1,
 created_at BIGINT UNSIGNED NOT NULL, updated_at BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (id), UNIQUE KEY uq_portops_gate_booking_ref (booking_ref),
 KEY idx_portops_gate_window (window_start, window_end, status)
);
