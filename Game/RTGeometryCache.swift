//
//  RTGeometryCache.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Metal
import simd

struct RTGeometryBuffers {
    let staticVertexBuffer: MTLBuffer
    let staticIndexBuffer: MTLBuffer
    let instanceInfoBuffer: MTLBuffer
    let staticUVBuffer: MTLBuffer
    let dynamicVertexBuffer: MTLBuffer
    let dynamicIndexBuffer: MTLBuffer
    let dynamicUVBuffer: MTLBuffer
    let textures: [MTLTexture]
}

struct RTGeometrySlice {
    let baseVertex: Int
    let baseIndex: Int
    let indexCount: Int
    let bufferIndex: UInt32
}

struct RTGeometryState {
    let buffers: RTGeometryBuffers
    let instanceSlices: [RTGeometrySlice]
    let staticSlices: [RTGeometrySlice]
    let dynamicSlices: [RTGeometrySlice]
    let staticChanged: Bool
    let dynamicChanged: Bool
}

final class RTGeometryCache {
    private let device: MTLDevice

    private var staticVertexBuffer: MTLBuffer?
    private var staticIndexBuffer: MTLBuffer?
    private var staticUVBuffer: MTLBuffer?
    private var dynamicVertexBuffer: MTLBuffer?
    private var dynamicIndexBuffer: MTLBuffer?
    private var dynamicUVBuffer: MTLBuffer?
    private var geometryInstanceInfoBuffer: MTLBuffer?
    private var dynamicVertexCapacity: Int = 0
    private var dynamicIndexCapacity: Int = 0
    private var dynamicUVCapacity: Int = 0
    private var instanceInfoCapacity: Int = 0

    private var cachedStaticSlices: [RTGeometrySlice] = []
    private var cachedDynamicSlices: [RTGeometrySlice] = []
    private var cachedStaticKey: [StaticKey] = []
    private var cachedDynamicKey: [DynamicKey] = []

    init(device: MTLDevice) {
        self.device = device
    }

    private struct StaticKey: Equatable {
        let meshID: ObjectIdentifier
        let vertexBytes: Int
        let indexCount: Int
        let indexType: MTLIndexType
    }

    private struct DynamicKey: Equatable {
        let vertexCount: Int
        let indexCount: Int
    }

