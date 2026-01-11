//
//  MeshTangents.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

enum MeshTangents {
    static func compute(positions: [SIMD3<Float>],
                        normals: [SIMD3<Float>],
                        uvs: [SIMD2<Float>],
                        indices16: [UInt16]?,
                        indices32: [UInt32]?) -> [SIMD4<Float>] {
        let vCount = positions.count
        guard vCount > 0 else { return [] }

        var tan1 = [SIMD3<Float>](repeating: .zero, count: vCount)
        var tan2 = [SIMD3<Float>](repeating: .zero, count: vCount)

        func addTriangle(i0: Int, i1: Int, i2: Int) {
            let p0 = positions[i0]
            let p1 = positions[i1]
            let p2 = positions[i2]
            let uv0 = uvs[i0]
            let uv1 = uvs[i1]
            let uv2 = uvs[i2]

            let dp1 = p1 - p0
            let dp2 = p2 - p0
            let duv1 = uv1 - uv0
            let duv2 = uv2 - uv0
            let denom = duv1.x * duv2.y - duv1.y * duv2.x
            if abs(denom) < 1e-6 { return }
            let r = 1.0 / denom
            let t = (dp1 * duv2.y - dp2 * duv1.y) * r
            let b = (dp2 * duv1.x - dp1 * duv2.x) * r

            tan1[i0] += t
            tan1[i1] += t
            tan1[i2] += t

            tan2[i0] += b
            tan2[i1] += b
            tan2[i2] += b
        }

        if let i16 = indices16 {
            var idx = 0
            while idx + 2 < i16.count {
                addTriangle(i0: Int(i16[idx]),
                            i1: Int(i16[idx + 1]),
                            i2: Int(i16[idx + 2]))
                idx += 3
            }
        } else if let i32 = indices32 {
            var idx = 0
            while idx + 2 < i32.count {
                addTriangle(i0: Int(i32[idx]),
                            i1: Int(i32[idx + 1]),
                            i2: Int(i32[idx + 2]))
                idx += 3
            }
        }

        var tangents: [SIMD4<Float>] = []
        tangents.reserveCapacity(vCount)
        for i in 0..<vCount {
            let n = simd_normalize(normals[i])
            var t = tan1[i]
            if simd_length_squared(t) < 1e-8 {
                tangents.append(SIMD4<Float>(1, 0, 0, 1))
                continue
            }
            t = simd_normalize(t - n * simd_dot(n, t))
            let b = tan2[i]
            let w: Float = simd_dot(simd_cross(n, t), b) < 0.0 ? -1.0 : 1.0
            tangents.append(SIMD4<Float>(t.x, t.y, t.z, w))
        }
        return tangents
    }
}
