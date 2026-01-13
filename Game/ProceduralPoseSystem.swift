//
//  ProceduralPoseSystem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class PoseStackSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let entities = world.query(SkeletonComponent.self, PoseComponent.self)
        if entities.isEmpty { return }

        let sStore = world.store(SkeletonComponent.self)
        let pStore = world.store(PoseComponent.self)
        let aStore = world.store(AnimationComponent.self)
        let tStore = world.store(TransformComponent.self)
        let controllerStore = world.store(CharacterControllerComponent.self)

        for e in entities {
            guard let skeleton = sStore[e]?.skeleton,
                  var pose = pStore[e] else {
                continue
            }

            if pose.local.count != skeleton.boneCount {
                pose = PoseComponent(boneCount: skeleton.boneCount, local: skeleton.bindLocal)
            }

            if var anim = aStore[e] {
                let clip = anim.clip
                anim.time += dt * anim.playbackRate
                if anim.loop {
                    anim.time = anim.time.truncatingRemainder(dividingBy: clip.duration)
                } else {
                    anim.time = min(anim.time, clip.duration)
                }

                var local = skeleton.bindLocal
                for i in 0..<skeleton.boneCount {
                    let name = skeleton.names[i]
                    guard let boneAnim = clip.boneAnimations[name] else {
                        continue
                    }

                    let restScaled = skeleton.restTranslation[i]
                    let restRaw = skeleton.rawRestTranslation[i]
                    let animRaw = boneAnim.translation?.sample(at: anim.time, defaultValue: restRaw) ?? restRaw
                    let delta = animRaw - restRaw
                    var t = restScaled + (delta * skeleton.unitScale)

                    if i == 0 && anim.inPlace {
                        t.x = restScaled.x
                        t.z = restScaled.z
                    }

                    let defaultR = SIMD3<Float>(0, 0, 0)
                    let animR = boneAnim.rotation?.sample(at: anim.time, defaultValue: defaultR) ?? defaultR
                    var rot = simd_mul(Skeleton.rotationXYZDegrees(skeleton.preRotationDegrees[i]),
                                       Skeleton.rotationXYZDegrees(animR))
                    if i == 0 {
                        rot = simd_mul(skeleton.rootRotationFix, rot)
                    }

                    let trans = matrix4x4_translation(t.x, t.y, t.z)
                    local[i] = simd_mul(trans, rot)
                }
                pose.local = local
                aStore[e] = anim
            } else {
                pose.local = skeleton.bindLocal
            }

            if let pelvis = skeleton.semantic(.pelvis) {
                let forward = tStore[e].map { simd_act($0.rotation, SIMD3<Float>(0, 0, -1)) }
                    ?? SIMD3<Float>(0, 0, -1)
                let forwardHoriz = simd_length_squared(SIMD3<Float>(forward.x, 0, forward.z)) > 0.0001
                    ? simd_normalize(SIMD3<Float>(forward.x, 0, forward.z))
                    : SIMD3<Float>(0, 0, -1)
                let groundNormal = controllerStore[e]?.groundNormal ?? SIMD3<Float>(0, 1, 0)
                let useTilt = controllerStore[e]?.groundedNear ?? false
                let alignStrength: Float = 0.33
                let alignQuat: simd_quatf = {
                    guard useTilt else {
                        return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                    }
                    // Pitch-only align: remove roll by projecting the normal into the forward/up plane.
                    let up = SIMD3<Float>(0, 1, 0)
                    let right = simd_normalize(simd_cross(up, forwardHoriz))
                    let nProj = simd_normalize(groundNormal - right * simd_dot(groundNormal, right))
                    let crossUp = simd_cross(up, nProj)
                    let angle = atan2(simd_dot(crossUp, right), simd_dot(up, nProj)) * alignStrength
                    return simd_quatf(angle: angle, axis: right)
                }()
                let alignMat = matrix_float4x4(alignQuat)
                // Apply in parent space to avoid local-axis skew from pre-rotations.
                pose.local[pelvis] = simd_mul(alignMat, pose.local[pelvis])
            }

            pose.model = Skeleton.buildModelTransforms(parent: skeleton.parent, local: pose.local)
            pose.palette = zip(pose.model, skeleton.invBindModel).map { simd_mul($0, $1) }

            pStore[e] = pose
        }
    }
}

private func rotationFromUp(to normal: SIMD3<Float>) -> simd_quatf {
    let up = SIMD3<Float>(0, 1, 0)
    let n = simd_normalize(normal)
    let d = max(-1.0, min(1.0, simd_dot(up, n)))
    if d > 0.999 {
        return simd_quatf(angle: 0, axis: up)
    }
    if d < -0.999 {
        return simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
    }
    let axis = simd_normalize(simd_cross(up, n))
    let angle = acos(d)
    return simd_quatf(angle: angle, axis: axis)
}
