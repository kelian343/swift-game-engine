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

    public init(baseColorTexture: TextureResource? = nil) {
        self.baseColorTexture = baseColorTexture
    }
}
