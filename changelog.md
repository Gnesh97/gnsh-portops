# Changelog

All notable changes to PortOps are documented in this file.

## [Unreleased]

### Added

- Initialized the repository workflow with `main` as the release branch and `dev` as the integration branch.
- Added the project branch policy and changelog.
- Added S00 crane research notes, profile-driven coordinate specification, and measurable prototype gate contract.
- Added the S01 standalone crane prototype resource with canonical rig transforms, frame-independent controls, camera modes, alignment metrics, and local attach/detach cycle harness.
- Added the root production `fxmanifest.lua` and staged bootstrap (`CONFIG -> DB -> ADAPTERS -> SERVICES -> READY`).
- Added production crane registry/config validation with an explicit development memory provider and fail-fast profile/feature checks.
- Added PORT-020 crane session authority: atomic reserve, source/operator/session-token binding, release idempotency, expiry, and disconnect cleanup.
- Added PORT-021/022 snapshot protocol and observer sync: finite normalized state validation, timestamp window, receive-time delta limits, rate/burst/payload guards, interpolation buffer, late discard, and scope re-entry resync.
- Added PORT-023/024 short-lived action tokens and disconnect recovery: opaque random credentials, one-time consume, binding checks, replay-safe logs, canonical freeze, token/session invalidation, and observer recovery markers.
- Added development-only live smoke commands for reserve, observe, snapshot, action-token issue/consume, release, and resource status checks.
- Added session-bound snapshot guard reset, server-clock localization for client interpolation, and bounded action-token issue/active limits.
- Fixed fallback session and action-token identifiers leaking Lua `table:` allocation formatting.
- Added S03 production foundation contracts: idempotent memory/oxmysql migration boundary, normalized framework adapters, Result/Logger/EventBus utilities, and resource-stop cleanup.
- Hardened S03 boundaries with Qbox validation, strict framework identity checks, credential-key log redaction, migration metadata validation, database failure cleanup, and real framework hook unsubscribe.
- Improved bootstrap diagnostics so missing foundation modules are named in the startup failure message.
- Added S04 persistent container core: schema migration 003, validated logical container domain, CRUD repository, optimistic version checks, lifecycle state machine, transition guards, safe DTOs, and activity events.
- Added S04 ISO visual resolver and nearby-only container streaming with bounded descriptors, interest-radius hysteresis, unload/re-entry reconciliation, and client/server bootstrap wiring.

### Notes

- The master development plan has been received and reviewed.
- S01 remains a historical development-only client prototype and is excluded from the root production manifest.
- Yard/berth transitions, customs/gate workflows, and visual crane controls remain explicitly deferred to their planned phases; the logical container persistence phase is now complete.
- Root Lua syntax and offline contracts pass; FiveM runtime acceptance now includes the live `READY` bootstrap log and the documented development smoke commands.
