//
//  RenderScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation

public protocol RenderScene: AnyObject {
    /// Called once after Renderer is created (device is ready).
    func build(context: SceneContext)

    /// Per-frame update (dt in seconds).
    func update(dt: Float)

    /// Current draw calls.
    var renderItems: [RenderItem] { get }

    /// Increment this when renderItems/resources change (mesh/texture/material changes).
    var revision: UInt64 { get }
}
