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
    private let agentSeparationSystem: AgentSeparationSystem?
    private let queryService: CollisionQueryService

    public init(kinematicMoveSystem: KinematicMoveStopSystem,
                agentSeparationSystem: AgentSeparationSystem? = nil,
                queryService: CollisionQueryService) {
        self.kinematicMoveSystem = kinematicMoveSystem
        self.agentSeparationSystem = agentSeparationSystem
        self.queryService = queryService
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        queryService.update(world: world)
        guard let query = queryService.query else { return }
        kinematicMoveSystem.setQuery(query)
        agentSeparationSystem?.setQuery(query)
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

/// Drive simple oscillating move intents (demo).
public final class OscillateMoveSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        let entities = world.query(MoveIntentComponent.self, OscillateMoveComponent.self)
        let mStore = world.store(MoveIntentComponent.self)
        let oStore = world.store(OscillateMoveComponent.self)

        for e in entities {
            guard var intent = mStore[e], var osc = oStore[e] else { continue }
            let axisLen = simd_length(osc.axis)
            let axis = axisLen > 1e-5 ? (osc.axis / axisLen) : SIMD3<Float>(1, 0, 0)
            osc.time += dt
            let phase = osc.time * osc.speed
            let vel = axis * (cos(phase) * osc.amplitude * osc.speed)
            intent.desiredVelocity = SIMD3<Float>(vel.x, 0, vel.z)
            mStore[e] = intent
            oStore[e] = osc
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

private struct PlatformCarryResolver {
    static func computeDelta(position: SIMD3<Float>,
                             controller: CharacterControllerComponent,
                             platformEntities: [Entity],
                             bodies: ComponentStore<PhysicsBodyComponent>,
                             colliders: ComponentStore<ColliderComponent>) -> SIMD3<Float> {
        guard !platformEntities.isEmpty else { return .zero }
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
            guard let pBody = bodies[pe], let pCol = colliders[pe] else { continue }
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
                    if sideDistSq <= sidePushTol * sidePushTol {
                        let dirLen = sqrt(max(sideDistSq, 0))
                        if dirLen > 1e-5 {
                            let dir = SIMD3<Float>(dx / dirLen, 0, dz / dirLen)
                            let moveToward = simd_dot(SIMD3<Float>(pDelta.x, 0, pDelta.z), dir)
                            if moveToward > 0 {
                                pushDelta += SIMD3<Float>(pDelta.x, 0, pDelta.z)
                            }
                        }
                    }
                }
            }
        }

        if simd_length_squared(bestCarry) > 1e-8 {
            return bestCarry
        }
        if simd_length_squared(pushDelta) > 1e-8 {
            return pushDelta
        }
        return .zero
    }

    static func applyPenetrationCorrection(position: inout SIMD3<Float>,
                                           controller: CharacterControllerComponent,
                                           platformEntities: [Entity],
                                           bodies: ComponentStore<PhysicsBodyComponent>,
                                           colliders: ComponentStore<ColliderComponent>) {
        for pe in platformEntities {
            guard let pBody = bodies[pe], let pCol = colliders[pe] else { continue }
            if pBody.bodyType != .kinematic { continue }
            let pDelta = pBody.position - pBody.prevPosition
            if simd_length_squared(pDelta) < 1e-8 { continue }
            guard case .box = pCol.shape else { continue }
            let aabb = ColliderComponent.computeAABB(position: pBody.position,
                                                     rotation: pBody.rotation,
                                                     collider: pCol)
            let capsuleHalf = controller.halfHeight + controller.radius
            let baseY = position.y - capsuleHalf
            let topTol = controller.snapDistance + max(controller.skinWidth, controller.groundSnapSkin) + 0.05
            let onTop = baseY >= aabb.max.y - topTol && baseY <= aabb.max.y + topTol
            if onTop {
                continue
            }
            if let (n, depth) = capsuleBoxPenetrationXZ(center: position,
                                                       halfHeight: controller.halfHeight,
                                                       radius: controller.radius,
                                                       boxMin: aabb.min,
                                                       boxMax: aabb.max) {
                let moveToward = simd_dot(SIMD3<Float>(pDelta.x, 0, pDelta.z), n)
                if moveToward > 0 {
                    position += n * depth
                }
            }
        }
    }

    static func applyPostMovePushOut(position: inout SIMD3<Float>,
                                     body: inout PhysicsBodyComponent,
                                     controller: CharacterControllerComponent,
                                     platformEntities: [Entity],
                                     bodies: ComponentStore<PhysicsBodyComponent>,
                                     colliders: ComponentStore<ColliderComponent>) -> Bool {
        guard !platformEntities.isEmpty else { return false }
        let contactRadius = controller.radius + controller.skinWidth
        let capsuleHalf = controller.halfHeight + controller.radius
        var blocked = false
        for pe in platformEntities {
            guard let pBody = bodies[pe], let pCol = colliders[pe] else { continue }
            if pBody.bodyType != .kinematic { continue }
            guard case .box = pCol.shape else { continue }
            let aabb = ColliderComponent.computeAABB(position: pBody.position,
                                                     rotation: pBody.rotation,
                                                     collider: pCol)
            let baseY = position.y - capsuleHalf
            let topTol = controller.snapDistance + max(controller.skinWidth, controller.groundSnapSkin) + 0.05
            let onTop = baseY >= aabb.max.y - topTol && baseY <= aabb.max.y + topTol
            if onTop {
                continue
            }
            if let (n, depth) = capsuleBoxPenetrationXZ(center: position,
                                                       halfHeight: controller.halfHeight,
                                                       radius: contactRadius,
                                                       boxMin: aabb.min,
                                                       boxMax: aabb.max) {
                position += n * depth
                let vInto = simd_dot(body.linearVelocity, n)
                if vInto < 0 {
                    body.linearVelocity -= n * vInto
                }
                blocked = true
            }
        }
        return blocked
    }

    private static func capsuleBoxPenetrationXZ(center: SIMD3<Float>,
                                                halfHeight: Float,
                                                radius: Float,
                                                boxMin: SIMD3<Float>,
                                                boxMax: SIMD3<Float>) -> (SIMD3<Float>, Float)? {
        let segMin = center.y - halfHeight
        let segMax = center.y + halfHeight
        if segMax < boxMin.y - radius || segMin > boxMax.y + radius {
            return nil
        }
        let cx = center.x
        let cz = center.z
        let closestX = max(boxMin.x, min(cx, boxMax.x))
        let closestZ = max(boxMin.z, min(cz, boxMax.z))
        let dx = cx - closestX
        let dz = cz - closestZ
        let distSq = dx * dx + dz * dz
        if distSq > radius * radius {
            return nil
        }
        if distSq > 1e-6 {
            let dist = sqrt(distSq)
            let n = SIMD3<Float>(dx / dist, 0, dz / dist)
            return (n, radius - dist)
        }
        let left = cx - boxMin.x
        let right = boxMax.x - cx
        let back = cz - boxMin.z
        let front = boxMax.z - cz
        var minDist = left
        var n = SIMD3<Float>(1, 0, 0)
        if right < minDist {
            minDist = right
            n = SIMD3<Float>(-1, 0, 0)
        }
        if back < minDist {
            minDist = back
            n = SIMD3<Float>(0, 0, 1)
        }
        if front < minDist {
            minDist = front
            n = SIMD3<Float>(0, 0, -1)
        }
        let depth = radius - minDist
        if depth <= 0 {
            return nil
        }
        return (n, depth)
    }
}

