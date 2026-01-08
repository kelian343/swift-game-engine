# Project Progress

## Current Status
- Phase 1 complete: static TriMesh + Uniform Grid query layer (raycast/capsule cast).
- Phase 2 complete: player collider is capsule.
- Phase 3 complete: capsule sweep CCD (TOI) integrated into kinematic movement.
- Phase 4 complete: move & slide + ground snap; added stability filters for wall/ground noise.
- Phase 5 complete: mu_s stick/slide slope behavior; per-triangle surface material support; uphill assist.
- Agent-agent collision in place: capsule-capsule CCD in move & slide + post-move separation with velocity correction and wall-block transfer to avoid jitter.
- Gravity + jump input integrated; jump preserves Y velocity; grounded state stabilized.
- High-speed landing smoothing added: groundedNear gating for clamp/gravity, ground sweep/snap soft limits, and ground contact skin tuning.
- Fixed-step frequency increased to 120Hz with maxSubsteps=8 to reduce large per-step motion.
- Jump height increased (jumpSpeed raised).
- Demo tweaks: ground plane enlarged; dynamic oscillating NPC added for push tests (higher massWeight).

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
 - Uphill assist: boost uphill input to reduce slope penalty.

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
- Phase 6 next: kinematic platforms + carry.
- Continue tuning agent collision weights/margins as needed for push feel.
- Phase 7 later: cleanup (remove old penetration/solver paths; keep triggers).

## Phase 6 (Planned): Kinematic Platforms + Carry
Goal: platform carry without tunneling or jitter.
- Platforms sweep first (box cast preferred; capsule as fallback).
- If blocked, stop or reverse platform.
- If player grounded on platform, apply platformDelta before player move & slide.
- If platform would squeeze player against ceiling, platform stops.
✅ Acceptance: stable carry, no wall squeeze, no jitter.

## Phase 7 (Planned): Cleanup
Goal: remove old penetration/solver paths.
- Disable old solver/manifold for player/platform.
- Keep triggers/overlap system for interactions.
✅ Acceptance: simpler core physics path, fewer bugs.

## Debug Logging Currently Enabled
- None (all debug logging removed).
