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
    var ambientIntensity: Float
    var historyWeight: Float
    var historyClamp: Float
    var samplesPerPixel: UInt32
    var dirLightCount: UInt32
    var pointLightCount: UInt32
    var areaLightCount: UInt32
    var areaLightSamples: UInt32
    var textureCount: UInt32
    var denoiseSigma: Float
    var padding: SIMD2<Float>
}

struct RTDirectionalLightSwift {
    var direction: SIMD3<Float>
    var intensity: Float
    var color: SIMD3<Float>
    var padding: Float
}

struct RTPointLightSwift {
    var position: SIMD3<Float>
    var intensity: Float
    var color: SIMD3<Float>
    var radius: Float
}

struct RTAreaLightSwift {
    var position: SIMD3<Float>
    var intensity: Float
    var u: SIMD3<Float>
    var padding0: Float
    var v: SIMD3<Float>
    var padding1: Float
    var color: SIMD3<Float>
    var padding2: Float
}

struct RTInstanceInfoSwift {
    var baseIndex: UInt32
    var baseVertex: UInt32
    var indexCount: UInt32
    var padding: UInt32
    var modelMatrix: matrix_float4x4
    var baseColor: SIMD3<Float>
    var metallic: Float
    var roughness: Float
    var padding2: SIMD3<Float>
    var baseColorTexIndex: UInt32
    var padding3: SIMD3<UInt32>
}
