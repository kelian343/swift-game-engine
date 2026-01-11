//
//  RTSkinningEncoder.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Metal

final class RTSkinningEncoder {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState

    init?(device: MTLDevice) {
        self.device = device
        let library = device.makeDefaultLibrary()
        guard let fn = library?.makeFunction(name: "skinningKernel") else {
            return nil
        }
        do {
            self.pipelineState = try device.makeComputePipelineState(function: fn)
        } catch {
            return nil
        }
    }

    func encode(commandBuffer: MTLCommandBuffer,
                outputBuffer: MTLBuffer,
                jobs: [RTSkinningJob]) {
        guard !jobs.isEmpty,
              let enc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        enc.setComputePipelineState(pipelineState)
        for job in jobs {
            var params = SkinningParamsSwift(baseVertex: UInt32(job.dstBaseVertex),
                                             vertexCount: UInt32(job.vertexCount))
            enc.setBuffer(job.sourcePositions, offset: 0, index: 0)
            enc.setBuffer(job.sourceBoneIndices, offset: 0, index: 1)
            enc.setBuffer(job.sourceBoneWeights, offset: 0, index: 2)
            enc.setBuffer(job.paletteBuffer, offset: 0, index: 3)
            enc.setBuffer(outputBuffer, offset: 0, index: 4)
            enc.setBytes(&params, length: MemoryLayout<SkinningParamsSwift>.stride, index: 5)

            let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
            let threadsPerGrid = MTLSize(width: job.vertexCount, height: 1, depth: 1)
            enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        }
        enc.endEncoding()
    }
}

private struct SkinningParamsSwift {
    var baseVertex: UInt32
    var vertexCount: UInt32
}