private struct GroundContactState {
    var grounded: Bool
    var groundedNear: Bool
    var normal: SIMD3<Float>
    var material: SurfaceMaterial
}

private struct GroundContactResolver {
    static func resolveSnap(position: inout SIMD3<Float>,
                            body: inout PhysicsBodyComponent,
                            controller: CharacterControllerComponent,
                            query: CollisionQuery,
                            wasGrounded: Bool,
                            wasGroundedNear: Bool) -> GroundContactState {
        var state = GroundContactState(grounded: false,
                                       groundedNear: false,
                                       normal: SIMD3<Float>(0, 1, 0),
                                       material: .default)
        if controller.snapDistance <= 0 {
            return state
        }

        let down = SIMD3<Float>(0, -1, 0)
        let snapDelta = down * controller.snapDistance
        if let hit = query.capsuleCastGround(from: position,
                                             delta: snapDelta,
                                             radius: controller.radius,
                                             halfHeight: controller.halfHeight,
                                             minNormalY: controller.minGroundDot),
           hit.toi <= controller.snapDistance {
            let baseCenterY = position.y - controller.halfHeight
            let bottomY = baseCenterY - controller.radius
            let groundTol = max(controller.skinWidth, controller.groundSnapSkin)
            let validGroundPoint = hit.position.y <= bottomY + groundTol
            let groundNearThreshold = max(controller.groundSnapSkin, controller.skinWidth)
            let nearGround = hit.toi <= groundNearThreshold
            state.groundedNear = nearGround
            let groundGateVel = body.linearVelocity.y <= 0
            let vInto = simd_dot(body.linearVelocity, hit.normal)
            let groundGateSpeed = vInto >= -controller.groundSnapMaxSpeed
            let groundGateToi = hit.toi <= controller.groundSnapMaxToi
            var canSnap = validGroundPoint && groundGateVel && (nearGround || groundGateSpeed || groundGateToi)
            if wasGroundedNear && hit.toi <= controller.snapDistance {
                canSnap = validGroundPoint
            }
            if validGroundPoint && (nearGround || canSnap) {
                state.grounded = true
                state.normal = hit.triangleNormal
                state.material = hit.material
            }
            if canSnap {
                let rawMove = max(hit.toi - controller.groundSnapSkin, 0)
                var moveDist = rawMove
                if nearGround && moveDist > controller.groundSnapMaxStep {
                    moveDist = controller.groundSnapMaxStep
                }
                position += down * moveDist
                let vIntoSnap = simd_dot(body.linearVelocity, hit.normal)
                if vIntoSnap < 0 {
                    body.linearVelocity -= hit.normal * vIntoSnap
                }
            }
        }

        _ = wasGrounded
        return state
    }

