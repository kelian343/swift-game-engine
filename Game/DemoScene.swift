//
//  DemoScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import simd

public final class DemoScene: RenderScene {

    public let camera = Camera()

    public private(set) var renderItems: [RenderItem] = []
    public private(set) var overlayItems: [RenderItem] = []
    public private(set) var revision: UInt64 = 0
    public var toneMappingExposure: Float = 1.0
    public var toneMappingEnabled: Bool = false
    public var directionalLights: [DirectionalLight] = []
    public var rtResolutionScale: Float = 1.0
    private var fpsOverlaySystem: FPSOverlaySystem?

    // ECS
    private let world = World()
    private let timeSystem = TimeSystem()
    private let inputSystem: InputSystem
    private let spinSystem = SpinSystem()
    private let physicsBeginStepSystem = PhysicsBeginStepSystem()
    private let physicsIntentSystem = PhysicsIntentSystem()
    private let oscillateMoveSystem = OscillateMoveSystem()
    private let jumpSystem = JumpSystem()
    private let gravitySystem = GravitySystem()
    private let proceduralPoseSystem = ProceduralPoseSystem()
    private let platformMotionSystem = KinematicPlatformMotionSystem()
    private let kinematicMoveSystem = KinematicMoveStopSystem()
    private let agentSeparationSystem = AgentSeparationSystem()
    private let sceneServices = SceneServices()
    private let collisionQueryRefreshSystem: CollisionQueryRefreshSystem
    private let physicsIntegrateSystem = PhysicsIntegrateSystem()
    private let physicsWritebackSystem = PhysicsWritebackSystem()
    private let fixedRunner: FixedStepRunner
    private let extractSystem = RenderExtractSystem()

    public init() {
        self.inputSystem = InputSystem(camera: camera)
        self.collisionQueryRefreshSystem = CollisionQueryRefreshSystem(kinematicMoveSystem: kinematicMoveSystem,
                                                                       agentSeparationSystem: agentSeparationSystem,
                                                                       services: sceneServices)
        self.fixedRunner = FixedStepRunner(
            preFixed: [spinSystem, oscillateMoveSystem, physicsIntentSystem, jumpSystem, physicsBeginStepSystem],
            fixed: [platformMotionSystem,
                    collisionQueryRefreshSystem,
                    gravitySystem,
                    kinematicMoveSystem,
                    agentSeparationSystem,
                    physicsIntegrateSystem,
                    proceduralPoseSystem],
            postFixed: [physicsWritebackSystem]
        )
    }

