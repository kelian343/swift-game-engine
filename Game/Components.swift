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
}

public struct LocomotionProfileComponent {
    public var idleProfile: MotionProfile
    public var walkProfile: MotionProfile
    public var runProfile: MotionProfile
    public var idleEnterSpeed: Float
    public var idleExitSpeed: Float
    public var idleTime: Float
    public var walkTime: Float
    public var runTime: Float
    public var runEnterSpeed: Float
    public var runExitSpeed: Float
    public var blendTime: Float
    public var blendT: Float
    public var fromState: LocomotionState
    public var state: LocomotionState
    public var isBlending: Bool

    public init(idleProfile: MotionProfile,
                walkProfile: MotionProfile,
                runProfile: MotionProfile,
                idleEnterSpeed: Float = 0.15,
                idleExitSpeed: Float = 0.25,
                idleTime: Float = 0,
                walkTime: Float = 0,
                runTime: Float = 0,
                runEnterSpeed: Float = 6.0,
                runExitSpeed: Float = 5.0,
                blendTime: Float = 0.25,
                blendT: Float = 1.0,
                fromState: LocomotionState = .idle,
                state: LocomotionState = .idle,
                isBlending: Bool = false) {
        self.idleProfile = idleProfile
        self.walkProfile = walkProfile
        self.runProfile = runProfile
        self.idleEnterSpeed = idleEnterSpeed
        self.idleExitSpeed = idleExitSpeed
        self.idleTime = idleTime
        self.walkTime = walkTime
        self.runTime = runTime
        self.runEnterSpeed = runEnterSpeed
        self.runExitSpeed = runExitSpeed
        self.blendTime = blendTime
        self.blendT = blendT
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

    public init(mesh: ProceduralMeshDescriptor,
                collisionMesh: ProceduralMeshDescriptor? = nil,
                material: SurfaceMaterial = .default,
                triangleMaterials: [SurfaceMaterial]? = nil,
                dirty: Bool = false) {
        self.mesh = mesh
        self.collisionMesh = collisionMesh
        self.material = material
        self.triangleMaterials = triangleMaterials
        self.dirty = dirty
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

    public init(radius: Float = 1.5,
                halfHeight: Float = 1.0,
                skinWidth: Float = 0.3,
                groundSnapSkin: Float = 0.05,
                snapDistance: Float = 0.8,
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
                groundedNear: Bool = false) {
        self.radius = radius
        self.halfHeight = halfHeight
        self.skinWidth = skinWidth
        self.groundSnapSkin = groundSnapSkin
        self.snapDistance = snapDistance
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
    }
}

public struct AgentCollisionComponent {
    public var radiusOverride: Float?
    public var massWeight: Float
    public var isSolid: Bool
    public var filter: CollisionFilter

    public init(radiusOverride: Float? = nil,
                massWeight: Float = 1.0,
                isSolid: Bool = true,
                filter: CollisionFilter = .default) {
        self.radiusOverride = radiusOverride
        self.massWeight = massWeight
        self.isSolid = isSolid
        self.filter = filter
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
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var prevPosition: SIMD3<Float>
    public var prevRotation: simd_quatf
    public var linearVelocity: SIMD3<Float>
    public var angularVelocity: SIMD3<Float>
    public var mass: Float
    public var inverseMass: Float

    public init(bodyType: BodyType = .dynamic,
                position: SIMD3<Float> = .zero,
                rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                linearVelocity: SIMD3<Float> = .zero,
                angularVelocity: SIMD3<Float> = .zero,
                mass: Float = 1.0) {
        self.bodyType = bodyType
        self.position = position
        self.rotation = rotation
        self.prevPosition = position
        self.prevRotation = rotation
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
        self.mass = mass
        self.inverseMass = mass > 0 ? 1.0 / mass : 0
    }
}

public struct MoveIntentComponent {
    public var desiredVelocity: SIMD3<Float>
    public var desiredFacingYaw: Float
    public var hasFacingYaw: Bool
    public var jumpRequested: Bool

    public init(desiredVelocity: SIMD3<Float> = .zero,
                desiredFacingYaw: Float = 0,
                hasFacingYaw: Bool = false,
                jumpRequested: Bool = false) {
        self.desiredVelocity = desiredVelocity
        self.desiredFacingYaw = desiredFacingYaw
        self.hasFacingYaw = hasFacingYaw
        self.jumpRequested = jumpRequested
    }
}

public struct MovementComponent {
    public var walkSpeed: Float
    public var runSpeed: Float
    public var runThreshold: Float
    public var maxAcceleration: Float
    public var maxDeceleration: Float

    public init(walkSpeed: Float = 2.5,
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

public struct CollisionLayer: Equatable {
    public var bits: UInt32

    public static let `default` = CollisionLayer(bits: 1 << 0)

    public init(bits: UInt32) {
        self.bits = bits
    }
}

public struct CollisionFilter: Equatable {
    public var layer: CollisionLayer
    public var mask: UInt32

    public static let `default` = CollisionFilter(layer: .default, mask: UInt32.max)

    public init(layer: CollisionLayer = .default, mask: UInt32 = UInt32.max) {
        self.layer = layer
        self.mask = mask
    }

    public func canCollide(with other: CollisionFilter) -> Bool {
        (layer.bits & other.mask) != 0 && (other.layer.bits & mask) != 0
    }
}

public enum ColliderShape: Equatable {
    case box(halfExtents: SIMD3<Float>)
    case sphere(radius: Float)
    /// Capsule aligned to local Y axis (center at origin)
    case capsule(halfHeight: Float, radius: Float)
}

public struct ColliderComponent: Equatable {
    public var shape: ColliderShape
    public var filter: CollisionFilter

    public init(shape: ColliderShape,
                filter: CollisionFilter = .default) {
        self.shape = shape
        self.filter = filter
    }

    public struct AABB {
        public var min: SIMD3<Float>
        public var max: SIMD3<Float>
    }

    public static func computeAABB(position: SIMD3<Float>,
                                   rotation: simd_quatf,
                                   collider: ColliderComponent) -> AABB {
        switch collider.shape {
        case .box(let he):
            // OBB -> world AABB using |R| * he
            let r = simd_float3x3(rotation)
            let absR = simd_float3x3(columns: (
                simd_abs(r.columns.0),
                simd_abs(r.columns.1),
                simd_abs(r.columns.2)
            ))
            let worldHe = simd_mul(absR, he)
            return AABB(min: position - worldHe, max: position + worldHe)
        case .sphere(let radius):
            let ext = SIMD3<Float>(repeating: radius)
            return AABB(min: position - ext, max: position + ext)
        case .capsule(let halfHeight, let radius):
            let localA = SIMD3<Float>(0, -halfHeight, 0)
            let localB = SIMD3<Float>(0, halfHeight, 0)
            let worldA = position + rotation.act(localA)
            let worldB = position + rotation.act(localB)
            let minBase = simd_min(worldA, worldB)
            let maxBase = simd_max(worldA, worldB)
            let ext = SIMD3<Float>(repeating: radius)
            return AABB(min: minBase - ext, max: maxBase + ext)
        }
    }
}