    static func applySlopeFriction(body: inout PhysicsBodyComponent,
                                   controller: CharacterControllerComponent,
                                   gravity: SIMD3<Float>,
                                   dt: Float,
                                   state: GroundContactState) {
        guard state.grounded else { return }
        let normal = simd_normalize(state.normal)
        let gN = simd_dot(gravity, normal)
        let gTan = gravity - normal * gN
        let gTanLen = simd_length(gTan)
        let slopeAccelEps: Float = 0.5
        if gTanLen > slopeAccelEps {
            let gNMag = abs(gN)
            let gTanDir = gTan / gTanLen
            let stickLimit = state.material.muS * gNMag
            if gTanLen <= stickLimit {
                let v = body.linearVelocity
                let vTan = v - normal * simd_dot(v, normal)
                let downhillSpeed = simd_dot(vTan, gTanDir)
                if downhillSpeed > 0 {
                    body.linearVelocity -= gTanDir * downhillSpeed
                }
            } else {
                let slideAccelMag = max(gTanLen - state.material.muK * gNMag, 0)
                if slideAccelMag > 0 {
                    body.linearVelocity += gTanDir * slideAccelMag * dt
                }
            }
        }
    }
}

private struct AgentSweepState {
    let entity: Entity
    let position: SIMD3<Float>
    let velocity: SIMD3<Float>
    let radius: Float
    let halfHeight: Float
    let filter: CollisionFilter
}

private struct CapsuleCapsuleHit {
    let toi: Float
    let normal: SIMD3<Float>
    let other: Entity
}

private struct VelocityGate {
    static func apply(body: inout PhysicsBodyComponent,
                      wasGrounded: Bool,
                      wasGroundedNear: Bool,
                      dt: Float) -> SIMD3<Float> {
        if wasGrounded && wasGroundedNear && body.linearVelocity.y < 0 {
            body.linearVelocity.y = 0
        }
        var remaining = body.linearVelocity * dt
        if wasGrounded && wasGroundedNear && remaining.y < 0 {
            remaining.y = 0
        }
        return remaining
    }
}

private struct AgentSweepSolver {
    static func bestHit(position: SIMD3<Float>,
                        remaining: SIMD3<Float>,
                        remainingLen: Float,
                        baseMoveLen: Float,
                        dt: Float,
                        selfEntity: Entity,
                        selfAgent: AgentCollisionComponent?,
                        selfRadius: Float,
                        halfHeight: Float,
                        selfFilter: CollisionFilter,
                        agentStates: [AgentSweepState],
                        sweep: (SIMD3<Float>, SIMD3<Float>, Float, Float, Entity, SIMD3<Float>, SIMD3<Float>, Float, Float) -> CapsuleCapsuleHit?) -> CapsuleCapsuleHit? {
        guard let selfAgent, selfAgent.isSolid else { return nil }
        var agentHit: CapsuleCapsuleHit?
        let timeScale = baseMoveLen > 1e-6 ? min(remainingLen / baseMoveLen, 1) : 1
        let segmentDt = dt * timeScale
        for other in agentStates {
            if other.entity == selfEntity { continue }
            if !selfFilter.canCollide(with: other.filter) { continue }
            let otherDelta = other.velocity * segmentDt
            if let hit = sweep(position,
                               remaining,
                               selfRadius,
                               halfHeight,
                               other.entity,
                               other.position,
                               otherDelta,
                               other.radius,
                               other.halfHeight) {
                let candidate = CapsuleCapsuleHit(toi: hit.toi,
                                                  normal: hit.normal,
                                                  other: other.entity)
                if agentHit == nil || candidate.toi < agentHit!.toi {
                    agentHit = candidate
                }
            }
        }
        return agentHit
    }
}

private struct SlideResolver {
    struct SlideOptions {
        let allowHorizontalGroundPass: Bool
        let adjustVelocity: Bool
        let useGroundSnapSkinForStatic: Bool
        let allowTriangleNormalGroundLike: Bool

        static let kinematicMove = SlideOptions(allowHorizontalGroundPass: false,
                                                adjustVelocity: true,
                                                useGroundSnapSkinForStatic: true,
                                                allowTriangleNormalGroundLike: true)
        static let agentSeparation = SlideOptions(allowHorizontalGroundPass: true,
                                                  adjustVelocity: false,
                                                  useGroundSnapSkinForStatic: false,
                                                  allowTriangleNormalGroundLike: false)
    }

    enum SlideHit {
        case staticHit(CapsuleCastHit)
        case agentHit(CapsuleCapsuleHit)
    }

