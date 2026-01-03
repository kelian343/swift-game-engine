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
    static func plane(size: Float = 20) -> MeshData {
        let s = size * 0.5
        let n = SIMD3<Float>(0, 1, 0)

        let v: [VertexPNUT] = [
            VertexPNUT(position: SIMD3<Float>(-s, 0,  s), normal: n, uv: SIMD2<Float>(0, 0)),
            VertexPNUT(position: SIMD3<Float>( s, 0,  s), normal: n, uv: SIMD2<Float>(1, 0)),
            VertexPNUT(position: SIMD3<Float>( s, 0, -s), normal: n, uv: SIMD2<Float>(1, 1)),
            VertexPNUT(position: SIMD3<Float>(-s, 0, -s), normal: n, uv: SIMD2<Float>(0, 1)),
        ]
        let i: [UInt16] = [0, 1, 2, 0, 2, 3]
        return MeshData(vertices: v, indices16: i)
    }

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

    static func tetrahedron(size: Float = 4) -> MeshData {
        let s = size * 0.5
        let p0 = SIMD3<Float>( 0,  s,  0)
        let p1 = SIMD3<Float>(-s, -s,  s)
        let p2 = SIMD3<Float>( s, -s,  s)
        let p3 = SIMD3<Float>( 0, -s, -s)

        var v: [VertexPNUT] = []
        var i: [UInt16] = []

        func addFace(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let n = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt16(v.count)
            v.append(VertexPNUT(position: a, normal: n, uv: SIMD2<Float>(0, 0)))
            v.append(VertexPNUT(position: b, normal: n, uv: SIMD2<Float>(1, 0)))
            v.append(VertexPNUT(position: c, normal: n, uv: SIMD2<Float>(0.5, 1)))
            i += [base, base + 1, base + 2]
        }

        addFace(p0, p1, p2)
        addFace(p0, p2, p3)
        addFace(p0, p3, p1)
        addFace(p1, p3, p2)

        return MeshData(vertices: v, indices16: i)
    }

    static func triangularPrism(size: Float = 4, height: Float = 3) -> MeshData {
        let s = size * 0.5
        let h = height * 0.5

        let a0 = SIMD3<Float>(-s, -h,  s)
        let b0 = SIMD3<Float>( s, -h,  s)
        let c0 = SIMD3<Float>( 0, -h, -s)

        let a1 = SIMD3<Float>(-s,  h,  s)
        let b1 = SIMD3<Float>( s,  h,  s)
        let c1 = SIMD3<Float>( 0,  h, -s)

        var v: [VertexPNUT] = []
        var i: [UInt16] = []

        func addTri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let n = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt16(v.count)
            v.append(VertexPNUT(position: a, normal: n, uv: SIMD2<Float>(0, 0)))
            v.append(VertexPNUT(position: b, normal: n, uv: SIMD2<Float>(1, 0)))
            v.append(VertexPNUT(position: c, normal: n, uv: SIMD2<Float>(0.5, 1)))
            i += [base, base + 1, base + 2]
        }

        func addQuad(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) {
            let n = simd_normalize(simd_cross(p1 - p0, p2 - p0))
            let base = UInt16(v.count)
            v.append(VertexPNUT(position: p0, normal: n, uv: SIMD2<Float>(0, 0)))
            v.append(VertexPNUT(position: p1, normal: n, uv: SIMD2<Float>(1, 0)))
            v.append(VertexPNUT(position: p2, normal: n, uv: SIMD2<Float>(1, 1)))
            v.append(VertexPNUT(position: p3, normal: n, uv: SIMD2<Float>(0, 1)))
            i += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        // Top/Bottom triangles
        addTri(a1, b1, c1)
        addTri(a0, c0, b0)

        // Side quads
        addQuad(a0, b0, b1, a1)
        addQuad(b0, c0, c1, b1)
        addQuad(c0, a0, a1, c1)

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
