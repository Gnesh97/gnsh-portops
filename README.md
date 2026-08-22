# PortOps

PortOps is a FiveM container-terminal operations platform for QBCore, Qbox, and ESX Legacy.

## Branch policy

- `main` is the release branch and must remain production-ready.
- `dev` is the integration branch used for implementation work.
- Feature and fix branches are created from `dev` and merged back into `dev`.
- A completed release is promoted from `dev` to `main`.
- `changelog.md` is updated for every development phase.

The master and implementation plans have been reviewed. S00 technical research and crane contract documents are complete; implementation proceeds one sprint at a time on `dev` and stops at each exit gate.

## S01 local crane prototype

The framework-independent prototype lives under [`prototype/portops_crane`](prototype/portops_crane). It provides a profile-driven rig, frame-time controller, camera modes, alignment metrics, and local attach/detach debug commands. It is intentionally client-only and is not the production PortOps resource.

Offline contract checks can be run with:

```powershell
& 'C:\Users\Gnesh\AppData\Local\Programs\Lua\5.5.1\lua.exe' tests\prototype_crane_contract.lua
```
