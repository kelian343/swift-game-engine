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

    private var tlas: MTLAccelerationStructure?
    private var tlasSize: Int = 0
    private var tlasScratch: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var lastInstanceCount: Int = 0

    private var staticVertexBuffer: MTLBuffer?
    private var staticIndexBuffer: MTLBuffer?
    private var staticUVBuffer: MTLBuffer?
    private var dynamicVertexBuffer: MTLBuffer?
    private var dynamicIndexBuffer: MTLBuffer?
    private var dynamicUVBuffer: MTLBuffer?
    private var geometryInstanceInfoBuffer: MTLBuffer?
    private var lastInstanceSlices: [GeometrySlice] = []
    private var cachedStaticSlices: [GeometrySlice] = []
    private var cachedStaticKey: [StaticKey] = []
    private var transientBLAS: [MTLAccelerationStructure] = []
    private var transientScratch: [MTLBuffer] = []

    init(device: MTLDevice) {
        self.device = device
    }

    struct GeometryBuffers {
        let staticVertexBuffer: MTLBuffer
        let staticIndexBuffer: MTLBuffer
        let instanceInfoBuffer: MTLBuffer
        let staticUVBuffer: MTLBuffer
        let dynamicVertexBuffer: MTLBuffer
        let dynamicIndexBuffer: MTLBuffer
        let dynamicUVBuffer: MTLBuffer
        let textures: [MTLTexture]
    }

    private struct GeometrySlice {
        let baseVertex: Int
        let baseIndex: Int
        let indexCount: Int
        let bufferIndex: UInt32
    }

    private struct StaticKey: Equatable {
        let meshID: ObjectIdentifier
        let vertexBytes: Int
        let indexCount: Int
        let indexType: MTLIndexType
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard !items.isEmpty else { return nil }
        guard let staticVB = staticVertexBuffer,
              let staticIB = staticIndexBuffer,
              let dynamicVB = dynamicVertexBuffer,
              let dynamicIB = dynamicIndexBuffer,
              lastInstanceSlices.count == items.count else {
            return nil
        }

        var blasList: [MTLAccelerationStructure] = []
        blasList.reserveCapacity(items.count)
        transientBLAS.removeAll(keepingCapacity: true)
        transientScratch.removeAll(keepingCapacity: true)

        let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        for (i, _) in items.enumerated() {
            let slice = lastInstanceSlices[i]
            let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
            geometry.vertexBuffer = slice.bufferIndex == 0 ? staticVB : dynamicVB
            geometry.vertexBufferOffset = slice.baseVertex * MemoryLayout<SIMD3<Float>>.stride
            geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
            geometry.vertexFormat = .float3
            geometry.indexBuffer = slice.bufferIndex == 0 ? staticIB : dynamicIB
            geometry.indexBufferOffset = slice.baseIndex * MemoryLayout<UInt32>.stride
            geometry.indexType = .uint32
            geometry.triangleCount = slice.indexCount / 3
            geometry.opaque = true

            let desc = MTLPrimitiveAccelerationStructureDescriptor()
            desc.geometryDescriptors = [geometry]

            let sizes = device.accelerationStructureSizes(descriptor: desc)
            let blas = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
            let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize,
                                            options: .storageModePrivate)!

            encoder.build(accelerationStructure: blas,
                          descriptor: desc,
                          scratchBuffer: scratch,
                          scratchBufferOffset: 0)

            transientBLAS.append(blas)
            transientScratch.append(scratch)
            blasList.append(blas)
        }
        encoder.endEncoding()

        var instances: [MTLAccelerationStructureInstanceDescriptor] = []
        instances.reserveCapacity(items.count)

        for (i, item) in items.enumerated() {
            var desc = MTLAccelerationStructureInstanceDescriptor()
            desc.accelerationStructureIndex = UInt32(i)
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

    func buildGeometryBuffers(items: [RenderItem]) -> GeometryBuffers? {
        guard !items.isEmpty else { return nil }

        var dynamicVertices: [SIMD3<Float>] = []
        var dynamicUVs: [SIMD2<Float>] = []
        var dynamicIndices: [UInt32] = []
        var instances: [RTInstanceInfoSwift] = []
        var textureIndexForTexture: [ObjectIdentifier: Int] = [:]
        var texturesByIndex: [MTLTexture] = []

        dynamicVertices.reserveCapacity(items.count * 128)
        dynamicIndices.reserveCapacity(items.count * 128)
        instances.reserveCapacity(items.count)
        lastInstanceSlices.removeAll(keepingCapacity: true)
        lastInstanceSlices.reserveCapacity(items.count)

        let staticKey = items.compactMap { item -> StaticKey? in
            guard let mesh = item.mesh, item.skinnedMesh == nil else { return nil }
            return StaticKey(meshID: ObjectIdentifier(mesh),
                             vertexBytes: mesh.vertexBuffer.length,
                             indexCount: mesh.indexCount,
                             indexType: mesh.indexType)
        }

        if staticKey != cachedStaticKey || staticVertexBuffer == nil || staticIndexBuffer == nil || staticUVBuffer == nil {
            cachedStaticKey = staticKey
            cachedStaticSlices.removeAll(keepingCapacity: true)

            var staticVertices: [SIMD3<Float>] = []
            var staticUVs: [SIMD2<Float>] = []
            var staticIndices: [UInt32] = []

            staticVertices.reserveCapacity(staticKey.count * 256)
            staticIndices.reserveCapacity(staticKey.count * 256)

            for item in items {
                guard let mesh = item.mesh, item.skinnedMesh == nil else { continue }
                let baseVertex = UInt32(staticVertices.count)
                let baseIndex = UInt32(staticIndices.count)

                let vCount = mesh.vertexBuffer.length / MemoryLayout<VertexPNUT>.stride
                let vPtr = mesh.vertexBuffer.contents().bindMemory(to: VertexPNUT.self,
                                                                   capacity: vCount)
                for i in 0..<vCount {
                    staticVertices.append(vPtr[i].position)
                    staticUVs.append(vPtr[i].uv)
                }

                let indexCount = mesh.indexCount
                switch mesh.indexType {
                case .uint16:
                    let iPtr = mesh.indexBuffer.contents().bindMemory(to: UInt16.self,
                                                                      capacity: indexCount)
                    for i in 0..<indexCount {
                        staticIndices.append(UInt32(iPtr[i]))
                    }
                case .uint32:
                    let iPtr = mesh.indexBuffer.contents().bindMemory(to: UInt32.self,
                                                                      capacity: indexCount)
                    for i in 0..<indexCount {
                        staticIndices.append(iPtr[i])
                    }
                @unknown default:
                    break
                }

                cachedStaticSlices.append(GeometrySlice(baseVertex: Int(baseVertex),
                                                        baseIndex: Int(baseIndex),
                                                        indexCount: indexCount,
                                                        bufferIndex: 0))
            }

            let vBytes = staticVertices.count * MemoryLayout<SIMD3<Float>>.stride
            let uvBytes = staticUVs.count * MemoryLayout<SIMD2<Float>>.stride
            let iBytes = staticIndices.count * MemoryLayout<UInt32>.stride
            staticVertexBuffer = device.makeBuffer(bytes: staticVertices,
                                                   length: max(vBytes, 1),
                                                   options: [.storageModeShared])
            staticUVBuffer = device.makeBuffer(bytes: staticUVs,
                                               length: max(uvBytes, 1),
                                               options: [.storageModeShared])
            staticIndexBuffer = device.makeBuffer(bytes: staticIndices,
                                                  length: max(iBytes, 1),
                                                  options: [.storageModeShared])
            staticVertexBuffer?.label = "RTStaticVertices"
            staticUVBuffer?.label = "RTStaticUVs"
            staticIndexBuffer?.label = "RTStaticIndices"
        }

        var staticSliceIndex = 0

        for item in items {
            var baseVertex: UInt32 = 0
            var baseIndex: UInt32 = 0
            var indexCount = 0
            var bufferIndex: UInt32 = 0

            if let skinned = item.skinnedMesh, let palette = item.skinningPalette {
                let vCount = skinned.vertices.count
                dynamicVertices.reserveCapacity(dynamicVertices.count + vCount)
                dynamicUVs.reserveCapacity(dynamicUVs.count + vCount)
                baseVertex = UInt32(dynamicVertices.count)
                baseIndex = UInt32(dynamicIndices.count)
                for v in skinned.vertices {
                    dynamicVertices.append(skinPosition(vertex: v, palette: palette))
                    dynamicUVs.append(v.uv)
                }

                indexCount = skinned.indexCount
                if let i16 = skinned.indices16 {
                    for i in i16 {
                        dynamicIndices.append(UInt32(i))
                    }
                } else if let i32 = skinned.indices32 {
                    dynamicIndices.append(contentsOf: i32)
                }
                bufferIndex = 1
            } else if let mesh = item.mesh {
                if staticSliceIndex >= cachedStaticSlices.count { return nil }
                let slice = cachedStaticSlices[staticSliceIndex]
                staticSliceIndex += 1
                baseVertex = UInt32(slice.baseVertex)
                baseIndex = UInt32(slice.baseIndex)
                indexCount = slice.indexCount
                bufferIndex = 0
            } else {
                continue
            }

            let baseTexIndex: UInt32 = {
                guard let tex = item.material.baseColorTexture?.texture else { return UInt32.max }
                let key = ObjectIdentifier(tex)
                if let existing = textureIndexForTexture[key] {
                    return UInt32(existing)
                }
                if texturesByIndex.count >= maxRTTextures {
                    return UInt32.max
                }
                let index = texturesByIndex.count
                texturesByIndex.append(tex)
                textureIndexForTexture[key] = index
                return UInt32(index)
            }()

            instances.append(RTInstanceInfoSwift(baseIndex: baseIndex,
                                                 baseVertex: baseVertex,
                                                 indexCount: UInt32(indexCount),
                                                 bufferIndex: bufferIndex,
                                                 modelMatrix: item.modelMatrix,
                                                 baseColor: item.material.baseColor,
                                                 metallic: item.material.metallic,
                                                 roughness: item.material.roughness,
                                                 baseAlpha: item.material.alpha,
                                                 padding2: .zero,
                                                 baseColorTexIndex: baseTexIndex,
                                                 padding3: .zero))

            lastInstanceSlices.append(GeometrySlice(baseVertex: Int(baseVertex),
                                                    baseIndex: Int(baseIndex),
                                                    indexCount: indexCount,
                                                    bufferIndex: bufferIndex))
        }

        let vBytes = dynamicVertices.count * MemoryLayout<SIMD3<Float>>.stride
        let uvBytes = dynamicUVs.count * MemoryLayout<SIMD2<Float>>.stride
        let iBytes = dynamicIndices.count * MemoryLayout<UInt32>.stride
        let instBytes = instances.count * MemoryLayout<RTInstanceInfoSwift>.stride

        dynamicVertexBuffer = device.makeBuffer(bytes: dynamicVertices,
                                                length: max(vBytes, 1),
                                                options: [.storageModeShared])
        dynamicUVBuffer = device.makeBuffer(bytes: dynamicUVs,
                                            length: max(uvBytes, 1),
                                            options: [.storageModeShared])
        dynamicIndexBuffer = device.makeBuffer(bytes: dynamicIndices,
                                               length: max(iBytes, 1),
                                               options: [.storageModeShared])
        geometryInstanceInfoBuffer = device.makeBuffer(bytes: instances,
                                                        length: max(instBytes, 1),
                                                        options: [.storageModeShared])

        if let staticVB = staticVertexBuffer,
           let staticUVB = staticUVBuffer,
           let staticIB = staticIndexBuffer,
           let dynamicVB = dynamicVertexBuffer,
           let dynamicUVB = dynamicUVBuffer,
           let dynamicIB = dynamicIndexBuffer,
           let instb = geometryInstanceInfoBuffer {
            dynamicVB.label = "RTDynamicVertices"
            dynamicUVB.label = "RTDynamicUVs"
            dynamicIB.label = "RTDynamicIndices"
            instb.label = "RTInstanceInfo"
            return GeometryBuffers(staticVertexBuffer: staticVB,
                                   staticIndexBuffer: staticIB,
                                   instanceInfoBuffer: instb,
                                   staticUVBuffer: staticUVB,
                                   dynamicVertexBuffer: dynamicVB,
                                   dynamicIndexBuffer: dynamicIB,
                                   dynamicUVBuffer: dynamicUVB,
                                   textures: texturesByIndex)
        }

        return nil
    }
}

private func skinPosition(vertex: VertexSkinnedPNUT4,
                          palette: [matrix_float4x4]) -> SIMD3<Float> {
    let idx = vertex.boneIndices
    let w = vertex.boneWeights

    var p = SIMD3<Float>(0, 0, 0)
    if w.x > 0 {
        let m = palette[Int(idx.x)]
        let v = simd_mul(m, SIMD4<Float>(vertex.position, 1))
        p += SIMD3<Float>(v.x, v.y, v.z) * w.x
    }
    if w.y > 0 {
        let m = palette[Int(idx.y)]
        let v = simd_mul(m, SIMD4<Float>(vertex.position, 1))
        p += SIMD3<Float>(v.x, v.y, v.z) * w.y
    }
    if w.z > 0 {
        let m = palette[Int(idx.z)]
        let v = simd_mul(m, SIMD4<Float>(vertex.position, 1))
        p += SIMD3<Float>(v.x, v.y, v.z) * w.z
    }
    if w.w > 0 {
        let m = palette[Int(idx.w)]
        let v = simd_mul(m, SIMD4<Float>(vertex.position, 1))
        p += SIMD3<Float>(v.x, v.y, v.z) * w.w
    }
    return p
}
