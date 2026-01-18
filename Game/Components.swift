//
//  Components.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

// MARK: - Transform (TRS)

public struct TransformComponent {
    public var translation: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>

    public init(translation: SIMD3<Float> = .zero,
                rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0,1,0)),
                scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    /// Derived model matrix from TRS (no drift, no repeated multiplication accumulation)
    public var modelMatrix: matrix_float4x4 {
        let t = matrix_float4x4(columns: (
            SIMD4<Float>(1,0,0,0),
            SIMD4<Float>(0,1,0,0),
            SIMD4<Float>(0,0,1,0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))

        let r = matrix_float4x4(rotation)

        let s = matrix_float4x4(columns: (
            SIMD4<Float>(scale.x,0,0,0),
            SIMD4<Float>(0,scale.y,0,0),
            SIMD4<Float>(0,0,scale.z,0),
            SIMD4<Float>(0,0,0,1)
        ))

        return simd_mul(t, simd_mul(r, s))
    }
}

public enum CollisionLayer {
    public static let all: UInt32 = 0xFFFF_FFFF
    public static let defaultLayer: UInt32 = 1 << 0
}

// MARK: - World Position (Chunk + Local)

public enum WorldPosition {
    public static let chunkSize: Double = 512.0
    public static let halfChunkSize: Double = chunkSize * 0.5

    public static func fromWorld(_ world: SIMD3<Double>) -> (SIMD3<Int64>, SIMD3<Double>) {
        func axis(_ value: Double) -> (Int64, Double) {
            let shift = Int64(floor((value + halfChunkSize) / chunkSize))
            let local = value - Double(shift) * chunkSize
            return (shift, local)
        }

        let (cx, lx) = axis(world.x)
        let (cy, ly) = axis(world.y)
        let (cz, lz) = axis(world.z)
        return (SIMD3<Int64>(cx, cy, cz), SIMD3<Double>(lx, ly, lz))
    }

    public static func canonicalize(chunk: inout SIMD3<Int64>, local: inout SIMD3<Double>) {
        func normalizeAxis(_ value: Double) -> (Int64, Double) {
            let shift = Int64(floor((value + halfChunkSize) / chunkSize))
            let local = value - Double(shift) * chunkSize
            return (shift, local)
        }

        let (dx, lx) = normalizeAxis(local.x)
        let (dy, ly) = normalizeAxis(local.y)
        let (dz, lz) = normalizeAxis(local.z)

        chunk.x += dx
        chunk.y += dy
        chunk.z += dz
        local = SIMD3<Double>(lx, ly, lz)
    }

    public static func toWorld(chunk: SIMD3<Int64>, local: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            Double(chunk.x) * chunkSize + local.x,
            Double(chunk.y) * chunkSize + local.y,
            Double(chunk.z) * chunkSize + local.z
        )
    }

    public static func relativePosition(chunk: SIMD3<Int64>,
                                        local: SIMD3<Double>,
                                        cameraChunk: SIMD3<Int64>,
                                        cameraLocal: SIMD3<Double>) -> SIMD3<Float> {
        let dx = Double(chunk.x - cameraChunk.x) * chunkSize + (local.x - cameraLocal.x)
        let dy = Double(chunk.y - cameraChunk.y) * chunkSize + (local.y - cameraLocal.y)
        let dz = Double(chunk.z - cameraChunk.z) * chunkSize + (local.z - cameraLocal.z)
        return SIMD3<Float>(Float(dx), Float(dy), Float(dz))
    }
}

public struct WorldPositionComponent {
    public var chunk: SIMD3<Int64>
    public var local: SIMD3<Double>
    public var prevChunk: SIMD3<Int64>
    public var prevLocal: SIMD3<Double>

    public init(chunk: SIMD3<Int64> = SIMD3<Int64>(0, 0, 0),
                local: SIMD3<Double> = SIMD3<Double>(0, 0, 0)) {
        self.chunk = chunk
        self.local = local
        self.prevChunk = chunk
        self.prevLocal = local
    }

    public init(world: SIMD3<Double>) {
        let (chunk, local) = WorldPosition.fromWorld(world)
        self.chunk = chunk
        self.local = local
        self.prevChunk = chunk
        self.prevLocal = local
    }

    public init(translation: SIMD3<Float>) {
        let world = SIMD3<Double>(Double(translation.x),
                                  Double(translation.y),
                                  Double(translation.z))
        self.init(world: world)
    }
}

// MARK: - Active Chunk Set

