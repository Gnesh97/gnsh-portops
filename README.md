# PortOps

PortOps is a FiveM container-terminal operations platform for QBCore, Qbox, and ESX Legacy.

## Branch policy

- `main` is the release branch and must remain production-ready.
- `dev` is the integration branch used for implementation work.
- Feature and fix branches are created from `dev` and merged back into `dev`.
- A completed release is promoted from `dev` to `main`.
- `changelog.md` is updated for every development phase.

The master and implementation plans have been reviewed. S00 technical research is retained as the contract, while implementation now proceeds directly in the root production resource on `dev` and stops at each phase exit gate.

## Production resource

The root [`fxmanifest.lua`](fxmanifest.lua) is the active PortOps resource. It loads shared contracts, server-authoritative crane sessions/snapshots/action tokens, disconnect recovery, the persistent logical container core, nearby-only container streaming, and the client observer interpolation path. The direct development profile uses an explicitly configured in-memory provider; the normalized oxmysql and QBCore/Qbox/ESX/standalone adapter boundaries are wired for later gameplay services.

The production bootstrap sequence is `CONFIG -> DB -> ADAPTERS -> SERVICES -> READY`. A malformed config or unsupported provider fails startup before network handlers are enabled. Snapshot broadcasts are sent only to registered observers, and the server never accepts client world coordinates as canonical state. Snapshot sequence guards reset per operator session, client interpolation localizes server timestamps, and action-token issuance is bounded per session/window. The active development profile wires the Yard and Move engines, critical crane-to-yard field-operation seams, vessel/berth/manifest planning, gate/customs/workforce/equipment services, audit/analytics, typed NUI callbacks, oxmysql persistence boundaries, and startup recovery reconciliation.

When `config.environment` is `development`, the root resource exposes a small live smoke surface for the production event contract. From an in-game client, run `/portops_client_status`, `/portops_reserve qc-01`, `/portops_observe qc-01`, `/portops_snapshot qc-01`, `/portops_issue_attach SMOKE-001`, `/portops_consume_attach SMOKE-001`, and `/portops_release` in that order. Run `/portops_status` in the server console to inspect stage, crane mode, canonical version, and recovery state. These commands are disabled for production.

## S01 local crane prototype

The framework-independent prototype remains under [`prototype/portops_crane`](prototype/portops_crane) as the historical S01 commit. It provides a profile-driven rig, frame-time controller, camera modes, alignment metrics, and local attach/detach debug commands. It is intentionally client-only, excluded from the root manifest, and is not the production PortOps resource.

Offline contract checks can be run with:

```powershell
& 'C:\Users\Gnesh\AppData\Local\Programs\Lua\5.5.1\lua.exe' tests\prototype_crane_contract.lua
```

Production contracts can be run offline with:

```powershell
$lua = 'C:\Users\Gnesh\AppData\Local\Programs\Lua\5.5.1\lua.exe'
& $lua tests\server_sessions_tokens_contract.lua
& $lua tests\server_snapshot_sync_contract.lua
& $lua tests\production_bootstrap_contract.lua
& $lua tests\client_bootstrap_contract.lua
& $lua tests\core_utilities_contract.lua
& $lua tests\database_migrations_contract.lua
& $lua tests\framework_adapters_contract.lua
& $lua tests\container_domain_contract.lua
& $lua tests\container_repository_contract.lua
& $lua tests\container_state_machine_contract.lua
& $lua tests\container_service_contract.lua
& $lua tests\container_visuals_contract.lua
& $lua tests\container_streaming_contract.lua
& $lua tests\yard_contract.lua
& $lua tests\yard_snap_contract.lua
& $lua tests\yard_streaming_contract.lua
& $lua tests\move_domain_contract.lua
& $lua tests\move_repository_contract.lua
& $lua tests\move_state_machine_contract.lua
& $lua tests\move_service_contract.lua
& $lua tests\move_assignment_contract.lua
```