    public func build(context: SceneContext) {
        let device = context.device

        func makeSolidMaterial(label: String,
                               color: SIMD4<UInt8>,
                               metallic: Float,
                               roughness: Float,
                               alpha: Float = 1.0) -> Material {
            let base = ProceduralTextureGenerator.solid(width: 4, height: 4, color: color)
            let mr = ProceduralTextureGenerator.metallicRoughness(width: 4,
                                                                  height: 4,
                                                                  metallic: metallic,
                                                                  roughness: roughness)
            let desc = MaterialDescriptor(baseColor: base,
                                          metallicRoughness: mr,
                                          metallicFactor: 1.0,
                                          roughnessFactor: 1.0,
                                          alpha: alpha)
            return MaterialFactory.make(device: device, descriptor: desc, label: label)
        }

        func makeBaseColorMaterial(label: String,
                                   baseColor: ProceduralTexture,
                                   metallic: Float,
                                   roughness: Float,
                                   alpha: Float = 1.0) -> Material {
            let mr = ProceduralTextureGenerator.metallicRoughness(width: 4,
                                                                  height: 4,
                                                                  metallic: metallic,
                                                                  roughness: roughness)
            let desc = MaterialDescriptor(baseColor: baseColor,
                                          metallicRoughness: mr,
                                          metallicFactor: 1.0,
                                          roughnessFactor: 1.0,
                                          alpha: alpha)
            return MaterialFactory.make(device: device, descriptor: desc, label: label)
        }


        // Camera initial state
        camera.position = SIMD3<Float>(0, 0, 8)
        camera.target = SIMD3<Float>(0, 0, 0)
        camera.updateView()

        let groundY: Float = -3.0
        directionalLights = [
            DirectionalLight(direction: SIMD3<Float>(0.6, -0.7, -0.1),
                             intensity: 2.0,
                             color: SIMD3<Float>(1.0, 0.86, 0.68),
                             enabled: true,
                             maxDistance: 450.0),
            DirectionalLight(direction: SIMD3<Float>(-0.3, -0.6, 0.6),
                             intensity: 0.4,
                             color: SIMD3<Float>(0.95, 0.85, 0.75),
                             enabled: true,
                             maxDistance: 300.0)
        ]

        // --- Ground: platform plane (4x area)
        do {
            let meshDesc = ProceduralMeshes.plane(PlaneParams(size: 80.0))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "Ground")
            let mat = makeSolidMaterial(label: "GroundMat",
                                        color: SIMD4<UInt8>(80, 80, 80, 255),
                                        metallic: 0.0,
                                        roughness: 0.8)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, groundY, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshDesc,
                                             material: SurfaceMaterial(muS: 0.9, muK: 0.8)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(40, 0.1, 40))))
        }

        // --- Kinematic Platforms: elevator + ground mover
        do {
            let meshDesc = ProceduralMeshes.box(BoxParams(size: 4.0))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "Platform")
            let matUp = makeSolidMaterial(label: "PlatformUpMat",
                                          color: SIMD4<UInt8>(120, 200, 255, 255),
                                          metallic: 0.0,
                                          roughness: 0.6)
            let matFlat = makeSolidMaterial(label: "PlatformFlatMat",
                                            color: SIMD4<UInt8>(160, 255, 140, 255),
                                            metallic: 0.0,
                                            roughness: 0.6)
            let platformScale = SIMD3<Float>(1.5, 0.2, 1.5)
            let platformHalfExtents = SIMD3<Float>(3.0, 0.4, 3.0)

            // Elevator (vertical loop)
            do {
                let e = world.createEntity()
                var t = TransformComponent()
                t.translation = SIMD3<Float>(16, -1.0, 0)
                t.scale = platformScale
                world.add(e, t)
                world.add(e, RenderComponent(mesh: mesh, material: matUp))
                world.add(e, StaticMeshComponent(mesh: meshDesc,
                                                 material: SurfaceMaterial(muS: 0.9, muK: 0.7)))
                world.add(e, PhysicsBodyComponent(bodyType: .kinematic,
                                                  position: t.translation,
                                                  rotation: t.rotation))
                world.add(e, ColliderComponent(shape: .box(halfExtents: platformHalfExtents)))
                world.add(e, KinematicPlatformComponent(origin: t.translation,
                                                        axis: SIMD3<Float>(0, 1, 0),
                                                        amplitude: 2.0,
                                                        speed: 1.1,
                                                        phase: 0))
            }

            // Ground mover (horizontal loop)
            do {
                let e = world.createEntity()
                var t = TransformComponent()
                t.translation = SIMD3<Float>(-16, -2.0, 12)
                t.scale = platformScale
                world.add(e, t)
                world.add(e, RenderComponent(mesh: mesh, material: matFlat))
                world.add(e, StaticMeshComponent(mesh: meshDesc,
                                                 material: SurfaceMaterial(muS: 0.9, muK: 0.7)))
                world.add(e, PhysicsBodyComponent(bodyType: .kinematic,
                                                  position: t.translation,
                                                  rotation: t.rotation))
                world.add(e, ColliderComponent(shape: .box(halfExtents: platformHalfExtents)))
                world.add(e, KinematicPlatformComponent(origin: t.translation,
                                                        axis: SIMD3<Float>(1, 0, 0),
                                                        amplitude: 4.0,
                                                        speed: 0.9,
                                                        phase: 0.7))
            }
        }

        // --- NPC: ground-level horizontal mover (dynamic)
        do {
            let capsuleRadius: Float = 1.5
            let capsuleHalfHeight: Float = 1.0
            let meshDesc = ProceduralMeshes.capsule(CapsuleParams(radius: capsuleRadius,
                                                                  halfHeight: capsuleHalfHeight))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "KinematicCapsule")
            let mat = makeSolidMaterial(label: "KinematicCapsuleMat",
                                        color: SIMD4<UInt8>(220, 120, 255, 255),
                                        metallic: 0.0,
                                        roughness: 0.5,
                                        alpha: 0.2)

            let e = world.createEntity()
            var t = TransformComponent()
            let groundContactY = groundY + capsuleRadius + capsuleHalfHeight
            t.translation = SIMD3<Float>(24.0, groundContactY + 2.0, 16.0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, PhysicsBodyComponent(bodyType: .dynamic,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .capsule(halfHeight: capsuleHalfHeight,
                                                          radius: capsuleRadius)))
            world.add(e, MoveIntentComponent())
            world.add(e, MovementComponent(maxAcceleration: 10.0, maxDeceleration: 12.0))
            world.add(e, CharacterControllerComponent(radius: capsuleRadius,
                                                      halfHeight: capsuleHalfHeight,
                                                      skinWidth: 0.3,
                                                      groundSnapSkin: 0.05))
            world.add(e, AgentCollisionComponent(massWeight: 500.0))
            world.add(e, OscillateMoveComponent(origin: t.translation,
                                                axis: SIMD3<Float>(1, 0, 0),
                                                amplitude: 6.0,
                                                speed: 0.6))
        }

        // --- Player: capsule + coarse checkerboard
        do {
            let playerRadius: Float = 1.5
            let playerHalfHeight: Float = 1.0
            let skinnedDesc = ProceduralMeshes.humanoidSkinned(HumanoidSkinnedParams(legHeight: 1.8,
                                                                                    legRadius: 0.35,
                                                                                    torsoHeight: 2.0,
                                                                                    torsoRadius: 0.55,
                                                                                    hipSeparation: 0.45,
                                                                                    radialSegments: 12,
                                                                                    heightSegments: 4))
            let baseColor = ProceduralTextureGenerator.checkerboard(width: 256, height: 256, cell: 48)
            let mat = makeBaseColorMaterial(label: "PlayerMat",
                                            baseColor: baseColor,
                                            metallic: 0.0,
                                            roughness: 0.4,
                                            alpha: 1.0)
            let capsuleMeshDesc = ProceduralMeshes.capsule(CapsuleParams(radius: playerRadius,
                                                                         halfHeight: playerHalfHeight))
            let capsuleMesh = GPUMesh(device: device, descriptor: capsuleMeshDesc, label: "PlayerCapsuleOverlay")
            let capsuleMat = makeSolidMaterial(label: "PlayerCapsuleOverlayMat",
                                               color: SIMD4<UInt8>(120, 160, 255, 255),
                                               metallic: 0.0,
                                               roughness: 0.4,
                                               alpha: 0.2)

            let e = world.createEntity()
            var t = TransformComponent()
            let groundContactY = groundY + playerRadius + playerHalfHeight
            t.translation = SIMD3<Float>(0, groundContactY + 8.0, 0)
            world.add(e, t)
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
            world.add(e, AgentCollisionComponent(massWeight: 3.0))

            let skeleton = Skeleton.humanoid8()
            world.add(e, SkeletonComponent(skeleton: skeleton))
            world.add(e, PoseComponent(boneCount: skeleton.boneCount, local: skeleton.bindLocal))
            world.add(e, SkinnedMeshComponent(mesh: skinnedDesc, material: mat))

            let overlay = world.createEntity()
            var to = TransformComponent()
            to.translation = t.translation
            world.add(overlay, to)
            world.add(overlay, RenderComponent(mesh: capsuleMesh, material: capsuleMat))
            world.add(overlay, FollowTargetComponent(target: e))
        }

        // --- NPCs: kinematic agents for separation testing
        do {
            let npcRadius: Float = 1.5
            let npcHalfHeight: Float = 1.0
            let meshDesc = ProceduralMeshes.capsule(CapsuleParams(radius: npcRadius,
                                                                  halfHeight: npcHalfHeight))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "NPCCapsule")
            let mat = makeSolidMaterial(label: "NPCMat",
                                        color: SIMD4<UInt8>(255, 180, 80, 255),
                                        metallic: 0.0,
                                        roughness: 0.5,
                                        alpha: 0.2)

            let positions: [SIMD3<Float>] = [
                SIMD3<Float>(-16.0, 0.9, 12.0),
                SIMD3<Float>(8.0, 3.5, -2.5),
                SIMD3<Float>(0.0, 5.5, -10.0)
            ]

            for pos in positions {
                let e = world.createEntity()
                var t = TransformComponent()
                t.translation = pos
                world.add(e, t)
                world.add(e, RenderComponent(mesh: mesh, material: mat))
                world.add(e, PhysicsBodyComponent(bodyType: .dynamic,
                                                  position: t.translation,
                                                  rotation: t.rotation))
                world.add(e, ColliderComponent(shape: .capsule(halfHeight: npcHalfHeight,
                                                              radius: npcRadius)))
                world.add(e, CharacterControllerComponent(radius: npcRadius,
                                                          halfHeight: npcHalfHeight,
                                                          skinWidth: 0.3,
                                                          groundSnapSkin: 0.05))
                world.add(e, AgentCollisionComponent(massWeight: 1.0))
            }
        }

        // --- Test Wall: large static blocker
        do {
            let meshDesc = ProceduralMeshes.box(BoxParams(size: 6.0))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "TestWall")
            let mat = makeSolidMaterial(label: "WallMat",
                                        color: SIMD4<UInt8>(255, 80, 80, 255),
                                        metallic: 0.0,
                                        roughness: 0.02)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(0, 0, -10)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshDesc))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(3, 3, 3))))
        }

        // --- Test Ramp: sloped obstacle
        do {
            let rampHeight: Float = 4.0
            let meshDesc = ProceduralMeshes.ramp(RampParams(width: 8.0,
                                                            depth: 10.0,
                                                            height: rampHeight))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "TestRamp")
            let mat = Material(baseColorFactor: SIMD3<Float>(80.0 / 255.0,
                                                             160.0 / 255.0,
                                                             255.0 / 255.0),
                               metallicFactor: 0.0,
                               roughnessFactor: 0.6,
                               alpha: 1.0)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(8, groundY + rampHeight * 0.5, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshDesc,
                                             material: SurfaceMaterial(muS: 0.35, muK: 0.25)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 2, 4))))
        }

        // --- Test Dome: curved top for sliding
        do {
            let meshDesc = ProceduralMeshes.dome(DomeParams(radius: 4.0,
                                                           radialSegments: 32,
                                                           ringSegments: 12))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "TestDome")
            let mat = makeSolidMaterial(label: "DomeMat",
                                        color: SIMD4<UInt8>(120, 200, 140, 255),
                                        metallic: 0.0,
                                        roughness: 0.5)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(-10, groundY, -6)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshDesc,
                                             material: SurfaceMaterial(muS: 0.3, muK: 0.2)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 4, 4))))
        }


        // --- Test Step: small ledge
        do {
            let meshDesc = ProceduralMeshes.box(BoxParams(size: 2.0))
            let mesh = GPUMesh(device: device, descriptor: meshDesc, label: "TestStep")
            let base = ProceduralTextureGenerator.solid(width: 4,
                                                        height: 4,
                                                        color: SIMD4<UInt8>(255, 220, 120, 255))
            let mr = ProceduralTextureGenerator.metallicRoughness(width: 4,
                                                                  height: 4,
                                                                  metallic: 0.0,
                                                                  roughness: 0.8)
            let emissive = ProceduralTextureGenerator.emissive(width: 4,
                                                               height: 4,
                                                               color: SIMD3<Float>(1.0, 0.7, 0.2))
            let desc = MaterialDescriptor(baseColor: base,
                                          metallicRoughness: mr,
                                          emissive: emissive,
                                          metallicFactor: 1.0,
                                          roughnessFactor: 1.0,
                                          emissiveFactor: SIMD3<Float>(2.5, 2.0, 1.2),
                                          alpha: 1.0)
            let mat = MaterialFactory.make(device: device, descriptor: desc, label: "StepMat")

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(-6, -2, 4)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshDesc))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(1, 1, 1))))
        }

        // --- FPS overlay resources
        fpsOverlaySystem = FPSOverlaySystem(device: device)

        // Extract initial draw calls
        renderItems = extractSystem.extract(world: world)
        sceneServices.rebuildAll(world: world)

        // New resources were created -> bump revision once
        revision &+= 1
    }

    public func update(dt: Float) {
        // ECS simulation step
        timeSystem.update(world: world, dt: dt)
        inputSystem.update(world: world, dt: dt)
        if inputSystem.exposureDelta != 0 {
            toneMappingExposure = min(max(toneMappingExposure + inputSystem.exposureDelta * dt, 0.1), 2.0)
        }
        fixedRunner.update(world: world)

        camera.updateView()

        // Render extraction (derived every frame)
        renderItems = extractSystem.extract(world: world)
        overlayItems = fpsOverlaySystem?.update(dt: dt) ?? []
    }

    public func viewportDidChange(size: SIMD2<Float>) {
        fpsOverlaySystem?.viewportDidChange(size: size)
    }
}
