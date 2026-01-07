# Project Progress

## Current Status
- Phase 1 complete: static TriMesh + Uniform Grid query layer (raycast/capsule cast).
- Phase 2 complete: player collider is capsule.
- Phase 3 complete: capsule sweep CCD (TOI) integrated into kinematic movement.
- Phase 4 complete: move & slide + ground snap; added stability filters for wall/ground noise.
- Gravity + jump input integrated; jump preserves Y velocity; grounded state stabilized.

## Project Overview
- macOS Metal game; renderer uses ray tracing compute path with ECS + fixed-step physics.
- Physics architecture is being rebuilt around kinematic capsule movement + sweep CCD against static TriMesh.
- Static geometry is derived from ProceduralMeshes and fed to CollisionQuery/StaticTriMesh.

## Full Plan (Reference)
### Phase 1: Static TriMesh + Uniform Grid Query Layer
Goal: make stable, reusable "who would I hit?" queries.
- Add CollisionQuery interface with raycast / capsuleCast (sphereCast optional).
- Build static TriMesh (positions + triangle indices + per-tri AABB).
- Build Uniform Grid: cell -> [triangleId]. No BVH yet.
- Acceptance: raycast can hit triangles; grid returns candidates.

### Phase 2: Capsule Player (keep old response)
Goal: gain capsule stability with minimal response changes.
- Add CharacterControllerComponent (radius/halfHeight/skin/snap/etc).
- Decouple render mesh vs collider (capsule collider, render mesh can be box).
- Acceptance: fewer corner/step snags.

### Phase 3: Capsule Sweep CCD (TOI), stop only
Goal: remove penetration as main path; stop at contact.
- Broadphase via grid candidates; narrowphase compute earliest TOI.
- Add KinematicMoveStopSystem: move to TOI (with skin) or full delta.
- Acceptance: high-speed impacts do not tunnel.

### Phase 4: Move & Slide + Ground Snap
Goal: smooth wall/terrain movement.
- Iterate 3–5 casts per step: move to contact, project remaining onto tangent.
- Ground probe + snap to prevent jitter on curved/triangulated surfaces.
- Acceptance: stable wall sliding and terrain following.

### Phase 5: Mu_s Stick/Slide
Goal: slope behavior with material tuning (ice/mud/stone).
- Add per-triangle material with mu_s/mu_k.
- Grounded: compare tangential gravity vs mu_s; decide stick/slide.
- Stick: cancel downhill drift; Slide: apply g_tan with mu_k.

### Phase 6: Kinematic Platforms + Carry
Goal: stable moving platforms without tunneling.
- Platform sweep (box or capsule cast).
- Update order: platform first, then player (carry delta into player).
- If squeezed against ceiling, platform stops (stable first).

### Phase 7: Cleanup
Goal: remove old penetration/solver paths.
- Disable/remove old solver/manifold for player/platform.
- Keep triggers/overlap system for interactions.

## In Progress / Next
- Verify jump/landing after the latest "vY <= 0" snap gate.
- Remove debug logging once behavior is confirmed.
- Phase 5 next: mu_s stick/slide and slope behavior.
- Phase 6 later: kinematic platforms + carry.

## Debug Logging Currently Enabled
- `InputSystem` prints "JumpInput requested" when A is pressed (debugLogs=true).
- `JumpSystem` prints "JumpApplied"/"JumpQueued" (debugLogs=true).
- `KinematicMoveStopSystem` prints "KinematicState ... Grounded/Airborne" on state changes (debugLogs=true).
- `DemoScene.debugRaycast()` prints "Ray hit"/"Ray miss" on hit changes.