    static func selectBestHit(staticHit: CapsuleCastHit?,
                              agentHit: CapsuleCapsuleHit?,
                              controller: CharacterControllerComponent) -> SlideHit? {
        if let sHit = staticHit, let aHit = agentHit {
            let staticSkin = sHit.normal.y >= controller.minGroundDot ? controller.groundSnapSkin : controller.skinWidth
            let staticStop = max(sHit.toi - staticSkin, 0)
            let agentStop = max(aHit.toi, 0)
            if staticStop <= agentStop {
                return .staticHit(sHit)
            }
            return .agentHit(aHit)
        }
        if let sHit = staticHit {
            return .staticHit(sHit)
        }
        if let aHit = agentHit {
            return .agentHit(aHit)
        }
        return nil
    }

    static func resolveHit(remaining: inout SIMD3<Float>,
                           len: Float,
                           hit: SlideHit,
                           controller: CharacterControllerComponent,
                           wasGrounded: Bool,
                           wasGroundedNear: Bool,
                           body: inout PhysicsBodyComponent,
                           position: inout SIMD3<Float>,
                           options: SlideOptions) -> Bool {
        if options.allowHorizontalGroundPass,
           case .staticHit(let sHit) = hit,
           abs(remaining.y) < 1e-5,
           sHit.normal.y >= controller.minGroundDot {
            position += remaining
            remaining = .zero
            return true
        }

        let contactSkin: Float
        var slideNormal: SIMD3<Float>
        let hitToi: Float
        var hitTriNormal: SIMD3<Float> = .zero
        var hitIsStatic = false
        var hitIsGroundLike = false
        switch hit {
        case .staticHit(let sHit):
            hitToi = sHit.toi
            slideNormal = sHit.normal
            hitIsGroundLike = sHit.triangleNormal.y >= controller.minGroundDot
            if options.useGroundSnapSkinForStatic && hitIsGroundLike {
                contactSkin = controller.groundSnapSkin
            } else {
                contactSkin = controller.skinWidth
            }
            hitTriNormal = sHit.triangleNormal
            hitIsStatic = true
        case .agentHit(let aHit):
            hitToi = aHit.toi
            slideNormal = aHit.normal
            contactSkin = 0
        }

        if slideNormal.y < controller.minGroundDot {
            if hitIsStatic && hitIsGroundLike && options.allowTriangleNormalGroundLike {
                slideNormal = hitTriNormal
            }
            if slideNormal.y < controller.minGroundDot {
                slideNormal.y = 0
                let nLen = simd_length(slideNormal)
                if nLen > 1e-5 {
                    slideNormal /= nLen
                } else {
                    position += remaining
                    remaining = .zero
                    return true
                }
            }
        }

        let into = simd_dot(remaining, slideNormal)
        let intoEps = 1e-4 * len
        if into >= -intoEps {
            if wasGroundedNear && hitIsStatic && !hitIsGroundLike && remaining.y < 0 {
                remaining.y = 0
            }
            position += remaining
            remaining = .zero
            return true
        }
        if hitToi <= contactSkin && abs(into) <= intoEps {
            position += remaining
            remaining = .zero
            return true
        }
        if into >= 0 {
            position += remaining
            remaining = .zero
            return true
        }

        let rawMoveDist = max(hitToi - contactSkin, 0)
        var moveDist = rawMoveDist
        if slideNormal.y >= controller.minGroundDot && remaining.y < 0 &&
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
            return true
        }
        remaining = leftover

        if options.adjustVelocity {
            let vInto = simd_dot(body.linearVelocity, slideNormal)
            if vInto < 0 {
                body.linearVelocity -= slideNormal * vInto
            }
        }

        return false
    }
}

/// Kinematic capsule sweep: move & slide with ground snap.
public final class KinematicMoveStopSystem: FixedStepSystem {
    private var query: CollisionQuery?
    private let gravity: SIMD3<Float>

    public init(gravity: SIMD3<Float> = SIMD3<Float>(0, -98.0, 0)) {
        self.gravity = gravity
    }

    public func setQuery(_ query: CollisionQuery) {
        self.query = query
    }

    private func clampInterval(_ start: Float, _ end: Float) -> (Float, Float)? {
        let s = max(start, 0)
        let e = min(end, 1)
        if e < s {
            return nil
        }
        return (s, e)
    }

    private func intervalGreaterEqual(y0: Float, vy: Float, threshold: Float) -> (Float, Float)? {
        let eps: Float = 1e-6
        if abs(vy) < eps {
            return y0 >= threshold ? (0, 1) : nil
        }
        let t = (threshold - y0) / vy
        if vy > 0 {
            return clampInterval(t, 1)
        }
        return clampInterval(0, t)
    }

    private func intervalLessEqual(y0: Float, vy: Float, threshold: Float) -> (Float, Float)? {
        let eps: Float = 1e-6
        if abs(vy) < eps {
            return y0 <= threshold ? (0, 1) : nil
        }
        let t = (threshold - y0) / vy
        if vy > 0 {
            return clampInterval(0, t)
        }
        return clampInterval(t, 1)
    }

