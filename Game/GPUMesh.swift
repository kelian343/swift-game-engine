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

    public init(device: MTLDevice, data: MeshData, label: String = "GPUMesh") {
        let vSize = data.vertices.count * MemoryLayout<VertexPNUT>.stride
        self.vertexBuffer = device.makeBuffer(bytes: data.vertices, length: vSize, options: [.storageModeShared])!
        self.vertexBuffer.label = "\(label).vb"

        if let i16 = data.indices16 {
            self.indexType = .uint16
            self.indexCount = i16.count
            let iSize = i16.count * MemoryLayout<UInt16>.stride
            self.indexBuffer = device.makeBuffer(bytes: i16, length: iSize, options: [.storageModeShared])!
        } else if let i32 = data.indices32 {
            self.indexType = .uint32
            self.indexCount = i32.count
            let iSize = i32.count * MemoryLayout<UInt32>.stride
            self.indexBuffer = device.makeBuffer(bytes: i32, length: iSize, options: [.storageModeShared])!
        } else {
            fatalError("MeshData must provide indices16 or indices32")
        }

        self.indexBuffer.label = "\(label).ib"
    }
}
