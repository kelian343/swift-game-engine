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
        let mStore = world.store(MotionProfileComponent.self)
        let lStore = world.store(LocomotionProfileComponent.self)
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

            if var locomotion = lStore[e],
               let profile = mStore[e] {
                let idleCycle = max(locomotion.idleProfile.phase?.cycleDuration ?? locomotion.idleProfile.duration, 0.001)
                let walkCycle = max(locomotion.walkProfile.phase?.cycleDuration ?? locomotion.walkProfile.duration, 0.001)
                locomotion.idleTime += dt * profile.playbackRate
                locomotion.walkTime += dt * profile.playbackRate
                if profile.loop {
                    locomotion.idleTime = locomotion.idleTime.truncatingRemainder(dividingBy: idleCycle)
                    locomotion.walkTime = locomotion.walkTime.truncatingRemainder(dividingBy: walkCycle)
                } else {
                    locomotion.idleTime = min(locomotion.idleTime, idleCycle)
                    locomotion.walkTime = min(locomotion.walkTime, walkCycle)
                }

                if locomotion.isBlending {
                    let blendDuration = max(locomotion.blendTime, 0.001)
                    locomotion.blendT = min(locomotion.blendT + dt / blendDuration, 1.0)
                    if locomotion.blendT >= 1.0 {
                        locomotion.isBlending = false
                    }
                }

                let phaseIdle = max(0, min(locomotion.idleTime / idleCycle, 1))
                let phaseWalk = max(0, min(locomotion.walkTime / walkCycle, 1))
                pose.phase = locomotion.isIdle ? phaseIdle : phaseWalk

                if pose.local.count != skeleton.boneCount {
                    pose.local = Array(repeating: matrix_identity_float4x4, count: skeleton.boneCount)
                }
                for i in 0..<skeleton.boneCount {
                    pose.local[i] = skeleton.bindLocal[i]
                }

                let weightWalk: Float = {
                    if locomotion.isBlending {
                        return locomotion.isIdle ? (1.0 - locomotion.blendT) : locomotion.blendT
                    }
                    return locomotion.isIdle ? 0.0 : 1.0
                }()

                for i in 0..<skeleton.boneCount {
                    let name = skeleton.names[i]
                    let restScaled = skeleton.restTranslation[i]
                    let restRaw = skeleton.rawRestTranslation[i]

                    let idleBone = locomotion.idleProfile.bones[name]
                    let walkBone = locomotion.walkProfile.bones[name]

                    let idleRaw = idleBone.map {
                        MotionProfileEvaluator.evaluateChannel($0.translation,
                                                               phase: phaseIdle,
                                                               order: locomotion.idleProfile.order,
                                                               defaultValue: restRaw)
                    } ?? restRaw
                    let walkRaw = walkBone.map {
                        MotionProfileEvaluator.evaluateChannel($0.translation,
                                                               phase: phaseWalk,
                                                               order: locomotion.walkProfile.order,
                                                               defaultValue: restRaw)
                    } ?? restRaw

                    let idleDelta = idleRaw - restRaw
                    let walkDelta = walkRaw - restRaw
                    var idleT = restScaled + (idleDelta * skeleton.unitScale)
                    var walkT = restScaled + (walkDelta * skeleton.unitScale)

                    if i == 0 && profile.inPlace {
                        idleT.x = restScaled.x
                        idleT.z = restScaled.z
                        walkT.x = restScaled.x
                        walkT.z = restScaled.z
                    }

                    let idleR = idleBone.map {
                        MotionProfileEvaluator.evaluateChannel($0.rotation,
                                                               phase: phaseIdle,
                                                               order: locomotion.idleProfile.order,
                                                               defaultValue: SIMD3<Float>(0, 0, 0))
                    } ?? SIMD3<Float>(0, 0, 0)
                    let walkR = walkBone.map {
                        MotionProfileEvaluator.evaluateChannel($0.rotation,
                                                               phase: phaseWalk,
                                                               order: locomotion.walkProfile.order,
                                                               defaultValue: SIMD3<Float>(0, 0, 0))
                    } ?? SIMD3<Float>(0, 0, 0)
                    var idleRot = simd_mul(Skeleton.rotationXYZDegrees(skeleton.preRotationDegrees[i]),
                                           Skeleton.rotationXYZDegrees(idleR))
                    var walkRot = simd_mul(Skeleton.rotationXYZDegrees(skeleton.preRotationDegrees[i]),
                                           Skeleton.rotationXYZDegrees(walkR))
                    if i == 0 {
                        idleRot = simd_mul(skeleton.rootRotationFix, idleRot)
                        walkRot = simd_mul(skeleton.rootRotationFix, walkRot)
                    }

                    let t = idleT + (walkT - idleT) * weightWalk
                    let idleQuat = simd_quaternion(idleRot)
                    let walkQuat = simd_quaternion(walkRot)
                    let rotQuat = simd_slerp(idleQuat, walkQuat, weightWalk)
                    let trans = matrix4x4_translation(t.x, t.y, t.z)
                    pose.local[i] = simd_mul(trans, matrix_float4x4(rotQuat))
                }
                lStore[e] = locomotion
                mStore[e] = profile
            } else if var profile = mStore[e] {
                let cycle = max(profile.profile.phase?.cycleDuration ?? profile.profile.duration, 0.001)
                profile.time += dt * profile.playbackRate
                if profile.loop {
                    profile.time = profile.time.truncatingRemainder(dividingBy: cycle)
                } else {
                    profile.time = min(profile.time, cycle)
                }

                let phase = max(0, min(profile.time / cycle, 1))
                pose.phase = phase

                // Reset local to bind pose without allocating a new array.
                if pose.local.count != skeleton.boneCount {
                    pose.local = Array(repeating: matrix_identity_float4x4, count: skeleton.boneCount)
                }
                for i in 0..<skeleton.boneCount {
                    pose.local[i] = skeleton.bindLocal[i]
                }
                for i in 0..<skeleton.boneCount {
                    let name = skeleton.names[i]
                    guard let bone = profile.profile.bones[name] else {
                        continue
                    }

                    let restScaled = skeleton.restTranslation[i]
                    let restRaw = skeleton.rawRestTranslation[i]
                    let animRaw = MotionProfileEvaluator.evaluateChannel(bone.translation,
                                                                         phase: phase,
                                                                         order: profile.profile.order,
                                                                         defaultValue: restRaw)
                    let delta = animRaw - restRaw
                    var t = restScaled + (delta * skeleton.unitScale)

                    if i == 0 && profile.inPlace {
                        t.x = restScaled.x
                        t.z = restScaled.z
                    }

                    let animR = MotionProfileEvaluator.evaluateChannel(bone.rotation,
                                                                       phase: phase,
                                                                       order: profile.profile.order,
                                                                       defaultValue: SIMD3<Float>(0, 0, 0))
                    var rot = simd_mul(Skeleton.rotationXYZDegrees(skeleton.preRotationDegrees[i]),
                                       Skeleton.rotationXYZDegrees(animR))
                    if i == 0 {
                        rot = simd_mul(skeleton.rootRotationFix, rot)
                    }

                    let trans = matrix4x4_translation(t.x, t.y, t.z)
                    pose.local[i] = simd_mul(trans, rot)
                }
                mStore[e] = profile
            } else {
                if pose.local.count != skeleton.boneCount {
                    pose.local = Array(repeating: matrix_identity_float4x4, count: skeleton.boneCount)
                }
                for i in 0..<skeleton.boneCount {
                    pose.local[i] = skeleton.bindLocal[i]
                }
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

            Skeleton.buildModelTransforms(parent: skeleton.parent, local: pose.local, into: &pose.model)
            if pose.palette.count != skeleton.boneCount {
                pose.palette = Array(repeating: matrix_identity_float4x4, count: skeleton.boneCount)
            }
            for i in 0..<skeleton.boneCount {
                pose.palette[i] = simd_mul(pose.model[i], skeleton.invBindModel[i])
            }

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
