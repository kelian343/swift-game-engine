//
//  Systems.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public protocol System {
    func update(world: World, dt: Float)
}

public protocol FixedStepSystem {
    func fixedUpdate(world: World, dt: Float)
}

public protocol Narrowphase {
    func generateManifolds(world: PhysicsWorld,
                           pairs: [(PhysicsWorld.ProxyHandle, PhysicsWorld.ProxyHandle)])
    -> [PhysicsWorld.ContactManifold]
}

public struct NullNarrowphase: Narrowphase {
    public init() {}
    public func generateManifolds(world: PhysicsWorld,
                                  pairs: [(PhysicsWorld.ProxyHandle, PhysicsWorld.ProxyHandle)])
    -> [PhysicsWorld.ContactManifold] {
        _ = world
        _ = pairs
        return []
    }
}

/// Tracks global time inside ECS via a singleton TimeComponent.
public final class TimeSystem: System {
    private var timeEntity: Entity?

    public init() {}

    public func update(world: World, dt: Float) {
        let e: Entity = {
            if let existing = timeEntity, world.isAlive(existing) {
                return existing
            }
            let created = world.createEntity()
            world.add(created, TimeComponent())
            timeEntity = created
            return created
        }()

        let store = world.store(TimeComponent.self)
        var t = store[e] ?? TimeComponent()
        t.unscaledDeltaTime = dt
        t.deltaTime = dt * t.timeScale
        t.unscaledTime += t.unscaledDeltaTime
        t.time += t.deltaTime
        t.frame &+= 1
        store[e] = t
    }
}

/// Runs fixed-step systems using TimeComponent's accumulator.
public final class FixedStepRunner {
    private let preFixedSystems: [FixedStepSystem]
    private let fixedSystems: [FixedStepSystem]
    private let postFixedSystems: [FixedStepSystem]

    public init(preFixed: [FixedStepSystem] = [],
                fixed: [FixedStepSystem] = [],
                postFixed: [FixedStepSystem] = []) {
        self.preFixedSystems = preFixed
        self.fixedSystems = fixed
        self.postFixedSystems = postFixed
    }

    public func update(world: World) {
        guard let e = world.query(TimeComponent.self).first else { return }
        let store = world.store(TimeComponent.self)
        guard var t = store[e] else { return }

        t.accumulator += t.deltaTime
        let fixedDt = max(t.fixedDelta, 0.0001)

        var steps = 0
        while t.accumulator >= fixedDt && steps < t.maxSubsteps {
            for s in preFixedSystems {
                s.fixedUpdate(world: world, dt: fixedDt)
            }
            for s in fixedSystems {
                s.fixedUpdate(world: world, dt: fixedDt)
            }
            for s in postFixedSystems {
                s.fixedUpdate(world: world, dt: fixedDt)
            }
            t.accumulator -= fixedDt
            steps += 1
        }

        if steps == t.maxSubsteps && t.accumulator >= fixedDt {
            t.accumulator = 0
        }

        store[e] = t
    }
}

/// Demo system: apply SpinComponent to TransformComponent via quaternion integration.
public final class SpinSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let entities = world.query(TransformComponent.self, SpinComponent.self)
        let tStore = world.store(TransformComponent.self)
        let sStore = world.store(SpinComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)

        for e in entities {
            guard var t = tStore[e], let s = sStore[e] else { continue }
            let angle = s.speed * dt
            let dq = simd_quatf(angle: angle, axis: simd_normalize(s.axis))
            if var p = pStore[e] {
                p.rotation = simd_normalize(dq * p.rotation)
                pStore[e] = p
            } else {
                t.rotation = simd_normalize(dq * t.rotation)
                tStore[e] = t
            }
        }
    }
}

/// Lock previous transforms at the start of a physics fixed step.
public final class PhysicsBeginStepSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let bodies = world.query(PhysicsBodyComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            if body.bodyType == .dynamic || body.bodyType == .kinematic {
                body.prevPosition = body.position
                body.prevRotation = body.rotation
                pStore[e] = body
            }
        }
    }
}

/// Sync ECS transforms/colliders to PhysicsWorld proxies.
public final class PhysicsSyncSystem: FixedStepSystem {
    private let physicsWorld: PhysicsWorld

    public init(physicsWorld: PhysicsWorld) {
        self.physicsWorld = physicsWorld
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        physicsWorld.sync(world: world)
    }
}

/// Broadphase pass using a simple sweep-and-prune on X axis.
public final class PhysicsBroadphaseSystem: FixedStepSystem {
    private let physicsWorld: PhysicsWorld

    public init(physicsWorld: PhysicsWorld) {
        self.physicsWorld = physicsWorld
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = world
        _ = dt
        physicsWorld.buildBroadphasePairs()
    }
}

/// Narrowphase placeholder: build contact manifolds from broadphase pairs.
public final class PhysicsNarrowphaseSystem: FixedStepSystem {
    private let physicsWorld: PhysicsWorld
    private let narrowphase: Narrowphase

    public init(physicsWorld: PhysicsWorld, narrowphase: Narrowphase = NullNarrowphase()) {
        self.physicsWorld = physicsWorld
        self.narrowphase = narrowphase
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = world
        _ = dt
        let manifolds = narrowphase.generateManifolds(world: physicsWorld,
                                                      pairs: physicsWorld.broadphaseProxyPairs)
        physicsWorld.setManifolds(manifolds)
    }
}

/// Solver placeholder: resolve contacts and apply impulses.
public final class PhysicsSolverSystem: FixedStepSystem {
    private let physicsWorld: PhysicsWorld

    public init(physicsWorld: PhysicsWorld) {
        self.physicsWorld = physicsWorld
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = world
        _ = dt
        _ = physicsWorld
        // TODO: Sequential impulse / PGS using physicsWorld.manifolds.
    }
}

