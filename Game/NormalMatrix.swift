//
//  NormalMatrix.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

enum NormalMatrix {
    /// inverse-transpose of model's upper-left 3x3
    static func fromModel(_ model: matrix_float4x4) -> float3x3 {
        let c0 = SIMD3<Float>(model.columns.0.x, model.columns.0.y, model.columns.0.z)
        let c1 = SIMD3<Float>(model.columns.1.x, model.columns.1.y, model.columns.1.z)
        let c2 = SIMD3<Float>(model.columns.2.x, model.columns.2.y, model.columns.2.z)
        let m3 = float3x3([c0, c1, c2])
        return m3.inverse.transpose
    }
}
