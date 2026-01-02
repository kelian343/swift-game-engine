//
//  UniformRingBuffer.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

struct UniformAllocation {
    let buffer: MTLBuffer
    let offset: Int
    let pointer: UnsafeMutablePointer<Uniforms>
    let frameIndex: Int
}

/// Per-frame ring + per-draw linear allocator:
/// buffer layout: [frame0 draw0..drawN] [frame1 draw0..drawN] ...
final class UniformRingBuffer {
    let buffer: MTLBuffer
    private let alignedSize: Int
    private let maxFrames: Int
    private let maxDrawsPerFrame: Int

    private(set) var frameIndex: Int = 0
    private var drawIndex: Int = 0

    init?(device: MTLDevice,
          maxFramesInFlight: Int,
          maxDrawsPerFrame: Int = 256,
          alignedUniformSize: Int = alignedUniformsSize) {

        self.alignedSize = alignedUniformSize
        self.maxFrames = maxFramesInFlight
        self.maxDrawsPerFrame = maxDrawsPerFrame

        let totalSize = alignedSize * maxFrames * maxDrawsPerFrame
        guard let buf = device.makeBuffer(length: totalSize, options: [.storageModeShared]) else {
            return nil
        }
        buf.label = "UniformBuffer"
        self.buffer = buf
    }

    /// Call once per frame before encoding draw calls.
    func beginFrame() -> Int {
        frameIndex = (frameIndex + 1) % maxFrames
        drawIndex = 0
        return frameIndex
    }

    /// Allocate one Uniforms slot for one draw call.
    func allocate() -> UniformAllocation {
        precondition(drawIndex < maxDrawsPerFrame, "Exceeded maxDrawsPerFrame=\(maxDrawsPerFrame)")

        let base = (frameIndex * maxDrawsPerFrame + drawIndex) * alignedSize
        drawIndex += 1

        let ptr = UnsafeMutableRawPointer(buffer.contents() + base)
            .bindMemory(to: Uniforms.self, capacity: 1)

        return UniformAllocation(buffer: buffer, offset: base, pointer: ptr, frameIndex: frameIndex)
    }
}
