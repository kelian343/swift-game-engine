//
//  RayTracingTypes.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

struct RTFrameUniformsSwift {
    var invViewProj: matrix_float4x4
    var cameraPosition: SIMD3<Float>
    var frameIndex: UInt32
    var imageSize: SIMD2<UInt32>
    var lightDirection: SIMD3<Float>
    var lightIntensity: Float
    var lightColor: SIMD3<Float>
    var ambientIntensity: Float
}

struct RTInstanceInfoSwift {
    var baseIndex: UInt32
    var baseVertex: UInt32
    var indexCount: UInt32
    var padding: UInt32
    var modelMatrix: matrix_float4x4
}