public struct ActiveChunkComponent {
    public var centerChunk: SIMD3<Int64>
    public var originChunk: SIMD3<Int64>
    public var originLocal: SIMD3<Double>
    public var radiusChunks: Int
    public var activeEntityIDs: Set<UInt32>
    public var activeStaticEntityIDs: Set<UInt32>

    public init(centerChunk: SIMD3<Int64> = SIMD3<Int64>(0, 0, 0),
                originChunk: SIMD3<Int64> = SIMD3<Int64>(0, 0, 0),
                originLocal: SIMD3<Double> = SIMD3<Double>(0, 0, 0),
                radiusChunks: Int = 2,
                activeEntityIDs: Set<UInt32> = [],
                activeStaticEntityIDs: Set<UInt32> = []) {
        self.centerChunk = centerChunk
        self.originChunk = originChunk
        self.originLocal = originLocal
        self.radiusChunks = radiusChunks
        self.activeEntityIDs = activeEntityIDs
        self.activeStaticEntityIDs = activeStaticEntityIDs
    }
}

public struct PlayerTagComponent {
    public init() {}
}

// MARK: - Render

public struct RenderComponent {
    public var mesh: GPUMesh
    public var material: Material

    public init(mesh: GPUMesh, material: Material) {
        self.mesh = mesh
        self.material = material
    }
}

// MARK: - Skeleton / Pose (skinning)

public struct SkeletonComponent {
    public var skeleton: Skeleton

    public init(skeleton: Skeleton) {
        self.skeleton = skeleton
    }
}

public struct PoseComponent {
    public var local: [matrix_float4x4]
    public var model: [matrix_float4x4]
    public var palette: [matrix_float4x4]
    public var phase: Float

    public init(boneCount: Int, local: [matrix_float4x4]? = nil) {
        let base = local ?? Array(repeating: matrix_identity_float4x4, count: boneCount)
        self.local = base
        self.model = base
        self.palette = base
        self.phase = 0
    }
}

public struct MotionProfileComponent {
    public var profile: MotionProfile
    public var time: Float
    public var playbackRate: Float
    public var loop: Bool
    public var inPlace: Bool

    public init(profile: MotionProfile,
                time: Float = 0,
                playbackRate: Float = 1,
                loop: Bool = true,
                inPlace: Bool = true) {
        self.profile = profile
        self.time = time
        self.playbackRate = playbackRate
        self.loop = loop
        self.inPlace = inPlace
    }
}

public enum LocomotionState: Int {
    case idle
    case walk
    case run
    case falling
}

public struct LocomotionProfileComponent {
    public var idleProfile: MotionProfile
    public var walkProfile: MotionProfile
    public var runProfile: MotionProfile
    public var fallProfile: MotionProfile
    public var idleEnterSpeed: Float
    public var idleExitSpeed: Float
    public var idleTime: Float
    public var walkTime: Float
    public var runTime: Float
    public var fallTime: Float
    public var runEnterSpeed: Float
    public var runExitSpeed: Float
    public var fallMinDropHeight: Float
    public var blendTime: Float
    public var blendT: Float
    public var idleInertiaHalfLife: Float
    public var idleInertia: Float
    public var fromState: LocomotionState
    public var state: LocomotionState
    public var isBlending: Bool

    public init(idleProfile: MotionProfile,
                walkProfile: MotionProfile,
                runProfile: MotionProfile,
                fallProfile: MotionProfile,
                idleEnterSpeed: Float = 0.15,
                idleExitSpeed: Float = 0.25,
                idleTime: Float = 0,
                walkTime: Float = 0,
                runTime: Float = 0,
                fallTime: Float = 0,
                runEnterSpeed: Float = 6.0,
                runExitSpeed: Float = 5.0,
                fallMinDropHeight: Float = 10.0,
                blendTime: Float = 0.2,
                blendT: Float = 1.0,
                idleInertiaHalfLife: Float = 0.18,
                idleInertia: Float = 0,
                fromState: LocomotionState = .idle,
                state: LocomotionState = .idle,
                isBlending: Bool = false) {
        self.idleProfile = idleProfile
        self.walkProfile = walkProfile
        self.runProfile = runProfile
        self.fallProfile = fallProfile
        self.idleEnterSpeed = idleEnterSpeed
        self.idleExitSpeed = idleExitSpeed
        self.idleTime = idleTime
        self.walkTime = walkTime
        self.runTime = runTime
        self.fallTime = fallTime
        self.runEnterSpeed = runEnterSpeed
        self.runExitSpeed = runExitSpeed
        self.fallMinDropHeight = fallMinDropHeight
        self.blendTime = blendTime
        self.blendT = blendT
        self.idleInertiaHalfLife = idleInertiaHalfLife
        self.idleInertia = idleInertia
        self.fromState = fromState
        self.state = state
        self.isBlending = isBlending
    }
}

