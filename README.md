# gnsh-portops (PortOps)

[![PortOps CI](https://github.com/Gnesh97/gnsh-portops/actions/workflows/ci.yml/badge.svg)](https://github.com/Gnesh97/gnsh-portops/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Server-authoritative FiveM container-terminal operations platform for **QBCore**, **Qbox**, **ESX Legacy**, and **standalone** deployments.

## Overview

PortOps models end-to-end maritime terminal logistics inside FiveM while keeping canonical world and inventory state on the server. It coordinates ship-to-shore crane sessions, ISO container lifecycle and nearby-only streaming, yard slot reservations, multi-step move orders, vessel calls and manifests, gate appointments, customs holds, workforce/equipment assignment, and audit analytics.

The production bootstrap sequence runs strictly through `CONFIG -> DB -> ADAPTERS -> SERVICES -> READY`. Any invalid configuration, unsupported provider, or failed migration aborts startup before network handlers are enabled.

## Features

- **Server-authoritative crane operations:** Atomic operator reservations, source/session-token binding, snapshot sequence guards, client timestamp localization, one-time attach/detach action tokens, and disconnect recovery.
- **Container & yard engines:** Persistent logical container domain, optimistic versioning, ISO/zone compatibility validation, owner-bound TTL slot reservations, snap placement, and bounded nearby-only container/yard streaming.
- **Move order orchestration:** Transactional move and step state machines, prerequisite enforcement, role/availability assignment, and terminal tractor / yard handler validation.
- **Port logistics & compliance:** Vessel/voyage/berth scheduling, manifest materialization, discharge planning, gate appointments, customs risk/hold enforcement, workforce certifications, and exception recovery.
- **Framework & database adapters:** Normalized adapters for `qbcore`, `qbox`, `esx`, and `standalone`, paired with `oxmysql` persistence (13 incremental SQL migrations in [`sql/`](sql)) or an explicit in-memory provider for development.
- **Idempotent public API & typed NUI:** Result-wrapped DTO exports (`{ ok, data, meta }` / `{ ok = false, error }`), idempotency key enforcement, event bus, audit logs, and analytics.

## Installation

1. Copy the repository into your server resources directory as `gnsh-portops` (for example under `resources/[standalone]/gnsh-portops`).
2. Start `oxmysql` and your chosen framework (`qb-core`, `qbx_core`, or `es_extended`) before `gnsh-portops`.
3. Add `ensure gnsh-portops` to `server.cfg`.
4. Configure [`config/config.lua`](config/config.lua) for production (`environment = 'production'`, framework provider, and `database.provider = 'oxmysql'`), along with domain settings in [`config/yard.lua`](config/yard.lua), [`config/berths.lua`](config/berths.lua), [`config/customs.lua`](config/customs.lua), [`config/equipment.lua`](config/equipment.lua), and [`config/features.lua`](config/features.lua).
5. Apply or enable the SQL migrations under [`sql/`](sql) (`001_initial.sql` through `013_idempotency.sql`).

## Development Smoke Surface

When `config.environment` is set to `development`, the resource exposes live smoke commands (disabled in production):

- Client commands (run in order): `/portops_client_status`, `/portops_reserve qc-01`, `/portops_observe qc-01`, `/portops_snapshot qc-01`, `/portops_issue_attach SMOKE-001`, `/portops_consume_attach SMOKE-001`, `/portops_release`
- Server console command: `/portops_status`

## Server Exports

Declared in [`fxmanifest.lua`](fxmanifest.lua) (all mutations require a stable idempotency key):

- `CreateVesselCall` / `GetVesselCall`
- `CreateContainer` / `GetContainer`
- `CreateMoveOrder`
- `CreateGateAppointment`
- `SetCustomsHold`
- `ReleaseContainer`
- `GetHealth`

See [`docs/API.md`](docs/API.md) and [`integrations/`](integrations/README.md) for payload contracts and examples.

## Offline Verification & Release Build

Run the Lua 5.4 syntax checks and contract test suite locally (matching [`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

```bash
find . -name '*.lua' -not -path './tests/*' -print0 | xargs -0 -n1 luac5.4 -p
for test in tests/*_contract.lua; do lua5.4 "$test"; done
```

Build a clean release archive:

```bash
python3 scripts/build_release.py --output /tmp/gnsh-portops-release.zip
```

> Note: [`prototype/portops_crane`](prototype/portops_crane) is preserved as the historical S01 client-only prototype and is excluded from the root [`fxmanifest.lua`](fxmanifest.lua).

## Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) · [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) · [`docs/FRAMEWORKS.md`](docs/FRAMEWORKS.md)
- [`docs/CRANE.md`](docs/CRANE.md) · [`docs/YARD.md`](docs/YARD.md) · [`docs/API.md`](docs/API.md) · [`docs/INTEGRATIONS.md`](docs/INTEGRATIONS.md)
- [`docs/PERFORMANCE_BUDGET.md`](docs/PERFORMANCE_BUDGET.md) · [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) · [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`changelog.md`](changelog.md)

## License

Licensed under the [MIT License](LICENSE).
