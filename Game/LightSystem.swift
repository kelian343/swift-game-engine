//
//  LightSystem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import simd

final class LightSystem {
    let buffer: MTLBuffer

    init(device: MTLDevice) {
        buffer = device.makeBuffer(length: MemoryLayout<LightParams>.stride, options: [.storageModeShared])!
        buffer.label = "LightParams"
    }

    func update(cameraPos: SIMD3<Float>) {
        let p = buffer.contents().bindMemory(to: LightParams.self, capacity: 1)

        let dir = simd_normalize(SIMD3<Float>(-0.5, -1.0, -0.3))
        p[0].lightDirection = dir
        p[0].lightColor = SIMD3<Float>(1, 1, 1)
        p[0].ambientIntensity = 0.08
        p[0].cameraPosition = cameraPos
        p[0].shadowBias = 0.003
    }

    func lightViewProj() -> matrix_float4x4 {
        let lightDir = simd_normalize(SIMD3<Float>(-0.5, -1.0, -0.3))
        let center = SIMD3<Float>(0, 0, 0)
        let lightPos = center - lightDir * 15.0

        let view = lookAtRH(eye: lightPos, center: center, up: SIMD3<Float>(0,1,0))
        let proj = orthoRH(left: -12, right: 12, bottom: -12, top: 12, near: 0.1, far: 40)
        return simd_mul(proj, view)
    }
}