public struct SkinnedMeshComponent {
    public var mesh: SkinnedMeshDescriptor
    public var material: Material

    public init(mesh: SkinnedMeshDescriptor, material: Material) {
        self.mesh = mesh
        self.material = material
    }
}

public struct SkinnedMeshGroupComponent {
    public var meshes: [SkinnedMeshDescriptor]
    public var materials: [Material]

    public init(meshes: [SkinnedMeshDescriptor], materials: [Material]) {
        self.meshes = meshes
        self.materials = materials
    }
}

public struct FollowTargetComponent {
    public var target: Entity

    public init(target: Entity) {
        self.target = target
    }
}

public struct StaticMeshComponent {
    public var mesh: ProceduralMeshDescriptor
    public var collisionMesh: ProceduralMeshDescriptor?
    public var material: SurfaceMaterial
    public var triangleMaterials: [SurfaceMaterial]?
    public var dirty: Bool
    public var collides: Bool
    public var collisionLayer: UInt32

    public init(mesh: ProceduralMeshDescriptor,
                collisionMesh: ProceduralMeshDescriptor? = nil,
                material: SurfaceMaterial = .default,
                triangleMaterials: [SurfaceMaterial]? = nil,
                dirty: Bool = false,
                collides: Bool = true,
                collisionLayer: UInt32 = CollisionLayer.defaultLayer) {
        self.mesh = mesh
        self.collisionMesh = collisionMesh
        self.material = material
        self.triangleMaterials = triangleMaterials
        self.dirty = dirty
        self.collides = collides
        self.collisionLayer = collisionLayer
    }

    public mutating func markDirty() {
        dirty = true
    }
}

public struct CharacterControllerComponent {
    public var radius: Float
    public var halfHeight: Float
    public var skinWidth: Float
    public var groundSnapSkin: Float
    public var snapDistance: Float
    public var fallProbeDistance: Float
    public var groundSnapMaxSpeed: Float
    public var groundSnapMaxToi: Float
    public var groundSnapMaxStep: Float
    public var groundSweepMaxStep: Float
    public var maxSlideIterations: Int
    public var minGroundDot: Float
    public var groundNormal: SIMD3<Float>
    public var groundTriangleIndex: Int
    public var groundSliding: Bool
    public var groundTransitionFrames: Int
    public var sideContactNormal: SIMD3<Float>
    public var sideContactFrames: Int
    public var contactManifoldTriangles: [Int]
    public var contactManifoldNormals: [SIMD3<Float>]
    public var contactManifoldFrames: Int
    public var grounded: Bool
    public var groundedNear: Bool
    public var groundDistance: Float
    public var collisionMask: UInt32

    public init(radius: Float = 1.5,
                halfHeight: Float = 1.0,
                skinWidth: Float = 0.3,
                groundSnapSkin: Float = 0.05,
                snapDistance: Float = 0.8,
                fallProbeDistance: Float = 200.0,
                groundSnapMaxSpeed: Float = 5.0,
                groundSnapMaxToi: Float = 0.1,
                groundSnapMaxStep: Float = 0.1,
                groundSweepMaxStep: Float = 0.1,
                maxSlideIterations: Int = 4,
                minGroundDot: Float = 0.5,
                groundNormal: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                groundTriangleIndex: Int = -1,
                groundSliding: Bool = false,
                groundTransitionFrames: Int = 0,
                sideContactNormal: SIMD3<Float> = .zero,
                sideContactFrames: Int = 0,
                contactManifoldTriangles: [Int] = [],
                contactManifoldNormals: [SIMD3<Float>] = [],
                contactManifoldFrames: Int = 0,
                grounded: Bool = false,
                groundedNear: Bool = false,
                groundDistance: Float = Float.greatestFiniteMagnitude,
                collisionMask: UInt32 = CollisionLayer.all) {
        self.radius = radius
        self.halfHeight = halfHeight
        self.skinWidth = skinWidth
        self.groundSnapSkin = groundSnapSkin
        self.snapDistance = snapDistance
        self.fallProbeDistance = fallProbeDistance
        self.groundSnapMaxSpeed = groundSnapMaxSpeed
        self.groundSnapMaxToi = groundSnapMaxToi
        self.groundSnapMaxStep = groundSnapMaxStep
        self.groundSweepMaxStep = groundSweepMaxStep
        self.maxSlideIterations = maxSlideIterations
        self.minGroundDot = minGroundDot
        self.groundNormal = groundNormal
        self.groundTriangleIndex = groundTriangleIndex
        self.groundSliding = groundSliding
        self.groundTransitionFrames = groundTransitionFrames
        self.sideContactNormal = sideContactNormal
        self.sideContactFrames = sideContactFrames
        self.contactManifoldTriangles = contactManifoldTriangles
        self.contactManifoldNormals = contactManifoldNormals
        self.contactManifoldFrames = contactManifoldFrames
        self.grounded = grounded
        self.groundedNear = groundedNear
        self.groundDistance = groundDistance
        self.collisionMask = collisionMask
    }
}

