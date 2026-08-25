# Troubleshooting

Inspect the startup stage and `READY` log first. A failure at CONFIG, DB,
ADAPTERS, or SERVICES disables network handlers. For rejected writes, retain the
error code and correlation/idempotency key; never request raw credentials in
logs. See the relevant scenario report before retrying production changes.
