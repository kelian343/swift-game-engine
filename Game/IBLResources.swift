//
//  IBLResources.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Metal
import simd

final class IBLResources {
    let envCube: MTLTexture
    let brdfLUT: MTLTexture
    let envMipCount: UInt32

    init(device: MTLDevice) {
        let envSize = 128
        let envDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm,
                                                                  size: envSize,
                                                                  mipmapped: true)
        envDesc.usage = [.shaderRead]
        envDesc.storageMode = .shared
        let env = device.makeTexture(descriptor: envDesc)!
        env.label = "IBL.EnvCube"

        let mipCount = env.mipmapLevelCount
        for mip in 0..<mipCount {
            let size = max(envSize >> mip, 1)
            let roughness = mipCount > 1 ? Float(mip) / Float(mipCount - 1) : 0.0
            for face in 0..<6 {
                var bytes = [UInt8](repeating: 0, count: size * size * 4)
                for y in 0..<size {
                    for x in 0..<size {
                        let u = (2.0 * (Float(x) + 0.5) / Float(size)) - 1.0
                        let v = (2.0 * (Float(y) + 0.5) / Float(size)) - 1.0
                        let dir = cubeDirection(face: face, u: u, v: v)
                        let color = sampleEnvColor(dir: dir, roughness: roughness)
                        let idx = (y * size + x) * 4
                        bytes[idx + 0] = UInt8(max(0, min(255, Int(color.x * 255.0))))
                        bytes[idx + 1] = UInt8(max(0, min(255, Int(color.y * 255.0))))
                        bytes[idx + 2] = UInt8(max(0, min(255, Int(color.z * 255.0))))
                        bytes[idx + 3] = 255
                    }
                }
                let region = MTLRegionMake2D(0, 0, size, size)
                bytes.withUnsafeBytes { raw in
                    env.replace(region: region,
                                mipmapLevel: mip,
                                slice: face,
                                withBytes: raw.baseAddress!,
                                bytesPerRow: size * 4,
                                bytesPerImage: size * size * 4)
                }
            }
        }

        self.envCube = env
        self.envMipCount = UInt32(env.mipmapLevelCount)

        let lutSize = 128
        let lutDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                               width: lutSize,
                                                               height: lutSize,
                                                               mipmapped: false)
        lutDesc.usage = [.shaderRead]
        lutDesc.storageMode = .shared
        let lut = device.makeTexture(descriptor: lutDesc)!
        lut.label = "IBL.BRDFLUT"
        var lutData = [Float](repeating: 0, count: lutSize * lutSize * 4)
        for y in 0..<lutSize {
            let roughness = max(Float(y) / Float(lutSize - 1), 0.001)
            for x in 0..<lutSize {
                let nDotV = max(Float(x) / Float(lutSize - 1), 0.001)
                let brdf = integrateBRDF(nDotV: nDotV, roughness: roughness, sampleCount: 256)
                let idx = (y * lutSize + x) * 4
                lutData[idx + 0] = brdf.x
                lutData[idx + 1] = brdf.y
                lutData[idx + 2] = 0
                lutData[idx + 3] = 0
            }
        }
        lutData.withUnsafeBytes { raw in
            let region = MTLRegionMake2D(0, 0, lutSize, lutSize)
            lut.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: lutSize * MemoryLayout<SIMD4<Float>>.stride)
        }
        self.brdfLUT = lut
    }
}

private func cubeDirection(face: Int, u: Float, v: Float) -> SIMD3<Float> {
    let dir: SIMD3<Float>
    switch face {
    case 0: dir = SIMD3<Float>( 1, -v, -u) // +X
    case 1: dir = SIMD3<Float>(-1, -v,  u) // -X
    case 2: dir = SIMD3<Float>( u,  1,  v) // +Y
    case 3: dir = SIMD3<Float>( u, -1, -v) // -Y
    case 4: dir = SIMD3<Float>( u, -v,  1) // +Z
    default: dir = SIMD3<Float>(-u, -v, -1) // -Z
    }
    return simd_normalize(dir)
}

private func sampleEnvColor(dir: SIMD3<Float>, roughness: Float) -> SIMD3<Float> {
    let sky = SIMD3<Float>(0.65, 0.72, 0.9)
    let ground = SIMD3<Float>(0.12, 0.12, 0.14)
    let t = max(min(dir.y * 0.5 + 0.5, 1.0), 0.0)
    var color = simd_mix(ground, sky, SIMD3<Float>(repeating: t))

    let sunDir = simd_normalize(SIMD3<Float>(0.2, 0.9, 0.1))
    let ndotl = max(simd_dot(dir, sunDir), 0.0)
    let exponent = simd_mix(800.0, 30.0, roughness)
    let sun = pow(ndotl, exponent) * 4.0
    color += SIMD3<Float>(repeating: sun)

    return simd_clamp(color, SIMD3<Float>(repeating: 0.0), SIMD3<Float>(repeating: 1.0))
}

private func integrateBRDF(nDotV: Float, roughness: Float, sampleCount: Int) -> SIMD2<Float> {
    let V = SIMD3<Float>(sqrt(max(1.0 - nDotV * nDotV, 0.0)), 0.0, nDotV)
    var A: Float = 0.0
    var B: Float = 0.0
    for i in 0..<sampleCount {
        let xi = hammersley(i: i, count: sampleCount)
        let H = importanceSampleGGX(xi: xi, roughness: roughness)
        let L = simd_normalize(2.0 * simd_dot(V, H) * H - V)
        let NoL = max(L.z, 0.0)
        let NoH = max(H.z, 0.0)
        let VoH = max(simd_dot(V, H), 0.0)
        if NoL > 0.0 {
            let G = geometrySmith(nDotV: nDotV, nDotL: NoL, roughness: roughness)
            let GVis = (G * VoH) / max(NoH * nDotV, 1e-4)
            let Fc = pow(1.0 - VoH, 5.0)
            A += (1.0 - Fc) * GVis
            B += Fc * GVis
        }
    }
    let inv = 1.0 / Float(sampleCount)
    return SIMD2<Float>(A * inv, B * inv)
}

private func hammersley(i: Int, count: Int) -> SIMD2<Float> {
    return SIMD2<Float>(Float(i) / Float(count), radicalInverseVdC(UInt32(i)))
}

private func radicalInverseVdC(_ bits: UInt32) -> Float {
    var x = bits
    x = (x << 16) | (x >> 16)
    x = ((x & 0x55555555) << 1) | ((x & 0xAAAAAAAA) >> 1)
    x = ((x & 0x33333333) << 2) | ((x & 0xCCCCCCCC) >> 2)
    x = ((x & 0x0F0F0F0F) << 4) | ((x & 0xF0F0F0F0) >> 4)
    x = ((x & 0x00FF00FF) << 8) | ((x & 0xFF00FF00) >> 8)
    return Float(x) * 2.3283064365386963e-10
}

private func importanceSampleGGX(xi: SIMD2<Float>, roughness: Float) -> SIMD3<Float> {
    let a = roughness * roughness
    let phi = 2.0 * Float.pi * xi.x
    let cosTheta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y))
    let sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0))
    let H = SIMD3<Float>(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta)
    return H
}

private func geometrySmith(nDotV: Float, nDotL: Float, roughness: Float) -> Float {
    let a = roughness
    let k = (a * a) * 0.5
    let gV = nDotV / (nDotV * (1.0 - k) + k)
    let gL = nDotL / (nDotL * (1.0 - k) + k)
    return gV * gL
}
