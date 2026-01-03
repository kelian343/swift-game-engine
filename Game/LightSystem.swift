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
    private var cachedLightViewProj = matrix_identity_float4x4

    init(device: MTLDevice) {
        buffer = device.makeBuffer(length: MemoryLayout<LightParams>.stride, options: [.storageModeShared])!
        buffer.label = "LightParams"
    }

    func update(cameraPos: SIMD3<Float>,
                cameraViewProj: matrix_float4x4,
                shadowMapSize: Int) {
        let p = buffer.contents().bindMemory(to: LightParams.self, capacity: 1)

        let dir = simd_normalize(SIMD3<Float>(-0.5, -1.0, -0.3))
        p[0].lightDirection = dir
        p[0].lightColor = SIMD3<Float>(1, 1, 1)
        p[0].ambientIntensity = 0.08
        p[0].cameraPosition = cameraPos
        p[0].shadowMapSize = SIMD2<Float>(Float(shadowMapSize), Float(shadowMapSize))
        p[0].normalBias = 0.004
        p[0].slopeBias = 0.0015

        cachedLightViewProj = buildLightViewProj(cameraViewProj: cameraViewProj,
                                                 lightDir: dir,
                                                 shadowMapSize: shadowMapSize)
    }

    func lightViewProj() -> matrix_float4x4 {
        cachedLightViewProj
    }

    private func buildLightViewProj(cameraViewProj: matrix_float4x4,
                                    lightDir: SIMD3<Float>,
                                    shadowMapSize: Int) -> matrix_float4x4 {
        let invViewProj = simd_inverse(cameraViewProj)

        let ndc: [SIMD3<Float>] = [
            SIMD3<Float>(-1, -1, 0),
            SIMD3<Float>( 1, -1, 0),
            SIMD3<Float>( 1,  1, 0),
            SIMD3<Float>(-1,  1, 0),
            SIMD3<Float>(-1, -1, 1),
            SIMD3<Float>( 1, -1, 1),
            SIMD3<Float>( 1,  1, 1),
            SIMD3<Float>(-1,  1, 1),
        ]

        var corners: [SIMD3<Float>] = []
        corners.reserveCapacity(8)

        for p in ndc {
            let h = SIMD4<Float>(p.x, p.y, p.z, 1)
            let w = simd_mul(invViewProj, h)
            corners.append(SIMD3<Float>(w.x, w.y, w.z) / w.w)
        }

        var center = SIMD3<Float>(repeating: 0)
        for c in corners { center += c }
        center /= Float(corners.count)

        let radius = corners.map { simd_length($0 - center) }.max() ?? 1
        let lightPos = center - lightDir * radius * 2.0

        let view = lookAtRH(eye: lightPos, center: center, up: SIMD3<Float>(0, 1, 0))

        var minV = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for c in corners {
            let v = simd_mul(view, SIMD4<Float>(c, 1))
            minV = simd.min(minV, SIMD3<Float>(v.x, v.y, v.z))
            maxV = simd.max(maxV, SIMD3<Float>(v.x, v.y, v.z))
        }

        let margin: Float = 2.0
        minV -= SIMD3<Float>(repeating: margin)
        maxV += SIMD3<Float>(repeating: margin)

        let size = maxV - minV
        let texelSize = SIMD2<Float>(size.x / Float(shadowMapSize),
                                     size.y / Float(shadowMapSize))
        let centerLS = (minV + maxV) * 0.5
        let snappedCenter = SIMD3<Float>(
            floor(centerLS.x / texelSize.x) * texelSize.x,
            floor(centerLS.y / texelSize.y) * texelSize.y,
            centerLS.z
        )
        let half = size * 0.5
        minV = snappedCenter - half
        maxV = snappedCenter + half

        let near = max(0.1, -maxV.z)
        let far = max(near + 0.1, -minV.z)

        let proj = orthoRH(left: minV.x, right: maxV.x,
                           bottom: minV.y, top: maxV.y,
                           near: near, far: far)
        return simd_mul(proj, view)
    }
}