public struct AgentCollisionComponent {
    public var radiusOverride: Float?
    public var massWeight: Float
    public var isSolid: Bool

    public init(radiusOverride: Float? = nil,
                massWeight: Float = 1.0,
                isSolid: Bool = true) {
        self.radiusOverride = radiusOverride
        self.massWeight = massWeight
        self.isSolid = isSolid
    }
}

// MARK: - Simple oscillating movement (demo)

public struct OscillateMoveComponent {
    public var origin: SIMD3<Float>
    public var axis: SIMD3<Float>
    public var amplitude: Float
    public var speed: Float
    public var time: Float

    public init(origin: SIMD3<Float>,
                axis: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
                amplitude: Float = 4.0,
                speed: Float = 1.0,
                time: Float = 0) {
        self.origin = origin
        self.axis = axis
        self.amplitude = amplitude
        self.speed = speed
        self.time = time
    }
}

// MARK: - Optional: Simple rotation driver (demo)

public struct SpinComponent {
    /// radians per second
    public var speed: Float
    public var axis: SIMD3<Float>

    public init(speed: Float, axis: SIMD3<Float>) {
        self.speed = speed
        self.axis = axis
    }
}

// MARK: - Kinematic platforms (demo motion)

public struct KinematicPlatformComponent {
    public var origin: SIMD3<Float>
    public var axis: SIMD3<Float>
    public var amplitude: Float
    public var speed: Float
    public var phase: Float
    public var time: Float

    public init(origin: SIMD3<Float> = .zero,
                axis: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                amplitude: Float = 2.0,
                speed: Float = 1.0,
                phase: Float = 0,
                time: Float = 0) {
        self.origin = origin
        self.axis = axis
        self.amplitude = amplitude
        self.speed = speed
        self.phase = phase
        self.time = time
    }
}

// MARK: - Time

public struct TimeComponent {
    public var time: Float
    public var deltaTime: Float
    public var unscaledTime: Float
    public var unscaledDeltaTime: Float
    public var frame: UInt64
    public var timeScale: Float
    public var fixedDelta: Float
    public var accumulator: Float
    public var maxSubsteps: Int

    public init(time: Float = 0,
                deltaTime: Float = 0,
                unscaledTime: Float = 0,
                unscaledDeltaTime: Float = 0,
                frame: UInt64 = 0,
                timeScale: Float = 1,
                fixedDelta: Float = 1.0 / 60.0,
                accumulator: Float = 0,
                maxSubsteps: Int = 4) {
        self.time = time
        self.deltaTime = deltaTime
        self.unscaledTime = unscaledTime
        self.unscaledDeltaTime = unscaledDeltaTime
        self.frame = frame
        self.timeScale = timeScale
        self.fixedDelta = fixedDelta
        self.accumulator = accumulator
        self.maxSubsteps = maxSubsteps
    }
}

// MARK: - Physics

public enum BodyType {
    case `static`
    case kinematic
    case dynamic
}

public struct PhysicsBodyComponent {
    public var bodyType: BodyType
    public var position: SIMD3<Double>
    public var rotation: simd_quatf
    public var prevPosition: SIMD3<Double>
    public var prevRotation: simd_quatf
    public var linearVelocity: SIMD3<Double>
    public var angularVelocity: SIMD3<Double>
    public var mass: Float
    public var inverseMass: Float

    public init(bodyType: BodyType = .dynamic,
                position: SIMD3<Float> = .zero,
                rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                linearVelocity: SIMD3<Float> = .zero,
                angularVelocity: SIMD3<Float> = .zero,
                mass: Float = 1.0) {
        self.bodyType = bodyType
        self.position = SIMD3<Double>(Double(position.x),
                                      Double(position.y),
                                      Double(position.z))
        self.rotation = rotation
        self.prevPosition = self.position
        self.prevRotation = rotation
        self.linearVelocity = SIMD3<Double>(Double(linearVelocity.x),
                                            Double(linearVelocity.y),
                                            Double(linearVelocity.z))
        self.angularVelocity = SIMD3<Double>(Double(angularVelocity.x),
                                             Double(angularVelocity.y),
                                             Double(angularVelocity.z))
        self.mass = mass
        self.inverseMass = mass > 0 ? 1.0 / mass : 0
    }

