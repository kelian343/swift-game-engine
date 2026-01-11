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

        // Camera initial state
        camera.position = SIMD3<Float>(0, 0, 8)
        camera.target = SIMD3<Float>(0, 0, 0)
        camera.updateView()

        let groundY: Float = -3.0

        // --- Ground: platform plane (4x area)
        do {
            let meshDesc = ProceduralMeshes.plane(size: 80.0)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
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
            world.add(e, StaticMeshComponent(mesh: meshData,
                                             material: SurfaceMaterial(muS: 0.9, muK: 0.8)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(40, 0.1, 40))))
        }

        // --- Kinematic Platforms: elevator + ground mover
        do {
            let meshDesc = ProceduralMeshes.box(size: 4.0)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
            let mesh = GPUMesh(device: device, data: meshData, label: "Platform")
            let texUp = TextureResource(device: device,
                                        source: .solid(width: 4, height: 4, r: 120, g: 200, b: 255, a: 255),
                                        label: "PlatformUpTex")
            let texFlat = TextureResource(device: device,
                                          source: .solid(width: 4, height: 4, r: 160, g: 255, b: 140, a: 255),
                                          label: "PlatformFlatTex")
            let matUp = Material(baseColorTexture: texUp, metallic: 0.0, roughness: 0.6)
            let matFlat = Material(baseColorTexture: texFlat, metallic: 0.0, roughness: 0.6)
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
                world.add(e, StaticMeshComponent(mesh: meshData,
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
                world.add(e, StaticMeshComponent(mesh: meshData,
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
            let meshDesc = ProceduralMeshes.capsule(radius: capsuleRadius,
                                                    halfHeight: capsuleHalfHeight)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
            let mesh = GPUMesh(device: device, data: meshData, label: "KinematicCapsule")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 220, g: 120, b: 255, a: 255),
                                      label: "KinematicCapsuleTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.5, alpha: 0.2)

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
            let skinnedDesc = ProceduralMeshes.humanoidSkinned(legHeight: 1.8,
                                                              legRadius: 0.35,
                                                              torsoHeight: 2.0,
                                                              torsoRadius: 0.55,
                                                              hipSeparation: 0.45,
                                                              radialSegments: 12,
                                                              heightSegments: 4)
            let skinnedData = ProceduralMeshBridge.toSkinnedMeshData(skinnedDesc)
                ?? SkinnedMeshData(vertices: [], indices16: [])
            let tex = TextureResource(device: device,
                                      source: ProceduralTextures.checkerboard(width: 256, height: 256, cell: 48),
                                      label: "TexB")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.4, alpha: 1.0)
            let capsuleMeshDesc = ProceduralMeshes.capsule(radius: playerRadius,
                                                           halfHeight: playerHalfHeight)
            let capsuleMeshData = ProceduralMeshBridge.toMeshDataPNUT(capsuleMeshDesc)
                ?? MeshData(vertices: [], indices16: [])
            let capsuleMesh = GPUMesh(device: device, data: capsuleMeshData, label: "PlayerCapsuleOverlay")
            let capsuleTex = TextureResource(device: device,
                                             source: .solid(width: 4, height: 4, r: 120, g: 160, b: 255, a: 255),
                                             label: "PlayerCapsuleOverlayTex")
            let capsuleMat = Material(baseColorTexture: capsuleTex, metallic: 0.0, roughness: 0.4, alpha: 0.2)

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
            world.add(e, SkinnedMeshComponent(mesh: skinnedData, material: mat))

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
            let meshDesc = ProceduralMeshes.capsule(radius: npcRadius,
                                                    halfHeight: npcHalfHeight)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
            let mesh = GPUMesh(device: device, data: meshData, label: "NPCCapsule")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 255, g: 180, b: 80, a: 255),
                                      label: "NPCTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.5, alpha: 0.2)

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
            let meshDesc = ProceduralMeshes.box(size: 6.0)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
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
            let rampHeight: Float = 4.0
            let meshDesc = ProceduralMeshes.ramp(width: 8.0, depth: 10.0, height: rampHeight)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
            let mesh = GPUMesh(device: device, data: meshData, label: "TestRamp")
            let tex = TextureResource(device: device,
                                      source: .solid(width: 4, height: 4, r: 80, g: 160, b: 255, a: 255),
                                      label: "RampTex")
            let mat = Material(baseColorTexture: tex, metallic: 0.0, roughness: 0.6)

            let e = world.createEntity()
            var t = TransformComponent()
            t.translation = SIMD3<Float>(8, groundY + rampHeight * 0.5, 0)
            world.add(e, t)
            world.add(e, RenderComponent(mesh: mesh, material: mat))
            world.add(e, StaticMeshComponent(mesh: meshData,
                                             material: SurfaceMaterial(muS: 0.35, muK: 0.25)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 2, 4))))
        }

        // --- Test Dome: curved top for sliding
        do {
            let meshDesc = ProceduralMeshes.dome(radius: 4.0,
                                                 radialSegments: 32,
                                                 ringSegments: 12)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
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
            world.add(e, StaticMeshComponent(mesh: meshData,
                                             material: SurfaceMaterial(muS: 0.3, muK: 0.2)))
            world.add(e, PhysicsBodyComponent(bodyType: .static,
                                              position: t.translation,
                                              rotation: t.rotation))
            world.add(e, ColliderComponent(shape: .box(halfExtents: SIMD3<Float>(4, 4, 4))))
        }

        // --- Test Step: small ledge
        do {
            let meshDesc = ProceduralMeshes.box(size: 2.0)
            let meshData = ProceduralMeshBridge.toMeshDataPNUT(meshDesc) ?? MeshData(vertices: [], indices16: [])
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
