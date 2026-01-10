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
    public var baseColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    public var cullMode: MTLCullMode = .back
    public var frontFacing: MTLWinding = .counterClockwise
    public var metallic: Float = 0.0
    public var roughness: Float = 0.5
    public var alpha: Float = 1.0

    public init(baseColorTexture: TextureResource? = nil,
                baseColor: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
                metallic: Float = 0.0,
                roughness: Float = 0.5,
                alpha: Float = 1.0) {
        self.baseColorTexture = baseColorTexture
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.alpha = alpha
    }
}