    public var positionF: SIMD3<Float> {
        SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z))
    }

    public var prevPositionF: SIMD3<Float> {
        SIMD3<Float>(Float(prevPosition.x), Float(prevPosition.y), Float(prevPosition.z))
    }

    public var linearVelocityF: SIMD3<Float> {
        SIMD3<Float>(Float(linearVelocity.x), Float(linearVelocity.y), Float(linearVelocity.z))
    }

    public var angularVelocityF: SIMD3<Float> {
        SIMD3<Float>(Float(angularVelocity.x), Float(angularVelocity.y), Float(angularVelocity.z))
    }
}

public struct MoveIntentComponent {
    public var desiredVelocity: SIMD3<Float>
    public var desiredFacingYaw: Float
    public var hasFacingYaw: Bool
    public var jumpRequested: Bool
    public var dodgeRequested: Bool

    public init(desiredVelocity: SIMD3<Float> = .zero,
                desiredFacingYaw: Float = 0,
                hasFacingYaw: Bool = false,
                jumpRequested: Bool = false,
                dodgeRequested: Bool = false) {
        self.desiredVelocity = desiredVelocity
        self.desiredFacingYaw = desiredFacingYaw
        self.hasFacingYaw = hasFacingYaw
        self.jumpRequested = jumpRequested
        self.dodgeRequested = dodgeRequested
    }
}

public struct ActionAnimationComponent {
    public var profile: MotionProfile
    public var time: Float
    public var playbackRate: Float
    public var loop: Bool
    public var inPlace: Bool
    public var active: Bool
    public var weight: Float
    public var blendInTime: Float
    public var blendOutHalfLife: Float
    public var exiting: Bool

    public init(profile: MotionProfile,
                time: Float = 0,
                playbackRate: Float = 1,
                loop: Bool = false,
                inPlace: Bool = true,
                active: Bool = false,
                weight: Float = 0,
                blendInTime: Float = 0.08,
                blendOutHalfLife: Float = 0.12,
                exiting: Bool = false) {
        self.profile = profile
        self.time = time
        self.playbackRate = playbackRate
        self.loop = loop
        self.inPlace = inPlace
        self.active = active
        self.weight = weight
        self.blendInTime = blendInTime
        self.blendOutHalfLife = blendOutHalfLife
        self.exiting = exiting
    }
}

public struct DodgeActionComponent {
    public var active: Bool
    public var time: Float
    public var duration: Float
    public var distance: Float
    public var startTime: Float
    public var endTime: Float
    public var direction: SIMD3<Float>
    public var facingYaw: Float

    public init(active: Bool = false,
                time: Float = 0,
                duration: Float = 0.35,
                distance: Float = 3.0,
                startTime: Float = 0,
                endTime: Float = 0,
                direction: SIMD3<Float> = .zero,
                facingYaw: Float = 0) {
        self.active = active
        self.time = time
        self.duration = duration
        self.distance = distance
        self.startTime = startTime
        self.endTime = endTime
        self.direction = direction
        self.facingYaw = facingYaw
    }
}

public struct MovementComponent {
    public var walkSpeed: Float
    public var runSpeed: Float
    public var runThreshold: Float
    public var maxAcceleration: Float
    public var maxDeceleration: Float

    public init(walkSpeed: Float = 4.5,
                runSpeed: Float = 12.5,
                runThreshold: Float = 0.78,
                maxAcceleration: Float = 20.0,
                maxDeceleration: Float = 30.0) {
        self.walkSpeed = walkSpeed
        self.runSpeed = runSpeed
        self.runThreshold = runThreshold
        self.maxAcceleration = maxAcceleration
        self.maxDeceleration = maxDeceleration
    }
}

public struct SurfaceMaterial: Equatable {
    public var muS: Float
    public var muK: Float
    public var flattenGround: Bool

    public static let `default` = SurfaceMaterial(muS: 0.8, muK: 0.6, flattenGround: false)

    public init(muS: Float = 0.8, muK: Float = 0.6, flattenGround: Bool = false) {
        self.muS = muS
        self.muK = muK
        self.flattenGround = flattenGround
    }
}
