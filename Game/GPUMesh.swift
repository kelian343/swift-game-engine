//
//  GPUMesh.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

public final class GPUMesh {
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexType: MTLIndexType
    public let indexCount: Int

    public init(device: MTLDevice, descriptor: ProceduralMeshDescriptor, label: String = "GPUMesh") {
        guard descriptor.validate() else {
            fatalError("ProceduralMeshDescriptor invalid")
        }

        let positions = descriptor.streams.positions
        let normals: [SIMD3<Float>] = descriptor.streams.normals
            ?? Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
        let uvs: [SIMD2<Float>] = descriptor.streams.uvs
            ?? Array(repeating: SIMD2<Float>(0, 0), count: positions.count)
        let tangents: [SIMD4<Float>] = {
            if let t = descriptor.streams.tangents {
                return t
            }
            return GPUMesh.computeTangents(positions: positions,
                                           normals: normals,
                                           uvs: uvs,
                                           indices16: descriptor.indices16,
                                           indices32: descriptor.indices32)
        }()

        var vertices: [VertexPNUT] = []
        vertices.reserveCapacity(positions.count)
        for i in 0..<positions.count {
            let tangent = i < tangents.count ? tangents[i] : SIMD4<Float>(1, 0, 0, 1)
            vertices.append(VertexPNUT(position: positions[i],
                                       normal: normals[i],
                                       uv: uvs[i],
                                       tangent: tangent))
        }

        let vSize = vertices.count * MemoryLayout<VertexPNUT>.stride
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: max(vSize, 1), options: [.storageModeShared])!
        self.vertexBuffer.label = "\(label).vb"

        if let i16 = descriptor.indices16 {
            self.indexType = .uint16
            self.indexCount = i16.count
            let iSize = i16.count * MemoryLayout<UInt16>.stride
            self.indexBuffer = device.makeBuffer(bytes: i16, length: max(iSize, 1), options: [.storageModeShared])!
        } else if let i32 = descriptor.indices32 {
            self.indexType = .uint32
            self.indexCount = i32.count
            let iSize = i32.count * MemoryLayout<UInt32>.stride
            self.indexBuffer = device.makeBuffer(bytes: i32, length: max(iSize, 1), options: [.storageModeShared])!
        } else {
            fatalError("ProceduralMeshDescriptor must provide indices16 or indices32")
        }

        self.indexBuffer.label = "\(label).ib"
    }
}

private extension GPUMesh {
    static func computeTangents(positions: [SIMD3<Float>],
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