    func build(items: [RenderItem]) -> RTGeometryState? {
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

        let staticKey = items.compactMap { item -> StaticKey? in
            guard let mesh = item.mesh, item.skinnedMesh == nil else { return nil }
            return StaticKey(meshID: ObjectIdentifier(mesh),
                             vertexBytes: mesh.vertexBuffer.length,
                             indexCount: mesh.indexCount,
                             indexType: mesh.indexType)
        }

        let staticChanged = staticKey != cachedStaticKey
            || staticVertexBuffer == nil
            || staticIndexBuffer == nil
            || staticUVBuffer == nil

        if staticChanged {
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

                cachedStaticSlices.append(RTGeometrySlice(baseVertex: Int(baseVertex),
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

        var instanceSlices: [RTGeometrySlice] = []
        instanceSlices.reserveCapacity(items.count)
        var staticSliceIndex = 0
        var dynamicKey: [DynamicKey] = []
        var dynamicSlices: [RTGeometrySlice] = []

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
                dynamicKey.append(DynamicKey(vertexCount: vCount, indexCount: indexCount))
                dynamicSlices.append(RTGeometrySlice(baseVertex: Int(baseVertex),
                                                     baseIndex: Int(baseIndex),
                                                     indexCount: indexCount,
                                                     bufferIndex: bufferIndex))
            } else if item.mesh != nil {
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

            instanceSlices.append(RTGeometrySlice(baseVertex: Int(baseVertex),
                                                  baseIndex: Int(baseIndex),
                                                  indexCount: indexCount,
                                                  bufferIndex: bufferIndex))
        }

        let dynamicChanged = dynamicKey != cachedDynamicKey
        cachedDynamicKey = dynamicKey
        cachedDynamicSlices = dynamicSlices

        let vBytes = dynamicVertices.count * MemoryLayout<SIMD3<Float>>.stride
        let uvBytes = dynamicUVs.count * MemoryLayout<SIMD2<Float>>.stride
        let iBytes = dynamicIndices.count * MemoryLayout<UInt32>.stride
        let instBytes = instances.count * MemoryLayout<RTInstanceInfoSwift>.stride

        if dynamicVertexBuffer == nil || vBytes > dynamicVertexCapacity {
            dynamicVertexCapacity = max(vBytes, 1)
            dynamicVertexBuffer = device.makeBuffer(length: dynamicVertexCapacity,
                                                    options: [.storageModeShared])
            dynamicVertexBuffer?.label = "RTDynamicVertices"
        }
        if dynamicUVBuffer == nil || uvBytes > dynamicUVCapacity {
            dynamicUVCapacity = max(uvBytes, 1)
            dynamicUVBuffer = device.makeBuffer(length: dynamicUVCapacity,
                                                options: [.storageModeShared])
            dynamicUVBuffer?.label = "RTDynamicUVs"
        }
        if dynamicIndexBuffer == nil || iBytes > dynamicIndexCapacity {
            dynamicIndexCapacity = max(iBytes, 1)
            dynamicIndexBuffer = device.makeBuffer(length: dynamicIndexCapacity,
                                                   options: [.storageModeShared])
            dynamicIndexBuffer?.label = "RTDynamicIndices"
        }
        if geometryInstanceInfoBuffer == nil || instBytes > instanceInfoCapacity {
            instanceInfoCapacity = max(instBytes, 1)
            geometryInstanceInfoBuffer = device.makeBuffer(length: instanceInfoCapacity,
                                                            options: [.storageModeShared])
            geometryInstanceInfoBuffer?.label = "RTInstanceInfo"
        }

        if let buf = dynamicVertexBuffer, !dynamicVertices.isEmpty {
            _ = dynamicVertices.withUnsafeBytes { raw in
                memcpy(buf.contents(), raw.baseAddress!, raw.count)
            }
        }
        if let buf = dynamicUVBuffer, !dynamicUVs.isEmpty {
            _ = dynamicUVs.withUnsafeBytes { raw in
                memcpy(buf.contents(), raw.baseAddress!, raw.count)
            }
        }
        if let buf = dynamicIndexBuffer, !dynamicIndices.isEmpty {
            _ = dynamicIndices.withUnsafeBytes { raw in
                memcpy(buf.contents(), raw.baseAddress!, raw.count)
            }
        }
        if let buf = geometryInstanceInfoBuffer, !instances.isEmpty {
            _ = instances.withUnsafeBytes { raw in
                memcpy(buf.contents(), raw.baseAddress!, raw.count)
            }
        }

        guard let staticVB = staticVertexBuffer,
              let staticUVB = staticUVBuffer,
              let staticIB = staticIndexBuffer,
              let dynamicVB = dynamicVertexBuffer,
              let dynamicUVB = dynamicUVBuffer,
              let dynamicIB = dynamicIndexBuffer,
              let instb = geometryInstanceInfoBuffer else {
            return nil
        }

        let buffers = RTGeometryBuffers(staticVertexBuffer: staticVB,
                                        staticIndexBuffer: staticIB,
                                        instanceInfoBuffer: instb,
                                        staticUVBuffer: staticUVB,
                                        dynamicVertexBuffer: dynamicVB,
                                        dynamicIndexBuffer: dynamicIB,
                                        dynamicUVBuffer: dynamicUVB,
                                        textures: texturesByIndex)

        return RTGeometryState(buffers: buffers,
                               instanceSlices: instanceSlices,
                               staticSlices: cachedStaticSlices,
                               dynamicSlices: cachedDynamicSlices,
                               staticChanged: staticChanged,
                               dynamicChanged: dynamicChanged)
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
