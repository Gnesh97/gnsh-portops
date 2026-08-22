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

### Notes

- The master development plan has been received and reviewed.
- S01 remains a historical development-only client prototype and is excluded from the root production manifest.
- Database persistence, framework adapters, container/yard/berth transitions, and visual crane controls remain explicitly deferred to their planned phases.
- Root Lua syntax and offline contracts pass; FiveM runtime acceptance still requires ensuring the root resource in a test server.
