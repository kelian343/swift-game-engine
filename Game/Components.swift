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

public struct StaticMeshComponent {
    public var mesh: MeshData

    public init(mesh: MeshData) {
        self.mesh = mesh
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

    public init(desiredVelocity: SIMD3<Float> = .zero,
                desiredFacingYaw: Float = 0,
                hasFacingYaw: Bool = false) {
        self.desiredVelocity = desiredVelocity
        self.desiredFacingYaw = desiredFacingYaw
        self.hasFacingYaw = hasFacingYaw
    }
}

public struct MovementComponent {
    public var maxAcceleration: Float
    public var maxDeceleration: Float

    public init(maxAcceleration: Float = 20.0,
                maxDeceleration: Float = 30.0) {
        self.maxAcceleration = maxAcceleration
        self.maxDeceleration = maxDeceleration
    }
}

public struct PhysicsMaterial: Equatable {
    public var friction: Float
    public var restitution: Float

    public static let `default` = PhysicsMaterial(friction: 0.5, restitution: 0.0)

    public init(friction: Float = 0.5, restitution: Float = 0.0) {
        self.friction = friction
        self.restitution = restitution
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
    public var material: PhysicsMaterial
    public var filter: CollisionFilter

    public init(shape: ColliderShape,
                material: PhysicsMaterial = .default,
                filter: CollisionFilter = .default) {
        self.shape = shape
        self.material = material
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