    private func earliestRoot(A: Float, B: Float, C: Float, tMin: Float, tMax: Float) -> Float? {
        let eps: Float = 1e-6
        if abs(A) < eps {
            if abs(B) < eps {
                return C <= 0 ? tMin : nil
            }
            let t = -C / B
            return (t >= tMin && t <= tMax) ? t : nil
        }
        let disc = B * B - 4 * A * C
        if disc < 0 {
            return nil
        }
        let sqrtD = sqrt(disc)
        let inv2A = 1 / (2 * A)
        let t0 = (-B - sqrtD) * inv2A
        let t1 = (-B + sqrtD) * inv2A
        let enter = min(t0, t1)
        let exit = max(t0, t1)
        let s = max(enter, tMin)
        let e = min(exit, tMax)
        return e >= s ? s : nil
    }

    private func capsuleCapsuleSeparationY(_ yRel: Float, halfHeightSum: Float) -> Float {
        if yRel > halfHeightSum {
            return yRel - halfHeightSum
        }
        if yRel < -halfHeightSum {
            return yRel + halfHeightSum
        }
        return 0
    }

    private func capsuleCapsuleHitNormal(rel: SIMD3<Float>, halfHeightSum: Float) -> SIMD3<Float> {
        let sepY = capsuleCapsuleSeparationY(rel.y, halfHeightSum: halfHeightSum)
        let sep = SIMD3<Float>(rel.x, sepY, rel.z)
        let lenSq = simd_length_squared(sep)
        if lenSq > 1e-8 {
            return sep / sqrt(lenSq)
        }
        let lateral = SIMD3<Float>(rel.x, 0, rel.z)
        let lateralLenSq = simd_length_squared(lateral)
        if lateralLenSq > 1e-8 {
            return lateral / sqrt(lateralLenSq)
        }
        return SIMD3<Float>(1, 0, 0)
    }

    private func capsuleCapsuleOverlap(rel: SIMD3<Float>, radiusSum: Float, halfHeightSum: Float) -> Bool {
        let sepY = capsuleCapsuleSeparationY(rel.y, halfHeightSum: halfHeightSum)
        let distSq = rel.x * rel.x + rel.z * rel.z + sepY * sepY
        return distSq <= radiusSum * radiusSum
    }

    private func capsuleCapsuleSweep(from: SIMD3<Float>,
                                     delta: SIMD3<Float>,
                                     radius: Float,
                                     halfHeight: Float,
                                     other: Entity,
                                     otherPos: SIMD3<Float>,
                                     otherDelta: SIMD3<Float>,
                                     otherRadius: Float,
                                     otherHalfHeight: Float) -> CapsuleCapsuleHit? {
        let relStart = from - otherPos
        let relDelta = delta - otherDelta
        let rSum = radius + otherRadius
        let hSum = halfHeight + otherHalfHeight
        let relLen = simd_length(relDelta)
        let moveLen = simd_length(delta)

        if relLen < 1e-6 {
            if capsuleCapsuleOverlap(rel: relStart, radiusSum: rSum, halfHeightSum: hSum) {
                let n = capsuleCapsuleHitNormal(rel: relStart, halfHeightSum: hSum)
                return CapsuleCapsuleHit(toi: 0, normal: n, other: other)
            }
            return nil
        }

        let y0 = relStart.y
        let vy = relDelta.y
        let vx = relDelta.x
        let vz = relDelta.z
        let r0x = relStart.x
        let r0z = relStart.z

        var bestT: Float?

        if let upper = intervalGreaterEqual(y0: y0, vy: vy, threshold: hSum) {
            let A = vx * vx + vz * vz + vy * vy
            let B = 2 * (r0x * vx + r0z * vz + (y0 - hSum) * vy)
            let C = r0x * r0x + r0z * r0z + (y0 - hSum) * (y0 - hSum) - rSum * rSum
            if let t = earliestRoot(A: A, B: B, C: C, tMin: upper.0, tMax: upper.1) {
                bestT = t
            }
        }

        if let lower = intervalLessEqual(y0: y0, vy: vy, threshold: -hSum) {
            let A = vx * vx + vz * vz + vy * vy
            let B = 2 * (r0x * vx + r0z * vz + (y0 + hSum) * vy)
            let C = r0x * r0x + r0z * r0z + (y0 + hSum) * (y0 + hSum) - rSum * rSum
            if let t = earliestRoot(A: A, B: B, C: C, tMin: lower.0, tMax: lower.1) {
                if bestT == nil || t < bestT! {
                    bestT = t
                }
            }
        }

        let eps: Float = 1e-6
        if abs(vy) < eps {
            if abs(y0) <= hSum {
                let A = vx * vx + vz * vz
                let B = 2 * (r0x * vx + r0z * vz)
                let C = r0x * r0x + r0z * r0z - rSum * rSum
                if let t = earliestRoot(A: A, B: B, C: C, tMin: 0, tMax: 1) {
                    if bestT == nil || t < bestT! {
                        bestT = t
                    }
                }
            }
        } else {
            let t1 = (hSum - y0) / vy
            let t2 = (-hSum - y0) / vy
            if let overlap = clampInterval(min(t1, t2), max(t1, t2)) {
                let A = vx * vx + vz * vz
                let B = 2 * (r0x * vx + r0z * vz)
                let C = r0x * r0x + r0z * r0z - rSum * rSum
                if let t = earliestRoot(A: A, B: B, C: C, tMin: overlap.0, tMax: overlap.1) {
                    if bestT == nil || t < bestT! {
                        bestT = t
                    }
                }
            }
        }

        guard let tHit = bestT else { return nil }
        let relAtHit = relStart + relDelta * tHit
        let n = capsuleCapsuleHitNormal(rel: relAtHit, halfHeightSum: hSum)
        let toi = tHit * moveLen
        return CapsuleCapsuleHit(toi: toi, normal: n, other: other)
    }

