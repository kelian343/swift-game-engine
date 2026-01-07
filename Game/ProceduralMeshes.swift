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

    static func ramp(width: Float = 8, depth: Float = 8, height: Float = 4) -> MeshData {
        let w = width * 0.5
        let d = depth * 0.5
        let h = height * 0.5

        let frontLeft = SIMD3<Float>(-w, -h,  d)
        let frontRight = SIMD3<Float>( w, -h,  d)
        let backLeft = SIMD3<Float>(-w, -h, -d)
        let backRight = SIMD3<Float>( w, -h, -d)
        let backLeftTop = SIMD3<Float>(-w,  h, -d)
        let backRightTop = SIMD3<Float>( w,  h, -d)

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

        // Bottom
        addQuad(frontLeft, frontRight, backRight, backLeft)
        // Back
        addQuad(backLeft, backRight, backRightTop, backLeftTop)
        // Sloped top
        addQuad(backLeftTop, backRightTop, frontRight, frontLeft)
        // Left side
        addTri(backLeft, backLeftTop, frontLeft)
        // Right side
        addTri(frontRight, backRightTop, backRight)

        return MeshData(vertices: v, indices16: i)
    }

    static func dome(radius: Float = 4,
                     radialSegments: Int = 32,
                     ringSegments: Int = 12) -> MeshData {
        let slices = max(radialSegments, 3)
        let rings = max(ringSegments, 2)

        var v: [VertexPNUT] = []
        var i: [UInt16] = []

        let twoPi = Float.pi * 2.0

        // Curved top (hemisphere)
        for r in 0...rings {
            let t = Float(r) / Float(rings)
            let theta = t * (Float.pi * 0.5)
            let y = cos(theta) * radius
            let ringR = sin(theta) * radius

            for s in 0...slices {
                let u = Float(s) / Float(slices)
                let phi = u * twoPi
                let x = cos(phi) * ringR
                let z = sin(phi) * ringR
                let pos = SIMD3<Float>(x, y, z)
                let n = simd_normalize(pos)
                v.append(VertexPNUT(position: pos, normal: n, uv: SIMD2<Float>(u, 1.0 - t)))
            }
        }

        let ringStride = slices + 1
        for r in 0..<rings {
            for s in 0..<slices {
                let i0 = UInt16(r * ringStride + s)
                let i1 = UInt16((r + 1) * ringStride + s)
                let i2 = UInt16((r + 1) * ringStride + s + 1)
                let i3 = UInt16(r * ringStride + s + 1)
                i += [i0, i1, i2, i0, i2, i3]
            }
        }

        // Flat base (disk)
        let baseCenter = UInt16(v.count)
        v.append(VertexPNUT(position: SIMD3<Float>(0, 0, 0),
                            normal: SIMD3<Float>(0, -1, 0),
                            uv: SIMD2<Float>(0.5, 0.5)))
        for s in 0...slices {
            let u = Float(s) / Float(slices)
            let phi = u * twoPi
            let x = cos(phi) * radius
            let z = sin(phi) * radius
            let uv = SIMD2<Float>(0.5 + 0.5 * cos(phi), 0.5 + 0.5 * sin(phi))
            v.append(VertexPNUT(position: SIMD3<Float>(x, 0, z),
                                normal: SIMD3<Float>(0, -1, 0),
                                uv: uv))
        }

        let baseStart = Int(baseCenter) + 1
        for s in 0..<slices {
            let i0 = baseCenter
            let i1 = UInt16(baseStart + s)
            let i2 = UInt16(baseStart + s + 1)
            i += [i0, i2, i1]
        }

        return MeshData(vertices: v, indices16: i)
    }

    static func capsule(radius: Float = 1.5,
                        halfHeight: Float = 1.0,
                        radialSegments: Int = 24,
                        hemisphereSegments: Int = 8) -> MeshData {
        let slices = max(radialSegments, 3)
        let hemi = max(hemisphereSegments, 2)

        struct Ring {
            var y: Float
            var r: Float
            var normalCenterY: Float?
        }

        var rings: [Ring] = []

        // Top hemisphere (top pole -> equator at +halfHeight)
        for i in 0...hemi {
            let t = Float(i) / Float(hemi)
            let theta = t * (Float.pi * 0.5)
            let y = halfHeight + cos(theta) * radius
            let r = sin(theta) * radius
            rings.append(Ring(y: y, r: r, normalCenterY: halfHeight))
        }

        // Cylinder to bottom equator
        if halfHeight > 0 {
            rings.append(Ring(y: -halfHeight, r: radius, normalCenterY: nil))
        }

        // Bottom hemisphere (just below equator -> bottom pole)
        if hemi > 1 {
            for i in stride(from: hemi - 1, through: 0, by: -1) {
                let t = Float(i) / Float(hemi)
                let theta = t * (Float.pi * 0.5)
                let y = -halfHeight - cos(theta) * radius
                let r = sin(theta) * radius
                rings.append(Ring(y: y, r: r, normalCenterY: -halfHeight))
            }
        }

        let minY = rings.map { $0.y }.min() ?? 0
        let maxY = rings.map { $0.y }.max() ?? 1
        let invRange = maxY > minY ? 1.0 / (maxY - minY) : 0

        var v: [VertexPNUT] = []
        var i: [UInt16] = []

        for ring in rings {
            let vCoord = (ring.y - minY) * invRange
            for s in 0..<slices {
                let u = Float(s) / Float(slices)
                let angle = u * Float.pi * 2.0
                let x = cos(angle) * ring.r
                let z = sin(angle) * ring.r
                let pos = SIMD3<Float>(x, ring.y, z)
                let normal: SIMD3<Float>
                if let centerY = ring.normalCenterY {
                    normal = simd_normalize(SIMD3<Float>(x, ring.y - centerY, z))
                } else {
                    normal = simd_normalize(SIMD3<Float>(x, 0, z))
                }
                v.append(VertexPNUT(position: pos, normal: normal, uv: SIMD2<Float>(u, vCoord)))
            }
        }

        let ringCount = rings.count
        for r in 0..<(ringCount - 1) {
            let base0 = r * slices
            let base1 = (r + 1) * slices
            for s in 0..<slices {
                let s1 = (s + 1) % slices
                let a = UInt16(base0 + s)
                let b = UInt16(base0 + s1)
                let c = UInt16(base1 + s)
                let d = UInt16(base1 + s1)
                i += [a, c, b,  b, c, d]
            }
        }

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
