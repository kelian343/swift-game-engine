//
//  RenderScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation
import simd

public protocol RenderScene: AnyObject {
    /// Scene-owned camera (Renderer should not assume concrete scene types)
    var camera: Camera { get }

    /// Called once after Renderer is created (device is ready).
    func build(context: SceneContext)

    /// Per-frame update (dt in seconds).
    func update(dt: Float)

    /// Current draw calls.
    var renderItems: [RenderItem] { get }

    /// Optional overlay draw calls (UI/debug).
    var overlayItems: [RenderItem] { get }

    /// Increment this when renderItems/resources change (mesh/texture/material changes).
    var revision: UInt64 { get }

    func viewportDidChange(size: SIMD2<Float>)
}

extension RenderScene {
    func viewportDidChange(size: SIMD2<Float>) {
        _ = size
    }
}
