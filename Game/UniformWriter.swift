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
                   baseColorFactor: SIMD3<Float>,
                   baseAlpha: Float,
                   unlit: Bool,
                   normalScale: Float,
                   cameraPosition: SIMD3<Float>) {

    ptr[0].projectionMatrix = projection
    ptr[0].viewMatrix = view
    ptr[0].modelMatrix = model
    ptr[0].baseColorFactor = baseColorFactor
    ptr[0].baseAlpha = baseAlpha
    ptr[0].unlit = unlit ? 1.0 : 0.0
    ptr[0].normalScale = normalScale
    ptr[0].cameraPosition = cameraPosition
}
