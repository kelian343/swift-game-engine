//
//  FrameSync.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

/// CPU/GPU synchronization for frames-in-flight using MTLSharedEvent.
final class FrameSync {

    private let event: MTLSharedEvent
    private(set) var frameIndex: Int
    private let maxFramesInFlight: Int

    init(device: MTLDevice, maxFramesInFlight: Int) {
        self.event = device.makeSharedEvent()!
        self.maxFramesInFlight = maxFramesInFlight

        // Match original behavior
        self.frameIndex = maxFramesInFlight
        self.event.signaledValue = UInt64(self.frameIndex - 1)
    }

    func waitIfNeeded(timeoutMS: UInt64 = 10) {
        let previousValueToWaitFor = frameIndex - maxFramesInFlight
        event.wait(
            untilSignaledValue: UInt64(previousValueToWaitFor),
            timeoutMS: timeoutMS
        )
    }

    func signalNextFrame(on queue: MTL4CommandQueue) {
        queue.signalEvent(event, value: UInt64(frameIndex))
        frameIndex += 1
    }
}
