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
- Base layer now samples Walking.fbx animation (Mixamo bone names) with in-place root option.
- Procedural corrections are reserved for follow-up layers (ground alignment/lean/IK).
- GPU skinning uses palette buffers to write skinned vertices each frame.
- Skeleton replaced with Mixamo Y Bot (65 bones, mixamorig naming), pelvis-aligned root, FBX PreRotation/LclRotation applied, facing fix on root.

## Physics System (Collision)
- Kinematic capsule movement with sweep CCD against static TriMesh.
- Uniform grid broadphase for triangle candidate queries.
- Move-and-slide with ground probe/snap for stable terrain traversal.
- Capsule-capsule CCD for agent interactions with separation and velocity correction.

## Known Issue
- Wall/edge corner jitter resolved: pre-sweep depenetration now uses the deepest single contact normal for side hits and skips slop on side contacts (push capped by skinWidth), preventing cross-corner jumps.
