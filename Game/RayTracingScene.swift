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
    private let skinningEncoder: RTSkinningEncoder?
    private var lastGeometryState: RTGeometryState?

    init(device: MTLDevice) {
        self.geometryCache = RTGeometryCache(device: device)
        self.accelBuilder = RTAccelerationBuilder(device: device)
        self.skinningEncoder = RTSkinningEncoder(device: device)
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard let state = lastGeometryState else { return nil }
        return accelBuilder.build(state: state, items: items, commandBuffer: commandBuffer)
    }

    func buildGeometryBuffers(items: [RenderItem],
                              commandBuffer: MTLCommandBuffer) -> RTGeometryBuffers? {
        guard let state = geometryCache.build(items: items) else {
            lastGeometryState = nil
            return nil
        }
        lastGeometryState = state
        if let encoder = skinningEncoder, !state.skinningJobs.isEmpty {
            encoder.encode(commandBuffer: commandBuffer,
                           outputBuffer: state.buffers.dynamicVertexBuffer,
                           outputNormalBuffer: state.buffers.dynamicNormalBuffer,
                           outputTangentBuffer: state.buffers.dynamicTangentBuffer,
                           jobs: state.skinningJobs)
        }
        return state.buffers
    }
}
