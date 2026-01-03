//
//  DemoScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class DemoScene: RenderScene {

    public let camera = Camera()

    public private(set) var renderItems: [RenderItem] = []
    public private(set) var revision: UInt64 = 0

    // ECS
    private let world = World()
    private let timeSystem = TimeSystem()
    private let spinSystem = SpinSystem()
    private let fixedRunner: FixedStepRunner
    private let extractSystem = RenderExtractSystem()

    public init() {
        self.fixedRunner = FixedStepRunner(systems: [spinSystem])
    }

    public func build(context: SceneContext) {
        let device = context.device

        // Camera initial state
        camera.position = SIMD3<Float>(0, 0, 8)
        camera.target = SIMD3<Float>(0, 0, 0)
        camera.updateView()

        // --- Entity A: small box + fine checkerboard
        do {
            let mesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 3.0), label: "BoxA")
            let tex = TextureResource(device: device,
                                      source: ProceduralTextures.checkerboard(width: 256, height: 256, cell: 16),
                                      label: "TexA")
            let mat = Material(baseColorTexture: tex)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(-5, 0, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, SpinComponent(speed: 0.9, axis: SIMD3<Float>(1, 1, 0)))
        }

        // --- Entity B: medium box + coarse checkerboard
        do {
            let mesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 4.0), label: "BoxB")
            let tex = TextureResource(device: device,
                                      source: ProceduralTextures.checkerboard(width: 256, height: 256, cell: 48),
                                      label: "TexB")
            let mat = Material(baseColorTexture: tex)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, 0, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, SpinComponent(speed: 1.2, axis: SIMD3<Float>(0, 1, 0)))
        }

        // --- Entity C: large box + solid color texture
        do {
            let mesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 5.0), label: "BoxC")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 255, g: 80, b: 80, a: 255),
                                      label: "TexC")
            let mat = Material(baseColorTexture: tex)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(5, 0, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, SpinComponent(speed: 0.7, axis: SIMD3<Float>(1, 0, 1)))
        }

        // Extract initial draw calls
        renderItems = extractSystem.extract(world: world)

        // New resources were created -> bump revision once
        revision &+= 1
    }

    public func update(dt: Float) {
        camera.updateView()

        // ECS simulation step
        timeSystem.update(world: world, dt: dt)
        fixedRunner.update(world: world)

        // Render extraction (derived every frame)
        renderItems = extractSystem.extract(world: world)
    }
}
