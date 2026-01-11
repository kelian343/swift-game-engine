//
//  Material.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import simd

public struct Material {
    public var baseColorTexture: TextureResource?
    public var normalTexture: TextureResource?
    public var metallicRoughnessTexture: TextureResource?
    public var emissiveTexture: TextureResource?
    public var occlusionTexture: TextureResource?
    public var baseColorFactor: SIMD3<Float>
    public var metallicFactor: Float
    public var roughnessFactor: Float
    public var emissiveFactor: SIMD3<Float>
    public var occlusionStrength: Float
    public var alpha: Float
    public var transmissionFactor: Float
    public var ior: Float
    public var unlit: Bool
    public var normalScale: Float
    public var exposure: Float
    public var toneMapped: Bool
    public var cullMode: MTLCullMode
    public var frontFacing: MTLWinding

    public init(baseColorTexture: TextureResource? = nil,
                normalTexture: TextureResource? = nil,
                metallicRoughnessTexture: TextureResource? = nil,
                emissiveTexture: TextureResource? = nil,
                occlusionTexture: TextureResource? = nil,
                baseColorFactor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
                metallicFactor: Float = 0.0,
                roughnessFactor: Float = 0.5,
                emissiveFactor: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
                occlusionStrength: Float = 1.0,
                alpha: Float = 1.0,
                transmissionFactor: Float = 0.0,
                ior: Float = 1.5,
                unlit: Bool = false,
                normalScale: Float = 1.0,
                exposure: Float = 1.0,
                toneMapped: Bool = false,
                cullMode: MTLCullMode = .back,
                frontFacing: MTLWinding = .counterClockwise) {
        self.baseColorTexture = baseColorTexture
        self.normalTexture = normalTexture
        self.metallicRoughnessTexture = metallicRoughnessTexture
        self.emissiveTexture = emissiveTexture
        self.occlusionTexture = occlusionTexture
        self.baseColorFactor = baseColorFactor
        self.metallicFactor = metallicFactor
        self.roughnessFactor = roughnessFactor
        self.emissiveFactor = emissiveFactor
        self.occlusionStrength = occlusionStrength
        self.alpha = alpha
        self.transmissionFactor = transmissionFactor
        self.ior = ior
        self.unlit = unlit
        self.normalScale = normalScale
        self.exposure = exposure
        self.toneMapped = toneMapped
        self.cullMode = cullMode
        self.frontFacing = frontFacing
    }
}

public struct MaterialDescriptor {
    public var baseColor: ProceduralTexture?
    public var normal: ProceduralTexture?
    public var metallicRoughness: ProceduralTexture?
    public var emissive: ProceduralTexture?
    public var occlusion: ProceduralTexture?
    public var baseColorFactor: SIMD3<Float>
    public var metallicFactor: Float
    public var roughnessFactor: Float
    public var emissiveFactor: SIMD3<Float>
    public var occlusionStrength: Float
    public var alpha: Float
    public var transmissionFactor: Float
    public var ior: Float
    public var unlit: Bool
    public var normalScale: Float
    public var exposure: Float
    public var toneMapped: Bool
    public var cullMode: MTLCullMode
    public var frontFacing: MTLWinding

    public init(baseColor: ProceduralTexture? = nil,
                normal: ProceduralTexture? = nil,
                metallicRoughness: ProceduralTexture? = nil,
                emissive: ProceduralTexture? = nil,
                occlusion: ProceduralTexture? = nil,
                baseColorFactor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
                metallicFactor: Float = 0.0,
                roughnessFactor: Float = 0.5,
                emissiveFactor: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
                occlusionStrength: Float = 1.0,
                alpha: Float = 1.0,
                transmissionFactor: Float = 0.0,
                ior: Float = 1.5,
                unlit: Bool = false,
                normalScale: Float = 1.0,
                exposure: Float = 1.0,
                toneMapped: Bool = false,
                cullMode: MTLCullMode = .back,
                frontFacing: MTLWinding = .counterClockwise) {
        self.baseColor = baseColor
        self.normal = normal
        self.metallicRoughness = metallicRoughness
        self.emissive = emissive
        self.occlusion = occlusion
        self.baseColorFactor = baseColorFactor
        self.metallicFactor = metallicFactor
        self.roughnessFactor = roughnessFactor
        self.emissiveFactor = emissiveFactor
        self.occlusionStrength = occlusionStrength
        self.alpha = alpha
        self.transmissionFactor = transmissionFactor
        self.ior = ior
        self.unlit = unlit
        self.normalScale = normalScale
        self.exposure = exposure
        self.toneMapped = toneMapped
        self.cullMode = cullMode
        self.frontFacing = frontFacing
    }
}

public enum MaterialFactory {
    public static func make(device: MTLDevice, descriptor: MaterialDescriptor, label: String) -> Material {
        let base = descriptor.baseColor.map { TextureResource(device: device, source: $0, label: "\(label).baseColor") }
        let normal = descriptor.normal.map { TextureResource(device: device, source: $0, label: "\(label).normal") }
        let mr = descriptor.metallicRoughness.map { TextureResource(device: device, source: $0, label: "\(label).metallicRoughness") }
        let emissive = descriptor.emissive.map { TextureResource(device: device, source: $0, label: "\(label).emissive") }
        let occlusion = descriptor.occlusion.map { TextureResource(device: device, source: $0, label: "\(label).occlusion") }

        return Material(baseColorTexture: base,
                        normalTexture: normal,
                        metallicRoughnessTexture: mr,
                        emissiveTexture: emissive,
                        occlusionTexture: occlusion,
                        baseColorFactor: descriptor.baseColorFactor,
                        metallicFactor: descriptor.metallicFactor,
                        roughnessFactor: descriptor.roughnessFactor,
                        emissiveFactor: descriptor.emissiveFactor,
                        occlusionStrength: descriptor.occlusionStrength,
                        alpha: descriptor.alpha,
                        transmissionFactor: descriptor.transmissionFactor,
                        ior: descriptor.ior,
                        unlit: descriptor.unlit,
                        normalScale: descriptor.normalScale,
                        exposure: descriptor.exposure,
                        toneMapped: descriptor.toneMapped,
                        cullMode: descriptor.cullMode,
                        frontFacing: descriptor.frontFacing)
    }
}
