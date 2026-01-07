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
    private let inputSystem: InputSystem
    private let spinSystem = SpinSystem()
    private let physicsWorld = PhysicsWorld()
    private let physicsSyncSystem: PhysicsSyncSystem
    private let physicsBroadphaseSystem: PhysicsBroadphaseSystem
    private let physicsBeginStepSystem = PhysicsBeginStepSystem()
    private let physicsNarrowphaseSystem: PhysicsNarrowphaseSystem
    private let physicsSolverSystem: PhysicsSolverSystem
    private let physicsIntentSystem = PhysicsIntentSystem()
    private let physicsIntegrateSystem = PhysicsIntegrateSystem()
    private let physicsWritebackSystem = PhysicsWritebackSystem()
    private let physicsEventsSystem: PhysicsEventsSystem
    private let fixedRunner: FixedStepRunner
    private let extractSystem = RenderExtractSystem()
    private var collisionQuery: CollisionQuery?
    private var lastRayHitTriangle: Int?

    public init() {
        self.inputSystem = InputSystem(camera: camera)
        self.physicsSyncSystem = PhysicsSyncSystem(physicsWorld: physicsWorld)
        self.physicsBroadphaseSystem = PhysicsBroadphaseSystem(physicsWorld: physicsWorld)
        self.physicsNarrowphaseSystem = PhysicsNarrowphaseSystem(physicsWorld: physicsWorld)
        self.physicsSolverSystem = PhysicsSolverSystem(physicsWorld: physicsWorld)
        self.physicsEventsSystem = PhysicsEventsSystem(physicsWorld: physicsWorld)
        self.fixedRunner = FixedStepRunner(
            preFixed: [spinSystem, physicsIntentSystem, physicsSyncSystem, physicsBeginStepSystem],
            fixed: [physicsBroadphaseSystem, physicsNarrowphaseSystem, physicsSolverSystem, physicsIntegrateSystem],
            postFixed: [physicsWritebackSystem, physicsEventsSystem]
        )
    }

    public func build(context: SceneContext) {
        let device = context.device

        // Camera initial state
        camera.position = SIMD3<Float>(0, 0, 8)
        camera.target = SIMD3<Float>(0, 0, 0)
        camera.updateView()

        // --- Ground: platform plane (4x area)
        do {
            let meshData = ProceduralMeshes.plane(size: 40.0)
            let mesh = GPUMesh(device: device, data: meshData, label: "Ground")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 80, g: 80, b: 80, a: 255),
                                      label: "GroundTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.8)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, -3, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(20, 0.1, 20))))
        }

        // --- Player: capsule + coarse checkerboard
        do {
            let playerRadius: Float = 1.5
            let playerHalfHeight: Float = 1.0
            let meshData = ProceduralMeshes.capsule(radius: playerRadius,
                                                    halfHeight: playerHalfHeight)
            let mesh = GPUMesh(device: device, data: meshData, label: "PlayerCapsule")
            let tex = TextureResource(device: device,
                                      source: ProceduralTextures.checkerboard(width: 256, height: 256, cell: 48),
                                      label: "TexB")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.4)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, 0.5, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            inputSystem.setPlayer(e)
            world.add(e, PhysicsBodyComponent(bodyType: .dynamic,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, MoveIntentComponent())
            world.add(e, MovementComponent(maxAcceleration: 16.0, maxDeceleration: 24.0))
            world.add(e, ColliderComponent(shape: .capsule(halfHeight: playerHalfHeight,
                                                          radius: playerRadius)))
        }

        // --- Test Wall: large static blocker
        do {
            let meshData = ProceduralMeshes.box(size: 6.0)
            let mesh = GPUMesh(device: device, data: meshData, label: "TestWall")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 255, g: 80, b: 80, a: 255),
                                      label: "WallTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.7)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, 0, -10)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(3, 3, 3))))
        }

        // --- Test Ramp: sloped obstacle
        do {
            let meshData = ProceduralMeshes.ramp(width: 8.0, depth: 10.0, height: 4.0)
            let mesh = GPUMesh(device: device, data: meshData, label: "TestRamp")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 80, g: 160, b: 255, a: 255),
                                      label: "RampTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.6)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(8, 0, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 2, 4))))
        }

        // --- Test Step: small ledge
        do {
            let meshData = ProceduralMeshes.box(size: 2.0)
            let mesh = GPUMesh(device: device, data: meshData, label: "TestStep")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 255, g: 220, b: 120, a: 255),
                                      label: "StepTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.8)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(-6, -2, 4)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(1, 1, 1))))
        }

        // Extract initial draw calls
        renderItems = extractSystem.extract(world: world)
        collisionQuery = CollisionQuery(world: world)

        // New resources were created -> bump revision once
        revision &+= 1
    }

    public func update(dt: Float) {
        // ECS simulation step
        timeSystem.update(world: world, dt: dt)
        inputSystem.update(world: world, dt: dt)
        fixedRunner.update(world: world)

        camera.updateView()
        debugRaycast()

        // Render extraction (derived every frame)
        renderItems = extractSystem.extract(world: world)
    }

    private func debugRaycast() {
        guard let query = collisionQuery else { return }
        let dir = camera.target - camera.position
        let lenSq = simd_length_squared(dir)
        if lenSq < 1e-6 {
            return
        }
        let hit = query.raycast(origin: camera.position,
                                direction: simd_normalize(dir),
                                maxDistance: 100.0)
        let tri = hit?.triangleIndex
        if tri != lastRayHitTriangle {
            if let hit = hit {
                print("Ray hit tri \(hit.triangleIndex) at \(hit.distance)")
            } else {
                print("Ray miss")
            }
            lastRayHitTriangle = tri
        }
    }
}
