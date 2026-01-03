//
//  UniformWriter.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

func writeUniforms(_ ptr: UnsafeMutablePointer<Uniforms>,
                   projection: matrix_float4x4,
                   view: matrix_float4x4,
                   model: matrix_float4x4,
                   lightViewProj: matrix_float4x4) {

    ptr[0].projectionMatrix = projection
    ptr[0].viewMatrix = view
    ptr[0].modelMatrix = model
    ptr[0].lightViewProjMatrix = lightViewProj

    let n3 = NormalMatrix.fromModel(model)
    ptr[0].normalMatrix0 = SIMD4<Float>(n3.columns.0, 0)
    ptr[0].normalMatrix1 = SIMD4<Float>(n3.columns.1, 0)
    ptr[0].normalMatrix2 = SIMD4<Float>(n3.columns.2, 0)
}
