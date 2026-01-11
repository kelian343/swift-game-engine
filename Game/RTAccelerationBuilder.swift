//
//  RTAccelerationBuilder.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Metal

final class RTAccelerationBuilder {
    private let device: MTLDevice

    private var tlas: MTLAccelerationStructure?
    private var tlasSize: Int = 0
    private var tlasScratch: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var lastInstanceCount: Int = 0

    private var cachedStaticBLAS: [MTLAccelerationStructure] = []
    private var cachedDynamicBLAS: [MTLAccelerationStructure] = []
    private var dynamicRefitScratch: [MTLBuffer] = []
    private var transientScratch: [MTLBuffer] = []

    init(device: MTLDevice) {
        self.device = device
    }

    func build(state: RTGeometryState,
               items: [RenderItem],
               commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        let buffers = state.buffers

        transientScratch.removeAll(keepingCapacity: true)

        if state.staticChanged || cachedStaticBLAS.count != state.staticSlices.count {
            cachedStaticBLAS.removeAll(keepingCapacity: true)
            cachedStaticBLAS.reserveCapacity(state.staticSlices.count)
            let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
            for slice in state.staticSlices {
                let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
                geometry.vertexBuffer = buffers.staticVertexBuffer
                geometry.vertexBufferOffset = slice.baseVertex * MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexFormat = .float3
                geometry.indexBuffer = buffers.staticIndexBuffer
                geometry.indexBufferOffset = slice.baseIndex * MemoryLayout<UInt32>.stride
                geometry.indexType = .uint32
                geometry.triangleCount = slice.indexCount / 3
                geometry.opaque = true

                let desc = MTLPrimitiveAccelerationStructureDescriptor()
                desc.geometryDescriptors = [geometry]
                desc.usage = [.refit]

                let sizes = device.accelerationStructureSizes(descriptor: desc)
                let blas = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
                let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize,
                                                options: .storageModePrivate)!

                encoder.build(accelerationStructure: blas,
                              descriptor: desc,
                              scratchBuffer: scratch,
                              scratchBufferOffset: 0)

                cachedStaticBLAS.append(blas)
                transientScratch.append(scratch)
            }
            encoder.endEncoding()
        }

        if state.dynamicChanged || cachedDynamicBLAS.count != state.dynamicSlices.count {
            cachedDynamicBLAS.removeAll(keepingCapacity: true)
            cachedDynamicBLAS.reserveCapacity(state.dynamicSlices.count)
            dynamicRefitScratch.removeAll(keepingCapacity: true)
            dynamicRefitScratch.reserveCapacity(state.dynamicSlices.count)

            let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
            for slice in state.dynamicSlices {
                let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
                geometry.vertexBuffer = buffers.dynamicVertexBuffer
                geometry.vertexBufferOffset = slice.baseVertex * MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexFormat = .float3
                geometry.indexBuffer = buffers.dynamicIndexBuffer
                geometry.indexBufferOffset = slice.baseIndex * MemoryLayout<UInt32>.stride
                geometry.indexType = .uint32
                geometry.triangleCount = slice.indexCount / 3
                geometry.opaque = true

                let desc = MTLPrimitiveAccelerationStructureDescriptor()
                desc.geometryDescriptors = [geometry]
                desc.usage = [.refit]

                let sizes = device.accelerationStructureSizes(descriptor: desc)
                let blas = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
                let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize,
                                                options: .storageModePrivate)!

                encoder.build(accelerationStructure: blas,
                              descriptor: desc,
                              scratchBuffer: scratch,
                              scratchBufferOffset: 0)

                let refitScratch = device.makeBuffer(length: max(sizes.refitScratchBufferSize, 1),
                                                     options: .storageModePrivate)!
                cachedDynamicBLAS.append(blas)
                dynamicRefitScratch.append(refitScratch)
                transientScratch.append(scratch)
            }
            encoder.endEncoding()
        } else if !cachedDynamicBLAS.isEmpty {
            let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
            for (i, slice) in state.dynamicSlices.enumerated() {
                let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
                geometry.vertexBuffer = buffers.dynamicVertexBuffer
                geometry.vertexBufferOffset = slice.baseVertex * MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
                geometry.vertexFormat = .float3
                geometry.indexBuffer = buffers.dynamicIndexBuffer
                geometry.indexBufferOffset = slice.baseIndex * MemoryLayout<UInt32>.stride
                geometry.indexType = .uint32
                geometry.triangleCount = slice.indexCount / 3
                geometry.opaque = true

                let desc = MTLPrimitiveAccelerationStructureDescriptor()
                desc.geometryDescriptors = [geometry]
                desc.usage = [.refit]

                let sizes = device.accelerationStructureSizes(descriptor: desc)
                if dynamicRefitScratch[i].length < sizes.refitScratchBufferSize {
                    dynamicRefitScratch[i] = device.makeBuffer(length: sizes.refitScratchBufferSize,
                                                               options: .storageModePrivate)!
                }

                encoder.refit(sourceAccelerationStructure: cachedDynamicBLAS[i],
                              descriptor: desc,
                              destinationAccelerationStructure: cachedDynamicBLAS[i],
                              scratchBuffer: dynamicRefitScratch[i],
                              scratchBufferOffset: 0,
                              options: .vertexData)
            }
            encoder.endEncoding()
        }

        var blasList: [MTLAccelerationStructure] = []
        blasList.reserveCapacity(cachedStaticBLAS.count + cachedDynamicBLAS.count)
        blasList.append(contentsOf: cachedStaticBLAS)
        blasList.append(contentsOf: cachedDynamicBLAS)

        var accelIndexForItem: [UInt32] = []
        accelIndexForItem.reserveCapacity(items.count)
        var staticIndex = 0
        var dynamicIndex = 0

        for slice in state.instanceSlices {
            if slice.bufferIndex == 0 {
                accelIndexForItem.append(UInt32(staticIndex))
                staticIndex += 1
            } else {
                accelIndexForItem.append(UInt32(cachedStaticBLAS.count + dynamicIndex))
                dynamicIndex += 1
            }
        }

        var instances: [MTLAccelerationStructureInstanceDescriptor] = []
        instances.reserveCapacity(items.count)

        for (i, item) in items.enumerated() {
            var desc = MTLAccelerationStructureInstanceDescriptor()
            desc.accelerationStructureIndex = accelIndexForItem[i]
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