    public func fixedUpdate(world: World, dt: Float) {
        guard let query = query else { return }
        let bodies = world.query(PhysicsBodyComponent.self, CharacterControllerComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)
        let aStore = world.store(AgentCollisionComponent.self)
        let platBodies = world.store(PhysicsBodyComponent.self)
        let platCols = world.store(ColliderComponent.self)
        let platformEntities = world.query(PhysicsBodyComponent.self,
                                           ColliderComponent.self,
                                           KinematicPlatformComponent.self)
        var agentStates: [AgentSweepState] = []
        agentStates.reserveCapacity(bodies.count)
        for e in bodies {
            guard let body = pStore[e], let controller = cStore[e] else { continue }
            guard let agent = aStore[e], agent.isSolid else { continue }
            let radius = agent.radiusOverride ?? controller.radius
            agentStates.append(AgentSweepState(entity: e,
                                               position: body.position,
                                               velocity: body.linearVelocity,
                                               radius: radius,
                                               halfHeight: controller.halfHeight,
                                               filter: agent.filter))
        }
        for e in bodies {
            guard var body = pStore[e], var controller = cStore[e] else { continue }
            if body.bodyType == .static { continue }

            var position = body.position
            let selfAgent = aStore[e]
            let selfRadius = selfAgent?.radiusOverride ?? controller.radius
            let selfFilter = selfAgent?.filter ?? .default
            // Apply platform motion carry/push before character sweep.
            let platformDelta = PlatformCarryResolver.computeDelta(position: position,
                                                                  controller: controller,
                                                                  platformEntities: platformEntities,
                                                                  bodies: platBodies,
                                                                  colliders: platCols)
            let wasGrounded = controller.grounded
            let wasGroundedNear = controller.groundedNear
            var remaining = VelocityGate.apply(body: &body,
                                               wasGrounded: wasGrounded,
                                               wasGroundedNear: wasGroundedNear,
                                               dt: dt)
            if simd_length_squared(platformDelta) > 1e-8 {
                position += platformDelta
                PlatformCarryResolver.applyPenetrationCorrection(position: &position,
                                                                 controller: controller,
                                                                 platformEntities: platformEntities,
                                                                 bodies: platBodies,
                                                                 colliders: platCols)
            }
            var isGrounded = false
            var isGroundedNear = false
            let baseMove = body.linearVelocity * dt
            let baseMoveLen = simd_length(baseMove)
            for _ in 0..<controller.maxSlideIterations {
                let len = simd_length(remaining)
                if len < 1e-6 { break }

                let staticHit = query.capsuleCastBlocking(from: position,
                                                          delta: remaining,
                                                          radius: controller.radius,
                                                          halfHeight: controller.halfHeight)
                let agentHit = AgentSweepSolver.bestHit(position: position,
                                                        remaining: remaining,
                                                        remainingLen: len,
                                                        baseMoveLen: baseMoveLen,
                                                        dt: dt,
                                                        selfEntity: e,
                                                        selfAgent: selfAgent,
                                                        selfRadius: selfRadius,
                                                        halfHeight: controller.halfHeight,
                                                        selfFilter: selfFilter,
                                                        agentStates: agentStates,
                                                        sweep: capsuleCapsuleSweep)

                if let hit = SlideResolver.selectBestHit(staticHit: staticHit,
                                                         agentHit: agentHit,
                                                         controller: controller) {
                    let options = SlideResolver.SlideOptions.kinematicMove
                    let shouldBreak = SlideResolver.resolveHit(remaining: &remaining,
                                                               len: len,
                                                               hit: hit,
                                                               controller: controller,
                                                               wasGrounded: wasGrounded,
                                                               wasGroundedNear: wasGroundedNear,
                                                               body: &body,
                                                               position: &position,
                                                               options: options)
                    if shouldBreak {
                        break
                    }
                } else {
                    position += remaining
                    remaining = .zero
                    break
                }
            }

            let blocked = PlatformCarryResolver.applyPostMovePushOut(position: &position,
                                                                     body: &body,
                                                                     controller: controller,
                                                                     platformEntities: platformEntities,
                                                                     bodies: platBodies,
                                                                     colliders: platCols)
            if blocked {
                remaining = .zero
            }

            let groundState = GroundContactResolver.resolveSnap(position: &position,
                                                                body: &body,
                                                                controller: controller,
                                                                query: query,
                                                                wasGrounded: wasGrounded,
                                                                wasGroundedNear: wasGroundedNear)
            isGrounded = groundState.grounded
            isGroundedNear = groundState.groundedNear

            GroundContactResolver.applySlopeFriction(body: &body,
                                                     controller: controller,
                                                     gravity: gravity,
                                                     dt: dt,
                                                     state: groundState)

            body.position = position
            pStore[e] = body
            controller.grounded = isGrounded
            controller.groundedNear = isGroundedNear
            controller.groundNormal = groundState.grounded ? groundState.normal : SIMD3<Float>(0, 1, 0)
            cStore[e] = controller

        }
    }
}

