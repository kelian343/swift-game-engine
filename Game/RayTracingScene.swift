//
//  RayTracingScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import simd

final class RayTracingScene {
    private let device: MTLDevice

    private var blasForMesh: [ObjectIdentifier: MTLAccelerationStructure] = [:]
    private var blasDescriptorForMesh: [ObjectIdentifier: MTLAccelerationStructureDescriptor] = [:]
    private var blasScratchForMesh: [ObjectIdentifier: MTLBuffer] = [:]

    private var tlas: MTLAccelerationStructure?
    private var tlasSize: Int = 0
    private var tlasScratch: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var lastInstanceCount: Int = 0

    init(device: MTLDevice) {
        self.device = device
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard !items.isEmpty else { return nil }

        var blasList: [MTLAccelerationStructure] = []
        var blasIndexForMesh: [ObjectIdentifier: Int] = [:]

        for item in items {
            let key = ObjectIdentifier(item.mesh)
            if let existing = blasForMesh[key] {
                if blasIndexForMesh[key] == nil {
                    blasIndexForMesh[key] = blasList.count
                    blasList.append(existing)
                }
                continue
            }

            let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
            geometry.vertexBuffer = item.mesh.vertexBuffer
            geometry.vertexBufferOffset = 0
            geometry.vertexStride = MemoryLayout<VertexPNUT>.stride
            geometry.vertexFormat = .float3
            geometry.indexBuffer = item.mesh.indexBuffer
            geometry.indexBufferOffset = 0
            geometry.indexType = item.mesh.indexType
            geometry.triangleCount = item.mesh.indexCount / 3
            geometry.opaque = true

            let desc = MTLPrimitiveAccelerationStructureDescriptor()
            desc.geometryDescriptors = [geometry]

            let sizes = device.accelerationStructureSizes(descriptor: desc)
            let blas = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
            let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize,
                                            options: .storageModePrivate)!

            let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
            encoder.build(accelerationStructure: blas,
                          descriptor: desc,
                          scratchBuffer: scratch,
                          scratchBufferOffset: 0)
            encoder.endEncoding()

            blasForMesh[key] = blas
            blasDescriptorForMesh[key] = desc
            blasScratchForMesh[key] = scratch

            blasIndexForMesh[key] = blasList.count
            blasList.append(blas)
        }

        var instances: [MTLAccelerationStructureInstanceDescriptor] = []
        instances.reserveCapacity(items.count)

        for (_, item) in items.enumerated() {
            let key = ObjectIdentifier(item.mesh)
            guard let blasIndex = blasIndexForMesh[key] else { continue }

            var desc = MTLAccelerationStructureInstanceDescriptor()
            desc.accelerationStructureIndex = UInt32(blasIndex)
            desc.mask = 0xFF
            desc.options = []
            desc.intersectionFunctionTableOffset = 0

            let m = item.modelMatrix
            desc.transformationMatrix = MTLPackedFloat4x3(columns: (
                MTLPackedFloat3Make(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                MTLPackedFloat3Make(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                MTLPackedFloat3Make(m.columns.2.x, m.columns.2.y, m.columns.2.z),
                MTLPackedFloat3Make(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            ))
            instances.append(desc)
        }

        let instanceSize = instances.count * MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride
        if instanceBuffer == nil || instances.count != lastInstanceCount {
            instanceBuffer = device.makeBuffer(length: max(instanceSize, 1),
                                               options: .storageModeShared)
            lastInstanceCount = instances.count
        }
        if let buf = instanceBuffer, !instances.isEmpty {
            let raw = instances.withUnsafeBytes { $0 }
            memcpy(buf.contents(), raw.baseAddress!, raw.count)
        }

        let tlasDesc = MTLInstanceAccelerationStructureDescriptor()
        tlasDesc.instanceCount = instances.count
        tlasDesc.instancedAccelerationStructures = blasList
        tlasDesc.instanceDescriptorBuffer = instanceBuffer
        tlasDesc.instanceDescriptorStride = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride

        let tlasSizes = device.accelerationStructureSizes(descriptor: tlasDesc)
        if tlas == nil || tlasSize < tlasSizes.accelerationStructureSize {
            tlas = device.makeAccelerationStructure(size: tlasSizes.accelerationStructureSize)
            tlasSize = tlasSizes.accelerationStructureSize
        }
        if tlasScratch == nil || tlasScratch!.length < tlasSizes.buildScratchBufferSize {
            tlasScratch = device.makeBuffer(length: tlasSizes.buildScratchBufferSize,
                                            options: .storageModePrivate)
        }

        if let tlas = tlas, let scratch = tlasScratch {
            let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
            encoder.build(accelerationStructure: tlas,
                          descriptor: tlasDesc,
                          scratchBuffer: scratch,
                          scratchBufferOffset: 0)
            encoder.endEncoding()
            return tlas
        }

        return nil
    }
}
