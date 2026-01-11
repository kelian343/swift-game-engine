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
    var imageSize: SIMD2<UInt32>
    var ambientIntensity: Float
    var pad0: UInt32
    var textureCount: UInt32
    var dirLightCount: UInt32
    var envMipCount: UInt32
    var pad1: UInt32
    var envSH0: SIMD3<Float>
    var envSH1: SIMD3<Float>
    var envSH2: SIMD3<Float>
    var envSH3: SIMD3<Float>
    var envSH4: SIMD3<Float>
    var envSH5: SIMD3<Float>
    var envSH6: SIMD3<Float>
    var envSH7: SIMD3<Float>
    var envSH8: SIMD3<Float>
}

struct RTDirectionalLightSwift {
    var direction: SIMD3<Float>
    var intensity: Float
    var color: SIMD3<Float>
    var enabled: Float
    var maxDistance: Float
    var padding: SIMD3<Float>
}


struct RTInstanceInfoSwift {
    var baseIndex: UInt32
    var baseVertex: UInt32
    var indexCount: UInt32
    var bufferIndex: UInt32
    var modelMatrix: matrix_float4x4
    var baseColorFactor: SIMD3<Float>
    var metallicFactor: Float
    var emissiveFactor: SIMD3<Float>
    var occlusionStrength: Float
    var mrFactors: SIMD2<Float>
    var padding0: SIMD2<Float>
    var normalScale: Float
    var pad2: SIMD3<Float>
    var baseColorTexIndex: UInt32
    var normalTexIndex: UInt32
    var metallicRoughnessTexIndex: UInt32
    var emissiveTexIndex: UInt32
    var occlusionTexIndex: UInt32
    var padding1: SIMD3<UInt32>
}
