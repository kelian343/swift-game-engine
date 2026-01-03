//
//  Components.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

// MARK: - Transform (TRS)

public struct TransformComponent {
    public var translation: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>

    public init(translation: SIMD3<Float> = .zero,
                rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0,1,0)),
                scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    /// Derived model matrix from TRS (no drift, no repeated multiplication accumulation)
    public var modelMatrix: matrix_float4x4 {
        let t = matrix_float4x4(columns: (
            SIMD4<Float>(1,0,0,0),
            SIMD4<Float>(0,1,0,0),
            SIMD4<Float>(0,0,1,0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))

        let r = matrix_float4x4(rotation)

        let s = matrix_float4x4(columns: (
            SIMD4<Float>(scale.x,0,0,0),
            SIMD4<Float>(0,scale.y,0,0),
            SIMD4<Float>(0,0,scale.z,0),
            SIMD4<Float>(0,0,0,1)
        ))

        return simd_mul(t, simd_mul(r, s))
    }
}

// MARK: - Render

public struct RenderComponent {
    public var mesh: GPUMesh
    public var material: Material

    public init(mesh: GPUMesh, material: Material) {
        self.mesh = mesh
        self.material = material
    }
}

// MARK: - Optional: Simple rotation driver (demo)

public struct SpinComponent {
    /// radians per second
    public var speed: Float
    public var axis: SIMD3<Float>

    public init(speed: Float, axis: SIMD3<Float>) {
        self.speed = speed
        self.axis = axis
    }
}

// MARK: - Time

public struct TimeComponent {
    public var time: Float
    public var deltaTime: Float
    public var unscaledTime: Float
    public var unscaledDeltaTime: Float
    public var frame: UInt64
    public var timeScale: Float
    public var fixedDelta: Float
    public var accumulator: Float
    public var maxSubsteps: Int

    public init(time: Float = 0,
                deltaTime: Float = 0,
                unscaledTime: Float = 0,
                unscaledDeltaTime: Float = 0,
                frame: UInt64 = 0,
                timeScale: Float = 1,
                fixedDelta: Float = 1.0 / 60.0,
                accumulator: Float = 0,
                maxSubsteps: Int = 4) {
        self.time = time
        self.deltaTime = deltaTime
        self.unscaledTime = unscaledTime
        self.unscaledDeltaTime = unscaledDeltaTime
        self.frame = frame
        self.timeScale = timeScale
        self.fixedDelta = fixedDelta
        self.accumulator = accumulator
        self.maxSubsteps = maxSubsteps
    }
}
