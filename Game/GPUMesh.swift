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
        let tangents: [SIMD4<Float>] = descriptor.streams.tangents
            ?? MeshTangents.compute(positions: positions,
                                    normals: normals,
                                    uvs: uvs,
                                    indices16: descriptor.indices16,
                                    indices32: descriptor.indices32)

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
