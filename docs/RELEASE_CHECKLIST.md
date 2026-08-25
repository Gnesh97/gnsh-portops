# Release checklist

- [ ] QBCore, Qbox, and ESX parity reports attached.
- [ ] Ownership, abuse, load, and profiler scenarios pass with evidence.
- [ ] Fresh/upgrade migration matrix passes.
- [ ] `config.environment=production` and durable DB are configured.
- [ ] CI is green; manifest, syntax, tests, and secret scan pass.
- [ ] Release artifact contains no tests, caches, `.env`, or credentials.
- [ ] Version, changelog, and artifact name agree.
- [ ] Public API/idempotency and recovery behavior reviewed.

Any unchecked item is NO-GO for v1.0.
