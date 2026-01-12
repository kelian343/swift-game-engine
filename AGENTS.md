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
- Skeleton and pose components drive procedural animation.
- Pose system computes local/model transforms and palette per fixed step.
- Procedural pose is speed-driven with ground-aware adjustments.
- GPU skinning uses palette buffers to write skinned vertices each frame.

## Physics System (Collision)
- Kinematic capsule movement with sweep CCD against static TriMesh.
- Uniform grid broadphase for triangle candidate queries.
- Move-and-slide with ground probe/snap for stable terrain traversal.
- Capsule-capsule CCD for agent interactions with separation and velocity correction.

## Known Issue
- Residual wall contact jitter: after recent collision refactors (BVH + overlap depenetration + sticky slide), characters can still exhibit small oscillations when continuously pushing into walls/edges. Logs show repeated `slide-stick` hits (low TOI) and `depenetration` on multiple triangle normals within the same area. Requires a stable contact manifold or velocity/intent projection onto the contact plane without reintroducing general wall jitter.