/// Resolve overlaps between kinematic agents after move & slide.
public final class AgentSeparationSystem: FixedStepSystem {
    private struct Agent {
        var entity: Entity
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var radius: Float
        var halfHeight: Float
        var invWeight: Float
        var filter: CollisionFilter
        var controller: CharacterControllerComponent
    }

    private struct AgentSeparationGrid {
        struct CellCoord: Hashable {
            let x: Int
            let z: Int
        }

        let cellSize: Float
        private(set) var cells: [CellCoord: [Int]]

        init(cellSize: Float, capacity: Int) {
            self.cellSize = cellSize
            self.cells = [:]
            self.cells.reserveCapacity(capacity)
        }

        mutating func rebuild(agents: [Agent]) {
            cells.removeAll(keepingCapacity: true)
            for i in agents.indices {
                let c = cellCoord(for: agents[i].position)
                cells[c, default: []].append(i)
            }
        }

        func cellCoord(for pos: SIMD3<Float>) -> CellCoord {
            let ix = Int(floor(pos.x / cellSize))
            let iz = Int(floor(pos.z / cellSize))
            return CellCoord(x: ix, z: iz)
        }
    }

    private struct AgentSeparationResolver {
        static func resolve(agents: inout [Agent],
                            grid: AgentSeparationGrid,
                            separationMargin: Float,
                            heightMargin: Float,
                            query: CollisionQuery?) {
            for i in agents.indices {
                let a = agents[i]
                let cell = grid.cellCoord(for: a.position)
                for dz in -1...1 {
                    for dx in -1...1 {
                        let neighbor = AgentSeparationGrid.CellCoord(x: cell.x + dx, z: cell.z + dz)
                        guard let list = grid.cells[neighbor] else { continue }
                        for j in list where j > i {
                            if !a.filter.canCollide(with: agents[j].filter) { continue }
                            let b = agents[j]
                            let aMin = a.position.y - a.halfHeight
                            let aMax = a.position.y + a.halfHeight
                            let bMin = b.position.y - b.halfHeight
                            let bMax = b.position.y + b.halfHeight
                            let dx = a.position.x - b.position.x
                            let dz = a.position.z - b.position.z
                            let distSq = dx * dx + dz * dz
                            let skinAllowance = min(a.controller.skinWidth, b.controller.skinWidth)
                            let margin = min(separationMargin, skinAllowance)
                            let minDist = a.radius + b.radius + margin
                            let heightSeparated = aMax < bMin - heightMargin || aMin > bMax + heightMargin
                            if heightSeparated { continue }

                            if distSq >= minDist * minDist {
                                continue
                            }

                            let dist = sqrt(max(distSq, 1e-8))
                            let nx = dx / dist
                            let nz = dz / dist
                            let penetration = minDist - dist
                            let wSum = a.invWeight + b.invWeight
                            if wSum <= 0 {
                                continue
                            }

                            let corr = penetration / wSum
                            var moveA = SIMD3<Float>(nx * corr * a.invWeight, 0, nz * corr * a.invWeight)
                            var moveB = SIMD3<Float>(-nx * corr * b.invWeight, 0, -nz * corr * b.invWeight)
                            let relV = a.velocity - b.velocity
                            let vn = relV.x * nx + relV.z * nz
                            if vn < 0 {
                                let impulse = -vn
                                let scaleA = a.invWeight / wSum
                                let scaleB = b.invWeight / wSum
                                agents[i].velocity.x += nx * impulse * scaleA
                                agents[i].velocity.z += nz * impulse * scaleA
                                agents[j].velocity.x -= nx * impulse * scaleB
                                agents[j].velocity.z -= nz * impulse * scaleB
                            }
                            if let query = query {
                                let eps: Float = 1e-6
                                var blockedA = false
                                var blockedB = false
                                let lenA = simd_length(moveA)
                                if lenA > eps,
                                   let hit = query.capsuleCastBlocking(from: agents[i].position,
                                                                       delta: moveA,
                                                                       radius: a.radius,
                                                                       halfHeight: a.halfHeight),
                                   hit.toi <= a.controller.skinWidth,
                                   hit.normal.y < a.controller.minGroundDot {
                                    blockedA = true
                                }
                                let lenB = simd_length(moveB)
                                if lenB > eps,
                                   let hit = query.capsuleCastBlocking(from: agents[j].position,
                                                                       delta: moveB,
                                                                       radius: b.radius,
                                                                       halfHeight: b.halfHeight),
                                   hit.toi <= b.controller.skinWidth,
                                   hit.normal.y < b.controller.minGroundDot {
                                    blockedB = true
                                }
                                if blockedA && !blockedB {
                                    moveA = .zero
                                    moveB = SIMD3<Float>(-nx * penetration, 0, -nz * penetration)
                                } else if blockedB && !blockedA {
                                    moveB = .zero
                                    moveA = SIMD3<Float>(nx * penetration, 0, nz * penetration)
                                } else if blockedA && blockedB {
                                    continue
                                }
                            }

                            agents[i].position += moveA
                            agents[j].position += moveB
                        }
                    }
                }
            }
        }
    }

