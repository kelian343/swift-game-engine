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
    public var enabled: Bool
    public var maxDistance: Float

    public init(direction: SIMD3<Float>,
                intensity: Float,
                color: SIMD3<Float>,
                enabled: Bool = true,
                maxDistance: Float = 200.0) {
        self.direction = direction
        self.intensity = intensity
        self.color = color
        self.enabled = enabled
        self.maxDistance = maxDistance
    }
}
