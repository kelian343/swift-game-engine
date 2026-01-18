//
//  CharacterFactory.swift
//  Game
//
//  Created by Codex on 3/8/26.
//

import Metal
import simd

enum CharacterFactory {
    static func makePlayer(world: World,
                           device: MTLDevice,
                           inputSystem: InputSystem,
                           groundY: Float) -> Entity {
        let playerRadius: Float = 1.5
        let playerHalfHeight: Float = 1.0
        guard let skeleton = SkeletonLoader.loadSkeleton(named: "YBot.skeleton") else {
            fatalError("Failed to load YBot.skeleton.json from bundle.")
        }
        let enableMotionProfile = true
        let walkPath = Bundle.main.path(forResource: "Walking.motionProfile", ofType: "json")
        let idlePath = Bundle.main.path(forResource: "Idle.motionProfile", ofType: "json")
        let runPath = Bundle.main.path(forResource: "Running.motionProfile", ofType: "json")
        let fallPath = Bundle.main.path(forResource: "FallingIdle.motionProfile", ofType: "json")
        let dodgeBackwardPath = Bundle.main.path(forResource: "StandingDodgeBackward.motionProfile", ofType: "json")
        let walkProfile = walkPath.flatMap { MotionProfileLoader.load(path: $0) }
        let idleProfile = idlePath.flatMap { MotionProfileLoader.load(path: $0) }
        let runProfile = runPath.flatMap { MotionProfileLoader.load(path: $0) }
        let fallProfile = fallPath.flatMap { MotionProfileLoader.load(path: $0) }
        let dodgeBackwardProfile = dodgeBackwardPath.flatMap { MotionProfileLoader.load(path: $0) }
        if walkProfile == nil && enableMotionProfile {
            print("Failed to load motion profile at:", walkPath ?? "missing bundle resource")
        }
        if idleProfile == nil && enableMotionProfile {
            print("Failed to load motion profile at:", idlePath ?? "missing bundle resource")
        }
        if runProfile == nil && enableMotionProfile {
            print("Failed to load motion profile at:", runPath ?? "missing bundle resource")
        }
        if fallProfile == nil && enableMotionProfile {
            print("Failed to load motion profile at:", fallPath ?? "missing bundle resource")
        }
        if dodgeBackwardProfile == nil && enableMotionProfile {
            print("Failed to load motion profile at:", dodgeBackwardPath ?? "missing bundle resource")
        }
        guard let skinnedAsset = SkinnedMeshLoader.loadSkinnedMeshAsset(named: "YBot.skinned",
                                                                        skeleton: skeleton) else {
            fatalError("Failed to load YBot.skinned.json from bundle.")
        }
        let materialTable = MaterialLoader.loadMaterials(named: "YBot.materials", device: device)
        let submeshMaterials = skinnedAsset.materialNames.map { name in
            materialTable[name] ?? Material()
        }
        let capsuleMeshDesc = ProceduralMeshes.capsule(CapsuleParams(radius: playerRadius,
                                                                     halfHeight: playerHalfHeight))
        let capsuleMesh = GPUMesh(device: device, descriptor: capsuleMeshDesc, label: "PlayerCapsuleOverlay")
        let overlayBase = ProceduralTextureGenerator.solid(width: 4,
                                                           height: 4,
                                                           color: SIMD4<UInt8>(120, 160, 255, 255),
                                                           format: .rgba8UnormSrgb)
        let overlayMR = ProceduralTextureGenerator.metallicRoughness(width: 4,
                                                                     height: 4,
                                                                     metallic: 0.0,
                                                                     roughness: 0.4)
        let overlayDesc = MaterialDescriptor(baseColor: overlayBase,
                                             metallicRoughness: overlayMR,
                                             metallicFactor: 1.0,
                                             roughnessFactor: 1.0,
                                             alpha: 0.2)
        let capsuleMat = MaterialFactory.make(device: device,
                                              descriptor: overlayDesc,
                                              label: "PlayerCapsuleOverlayMat")

        let e = world.createEntity()
        var t = TransformComponent()
        let groundContactY = groundY + playerRadius + playerHalfHeight
        t.translation = SIMD3<Float>(0, groundContactY + 8.0, 0)
        world.add(e, t)
        world.add(e, WorldPositionComponent(translation: t.translation))
        world.add(e, PlayerTagComponent())
        inputSystem.setPlayer(e)
        world.add(e, PhysicsBodyComponent(bodyType: .dynamic,
                                          position: t.translation,
                                          rotation: t.rotation))
        world.add(e, MoveIntentComponent())
        world.add(e, MovementComponent(maxAcceleration: 20.0, maxDeceleration: 36.0))
        world.add(e, CharacterControllerComponent(radius: playerRadius,
                                                  halfHeight: playerHalfHeight,
                                                  skinWidth: 0.3,
                                                  groundSnapSkin: 0.05))
        world.add(e, AgentCollisionComponent(massWeight: 3.0))

        world.add(e, SkeletonComponent(skeleton: skeleton))
        world.add(e, PoseComponent(boneCount: skeleton.boneCount, local: skeleton.bindLocal))
        if enableMotionProfile, let walkProfile, let idleProfile, let runProfile, let fallProfile {
            world.add(e, MotionProfileComponent(profile: idleProfile, playbackRate: 1.0, loop: true, inPlace: true))
            world.add(e, LocomotionProfileComponent(idleProfile: idleProfile,
                                                    walkProfile: walkProfile,
                                                    runProfile: runProfile,
                                                    fallProfile: fallProfile,
                                                    idleEnterSpeed: 0.15,
                                                    idleExitSpeed: 0.3,
                                                    runEnterSpeed: 6.0,
                                                    runExitSpeed: 5.0,
                                                    fallMinDropHeight: 50.0,
                                                    state: .idle))
        }
        if enableMotionProfile, let dodgeBackwardProfile {
            let fps = max(dodgeBackwardProfile.sample_fps, 1)
            let startTime: Float = 0
            let endTime = Float(34) / Float(fps)
            world.add(e, ActionAnimationComponent(profile: dodgeBackwardProfile,
                                                  playbackRate: 1.0,
                                                  loop: false,
                                                  inPlace: true,
                                                  blendInTime: 0.08,
                                                  blendOutHalfLife: 0.18))
            world.add(e, DodgeActionComponent(duration: endTime,
                                              distance: 8.0,
                                              startTime: startTime,
                                              endTime: endTime))
        }
        world.add(e, SkinnedMeshGroupComponent(meshes: skinnedAsset.meshes,
                                               materials: submeshMaterials))

        let overlay = world.createEntity()
        var to = TransformComponent()
        to.translation = t.translation
        world.add(overlay, to)
        world.add(overlay, RenderComponent(mesh: capsuleMesh, material: capsuleMat))
        world.add(overlay, FollowTargetComponent(target: e))

        return e
    }
}