    public var iterations: Int
    public var separationMargin: Float
    public var heightMargin: Float
    private var query: CollisionQuery?

    public init(iterations: Int = 2,
                separationMargin: Float = 0.2,
                heightMargin: Float = 0.1) {
        self.iterations = max(1, iterations)
        self.separationMargin = separationMargin
        self.heightMargin = heightMargin
    }

    public func setQuery(_ query: CollisionQuery) {
        self.query = query
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let entities = world.query(PhysicsBodyComponent.self, CharacterControllerComponent.self)
        guard entities.count > 1 else { return }

        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)
        let aStore = world.store(AgentCollisionComponent.self)

        var agents: [Agent] = []
        agents.reserveCapacity(entities.count)
        var originalPositions: [SIMD3<Float>] = []
        originalPositions.reserveCapacity(entities.count)

        var maxRadius: Float = 0
        for e in entities {
            guard let body = pStore[e], let controller = cStore[e] else { continue }
            let agent = aStore[e] ?? AgentCollisionComponent()
            if !agent.isSolid { continue }
            let radius = agent.radiusOverride ?? controller.radius
            let invWeight: Float
            if agent.massWeight > 0 {
                invWeight = 1.0 / agent.massWeight
            } else {
                invWeight = 0
            }
            maxRadius = max(maxRadius, radius)
            agents.append(Agent(entity: e,
                                position: body.position,
                                velocity: body.linearVelocity,
                                radius: radius,
                                halfHeight: controller.halfHeight,
                                invWeight: invWeight,
                                filter: agent.filter,
                                controller: controller))
            originalPositions.append(body.position)
        }

        guard agents.count > 1 else { return }

        let cellSize = max(maxRadius * 2 + separationMargin, 0.001)
        var grid = AgentSeparationGrid(cellSize: cellSize, capacity: agents.count * 2)

        for _ in 0..<iterations {
            grid.rebuild(agents: agents)
            AgentSeparationResolver.resolve(agents: &agents,
                                            grid: grid,
                                            separationMargin: separationMargin,
                                            heightMargin: heightMargin,
                                            query: query)
        }

        for idx in agents.indices {
            let agent = agents[idx]
            guard var body = pStore[agent.entity] else { continue }
            var position = agent.position

            if let query = query {
                let start = originalPositions[idx]
                let delta = position - start
                let len = simd_length(delta)
                var moved = false
                if len > 1e-6 {
                    moved = true
                    let slideIterations = 2
                    var remaining = delta
                    position = start
                    for _ in 0..<slideIterations {
                        let segLen = simd_length(remaining)
                        if segLen < 1e-6 { break }
                        if let hit = query.capsuleCastBlocking(from: position,
                                                               delta: remaining,
                                                               radius: agent.radius,
                                                               halfHeight: agent.halfHeight) {
                            let options = SlideResolver.SlideOptions.agentSeparation
                            let done = SlideResolver.resolveHit(remaining: &remaining,
                                                                len: segLen,
                                                                hit: .staticHit(hit),
                                                                controller: agent.controller,
                                                                wasGrounded: false,
                                                                wasGroundedNear: false,
                                                                body: &body,
                                                                position: &position,
                                                                options: options)
                            if done { break }
                        } else {
                            position += remaining
                            remaining = .zero
                            break
                        }
                    }
                }

                if moved && body.linearVelocity.y <= 0 {
                    var controller = agent.controller
                    if controller.snapDistance > 0 {
                        let down = SIMD3<Float>(0, -1, 0)
                        let snapDelta = down * controller.snapDistance
                        if let hit = query.capsuleCastGround(from: position,
                                                             delta: snapDelta,
                                                             radius: agent.radius,
                                                             halfHeight: agent.halfHeight,
                                                             minNormalY: controller.minGroundDot),
                           hit.toi <= controller.snapDistance {
                            let rawMove = max(hit.toi - controller.groundSnapSkin, 0)
                            let moveDist = min(rawMove, controller.groundSnapMaxStep)
                            position += down * moveDist
                            controller.grounded = true
                            controller.groundedNear = hit.toi <= max(controller.groundSnapSkin, controller.skinWidth)
                            controller.groundNormal = hit.triangleNormal
                            cStore[agent.entity] = controller
                        }
                    }
                }
            }

            body.position = position
            body.linearVelocity = agents[idx].velocity
            pStore[agent.entity] = body
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
