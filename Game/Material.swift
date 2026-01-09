//
//  Material.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

public struct Material {
    public var baseColorTexture: TextureResource?
    public var cullMode: MTLCullMode = .back
    public var frontFacing: MTLWinding = .counterClockwise
    public var metallic: Float = 0.0
    public var roughness: Float = 0.5

    public init(baseColorTexture: TextureResource? = nil,
                metallic: Float = 0.0,
                roughness: Float = 0.5) {
        self.baseColorTexture = baseColorTexture
        self.metallic = metallic
        self.roughness = roughness
    }
}

