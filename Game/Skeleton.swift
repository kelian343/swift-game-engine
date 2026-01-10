//
//  Skeleton.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public struct Skeleton {
    public let boneCount: Int
    public let parent: [Int]
    public let bindLocal: [matrix_float4x4]
    public let invBindModel: [matrix_float4x4]

    public init(parent: [Int], bindLocal: [matrix_float4x4]) {
        precondition(parent.count == bindLocal.count, "Skeleton parent/bindLocal count mismatch")
        self.parent = parent
        self.bindLocal = bindLocal
        self.boneCount = parent.count
        let model = Skeleton.buildModelTransforms(parent: parent, local: bindLocal)
        self.invBindModel = model.map { simd_inverse($0) }
    }

    public static func buildModelTransforms(parent: [Int],
                                            local: [matrix_float4x4]) -> [matrix_float4x4] {
        var model = Array(repeating: matrix_identity_float4x4, count: local.count)
        for i in 0..<local.count {
            let p = parent[i]
            if p < 0 {
                model[i] = local[i]
            } else {
                model[i] = simd_mul(model[p], local[i])
            }
        }
        return model
    }

    public static func humanoid8() -> Skeleton {
        let hipOffsetX: Float = 0.45
        let spineY: Float = 0.75
        let chestY: Float = 0.5
        let headY: Float = 0.5
        let thighY: Float = -0.8
        let calfY: Float = -0.75

        let parent: [Int] = [
            -1, // pelvis
            0,  // spine
            1,  // head
            0,  // thigh_L
            3,  // calf_L
            0,  // thigh_R
            5,  // calf_R
            1   // chest
        ]

        let bindLocal: [matrix_float4x4] = [
            matrix_identity_float4x4,                           // pelvis
            matrix4x4_translation(0, spineY, 0),                // spine
            matrix4x4_translation(0, headY, 0),                 // head
            matrix4x4_translation(-hipOffsetX, thighY, 0),      // thigh_L
            matrix4x4_translation(0, calfY, 0),                 // calf_L
            matrix4x4_translation(hipOffsetX, thighY, 0),       // thigh_R
            matrix4x4_translation(0, calfY, 0),                 // calf_R
            matrix4x4_translation(0, chestY, 0)                 // chest
        ]

        return Skeleton(parent: parent, bindLocal: bindLocal)
    }
}
