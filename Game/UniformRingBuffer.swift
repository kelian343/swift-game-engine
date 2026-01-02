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
    let index: Int
}

/// Triple-buffered (or N-buffered) dynamic uniform ring buffer.
final class UniformRingBuffer {
    let buffer: MTLBuffer
    private let alignedSize: Int
    private let maxFrames: Int

    private(set) var index: Int = 0

    init?(device: MTLDevice, maxFramesInFlight: Int, alignedUniformSize: Int = alignedUniformsSize) {
        self.alignedSize = alignedUniformSize
        self.maxFrames = maxFramesInFlight

        let totalSize = alignedSize * maxFrames
        guard let buf = device.makeBuffer(length: totalSize, options: [.storageModeShared]) else {
            return nil
        }
        buf.label = "UniformBuffer"
        self.buffer = buf
    }

    func next() -> UniformAllocation {
        index = (index + 1) % maxFrames
        let offset = alignedSize * index

        let ptr = UnsafeMutableRawPointer(buffer.contents() + offset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        return UniformAllocation(buffer: buffer, offset: offset, pointer: ptr, index: index)
    }
}
