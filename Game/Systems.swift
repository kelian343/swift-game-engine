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

/// Demo system: animate kinematic platforms along a single axis.
public final class KinematicPlatformMotionSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let entities = world.query(TransformComponent.self,
                                   PhysicsBodyComponent.self,
                                   KinematicPlatformComponent.self)
        let tStore = world.store(TransformComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let kStore = world.store(KinematicPlatformComponent.self)

        for e in entities {
            guard var t = tStore[e], var p = pStore[e], var k = kStore[e] else { continue }
            if p.bodyType == .static { continue }

            let axisLen = simd_length(k.axis)
            let axis = axisLen > 1e-4 ? k.axis / axisLen : SIMD3<Float>(0, 1, 0)
            k.time += dt
            let offset = sin(k.time * k.speed + k.phase) * k.amplitude
            let newPos = k.origin + axis * offset

            t.translation = newPos
            p.position = newPos
            p.linearVelocity = .zero

            tStore[e] = t
            pStore[e] = p
            kStore[e] = k
        }
    }
}

/// Rebuild static collision query from current transforms.
public final class CollisionQueryRefreshSystem: FixedStepSystem {
    private let kinematicMoveSystem: KinematicMoveStopSystem

    public init(kinematicMoveSystem: KinematicMoveStopSystem) {
        self.kinematicMoveSystem = kinematicMoveSystem
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let query = CollisionQuery(world: world)
        kinematicMoveSystem.setQuery(query)
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
        let cStore = world.store(CharacterControllerComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            guard let intent = mStore[e] else { continue }
            if body.bodyType == .dynamic || body.bodyType == .kinematic {
                let move = mvStore[e] ?? MovementComponent()
                if let controller = cStore[e] {
                    let input = SIMD3<Float>(intent.desiredVelocity.x, 0, intent.desiredVelocity.z)
                    var target = input
                    if controller.groundedNear {
                        let n = simd_normalize(controller.groundNormal)
                        let g = SIMD3<Float>(0, -1, 0)
                        let gTan = g - n * simd_dot(g, n)
                        let gTanLen = simd_length(gTan)
                        if gTanLen > 1e-5 {
                            let downhill = gTan / gTanLen
                            var uphill2D = SIMD3<Float>(-downhill.x, 0, -downhill.z)
                            let uphill2DLen = simd_length(uphill2D)
                            if uphill2DLen > 1e-5 {
                                uphill2D /= uphill2DLen
                                let uphillSpeed = simd_dot(target, uphill2D)
                                if uphillSpeed > 0 {
                                    target += uphill2D * (uphillSpeed * controller.uphillBoostScale)
                                }
                            }
                        }
                    }
                    let current = SIMD3<Float>(body.linearVelocity.x, 0, body.linearVelocity.z)
                    let accel = simd_length(target) >= simd_length(current) ? move.maxAcceleration : move.maxDeceleration
                    let next = approachVec(current: current, target: target, maxDelta: accel * dt)
                    body.linearVelocity = SIMD3<Float>(next.x, body.linearVelocity.y, next.z)
                } else {
                    let target = intent.desiredVelocity
                    let current = body.linearVelocity
                    let accel = simd_length(target) >= simd_length(current) ? move.maxAcceleration : move.maxDeceleration
                    body.linearVelocity = approachVec(current: current, target: target, maxDelta: accel * dt)
                }
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

/// Apply jump impulses for grounded characters.
public final class JumpSystem: FixedStepSystem {
    public var jumpSpeed: Float

    public init(jumpSpeed: Float = 34.0) {
        self.jumpSpeed = jumpSpeed
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let entities = world.query(PhysicsBodyComponent.self, MoveIntentComponent.self, CharacterControllerComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let mStore = world.store(MoveIntentComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)

        for e in entities {
            guard var body = pStore[e],
                  var intent = mStore[e],
                  var controller = cStore[e] else { continue }
            if intent.jumpRequested && controller.grounded {
                body.linearVelocity.y = jumpSpeed
                controller.grounded = false
                pStore[e] = body
                cStore[e] = controller
            }
            if intent.jumpRequested {
                intent.jumpRequested = false
                mStore[e] = intent
            }
        }
    }
}

/// Apply constant gravity acceleration to physics bodies.
public final class GravitySystem: FixedStepSystem {
    public var gravity: SIMD3<Float>

    public init(gravity: SIMD3<Float> = SIMD3<Float>(0, -98.0, 0)) {
        self.gravity = gravity
    }

    public func fixedUpdate(world: World, dt: Float) {
        let bodies = world.query(PhysicsBodyComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            if body.bodyType != .dynamic { continue }
            if let controller = cStore[e], controller.grounded, controller.groundedNear {
                continue
            }
            body.linearVelocity += gravity * dt
            pStore[e] = body
        }
    }
}

/// Kinematic capsule sweep: move & slide with ground snap.
public final class KinematicMoveStopSystem: FixedStepSystem {
    private var query: CollisionQuery?
    private let gravity: SIMD3<Float>
    private let debugPlatformCarry = true

    public init(gravity: SIMD3<Float> = SIMD3<Float>(0, -98.0, 0)) {
        self.gravity = gravity
    }

    public func setQuery(_ query: CollisionQuery) {
        self.query = query
    }

    public func fixedUpdate(world: World, dt: Float) {
        guard let query = query else { return }
        let bodies = world.query(PhysicsBodyComponent.self, CharacterControllerComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)
        let platBodies = world.store(PhysicsBodyComponent.self)
        let platCols = world.store(ColliderComponent.self)
        let platformEntities = world.query(PhysicsBodyComponent.self,
                                           ColliderComponent.self,
                                           KinematicPlatformComponent.self)
        for e in bodies {
            guard var body = pStore[e], var controller = cStore[e] else { continue }
            if body.bodyType == .static { continue }

            var position = body.position
            // Apply platform motion carry/push before character sweep.
            if !platformEntities.isEmpty {
                let capsuleHalf = controller.halfHeight + controller.radius
                let baseY = position.y - capsuleHalf
                let capMin = SIMD3<Float>(position.x - controller.radius,
                                          position.y - capsuleHalf,
                                          position.z - controller.radius)
                let capMax = SIMD3<Float>(position.x + controller.radius,
                                          position.y + capsuleHalf,
                                          position.z + controller.radius)
                let sideTol = max(controller.skinWidth, controller.groundSnapSkin)
                var bestCarry: SIMD3<Float> = .zero
                var pushDelta: SIMD3<Float> = .zero

                for pe in platformEntities {
                    guard let pBody = platBodies[pe], let pCol = platCols[pe] else { continue }
                    if pBody.bodyType != .kinematic { continue }
                    let pDelta = pBody.position - pBody.prevPosition
                    if simd_length_squared(pDelta) < 1e-8 { continue }

                    let aabb = ColliderComponent.computeAABB(position: pBody.position,
                                                             rotation: pBody.rotation,
                                                             collider: pCol)
                    let expandedMin = aabb.min - SIMD3<Float>(repeating: sideTol)
                    let expandedMax = aabb.max + SIMD3<Float>(repeating: sideTol)
                    let overlap = capMin.x <= expandedMax.x && capMax.x >= expandedMin.x &&
                                  capMin.y <= expandedMax.y && capMax.y >= expandedMin.y &&
                                  capMin.z <= expandedMax.z && capMax.z >= expandedMin.z
                    if !overlap { continue }

                    let withinXZ = position.x >= aabb.min.x - controller.radius &&
                                   position.x <= aabb.max.x + controller.radius &&
                                   position.z >= aabb.min.z - controller.radius &&
                                   position.z <= aabb.max.z + controller.radius
                    let topY = aabb.max.y
                    let topTol = controller.snapDistance + max(controller.skinWidth, controller.groundSnapSkin) + 0.05
                    let onTop = withinXZ && baseY >= topY - topTol && baseY <= topY + topTol

                    if debugPlatformCarry {
                        print("PlatformTest e=\(e.id) pe=\(pe.id) onTop=\(onTop) withinXZ=\(withinXZ) baseY=\(baseY) topY=\(topY) pDelta=\(pDelta)")
                    }
                    if onTop {
                        if simd_length_squared(pDelta) > simd_length_squared(bestCarry) {
                            bestCarry = pDelta
                        }
                    } else {
                        let yMin = aabb.min.y - capsuleHalf
                        let yMax = aabb.max.y + capsuleHalf
                        if position.y >= yMin && position.y <= yMax {
                            let outsideX = position.x < aabb.min.x - controller.radius ||
                                           position.x > aabb.max.x + controller.radius
                            let outsideZ = position.z < aabb.min.z - controller.radius ||
                                           position.z > aabb.max.z + controller.radius
                            if !outsideX && !outsideZ {
                                continue
                            }
                            let cx = max(aabb.min.x, min(position.x, aabb.max.x))
                            let cz = max(aabb.min.z, min(position.z, aabb.max.z))
                            let dx = position.x - cx
                            let dz = position.z - cz
                            let sideDistSq = dx * dx + dz * dz
                            let sidePushTol = controller.radius + sideTol
                            if debugPlatformCarry {
                                print("PlatformSide e=\(e.id) pe=\(pe.id) sideDistSq=\(sideDistSq) sidePushTol=\(sidePushTol) yRange=\(yMin)...\(yMax)")
                            }
                            if sideDistSq <= sidePushTol * sidePushTol {
                                pushDelta += SIMD3<Float>(pDelta.x, 0, pDelta.z)
                            }
                        }
                    }
                }

                if simd_length_squared(bestCarry) > 1e-8 {
                    if debugPlatformCarry {
                        print("PlatformCarryApply e=\(e.id) delta=\(bestCarry)")
                    }
                    position += bestCarry
                } else if simd_length_squared(pushDelta) > 1e-8 {
                    if debugPlatformCarry {
                        print("PlatformPushApply e=\(e.id) delta=\(pushDelta)")
                    }
                    position += pushDelta
                }
            }
            let wasGrounded = controller.grounded
            let wasGroundedNear = controller.groundedNear
            if wasGrounded && wasGroundedNear && body.linearVelocity.y < 0 {
                body.linearVelocity.y = 0
            }
            var remaining = body.linearVelocity * dt
            if wasGrounded && wasGroundedNear && remaining.y < 0 {
                remaining.y = 0
            }
            var isGrounded = false
            var isGroundedNear = false
            var groundNormal: SIMD3<Float>?
            var groundMaterial = SurfaceMaterial.default
            for _ in 0..<controller.maxSlideIterations {
                let len = simd_length(remaining)
                if len < 1e-6 { break }

                if let hit = query.capsuleCastBlocking(from: position,
                                                       delta: remaining,
                                                       radius: controller.radius,
                                                       halfHeight: controller.halfHeight) {
                    let contactSkin = hit.normal.y >= controller.minGroundDot ? controller.groundSnapSkin : controller.skinWidth
                    var slideNormal = hit.normal
                    if slideNormal.y < controller.minGroundDot {
                        slideNormal.y = 0
                        let nLen = simd_length(slideNormal)
                        if nLen > 1e-5 {
                            slideNormal /= nLen
                        } else {
                            position += remaining
                            remaining = .zero
                            break
                        }
                    }
                    let into = simd_dot(remaining, slideNormal)
                    let intoEps = 1e-4 * len
                    if into >= -intoEps {
                        position += remaining
                        remaining = .zero
                        break
                    }
                    if hit.toi <= contactSkin && abs(into) <= intoEps {
                        position += remaining
                        remaining = .zero
                        break
                    }
                    if into >= 0 {
                        position += remaining
                        remaining = .zero
                        break
                    }

                    let rawMoveDist = max(hit.toi - contactSkin, 0)
                    var moveDist = rawMoveDist
                    if hit.normal.y >= controller.minGroundDot && remaining.y < 0 &&
                        moveDist > controller.groundSweepMaxStep {
                        moveDist = controller.groundSweepMaxStep
                    }
                    let dir = remaining / len
                    position += dir * moveDist

                    var leftover = remaining - dir * moveDist
                    leftover -= slideNormal * simd_dot(leftover, slideNormal)
                    if wasGrounded && wasGroundedNear && leftover.y < 0 {
                        leftover.y = 0
                    }
                    let residual = simd_dot(leftover, slideNormal)
                    if abs(residual) < 1e-5 {
                        leftover -= slideNormal * residual
                    }
                    if simd_length_squared(leftover) < 1e-8 {
                        remaining = .zero
                        break
                    }
                    remaining = leftover

                    let vInto = simd_dot(body.linearVelocity, slideNormal)
                    if vInto < 0 {
                        body.linearVelocity -= slideNormal * vInto
                    }
                } else {
                    position += remaining
                    remaining = .zero
                    break
                }
            }

            if controller.snapDistance > 0 {
                let down = SIMD3<Float>(0, -1, 0)
                let snapDelta = down * controller.snapDistance
                if let hit = query.capsuleCastGround(from: position,
                                                     delta: snapDelta,
                                                     radius: controller.radius,
                                                     halfHeight: controller.halfHeight,
                                                     minNormalY: controller.minGroundDot),
                   hit.toi <= controller.snapDistance {
                    let groundNearThreshold = max(controller.groundSnapSkin, controller.skinWidth)
                    let nearGround = hit.toi <= groundNearThreshold
                    isGroundedNear = nearGround
                    let groundGateVel = body.linearVelocity.y <= 0
                    let vInto = simd_dot(body.linearVelocity, hit.normal)
                    let groundGateSpeed = vInto >= -controller.groundSnapMaxSpeed
                    let groundGateToi = hit.toi <= controller.groundSnapMaxToi
                    var canSnap = groundGateVel && (nearGround || groundGateSpeed || groundGateToi)
                    if wasGroundedNear && hit.toi <= controller.snapDistance {
                        canSnap = true
                    }
                    if nearGround || canSnap {
                        isGrounded = true
                        groundNormal = hit.normal
                        groundMaterial = hit.material
                    }
                    if canSnap {
                        let rawMove = max(hit.toi - controller.groundSnapSkin, 0)
                        var moveDist = rawMove
                        if nearGround && moveDist > controller.groundSnapMaxStep {
                            moveDist = controller.groundSnapMaxStep
                        }
                        position += down * moveDist
                        let vInto = simd_dot(body.linearVelocity, hit.normal)
                        if vInto < 0 {
                            body.linearVelocity -= hit.normal * vInto
                        }
                    }
                }
            }

            if isGrounded, let n = groundNormal {
                let normal = simd_normalize(n)
                let g = gravity
                let gN = simd_dot(g, normal)
                let gTan = g - normal * gN
                let gTanLen = simd_length(gTan)
                let slopeAccelEps: Float = 0.5
                if gTanLen > slopeAccelEps {
                    let gNMag = abs(gN)
                    let gTanDir = gTan / gTanLen
                    let stickLimit = groundMaterial.muS * gNMag
                    if gTanLen <= stickLimit {
                        let v = body.linearVelocity
                        let vTan = v - normal * simd_dot(v, normal)
                        let downhillSpeed = simd_dot(vTan, gTanDir)
                        if downhillSpeed > 0 {
                            body.linearVelocity -= gTanDir * downhillSpeed
                        }
                    } else {
                        let slideAccelMag = max(gTanLen - groundMaterial.muK * gNMag, 0)
                        if slideAccelMag > 0 {
                            body.linearVelocity += gTanDir * slideAccelMag * dt
                        }
                    }
                }
            }

            body.position = position
            pStore[e] = body
            controller.grounded = isGrounded
            controller.groundedNear = isGroundedNear
            controller.groundNormal = groundNormal ?? SIMD3<Float>(0, 1, 0)
            cStore[e] = controller

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
        let kStore = world.store(KinematicPlatformComponent.self)

        for e in bodies {
            guard var body = pStore[e] else { continue }
            if cStore.contains(e) { continue }
            if kStore.contains(e) { continue }

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
