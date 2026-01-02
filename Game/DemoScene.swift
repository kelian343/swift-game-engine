//
//  DemoScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class DemoScene: RenderScene {

    public private(set) var renderItems: [RenderItem] = []
    public private(set) var revision: UInt64 = 0

    public let camera = Camera()

    // ECS
    private let world = World()
    private let spinSystem = SpinSystem()
    private let extractSystem = RenderExtractSystem()

    public init() {}

    public func build(context: SceneContext) {
        let device = context.device

        // Resources (still created here; registry/handles later)
        let mesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 4), label: "ECSBox")
        let tex = TextureResource(device: device, source: ProceduralTextures.checkerboard(), label: "ECSChecker")
        let mat = Material(baseColorTexture: tex)

        // Create multiple entities (but Renderer/Scene interface unchanged)
        for n in 0..<3 {
            let e = world.createEntity()

            // TRS: place them apart; no matrix drift
            var t = TransformComponent()
            t.translation = SIMD3<Float>(Float(n) * 5.0 - 5.0, 0, 0) // -5, 0, +5
            t.scale = SIMD3<Float>(repeating: 1)

            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))

            // Slightly different spin speeds
            world.add(e, SpinComponent(speed: 0.8 + Float(n) * 0.3, axis: SIMD3<Float>(1, 1, 0)))
        }

        // First extraction
        renderItems = extractSystem.extract(world: world)

        // Resources changed (new mesh/texture/material) -> bump revision once
        revision &+= 1
    }

    public func update(dt: Float) {
        // Update camera (your existing behavior)
        camera.updateView()

        // ECS simulation step
        spinSystem.update(world: world, dt: dt)

        // Render extraction
        renderItems = extractSystem.extract(world: world)
    }
}
