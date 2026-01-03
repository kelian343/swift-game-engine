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
                   model: matrix_float4x4) {

    ptr[0].projectionMatrix = projection
    ptr[0].viewMatrix = view
    ptr[0].modelMatrix = model
}
