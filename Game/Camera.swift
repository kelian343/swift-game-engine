//
//  Camera.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class Camera {
    public var fovDegrees: Float = 65
    public var nearZ: Float = 0.1
    public var farZ: Float = 100.0

    public var position = SIMD3<Float>(0, 0, 8)  // camera at +Z looking at origin
    public var target   = SIMD3<Float>(0, 0, 0)
    public var up       = SIMD3<Float>(0, 1, 0)
    public var worldChunk = SIMD3<Int64>(0, 0, 0)
    public var worldLocal = SIMD3<Double>(0, 0, 0)

    public private(set) var projection = matrix_identity_float4x4
    public private(set) var view = matrix_identity_float4x4

    public init() {}

    public func updateProjection(width: Float, height: Float) {
        let aspect = max(width / max(height, 1), 0.0001)
        projection = matrix_perspective_right_hand(
            fovyRadians: radians_from_degrees(fovDegrees),
            aspectRatio: aspect,
            nearZ: nearZ,
            farZ: farZ
        )
    }

    public func updateView() {
        // A minimal right-handed look-at.
        // If you want to keep it simpler, you can just use translation like before.
        let zAxis = simd_normalize(position - target)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)

        let t = SIMD3<Float>(
            -simd_dot(xAxis, position),
            -simd_dot(yAxis, position),
            -simd_dot(zAxis, position)
        )

        view = matrix_float4x4(columns: (
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4<Float>(t.x,     t.y,     t.z,     1)
        ))
    }
}
