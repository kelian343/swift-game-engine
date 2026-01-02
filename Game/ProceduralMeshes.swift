//
//  ProceduralMeshes.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

/// Demo generator: a textured box with normals + UVs.
/// You can replace this with any procedural generator (marching cubes, hull, parametric, etc).
enum ProceduralMeshes {
    static func box(size: Float = 4) -> MeshData {
        let s = size * 0.5

        // 24 vertices (4 per face) for clean normals/UVs
        var v: [VertexPNUT] = []
        var i: [UInt16] = []

        func addFace(_ n: SIMD3<Float>,
                     _ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) {
            let base = UInt16(v.count)
            v.append(VertexPNUT(position: p0, normal: n, uv: SIMD2<Float>(0, 0)))
            v.append(VertexPNUT(position: p1, normal: n, uv: SIMD2<Float>(1, 0)))
            v.append(VertexPNUT(position: p2, normal: n, uv: SIMD2<Float>(1, 1)))
            v.append(VertexPNUT(position: p3, normal: n, uv: SIMD2<Float>(0, 1)))

            // two triangles
            i += [base+0, base+1, base+2,  base+0, base+2, base+3]
        }

        // +Z
        addFace(SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(-s, -s,  s), SIMD3<Float>( s, -s,  s),
                SIMD3<Float>( s,  s,  s), SIMD3<Float>(-s,  s,  s))
        // -Z
        addFace(SIMD3<Float>(0, 0, -1),
                SIMD3<Float>( s, -s, -s), SIMD3<Float>(-s, -s, -s),
                SIMD3<Float>(-s,  s, -s), SIMD3<Float>( s,  s, -s))
        // +X
        addFace(SIMD3<Float>(1, 0, 0),
                SIMD3<Float>( s, -s,  s), SIMD3<Float>( s, -s, -s),
                SIMD3<Float>( s,  s, -s), SIMD3<Float>( s,  s,  s))
        // -X
        addFace(SIMD3<Float>(-1, 0, 0),
                SIMD3<Float>(-s, -s, -s), SIMD3<Float>(-s, -s,  s),
                SIMD3<Float>(-s,  s,  s), SIMD3<Float>(-s,  s, -s))
        // +Y
        addFace(SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(-s,  s,  s), SIMD3<Float>( s,  s,  s),
                SIMD3<Float>( s,  s, -s), SIMD3<Float>(-s,  s, -s))
        // -Y
        addFace(SIMD3<Float>(0, -1, 0),
                SIMD3<Float>(-s, -s, -s), SIMD3<Float>( s, -s, -s),
                SIMD3<Float>( s, -s,  s), SIMD3<Float>(-s, -s,  s))

        return MeshData(vertices: v, indices16: i)
    }
}

enum ProceduralTextures {
    /// Simple checkerboard RGBA8
    static func checkerboard(width: Int = 256, height: Int = 256, cell: Int = 32) -> TextureSourceRGBA8 {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let cx = (x / cell) % 2
                let cy = (y / cell) % 2
                let on = (cx ^ cy) == 0
                let c: UInt8 = on ? 230 : 40
                let idx = (y * width + x) * 4
                bytes[idx+0] = c
                bytes[idx+1] = c
                bytes[idx+2] = c
                bytes[idx+3] = 255
            }
        }
        return .rgba8(width: width, height: height, bytes: bytes)
    }
}
