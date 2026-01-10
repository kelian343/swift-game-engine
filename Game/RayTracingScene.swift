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

    private var geometryVertexBuffer: MTLBuffer?
    private var geometryIndexBuffer: MTLBuffer?
    private var geometryInstanceInfoBuffer: MTLBuffer?
    private var lastGeometrySlices: [GeometrySlice] = []
    private var transientBLAS: [MTLAccelerationStructure] = []
    private var transientScratch: [MTLBuffer] = []

    init(device: MTLDevice) {
        self.device = device
    }

    struct GeometryBuffers {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let instanceInfoBuffer: MTLBuffer
        let uvBuffer: MTLBuffer
        let textures: [MTLTexture]
    }

    private struct GeometrySlice {
        let baseVertex: Int
        let baseIndex: Int
        let indexCount: Int
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard !items.isEmpty else { return nil }
        guard let vb = geometryVertexBuffer,
              let ib = geometryIndexBuffer,
              lastGeometrySlices.count == items.count else {
            return nil
        }

        var blasList: [MTLAccelerationStructure] = []
        blasList.reserveCapacity(items.count)
        transientBLAS.removeAll(keepingCapacity: true)
        transientScratch.removeAll(keepingCapacity: true)

        let encoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
        for (i, _) in items.enumerated() {
            let slice = lastGeometrySlices[i]
            let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
            geometry.vertexBuffer = vb
            geometry.vertexBufferOffset = slice.baseVertex * MemoryLayout<SIMD3<Float>>.stride
            geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
            geometry.vertexFormat = .float3
            geometry.indexBuffer = ib
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

        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var instances: [RTInstanceInfoSwift] = []
        var textureIndexForTexture: [ObjectIdentifier: Int] = [:]
        var texturesByIndex: [MTLTexture] = []

        vertices.reserveCapacity(items.count * 256)
        indices.reserveCapacity(items.count * 256)
        instances.reserveCapacity(items.count)
        lastGeometrySlices.removeAll(keepingCapacity: true)
        lastGeometrySlices.reserveCapacity(items.count)

        for item in items {
            let baseVertex = UInt32(vertices.count)
            let baseIndex = UInt32(indices.count)
            var indexCount = 0

            if let skinned = item.skinnedMesh, let palette = item.skinningPalette {
                let vCount = skinned.vertices.count
                vertices.reserveCapacity(vertices.count + vCount)
                uvs.reserveCapacity(uvs.count + vCount)
                for v in skinned.vertices {
                    vertices.append(skinPosition(vertex: v, palette: palette))
                    uvs.append(v.uv)
                }

                indexCount = skinned.indexCount
                if let i16 = skinned.indices16 {
                    for i in i16 {
                        indices.append(UInt32(i))
                    }
                } else if let i32 = skinned.indices32 {
                    indices.append(contentsOf: i32)
                }
            } else if let mesh = item.mesh {
                let vCount = mesh.vertexBuffer.length / MemoryLayout<VertexPNUT>.stride
                let vPtr = mesh.vertexBuffer.contents().bindMemory(to: VertexPNUT.self,
                                                                   capacity: vCount)
                for i in 0..<vCount {
                    vertices.append(vPtr[i].position)
                    uvs.append(vPtr[i].uv)
                }

                indexCount = mesh.indexCount
                switch mesh.indexType {
                case .uint16:
                    let iPtr = mesh.indexBuffer.contents().bindMemory(to: UInt16.self,
                                                                      capacity: indexCount)
                    for i in 0..<indexCount {
                        indices.append(UInt32(iPtr[i]))
                    }
                case .uint32:
                    let iPtr = mesh.indexBuffer.contents().bindMemory(to: UInt32.self,
                                                                      capacity: indexCount)
                    for i in 0..<indexCount {
                        indices.append(iPtr[i])
                    }
                @unknown default:
                    break
                }
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
                                                 padding: 0,
                                                 modelMatrix: item.modelMatrix,
                                                 baseColor: item.material.baseColor,
                                                 metallic: item.material.metallic,
                                                 roughness: item.material.roughness,
                                                 baseAlpha: item.material.alpha,
                                                 padding2: .zero,
                                                 baseColorTexIndex: baseTexIndex,
                                                 padding3: .zero))

            lastGeometrySlices.append(GeometrySlice(baseVertex: Int(baseVertex),
                                                    baseIndex: Int(baseIndex),
                                                    indexCount: indexCount))
        }

        let vBytes = vertices.count * MemoryLayout<SIMD3<Float>>.stride
        let uvBytes = uvs.count * MemoryLayout<SIMD2<Float>>.stride
        let iBytes = indices.count * MemoryLayout<UInt32>.stride
        let instBytes = instances.count * MemoryLayout<RTInstanceInfoSwift>.stride

        geometryVertexBuffer = device.makeBuffer(bytes: vertices,
                                                  length: max(vBytes, 1),
                                                  options: [.storageModeShared])
        let uvBuffer = device.makeBuffer(bytes: uvs,
                                         length: max(uvBytes, 1),
                                         options: [.storageModeShared])
        geometryIndexBuffer = device.makeBuffer(bytes: indices,
                                                 length: max(iBytes, 1),
                                                 options: [.storageModeShared])
        geometryInstanceInfoBuffer = device.makeBuffer(bytes: instances,
                                                        length: max(instBytes, 1),
                                                        options: [.storageModeShared])

        if let vb = geometryVertexBuffer,
           let uvb = uvBuffer,
           let ib = geometryIndexBuffer,
           let instb = geometryInstanceInfoBuffer {
            vb.label = "RTGeometryVertices"
            uvb.label = "RTGeometryUVs"
            ib.label = "RTGeometryIndices"
            instb.label = "RTInstanceInfo"
            return GeometryBuffers(vertexBuffer: vb,
                                   indexBuffer: ib,
                                   instanceInfoBuffer: instb,
                                   uvBuffer: uvb,
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
