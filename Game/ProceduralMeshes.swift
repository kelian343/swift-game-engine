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
    private static func buildDescriptor(name: String,
                                        vertices: [VertexPNUT],
                                        indices16: [UInt16]) -> ProceduralMeshDescriptor {
        var builder = ProceduralMeshBuilder()
        builder.setName(name)
        builder.setPositions(vertices.map { $0.position })
        builder.setNormals(vertices.map { $0.normal })
        builder.setUVs(vertices.map { $0.uv })
        builder.setIndices16(indices16)
        return builder.build()
            ?? ProceduralMeshDescriptor(topology: .triangles,
                                        streams: VertexStreams(positions: vertices.map { $0.position },
                                                               normals: vertices.map { $0.normal },
                                                               uvs: vertices.map { $0.uv }),
                                        indices16: indices16,
                                        name: name)
    }
    static func plane(size: Float = 20) -> ProceduralMeshDescriptor {
        let s = size * 0.5
        let n = SIMD3<Float>(0, 1, 0)

        let v: [VertexPNUT] = [
            VertexPNUT(position: SIMD3<Float>(-s, 0,  s), normal: n, uv: SIMD2<Float>(0, 0)),
            VertexPNUT(position: SIMD3<Float>( s, 0,  s), normal: n, uv: SIMD2<Float>(1, 0)),
            VertexPNUT(position: SIMD3<Float>( s, 0, -s), normal: n, uv: SIMD2<Float>(1, 1)),
            VertexPNUT(position: SIMD3<Float>(-s, 0, -s), normal: n, uv: SIMD2<Float>(0, 1)),
        ]
        let i: [UInt16] = [0, 1, 2, 0, 2, 3]
        return buildDescriptor(name: "plane", vertices: v, indices16: i)
    }

    static func box(size: Float = 4) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "box", vertices: v, indices16: i)
    }

    static func tetrahedron(size: Float = 4) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "tetrahedron", vertices: v, indices16: i)
    }

    static func triangularPrism(size: Float = 4, height: Float = 3) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "triangularPrism", vertices: v, indices16: i)
    }

    static func ramp(width: Float = 8, depth: Float = 8, height: Float = 4) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "ramp", vertices: v, indices16: i)
    }

    static func humanoidSkinned(legHeight: Float = 1.8,
                                legRadius: Float = 0.35,
                                torsoHeight: Float = 2.0,
                                torsoRadius: Float = 0.5,
                                hipSeparation: Float = 0.45,
                                radialSegments: Int = 12,
                                heightSegments: Int = 4) -> SkinnedMeshDescriptor {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var boneIndices: [SIMD4<UInt16>] = []
        var boneWeights: [SIMD4<Float>] = []
        var indices: [UInt16] = []

        func appendVertex(_ pos: SIMD3<Float>,
                          _ normal: SIMD3<Float>,
                          _ uv: SIMD2<Float>,
                          _ joints: SIMD4<UInt16>,
                          _ weights: SIMD4<Float>) {
            positions.append(pos)
            normals.append(normal)
            uvs.append(uv)
            boneIndices.append(joints)
            boneWeights.append(weights)
        }

        func addCylinder(centerX: Float,
                         centerY: Float,
                         centerZ: Float,
                         radius: Float,
                         height: Float,
                         radialSegs: Int,
                         heightSegs: Int,
                         weightForY: (Float) -> (SIMD4<UInt16>, SIMD4<Float>)) {
            let slices = max(radialSegs, 3)
            let stacks = max(heightSegs, 1)
            let twoPi = Float.pi * 2.0
            let yMin = centerY - height * 0.5
            let yMax = centerY + height * 0.5

            let baseIndex = UInt16(positions.count)

            for y in 0...stacks {
                let t = Float(y) / Float(stacks)
                let yy = yMin + (yMax - yMin) * t
                for s in 0...slices {
                    let u = Float(s) / Float(slices)
                    let theta = u * twoPi
                    let x = cos(theta) * radius + centerX
                    let z = sin(theta) * radius + centerZ
                    let pos = SIMD3<Float>(x, yy, z)
                    let n = simd_normalize(SIMD3<Float>(x - centerX, 0, z - centerZ))
                    let uv = SIMD2<Float>(u, t)
                    let (bIdx, bW) = weightForY(t)
                    appendVertex(pos, n, uv, bIdx, bW)
                }
            }

            let ring = slices + 1
            for y in 0..<stacks {
                for s in 0..<slices {
                    let i0 = baseIndex + UInt16(y * ring + s)
                    let i1 = baseIndex + UInt16((y + 1) * ring + s)
                    let i2 = baseIndex + UInt16((y + 1) * ring + s + 1)
                    let i3 = baseIndex + UInt16(y * ring + s + 1)
                    indices += [i0, i1, i2, i0, i2, i3]
                }
            }
        }

        func torsoWeights(_ t: Float) -> (SIMD4<UInt16>, SIMD4<Float>) {
            let pelvis: UInt16 = 0
            let spine: UInt16 = 1
            let head: UInt16 = 2
            let chest: UInt16 = 7

            var w = SIMD4<Float>(0, 0, 0, 0)
            if t < 0.4 {
                let a = t / 0.4
                w = SIMD4<Float>(1 - a, a, 0, 0)
                return (SIMD4<UInt16>(pelvis, spine, chest, head), w)
            } else if t < 0.7 {
                let a = (t - 0.4) / 0.3
                w = SIMD4<Float>(0, 1 - a, a, 0)
                return (SIMD4<UInt16>(pelvis, spine, chest, head), w)
            } else {
                let a = (t - 0.7) / 0.3
                w = SIMD4<Float>(0, 0, 1 - a, a)
                return (SIMD4<UInt16>(pelvis, spine, chest, head), w)
            }
        }

        func legWeights(thigh: UInt16, calf: UInt16, t: Float) -> (SIMD4<UInt16>, SIMD4<Float>) {
            let a = min(max(t, 0), 1)
            let wThigh = a
            let wCalf = 1 - a
            return (SIMD4<UInt16>(thigh, calf, 0, 0), SIMD4<Float>(wThigh, wCalf, 0, 0))
        }

        // Torso centered above hips
        addCylinder(centerX: 0,
                    centerY: torsoHeight * 0.5,
                    centerZ: 0,
                    radius: torsoRadius,
                    height: torsoHeight,
                    radialSegs: radialSegments,
                    heightSegs: heightSegments,
                    weightForY: torsoWeights)

        // Left leg
        addCylinder(centerX: -hipSeparation,
                    centerY: -legHeight * 0.5,
                    centerZ: 0,
                    radius: legRadius,
                    height: legHeight,
                    radialSegs: radialSegments,
                    heightSegs: heightSegments,
                    weightForY: { t in legWeights(thigh: 3, calf: 4, t: t) })

        // Right leg
        addCylinder(centerX: hipSeparation,
                    centerY: -legHeight * 0.5,
                    centerZ: 0,
                    radius: legRadius,
                    height: legHeight,
                    radialSegs: radialSegments,
                    heightSegs: heightSegments,
                    weightForY: { t in legWeights(thigh: 5, calf: 6, t: t) })

        var builder = SkinnedMeshBuilder()
        builder.setName("humanoidSkinned")
        builder.setPositions(positions)
        builder.setNormals(normals)
        builder.setUVs(uvs)
        builder.setBoneIndices(boneIndices)
        builder.setBoneWeights(boneWeights)
        builder.setIndices16(indices)
        return builder.build()
            ?? SkinnedMeshDescriptor(topology: .triangles,
                                     streams: SkinnedVertexStreams(positions: positions,
                                                                   normals: normals,
                                                                   uvs: uvs,
                                                                   boneIndices: boneIndices,
                                                                   boneWeights: boneWeights),
                                     indices16: indices,
                                     name: "humanoidSkinned")
    }

    static func dome(radius: Float = 4,
                     radialSegments: Int = 32,
                     ringSegments: Int = 12) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "dome", vertices: v, indices16: i)
    }

    static func capsule(radius: Float = 1.5,
                        halfHeight: Float = 1.0,
                        radialSegments: Int = 24,
                        hemisphereSegments: Int = 8) -> ProceduralMeshDescriptor {
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

        return buildDescriptor(name: "capsule", vertices: v, indices16: i)
    }

    static func quad(width: Float = 1,
                     height: Float = 1,
                     uvMin: SIMD2<Float> = SIMD2<Float>(0, 0),
                     uvMax: SIMD2<Float> = SIMD2<Float>(1, 1)) -> ProceduralMeshDescriptor {
        let normal = SIMD3<Float>(0, 0, 1)
        let v: [VertexPNUT] = [
            VertexPNUT(position: SIMD3<Float>(0, 0, 0), normal: normal, uv: SIMD2<Float>(uvMin.x, uvMin.y)),
            VertexPNUT(position: SIMD3<Float>(width, 0, 0), normal: normal, uv: SIMD2<Float>(uvMax.x, uvMin.y)),
            VertexPNUT(position: SIMD3<Float>(width, height, 0), normal: normal, uv: SIMD2<Float>(uvMax.x, uvMax.y)),
            VertexPNUT(position: SIMD3<Float>(0, height, 0), normal: normal, uv: SIMD2<Float>(uvMin.x, uvMax.y))
        ]
        let i: [UInt16] = [0, 1, 2, 0, 2, 3]
        return buildDescriptor(name: "quad", vertices: v, indices16: i)
    }
}

