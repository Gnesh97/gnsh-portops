# State bag policy

State bags are presentation metadata only, never canonical gameplay state.
Use granular scalar keys (`portops:craneId`, `portops:mode`, `portops:version`)
and keep each value bounded. The server is the preferred writer; clients may
observe but must not promote bag values into persistence. Nested payloads,
credentials, entity handles, and full container/move datasets are forbidden.
