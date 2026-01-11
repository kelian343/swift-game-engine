//
//  Lights.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

public struct DirectionalLight {
    public var direction: SIMD3<Float>
    public var intensity: Float
    public var color: SIMD3<Float>

    public init(direction: SIMD3<Float>,
                intensity: Float,
                color: SIMD3<Float>) {
        self.direction = direction
        self.intensity = intensity
        self.color = color
    }
}
