# Project Introduction

## Rendering System
- Metal-based renderer with a ray tracing compute path and a raster path.
- RenderGraph drives offscreen RT output, composite to drawable, and UI overlay pass.
- Unified command buffer for RT + raster; RT output uses 16-bit float where needed.
- RT supports transparency layers, refraction, and directional lighting with selective shadows.

## Procedural Mesh System
- Procedural mesh descriptors define vertex streams and index buffers.
- ECS render items carry mesh descriptors directly; GPU mesh builds from descriptors.
- Static collision meshes read positions/indices from procedural descriptors.
- Dynamic meshes can update buffers per frame for RT acceleration builds/refits.

## Procedural Material System
- Material descriptors unify PBR texture generation and parameter factors.
- Material factory creates baseColor/normal/metallicRoughness/emissive/occlusion maps.
- Render and RT instance data consume the same material descriptor layout.

## Procedural Pose System
- Skeleton and pose components drive animation pose stacks.
- Pose system computes local/model transforms and palette per fixed step.
- Base layer now uses MotionProfile JSON (Fourier-fit curves) generated offline; runtime does not parse FBX.
- Offline FitMotion tool converts ASCII FBX into MotionProfile JSON (Walking/Idle/Running) with smoothing and per-bone overrides; phase detection is conservative and may fall back to normalized_time.
- Locomotion now blends Idle/Walk/Run with cross-fade and hysteresis thresholds, plus phase alignment and smoothstep blend curve.
- Idle transitions now use inertial blending (exponential half-life decay) instead of fixed-time cross-fade.
- Root bone blending keeps yaw stable and snaps root Y to target animation during blends to reduce jitter.
- Procedural corrections include Ground Align plus Lean: run and idle add forward pitch on upper spine/chest, aligned to bone space; IK remains planned.
- GPU skinning uses palette buffers to write skinned vertices each frame.
- Skeleton replaced with Mixamo Y Bot (65 bones, mixamorig naming), pelvis-aligned root, preRotation applied, facing fix on root.

## External Resources
- FBX sources moved to ExternalResources/ (Walking.fbx, Idle.fbx, Running.fbx, Y Bot.fbx) for offline fitting only.

## Physics System (Collision)
- Kinematic capsule movement with sweep CCD against static TriMesh.
- Uniform grid broadphase for triangle candidate queries.
- Move-and-slide with ground probe/snap for stable terrain traversal.
- Capsule-capsule CCD for agent interactions with separation and velocity correction.
- BVH build uses in-place partitioning; refit deduplicates parent updates for better rebuild/refit performance.
- Walkable ground flattening is material-driven (SurfaceMaterial.flattenGround) for slope-as-floor behavior.

## Input / Character Setup
- Gamepad movement uses two-speed walk/run based on stick magnitude threshold; acceleration/deceleration still smooths.
- Player character creation (mesh/material/motion profiles/colliders) centralized in CharacterFactory.

## 2025-01-14 Update (Skin/Mesh/Material Pipeline)
- Added offline Blender export tools to generate skinned mesh JSON from FBX, with vertex weld + multi-mesh merge and submesh (material slot) splitting.
- Added offline Blender export tool to generate materials JSON (procedural PBR parameters) from FBX.
- Runtime now loads skinned mesh JSON assets, supports submeshes, and builds skinning palette using JSON inverse bind matrices with unit-scale + row/column correction.
- Added JSON-driven material loader for procedural PBR generation and wired submesh materials in DemoScene.
- DemoScene now uses YBot.skinned.json + YBot.materials.json for the player; animation re-enabled.
- Skeleton data for Mixamo Y Bot is now assetized as YBot.skeleton.json and loaded at runtime (no hardcoded skeleton arrays).
- Skeleton JSON schema now supports rigProfile definitions and per-semantic alias overrides to map bones without code changes.
- Skeleton root rules are JSON-driven (auto/zero/keep) with root rotation fix specified per asset.

## 2026-03-09 Update (Static Mesh + Collision + Perf)
- Added offline FBX static mesh exporter (FbxToStaticMeshJson) that outputs multi-mesh JSON with per-mesh transforms.
- Static mesh JSON now includes simplified collision hulls per part (loose parts -> convex hull -> decimate), with tunable max hulls and face limits.
- Added runtime StaticMeshLoader that returns per-part ProceduralMeshDescriptor + submesh materials + collision hulls.
- DemoScene loads 17-Cheese.static.json, spawns per-part render meshes, and visualizes collision hulls with transparent meshes.
- FBX material export now parses node networks and emits texture paths + channel hints.
- MaterialLoader now loads texture files at runtime when paths exist (no baked defaults).
- Collision system now supports layers/masks on StaticMeshComponent and CharacterControllerComponent for selective collision.
- Added CPU/GPU perf logging for update, RT encode, render graph, draw/tri counts, and GPU time.
- Added Semla static mesh/material JSON import, with runtime UV V-flip support in static mesh export.
- Semla textures manually copied into Game/ and wired in Semla.materials.json; AO optional and can be skipped.
