//
//  RayTracingScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

final class RayTracingScene {
    private let geometryCache: RTGeometryCache
    private let accelBuilder: RTAccelerationBuilder
    private var lastGeometryState: RTGeometryState?

    init(device: MTLDevice) {
        self.geometryCache = RTGeometryCache(device: device)
        self.accelBuilder = RTAccelerationBuilder(device: device)
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard let state = lastGeometryState else { return nil }
        return accelBuilder.build(state: state, items: items, commandBuffer: commandBuffer)
    }

    func buildGeometryBuffers(items: [RenderItem]) -> RTGeometryBuffers? {
        guard let state = geometryCache.build(items: items) else {
            lastGeometryState = nil
            return nil
        }
        lastGeometryState = state
        return state.buffers
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