/// Apply input intents to physics bodies before the physics step.
public final class PhysicsIntentSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let bodies = world.query(PhysicsBodyComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let mStore = world.store(MoveIntentComponent.self)
        let mvStore = world.store(MovementComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            guard let intent = mStore[e] else { continue }
            if body.bodyType == .dynamic || body.bodyType == .kinematic {
                let move = mvStore[e] ?? MovementComponent()
                let target = intent.desiredVelocity
                let current = body.linearVelocity
                let accel = simd_length(target) >= simd_length(current) ? move.maxAcceleration : move.maxDeceleration
                body.linearVelocity = approachVec(current: current, target: target, maxDelta: accel * dt)
                if intent.hasFacingYaw {
                    body.rotation = simd_quatf(angle: intent.desiredFacingYaw,
                                               axis: SIMD3<Float>(0, 1, 0))
                }
                pStore[e] = body
            }
        }
    }
}

private func approachVec(current: SIMD3<Float>, target: SIMD3<Float>, maxDelta: Float) -> SIMD3<Float> {
    let delta = target - current
    let len = simd_length(delta)
    if len <= maxDelta || len < 0.00001 {
        return target
    }
    return current + delta / len * maxDelta
}

/// Kinematic capsule sweep: move to TOI and stop (no slide yet).
public final class KinematicMoveStopSystem: FixedStepSystem {
    private var query: CollisionQuery?

    public init() {}

    public func setQuery(_ query: CollisionQuery) {
        self.query = query
    }

    public func fixedUpdate(world: World, dt: Float) {
        guard let query = query else { return }
        let bodies = world.query(PhysicsBodyComponent.self, CharacterControllerComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)
        for e in bodies {
            guard var body = pStore[e], let controller = cStore[e] else { continue }
            if body.bodyType == .static { continue }

            let delta = body.linearVelocity * dt
            let len = simd_length(delta)
            if len < 1e-6 { continue }

            if let hit = query.capsuleCast(from: body.position,
                                           delta: delta,
                                           radius: controller.radius,
                                           halfHeight: controller.halfHeight) {
                let into = simd_dot(delta, hit.normal)
                if into < 0 {
                    let moveDist = max(hit.toi - controller.skinWidth, 0)
                    let dir = delta / len
                    body.position += dir * moveDist
                    let vInto = simd_dot(body.linearVelocity, hit.normal)
                    if vInto < 0 {
                        body.linearVelocity -= hit.normal * vInto
                    }
                } else {
                    body.position += delta
                }
            } else {
                body.position += delta
            }

            pStore[e] = body
        }
    }
}

/// Minimal physics integration step (authoritative for entities with PhysicsBodyComponent).
public final class PhysicsIntegrateSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let bodies = world.query(PhysicsBodyComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            if cStore.contains(e) { continue }

            switch body.bodyType {
            case .static:
                break
            case .kinematic, .dynamic:
                body.position += body.linearVelocity * dt
                let w = body.angularVelocity
                let wLen = simd_length(w)
                if wLen > 0.0001 {
                    let axis = w / wLen
                    let dq = simd_quatf(angle: wLen * dt, axis: axis)
                    body.rotation = simd_normalize(dq * body.rotation)
                }
            }

            pStore[e] = body
        }
    }
}

/// Write back physics state to ECS transforms after physics step.
public final class PhysicsWritebackSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let bodies = world.query(PhysicsBodyComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let tStore = world.store(TransformComponent.self)

        for e in bodies {
            guard let body = pStore[e], var t = tStore[e] else { continue }
            t.translation = body.position
            t.rotation = body.rotation
            tStore[e] = t
        }
    }
}

/// Events placeholder: update enter/stay/exit sets after physics step.
public final class PhysicsEventsSystem: FixedStepSystem {
    private let physicsWorld: PhysicsWorld

    public init(physicsWorld: PhysicsWorld) {
        self.physicsWorld = physicsWorld
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = world
        _ = dt
        // TODO: Use real contact manifolds once narrowphase is in place.
        physicsWorld.updateContactCache(from: physicsWorld.broadphasePairs)
    }
}

/// Extract RenderItems from ECS.
/// This does NOT bump scene revision; it's per-frame derived output.
public final class RenderExtractSystem {
    public init() {}

    public func extract(world: World) -> [RenderItem] {
        // ✅ Stable ordering for deterministic draw-call order (picking/debug/sorting friendly)
        let entities = world
            .query(TransformComponent.self, RenderComponent.self)
            .sorted { $0.id < $1.id }

        let tStore = world.store(TransformComponent.self)
        let rStore = world.store(RenderComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let timeStore = world.store(TimeComponent.self)
        let alpha: Float = {
            guard let e = world.query(TimeComponent.self).first,
                  let t = timeStore[e],
                  t.fixedDelta > 0 else {
                return 1.0
            }
            let a = t.accumulator / t.fixedDelta
            return min(max(a, 0), 1)
        }()

        var items: [RenderItem] = []
        items.reserveCapacity(entities.count)

        for e in entities {
            guard let t = tStore[e], let r = rStore[e] else { continue }
            if let p = pStore[e] {
                let pos = p.prevPosition + (p.position - p.prevPosition) * alpha
                let rot = simd_slerp(p.prevRotation, p.rotation, alpha)
                let interp = TransformComponent(translation: pos, rotation: rot, scale: t.scale)
                items.append(RenderItem(mesh: r.mesh, material: r.material, modelMatrix: interp.modelMatrix))
            } else {
                items.append(RenderItem(mesh: r.mesh, material: r.material, modelMatrix: t.modelMatrix))
            }
        }
        return items
    }
}
