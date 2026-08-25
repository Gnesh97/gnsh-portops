# Public API

The resource exposes only DTOs through the server exports declared in
`fxmanifest.lua`. Results use `{ ok, data, meta }` or `{ ok=false, error }`.
Database handles, framework player objects, session credentials, and raw token
values are never returned. Writes should provide a stable idempotency key.

Available exports are `CreateVesselCall`, `GetVesselCall`, `CreateContainer`,
`GetContainer`, `CreateMoveOrder`, `CreateGateAppointment`, `SetCustomsHold`,
`ReleaseContainer`, and `GetHealth`. All writes require an idempotency key;
repeating the same scope/key returns the original DTO without creating a second
record. `GetHealth` reports readiness, stage, version, and schema version.
