//
//  SceneContext.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

/// What the scene needs to create GPU resources.
/// Keep it minimal; you can add more later (e.g. asset registry, thread pools).
public struct SceneContext {
    public let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }
}
