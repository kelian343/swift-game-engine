//
//  ProceduralPoseSystem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class ProceduralPoseSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let entities = world.query(SkeletonComponent.self, PoseComponent.self)
        if entities.isEmpty { return }

        let sStore = world.store(SkeletonComponent.self)
        let pStore = world.store(PoseComponent.self)
        let bodyStore = world.store(PhysicsBodyComponent.self)
        let controllerStore = world.store(CharacterControllerComponent.self)

        for e in entities {
            guard let skeleton = sStore[e]?.skeleton,
                  var pose = pStore[e] else {
                continue
            }

            if pose.local.count != skeleton.boneCount {
                pose = PoseComponent(boneCount: skeleton.boneCount, local: skeleton.bindLocal)
            }

            let freezePose = true
            if freezePose {
                // Keep bind pose (T-pose) and skip procedural motion.
                pose.local = skeleton.bindLocal
                pose.model = Skeleton.buildModelTransforms(parent: skeleton.parent, local: pose.local)
                pose.palette = zip(pose.model, skeleton.invBindModel).map { simd_mul($0, $1) }
                pStore[e] = pose
                continue
            }

            let body = bodyStore[e]
            let controller = controllerStore[e]

            let vel = body?.linearVelocity ?? .zero
            let speed = simd_length(SIMD3<Float>(vel.x, 0, vel.z))
            let baseFreq: Float = 1.4
            let speedFreq: Float = 0.5
            pose.phase += dt * (baseFreq + speed * speedFreq) * 2.0 * .pi
            pose.phase = pose.phase.truncatingRemainder(dividingBy: 2.0 * .pi)

            let phase = pose.phase
            let bobAmp: Float = 0.08
            let pelvisBob = sin(phase * 2.0) * bobAmp

            let groundNormal = controller?.groundNormal ?? SIMD3<Float>(0, 1, 0)
            let useTilt = controller?.groundedNear ?? false
            let tiltQuat = useTilt ? rotationFromUp(to: groundNormal) : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

            var local = skeleton.bindLocal
            let yawFix = matrix4x4_rotation(radians: .pi, axis: SIMD3<Float>(0, 1, 0))
            if let pelvis = skeleton.semantic(.pelvis) {
                local[pelvis] = simd_mul(local[pelvis],
                                         simd_mul(matrix4x4_translation(0, pelvisBob, 0),
                                                  simd_mul(matrix_float4x4(tiltQuat), yawFix)))
            }

            let thighAmp: Float = 0.7
            let calfAmp: Float = 0.6
            let spineAmp: Float = 0.2
            let chestTwist: Float = 0.15

            let s0 = sin(phase)
            let s1 = sin(phase + .pi)

            if let thighL = skeleton.semantic(.thighL) {
                local[thighL] = simd_mul(local[thighL],
                                         matrix4x4_rotation(radians: s0 * thighAmp, axis: SIMD3<Float>(1, 0, 0)))
            }
            if let calfL = skeleton.semantic(.calfL) {
                local[calfL] = simd_mul(local[calfL],
                                        matrix4x4_rotation(radians: max(0, -s0) * calfAmp, axis: SIMD3<Float>(1, 0, 0)))
            }
            if let thighR = skeleton.semantic(.thighR) {
                local[thighR] = simd_mul(local[thighR],
                                         matrix4x4_rotation(radians: s1 * thighAmp, axis: SIMD3<Float>(1, 0, 0)))
            }
            if let calfR = skeleton.semantic(.calfR) {
                local[calfR] = simd_mul(local[calfR],
                                        matrix4x4_rotation(radians: max(0, -s1) * calfAmp, axis: SIMD3<Float>(1, 0, 0)))
            }

            if let spine = skeleton.semantic(.spine1) {
                local[spine] = simd_mul(local[spine],
                                        matrix4x4_rotation(radians: -s0 * spineAmp, axis: SIMD3<Float>(1, 0, 0)))
            }
            if let chest = skeleton.semantic(.chest) ?? skeleton.semantic(.spine2) {
                local[chest] = simd_mul(local[chest],
                                        matrix4x4_rotation(radians: s0 * chestTwist, axis: SIMD3<Float>(0, 1, 0)))
            }
            if let head = skeleton.semantic(.head) {
                local[head] = simd_mul(local[head],
                                       matrix4x4_rotation(radians: -pelvisBob * 0.5, axis: SIMD3<Float>(1, 0, 0)))
            }

            pose.local = local
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
