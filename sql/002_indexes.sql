CREATE TABLE IF NOT EXISTS portops_crane_session_events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(128) NOT NULL,
    crane_id VARCHAR(64) NOT NULL,
    event_name VARCHAR(64) NOT NULL,
    created_at BIGINT NOT NULL,
    KEY idx_crane_session_events_crane (crane_id, created_at),
    KEY idx_crane_session_events_session (session_id, created_at)
);
