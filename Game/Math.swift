//
//  Math.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci: Float = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z

    return matrix_float4x4(columns: (
        vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
        vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
        vector_float4(              0,                 0,                 0, 1)
    ))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        vector_float4(1, 0, 0, 0),
        vector_float4(0, 1, 0, 0),
        vector_float4(0, 0, 1, 0),
        vector_float4(translationX, translationY, translationZ, 1)
    ))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)

    return matrix_float4x4(columns: (
        vector_float4(xs, 0, 0,  0),
        vector_float4(0, ys, 0,  0),
        vector_float4(0,  0, zs, -1),
        vector_float4(0,  0, zs * nearZ, 0)
    ))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}

func lookAtRH(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let f = simd_normalize(center - eye)
    let r = simd_normalize(simd_cross(f, up))
    let u = simd_cross(r, f)

    return matrix_float4x4(columns: (
        SIMD4<Float>( r.x,  u.x, -f.x, 0),
        SIMD4<Float>( r.y,  u.y, -f.y, 0),
        SIMD4<Float>( r.z,  u.z, -f.z, 0),
        SIMD4<Float>(-simd_dot(r, eye),
                     -simd_dot(u, eye),
                      simd_dot(f, eye),
                     1)
    ))
}

func orthoRH(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
    let rl = right - left
    let tb = top - bottom
    let fn = far - near

    return matrix_float4x4(columns: (
        SIMD4<Float>( 2/rl,     0,       0, 0),
        SIMD4<Float>(   0,   2/tb,       0, 0),
        SIMD4<Float>(   0,     0,    -1/fn, 0),
        SIMD4<Float>(-(right+left)/rl,
                     -(top+bottom)/tb,
                     -near/fn,
                     1)
    ))
}
