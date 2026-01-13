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

            pose.model = Skeleton.buildModelTransforms(parent: skeleton.parent, local: pose.local)
            pose.palette = zip(pose.model, skeleton.invBindModel).map { simd_mul($0, $1) }

            pStore[e] = pose
        }
    }
}
