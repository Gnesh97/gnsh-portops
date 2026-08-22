# Crane Reference Notes

Status: S00 / PORT-001 (clean-room behavioral contract)

## Scope and evidence

This document describes the behavior that a PortOps crane prototype must expose without depending on a particular source implementation. The development and implementation plans are the requirements baseline. No crane PoC source was present in this repository at the time of writing, and no third-party crane repository was copied or used as an implementation reference.

Evidence is deliberately separated:

- **Plan requirement:** normalized gantry/trolley/spreader state, local smooth control, server-canonical state, action-token attach, observer interpolation, and deterministic recovery are stated by the PortOps plans.
- **Platform/standard behavior:** FiveM/GTA entities, transforms, cameras, attachment natives, collision flags, and resource lifecycle are available runtime mechanisms. Their exact behavior is build-, model-, and native-dependent and must be verified in the prototype.
- **Design assumption:** choices below are proposed acceptance behavior where the plans do not specify a visual or input detail. They are not claims about an existing PoC.

## Behavioral contract

### Rig hierarchy

The rig is a transform hierarchy, not a collection of independent world-coordinate updates:

```text
crane origin/base
└─ gantry travel
   └─ trolley/cabin travel
      └─ hoist/spreader vertical travel
         └─ optional attached container
```

Every part has a canonical local transform. A profile supplies the origin, local axes, travel bounds, and initial pose; controller code must not hardcode a particular quay's world coordinates. Normalized state is canonical for gantry, trolley, and hoist/spreader (`0..1`); metric hoist height is presentation derived from profile bounds, with clamping at every input boundary.

### Gantry movement

Gantry movement translates the crane's moving frame along its configured local travel axis. Input changes a target velocity or position; it must not teleport the rig. Acceleration/deceleration and frame-time-based integration are required so movement is comparable at 30, 60, and 120 FPS. At either bound, velocity is clamped and further input has no effect. A profile may reverse the local axis without changing controller semantics.

### Trolley and cabin movement

The trolley moves along its parent gantry's local axis and carries the cabin/spreader assembly. Cabin visuals follow trolley state; a cabin is not a second independent authority. If a model exposes a separate cabin mesh, its animation/offset is visual only unless a future profile explicitly declares a coupled transform. Trolley bounds, acceleration, and velocity are independently configurable from gantry bounds. Gantry and trolley coordinates are evaluated in the same canonical snapshot.

### Spreader and hoist

The spreader moves vertically along the hoist axis between configured minimum and maximum heights. Up/down input is frame-rate independent and bounded. The canonical wire and persistence representation is always normalized `[0, 1]`; profile min/max values derive metric presentation height. Spreader yaw is optional profile state; if enabled it is clamped/normalized and alignment checks include yaw error. Cable/rope animation is cosmetic: gameplay follows the deterministic spreader transform, not rope physics. A container may only be considered liftable when the alignment gate passes and the server-approved action is consumed.

### Alignment, attach, and detach

Alignment is measurable and debuggable. At minimum it reports candidate identity, horizontal distance, vertical gap, and heading/yaw error against configurable tolerances. The expected flow is:

```text
candidate selected
→ correct move/container and valid operator session
→ alignment tolerances pass
→ server issues short-lived, one-time action token
→ client performs visual attachment
→ server records canonical attached state
```

The client must never self-declare `CRANE_ATTACHED`, complete a move, or choose an arbitrary container. Attach tokens are bound to crane, session, container, and action; expiry, replay, wrong-session, and wrong-container uses are rejected and logged. Detach uses the same validation boundary and additionally validates the intended target (for example, a terminal trailer) before the logical transition. Visual attachment may use the platform's entity-attachment mechanism, but the logical record remains server-owned and reconstructable if the visual entity disappears.

Collision behavior during attachment is a profile/test decision. The prototype must document whether the container is collision-disabled while carried and restore the prior collision state on detach; it must not leave a hidden collision mutation after failure or cleanup.

## Camera modes

The minimum camera contract is:

- cabin/default operating view;
- top-down alignment view;
- spreader-down/under-spreader view;
- side view;
- optional trailer-alignment view.

Switching camera mode changes only view state; it must not alter crane state, ownership, attachment, or input integration. Entering a camera stores/restores prior gameplay camera settings where practical. Exit, disconnect, and resource stop always restore the gameplay camera, input focus, and any disabled controls. Camera positions are profile-relative or derived from rig transforms rather than hardcoded to one crane model.

## Lifecycle and cleanup

The lifecycle is:

```text
OFFLINE → AVAILABLE → RESERVED → OPERATOR_ENTERING → OPERATING
OPERATING → ATTACHED | PAUSED | FAULTED
OPERATING → OPERATOR_EXITING → AVAILABLE
OPERATING/ATTACHED → disconnect or fault → RECOVERY_REQUIRED
RECOVERY_REQUIRED → recovery completed → AVAILABLE
```

Only one active operator session may reserve a crane. Reservation/release is atomic on the server. Leaving the crane, player disconnect, resource stop, or invalid session must release controls and invalidate the session. An unattached disconnect may return the crane to `AVAILABLE`; an attached disconnect/fault must enter `RECOVERY_REQUIRED`, reject new operator entry until recovery completes, and preserve a deterministic recovery marker. An unowned, floating GTA entity is not accepted as persistent truth. Resource cleanup removes or reverts spawned visual entities, attachments, collision changes, cameras, control overrides, and event handlers created by the prototype. Cleanup must be idempotent and safe when a model/entity was already deleted.

## Multiplayer authority boundary

The operator may simulate input locally at high frequency for smoothness. The server receives bounded, sequenced snapshots at a limited rate and validates session, timestamp/sequence, bounds, maximum delta/speed, and payload shape. The server canonical state is the authority for crane session, attach/detach, container identity, move-step progression, and completion. Observers receive snapshots and interpolate; late snapshots are discarded and scope re-entry performs a hard canonical resync.

FiveM network ownership or entity ownership is a replication optimization, not business authority. State bags may carry small replicated metadata, but they are not the source of truth for container lifecycle or yard placement. Raw client events cannot skip session, move, alignment, permission, or token checks.

## Reuse versus clean-room boundary

Reusable behavior is expressed as concepts and acceptance rules: hierarchical transforms, bounded frame-independent motion, camera mode semantics, alignment metrics, deterministic attachment lifecycle, interpolation, and cleanup. These are generic gameplay behaviors and are not copied source code.

Do not copy third-party Lua, coordinates, model offsets, event names, UI, assets, comments, or distinctive algorithms. No license compatibility was verifiable because no third-party source was supplied or found. Therefore the implementation decision is **clean-room rewrite**. If a future reference repository is considered, record its URL, commit/version, license, attribution obligations, and compatibility with PortOps before using it; when uncertain, do not incorporate it.

### Research audit record

| Checked date | Scope | Search/reference result | License decision |
| --- | --- | --- | --- |
| 2026-08-22 | `gnsh-portops` and the sibling FiveM resource tree; filenames and source text searched for crane/harbor/gantry/trolley/spreader references | No supplied or local third-party crane PoC source, URL, commit, or license record found | N/A; clean-room rewrite required |

This record describes the evidence available for S00. It is not a claim that no crane implementation exists elsewhere. Any later source must be added to this table before reuse is considered.

## Research limitations and prototype questions

This contract intentionally does not assert exact native names, model bones, camera offsets, attachment flags, collision quirks, or OneSync replication details. Those are runtime experiments for S01/S02. The prototype must measure and record:

1. transform hierarchy and model pivot/bone suitability;
2. attachment alignment and collision behavior through repeated cycles;
3. camera restore and cleanup on every exit path;
4. movement consistency at different frame rates;
5. snapshot rejection and observer interpolation under delay/loss;
6. disconnect/resource-restart behavior with an attached container.

Until those tests pass, visual fidelity is provisional and no implementation detail should be treated as a production contract.
