//
//  RayTracingScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation
import Metal

final class RayTracingScene {
    private let geometryCache: RTGeometryCache
    private let accelBuilder: RTAccelerationBuilder
    private let skinningEncoder: RTSkinningEncoder?
    private var lastGeometryState: RTGeometryState?
    private var debugLastPrint: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var debugFrames: Int = 0
    private var debugGeomMs: Double = 0
    private var debugSkinningMs: Double = 0
    private var debugAccelMs: Double = 0
    private var debugSkinnedJobs: Int = 0
    private var debugSkinnedVerts: Int = 0
    private var debugDynamicSlices: Int = 0
    private var debugStaticSlices: Int = 0

    init(device: MTLDevice) {
        self.geometryCache = RTGeometryCache(device: device)
        self.accelBuilder = RTAccelerationBuilder(device: device)
        self.skinningEncoder = RTSkinningEncoder(device: device)
    }

    func buildAccelerationStructures(items: [RenderItem],
                                     commandBuffer: MTLCommandBuffer) -> MTLAccelerationStructure? {
        guard let state = lastGeometryState else { return nil }
        let start = CFAbsoluteTimeGetCurrent()
        let accel = accelBuilder.build(state: state, items: items, commandBuffer: commandBuffer)
        debugAccelMs += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        debugStaticSlices = state.staticSlices.count
        debugDynamicSlices = state.dynamicSlices.count
        debugSkinnedJobs = state.skinningJobs.count
        debugSkinnedVerts = state.skinningJobs.reduce(0) { $0 + $1.vertexCount }
        debugFrames += 1
        printPerfIfNeeded()
        return accel
    }

    func buildGeometryBuffers(items: [RenderItem],
                              commandBuffer: MTLCommandBuffer) -> RTGeometryBuffers? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let state = geometryCache.build(items: items) else {
            lastGeometryState = nil
            return nil
        }
        debugGeomMs += (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        lastGeometryState = state
        if let encoder = skinningEncoder, !state.skinningJobs.isEmpty {
            let skinStart = CFAbsoluteTimeGetCurrent()
            encoder.encode(commandBuffer: commandBuffer,
                           outputBuffer: state.buffers.dynamicVertexBuffer,
                           outputNormalBuffer: state.buffers.dynamicNormalBuffer,
                           outputTangentBuffer: state.buffers.dynamicTangentBuffer,
                           jobs: state.skinningJobs)
            debugSkinningMs += (CFAbsoluteTimeGetCurrent() - skinStart) * 1000.0
        }
        return state.buffers
    }

    private func printPerfIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - debugLastPrint < 1.0 || debugFrames == 0 { return }
        let frames = max(debugFrames, 1)
        let geomMs = debugGeomMs / Double(frames)
        let skinMs = debugSkinningMs / Double(frames)
        let accelMs = debugAccelMs / Double(frames)
        print("RTPerf geomMs=\(geomMs) skinningEncodeMs=\(skinMs) accelMs=\(accelMs) skinnedJobs=\(debugSkinnedJobs) skinnedVerts=\(debugSkinnedVerts) dynamicSlices=\(debugDynamicSlices) staticSlices=\(debugStaticSlices)")
        debugLastPrint = now
        debugFrames = 0
        debugGeomMs = 0
        debugSkinningMs = 0
        debugAccelMs = 0
        debugSkinnedJobs = 0
        debugSkinnedVerts = 0
        debugDynamicSlices = 0
        debugStaticSlices = 0
    }
}