enum ProceduralTextures {
    static let digitsAtlasCellWidth: Int = 8
    static let digitsAtlasCellHeight: Int = 12

    /// Digits atlas (0-9) in a single row, alpha-masked for overlay text.
    static func digitsAtlas() -> TextureSourceRGBA8 {
        let cellW = digitsAtlasCellWidth
        let cellH = digitsAtlasCellHeight
        let atlasW = cellW * 10
        let atlasH = cellH
        var bytes = [UInt8](repeating: 0, count: atlasW * atlasH * 4)

        let glyphs: [[String]] = [
            ["01110","10001","10011","10101","11001","10001","01110"], // 0
            ["00100","01100","00100","00100","00100","00100","01110"], // 1
            ["01110","10001","00001","00010","00100","01000","11111"], // 2
            ["11110","00001","00001","01110","00001","00001","11110"], // 3
            ["00010","00110","01010","10010","11111","00010","00010"], // 4
            ["11111","10000","11110","00001","00001","10001","01110"], // 5
            ["00110","01000","10000","11110","10001","10001","01110"], // 6
            ["11111","00001","00010","00100","01000","01000","01000"], // 7
            ["01110","10001","10001","01110","10001","10001","01110"], // 8
            ["01110","10001","10001","01111","00001","00010","11100"]  // 9
        ]

        let padX = max((cellW - 5) / 2, 0)
        let padY = max((cellH - 7) / 2, 0)

        for digit in 0..<10 {
            let originX = digit * cellW + padX
            let originY = padY
            let rows = glyphs[digit]
            for y in 0..<rows.count {
                let row = Array(rows[y])
                for x in 0..<row.count {
                    if row[x] == "1" {
                        let px = originX + x
                        let py = originY + y
                        if px < atlasW && py < atlasH {
                            let idx = (py * atlasW + px) * 4
                            bytes[idx+0] = 255
                            bytes[idx+1] = 255
                            bytes[idx+2] = 255
                            bytes[idx+3] = 255
                        }
                    }
                }
            }
        }
        return .rgba8(width: atlasW, height: atlasH, bytes: bytes)
    }

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
