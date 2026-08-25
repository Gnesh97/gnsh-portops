# Integrations

Integrations call the public exports; they must not import PortOps internals or
mutate database tables. Treat every result as untrusted and log only the
correlation/idempotency key.
