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
    private let jumpSystem = JumpSystem()
    private let gravitySystem = GravitySystem()
    private let kinematicMoveSystem = KinematicMoveStopSystem()
    private let physicsIntegrateSystem = PhysicsIntegrateSystem()
    private let physicsWritebackSystem = PhysicsWritebackSystem()
    private let physicsEventsSystem: PhysicsEventsSystem
    private let fixedRunner: FixedStepRunner
    private let extractSystem = RenderExtractSystem()
    private var collisionQuery: CollisionQuery?

    public init() {
        self.inputSystem = InputSystem(camera: camera)
        self.physicsSyncSystem = PhysicsSyncSystem(physicsWorld: physicsWorld)
        self.physicsBroadphaseSystem = PhysicsBroadphaseSystem(physicsWorld: physicsWorld)
        self.physicsNarrowphaseSystem = PhysicsNarrowphaseSystem(physicsWorld: physicsWorld)
        self.physicsSolverSystem = PhysicsSolverSystem(physicsWorld: physicsWorld)
        self.physicsEventsSystem = PhysicsEventsSystem(physicsWorld: physicsWorld)
        self.fixedRunner = FixedStepRunner(
            preFixed: [spinSystem, physicsIntentSystem, jumpSystem, physicsSyncSystem, physicsBeginStepSystem],
            fixed: [physicsBroadphaseSystem,
                    physicsNarrowphaseSystem,
                    physicsSolverSystem,
                    gravitySystem,
                    kinematicMoveSystem,
                    physicsIntegrateSystem],
            postFixed: [physicsWritebackSystem, physicsEventsSystem]
        )
    }

    public func build(context: SceneContext) {
        let device = context.device

        // Camera initial state
        camera.position = SIMD3<Float>(0, 0, 8)
        camera.target = SIMD3<Float>(0, 0, 0)
        camera.updateView()

        let groundY: Float = -3.0

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
            t.translation = SIMD3<Float>(0, groundY, 0)
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
            let groundContactY = groundY + playerRadius + playerHalfHeight
            t.translation = SIMD3<Float>(0, groundContactY + 8.0, 0)
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
            world.add(e, CharacterControllerComponent(radius: playerRadius,
                                                      halfHeight: playerHalfHeight,
                                                      skinWidth: 0.3,
                                                      groundSnapSkin: 0.05))
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

        // --- Test Dome: curved top for sliding
        do {
            let meshData = ProceduralMeshes.dome(radius: 4.0,
                                                 radialSegments: 32,
                                                 ringSegments: 12)
            let mesh = GPUMesh(device: device, data: meshData, label: "TestDome")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 120, g: 200, b: 140, a: 255),
                                      label: "DomeTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.5)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(-10, groundY, -6)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 4, 4))))
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
        if let query = collisionQuery {
            kinematicMoveSystem.setQuery(query)
        }

        // New resources were created -> bump revision once
        revision &+= 1
    }

    public func update(dt: Float) {
        // ECS simulation step
        timeSystem.update(world: world, dt: dt)
        inputSystem.update(world: world, dt: dt)
        fixedRunner.update(world: world)

        camera.updateView()

        // Render extraction (derived every frame)
        renderItems = extractSystem.extract(world: world)
    }
}
