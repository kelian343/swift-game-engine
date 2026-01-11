//
//  FrameSync.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

final class FrameSync {
    private let event: MTLSharedEvent
    private(set) var frameIndex: Int
    private let maxFramesInFlight: Int

    init(device: MTLDevice, maxFramesInFlight: Int) {
        self.event = device.makeSharedEvent()!
        self.maxFramesInFlight = maxFramesInFlight
        self.frameIndex = maxFramesInFlight
        self.event.signaledValue = UInt64(self.frameIndex - 1)
    }

    func waitIfNeeded(timeoutMS: UInt64 = 10) {
        let previousValueToWaitFor = frameIndex - maxFramesInFlight
        event.wait(untilSignaledValue: UInt64(previousValueToWaitFor), timeoutMS: timeoutMS)
    }

    func signalNextFrame(on commandBuffer: MTLCommandBuffer) {
        commandBuffer.encodeSignalEvent(event, value: UInt64(frameIndex))
        frameIndex += 1
    }
}
