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

private func isActive(_ e: Entity, _ active: ActiveChunkComponent?) -> Bool {
    active?.activeEntityIDs.contains(e.id) ?? true
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in entities {
            if !isActive(e, active) { continue }
            guard var t = tStore[e], var p = pStore[e], var k = kStore[e] else { continue }
            if p.bodyType == .static { continue }

            let axisLen = simd_length(k.axis)
            let axis = axisLen > 1e-4 ? k.axis / axisLen : SIMD3<Float>(0, 1, 0)
            k.time += dt
            let offset = sin(k.time * k.speed + k.phase) * k.amplitude
            let newPos = k.origin + axis * offset

            t.translation = newPos
            p.position = d3(newPos)
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
    private let services: SceneServices

    public init(kinematicMoveSystem: KinematicMoveStopSystem,
                agentSeparationSystem: AgentSeparationSystem? = nil,
                services: SceneServices) {
        self.kinematicMoveSystem = kinematicMoveSystem
        self.agentSeparationSystem = agentSeparationSystem
        self.services = services
    }

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let queryService: CollisionQueryService = services.resolve() ?? services.collisionQuery
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }
        queryService.update(world: world, activeEntityIDs: active?.activeStaticEntityIDs)
        guard let query = queryService.query else { return }
        query.resetStats()
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in bodies {
            if !isActive(e, active) { continue }
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in bodies {
            if !isActive(e, active) { continue }
            guard var body = pStore[e] else { continue }
            guard let intent = mStore[e] else { continue }
            if body.bodyType == .dynamic || body.bodyType == .kinematic {
                let move = mvStore[e] ?? MovementComponent()
                if cStore.contains(e) {
                    let target = SIMD3<Double>(Double(intent.desiredVelocity.x), 0, Double(intent.desiredVelocity.z))
                    let current = SIMD3<Double>(body.linearVelocity.x, 0, body.linearVelocity.z)
                    let accel = simd_length(target) >= simd_length(current) ? move.maxAcceleration : move.maxDeceleration
                    let next = approachVecD(current: current, target: target, maxDelta: Double(accel) * Double(dt))
                    body.linearVelocity = SIMD3<Double>(next.x, body.linearVelocity.y, next.z)
                } else {
                    let target = d3(intent.desiredVelocity)
                    let current = body.linearVelocity
                    let accel = simd_length(target) >= simd_length(current) ? move.maxAcceleration : move.maxDeceleration
                    body.linearVelocity = approachVecD(current: current,
                                                       target: target,
                                                       maxDelta: Double(accel) * Double(dt))
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

/// Switch between idle and walk motion profiles based on horizontal speed.
public final class LocomotionProfileSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let entities = world.query(LocomotionProfileComponent.self,
                                   MotionProfileComponent.self,
                                   PhysicsBodyComponent.self,
                                   CharacterControllerComponent.self)
        guard !entities.isEmpty else { return }

        let lStore = world.store(LocomotionProfileComponent.self)
        let mStore = world.store(MotionProfileComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let cStore = world.store(CharacterControllerComponent.self)
        let wStore = world.store(WorldPositionComponent.self)
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        func cycleDuration(for profile: MotionProfile) -> Float {
            max(profile.phase?.cycleDuration ?? profile.duration, 0.001)
        }

        func groundedNextState(current: LocomotionState,
                               speed: Float,
                               locomotion: LocomotionProfileComponent) -> LocomotionState {
            let groundedState: LocomotionState = current == .falling ? .idle : current
            switch groundedState {
            case .idle:
                if speed >= locomotion.runEnterSpeed {
                    return .run
                } else if speed >= locomotion.idleExitSpeed {
                    return .walk
                }
                return .idle
            case .walk:
                if speed >= locomotion.runEnterSpeed {
                    return .run
                } else if speed < locomotion.idleEnterSpeed {
                    return .idle
                }
                return .walk
            case .run:
                if speed < locomotion.runExitSpeed {
                    return speed < locomotion.idleEnterSpeed ? .idle : .walk
                }
                return .run
            case .falling:
                return .falling
            }
        }

        for e in entities {
            if !isActive(e, active) { continue }
            guard var locomotion = lStore[e],
                  var profile = mStore[e],
                  let body = pStore[e],
                  let controller = cStore[e] else { continue }
            let worldY: Double = {
                if let w = wStore[e] {
                    return WorldPosition.toWorld(chunk: w.chunk, local: w.local).y
                }
                return body.position.y
            }()
            let speed = Float(simd_length(SIMD3<Double>(body.linearVelocity.x, 0, body.linearVelocity.z)))
            let isAirborne = !controller.groundedNear
            let nextState: LocomotionState
            if isAirborne {
                if locomotion.wasGroundedNear {
                    locomotion.fallStartWorldY = worldY
                }
                let drop = locomotion.fallStartWorldY - worldY
                let highFall = drop >= Double(locomotion.fallMinDropHeight)
                if locomotion.state == .falling || highFall {
                    nextState = .falling
                } else {
                    nextState = groundedNextState(current: locomotion.state,
                                                  speed: speed,
                                                  locomotion: locomotion)
                }
            } else {
                locomotion.fallStartWorldY = worldY
                nextState = groundedNextState(current: locomotion.state,
                                              speed: speed,
                                              locomotion: locomotion)
            }

            if nextState != locomotion.state {
                let fromState = locomotion.state
                let fromCycle: Float
                let fromTime: Float
                switch fromState {
                case .idle:
                    fromCycle = cycleDuration(for: locomotion.idleProfile)
                    fromTime = locomotion.idleTime
                case .walk:
                    fromCycle = cycleDuration(for: locomotion.walkProfile)
                    fromTime = locomotion.walkTime
                case .run:
                    fromCycle = cycleDuration(for: locomotion.runProfile)
                    fromTime = locomotion.runTime
                case .falling:
                    fromCycle = cycleDuration(for: locomotion.fallProfile)
                    fromTime = locomotion.fallTime
                }
                let fromPhase = max(0, min(fromTime / fromCycle, 1))
                let toCycle: Float
                switch nextState {
                case .idle:
                    toCycle = cycleDuration(for: locomotion.idleProfile)
                    locomotion.idleTime = fromPhase * toCycle
                case .walk:
                    toCycle = cycleDuration(for: locomotion.walkProfile)
                    locomotion.walkTime = fromPhase * toCycle
                case .run:
                    toCycle = cycleDuration(for: locomotion.runProfile)
                    locomotion.runTime = fromPhase * toCycle
                case .falling:
                    toCycle = cycleDuration(for: locomotion.fallProfile)
                    locomotion.fallTime = fromPhase * toCycle
                }

                locomotion.fromState = locomotion.state
                locomotion.state = nextState
                locomotion.isBlending = true
                locomotion.blendT = 0
                if nextState == .idle {
                    locomotion.idleInertia = 1.0
                }
            }

            switch locomotion.state {
            case .idle:
                profile.time = locomotion.idleTime
            case .walk:
                profile.time = locomotion.walkTime
            case .run:
                profile.time = locomotion.runTime
            case .falling:
                profile.time = locomotion.fallTime
            }
            locomotion.wasGroundedNear = controller.groundedNear
            lStore[e] = locomotion
            mStore[e] = profile
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

private func approachVecD(current: SIMD3<Double>, target: SIMD3<Double>, maxDelta: Double) -> SIMD3<Double> {
    let delta = target - current
    let len = simd_length(delta)
    if len <= maxDelta || len < 0.00001 {
        return target
    }
    return current + delta / len * maxDelta
}

private func d3(_ v: SIMD3<Float>) -> SIMD3<Double> {
    SIMD3<Double>(Double(v.x), Double(v.y), Double(v.z))
}

private func f3(_ v: SIMD3<Double>) -> SIMD3<Float> {
    SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in entities {
            if !isActive(e, active) { continue }
            guard var body = pStore[e],
                  var intent = mStore[e],
                  var controller = cStore[e] else { continue }
            if intent.jumpRequested && controller.grounded {
                body.linearVelocity.y = Double(jumpSpeed)
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in bodies {
            if !isActive(e, active) { continue }
            guard var body = pStore[e] else { continue }
            if body.bodyType != .dynamic { continue }
            if let controller = cStore[e], controller.grounded, controller.groundedNear {
                continue
            }
            body.linearVelocity += d3(gravity) * Double(dt)
            pStore[e] = body
        }
    }
}

private struct PlatformCarry {
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
            let pDelta = pBody.positionF - pBody.prevPositionF
            if simd_length_squared(pDelta) < 1e-8 { continue }

            let aabb = ColliderComponent.computeAABB(position: pBody.positionF,
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
}

private struct PlatformPushOut {
    static func applyPenetrationCorrection(position: inout SIMD3<Float>,
                                           controller: CharacterControllerComponent,
                                           platformEntities: [Entity],
                                           bodies: ComponentStore<PhysicsBodyComponent>,
                                           colliders: ComponentStore<ColliderComponent>) {
        for pe in platformEntities {
            guard let pBody = bodies[pe], let pCol = colliders[pe] else { continue }
            if pBody.bodyType != .kinematic { continue }
            let pDelta = pBody.positionF - pBody.prevPositionF
            if simd_length_squared(pDelta) < 1e-8 { continue }
            guard case .box = pCol.shape else { continue }
            let aabb = ColliderComponent.computeAABB(position: pBody.positionF,
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
            let aabb = ColliderComponent.computeAABB(position: pBody.positionF,
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
                let nD = d3(n)
                let vInto = simd_dot(body.linearVelocity, nD)
                if vInto < 0 {
                    body.linearVelocity -= nD * vInto
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

private struct DepenetrationResolver {
    static func resolve(position: inout SIMD3<Float>,
                        body: inout PhysicsBodyComponent,
                        controller: inout CharacterControllerComponent,
                        radius: Float,
                        halfHeight: Float,
                        skinWidth: Float,
                        query: CollisionQuery?,
                        cachePolicy: inout any ContactCachePolicy,
                        iterations: Int = 4,
                        debugLabel: String = "") -> SIMD3<Float>? {
        guard let query else { return nil }
        let slop = max(skinWidth * 0.5, 0.001)
        var didResolve = false
        var normalSum = SIMD3<Float>(repeating: 0)
        var normalWeight: Float = 0
        for _ in 0..<iterations {
            let hits = query.capsuleOverlapAll(from: position,
                                               radius: radius,
                                               halfHeight: halfHeight,
                                               maxHits: 8)
            if hits.isEmpty {
                break
            }
            let sortedHits = hits.sorted { $0.depth > $1.depth }
            guard let deepest = sortedHits.first else {
                break
            }
            let sideContact = deepest.normal.y < controller.minGroundDot
            let useCount = sideContact ? 1 : min(2, sortedHits.count)
            var maxDepth = deepest.depth
            var frameNormal = SIMD3<Float>(repeating: 0)
            for hit in sortedHits.prefix(useCount) {
                maxDepth = max(maxDepth, hit.depth)
                var n = hit.normal
                if let cached = cachePolicy.cachedNormal(controller: controller,
                                                         triangleIndex: hit.triangleIndex) {
                    if simd_dot(cached, n) < 0 {
                        n = -n
                    }
                    n = cached
                }
                frameNormal += n * hit.depth
                cachePolicy.record(controller: &controller,
                                   triangleIndex: hit.triangleIndex,
                                   normal: n,
                                   isSideContact: hit.normal.y < controller.minGroundDot)
            }
            let frameNormalLen = simd_length(frameNormal)
            let depenNormal = frameNormalLen > 1e-6 ? frameNormal / frameNormalLen : frameNormal
            var push = sideContact ? max(maxDepth, 0) : max(maxDepth + slop, 0)
            if sideContact {
                push = min(push, skinWidth)
            }
            if push <= 1e-6 { break }
            position += depenNormal * push
            let depenNormalD = d3(depenNormal)
            let vInto = simd_dot(body.linearVelocity, depenNormalD)
            if vInto < 0 {
                body.linearVelocity -= depenNormalD * vInto
            }
            didResolve = true
            normalSum += depenNormal * maxDepth
            normalWeight += maxDepth
        }
        if !didResolve {
            return nil
        }
        if normalWeight > 1e-6 {
            return simd_normalize(normalSum / normalWeight)
        }
        return simd_normalize(normalSum)
    }
}

private struct GroundContactState {
    var grounded: Bool
    var groundedNear: Bool
    var normal: SIMD3<Float>
    var material: SurfaceMaterial
    var triangleIndex: Int
}

private struct GroundProbeResult {
    var state: GroundContactState
    var canSnap: Bool
    var nearGround: Bool
    var hit: CapsuleCastHit?
}

private struct GroundProbe {
    static func resolve(position: SIMD3<Float>,
                        body: PhysicsBodyComponent,
                        controller: CharacterControllerComponent,
                        query: CollisionQuery,
                        wasGrounded: Bool,
                        wasGroundedNear: Bool,
                        prevNormal: SIMD3<Float>,
                        prevTriangleIndex: Int) -> GroundProbeResult {
        var state = GroundContactState(grounded: false,
                                       groundedNear: false,
                                       normal: SIMD3<Float>(0, 1, 0),
                                       material: .default,
                                       triangleIndex: -1)
        if controller.snapDistance <= 0 {
            return GroundProbeResult(state: state, canSnap: false, nearGround: false, hit: nil)
        }

        let down = SIMD3<Float>(0, -1, 0)
        let snapDelta = down * controller.snapDistance
        query.resetStats()
        let centerHit = query.capsuleCastGround(from: position,
                                                delta: snapDelta,
                                                radius: controller.radius,
                                                halfHeight: controller.halfHeight,
                                                minNormalY: controller.minGroundDot)
        guard let centerHit,
              centerHit.toi <= controller.snapDistance else {
            return GroundProbeResult(state: state, canSnap: false, nearGround: false, hit: nil)
        }

        let baseCenterY = position.y - controller.halfHeight
        let bottomY = baseCenterY - controller.radius
        let groundTol = max(controller.skinWidth, controller.groundSnapSkin)
        let validGroundPoint = centerHit.position.y <= bottomY + groundTol
        let groundNearThreshold = max(controller.groundSnapSkin, controller.skinWidth)
        let nearGround = centerHit.toi <= groundNearThreshold
        state.groundedNear = nearGround
        let groundGateVel = body.linearVelocity.y <= 0
        let vInto = simd_dot(body.linearVelocity, d3(centerHit.normal))
        let groundGateSpeed = vInto >= -Double(controller.groundSnapMaxSpeed)
        let groundGateToi = centerHit.toi <= controller.groundSnapMaxToi
        var canSnap = validGroundPoint && groundGateVel && (nearGround || groundGateSpeed || groundGateToi)
        if wasGroundedNear && centerHit.toi <= controller.snapDistance {
            canSnap = validGroundPoint
        }

        if validGroundPoint && (nearGround || canSnap) {
            state.grounded = true
            state.material = centerHit.material
            state.triangleIndex = centerHit.triangleIndex

            var normalSum = centerHit.triangleNormal
            let flatDot: Float = 0.98
            if centerHit.triangleNormal.y < flatDot && (wasGroundedNear || nearGround) {
                let offset = controller.radius * 0.6
                let sampleOffsets: [SIMD2<Float>] = [
                    SIMD2<Float>(offset, 0),
                    SIMD2<Float>(-offset, 0),
                    SIMD2<Float>(0, offset),
                    SIMD2<Float>(0, -offset)
                ]
                let combineTol = max(controller.groundSnapSkin, controller.skinWidth, 0.05)
                for offset in sampleOffsets {
                    let samplePos = position + SIMD3<Float>(offset.x, 0, offset.y)
                    query.resetStats()
                    let hit = query.capsuleCastGround(from: samplePos,
                                                      delta: snapDelta,
                                                      radius: controller.radius,
                                                      halfHeight: controller.halfHeight,
                                                      minNormalY: controller.minGroundDot)
                    if let hit,
                       hit.toi <= centerHit.toi + combineTol {
                        if simd_dot(hit.triangleNormal, centerHit.triangleNormal) > 0.98 {
                            normalSum += hit.triangleNormal
                        }
                    }
                }
            }
            let nLen = simd_length(normalSum)
            state.normal = nLen > 1e-6 ? normalSum / nLen : centerHit.triangleNormal
        }

        if state.grounded && wasGroundedNear {
            let dotN = simd_dot(prevNormal, state.normal)
            if dotN > 0.9 {
                let blend: Float = 0.2
                let smoothed = simd_normalize(prevNormal * (1 - blend) + state.normal * blend)
                state.normal = smoothed
            }
        }
        if state.grounded && state.material.flattenGround {
            state.normal = SIMD3<Float>(0, 1, 0)
        }

        _ = wasGrounded
        _ = prevTriangleIndex
        return GroundProbeResult(state: state, canSnap: canSnap, nearGround: nearGround, hit: centerHit)
    }
}

private struct GroundSnap {
    static func apply(position: inout SIMD3<Float>,
                      body: inout PhysicsBodyComponent,
                      controller: CharacterControllerComponent,
                      result: GroundProbeResult) {
        guard result.canSnap, let centerHit = result.hit else { return }
        let down = SIMD3<Float>(0, -1, 0)
        let rawMove = max(centerHit.toi - controller.groundSnapSkin, 0)
        var moveDist = rawMove
        if result.nearGround && moveDist > controller.groundSnapMaxStep {
            moveDist = controller.groundSnapMaxStep
        }
        position += down * moveDist
        let vIntoSnap = simd_dot(body.linearVelocity, d3(centerHit.normal))
        if vIntoSnap < 0 {
            body.linearVelocity -= d3(centerHit.normal) * vIntoSnap
        }
    }
}

private struct SlopeFriction {
    static func apply(body: inout PhysicsBodyComponent,
                      controller: inout CharacterControllerComponent,
                      gravity: SIMD3<Float>,
                      dt: Float,
                      state: GroundContactState) {
        guard state.grounded else {
            controller.groundSliding = false
            return
        }
        let normal = simd_normalize(state.normal)
        if normal.y > 0.98 {
            controller.groundTransitionFrames = 0
            controller.groundSliding = false
            return
        }
        if controller.groundTransitionFrames > 0 {
            controller.groundTransitionFrames -= 1
            controller.groundSliding = false
            return
        }
        let gN = simd_dot(gravity, normal)
        let gTan = gravity - normal * gN
        let gTanLen = simd_length(gTan)
        let slopeAccelEps: Float = 0.5
        if gTanLen > slopeAccelEps {
            let gNMag = abs(gN)
            let gTanDir = gTan / gTanLen
            let gTanDirD = d3(gTanDir)
            let normalD = d3(normal)
            let stickLimit = state.material.muS * gNMag
            let enterSlide = gTanLen > stickLimit * 1.05
            let exitSlide = gTanLen < stickLimit * 0.9
            if controller.groundSliding {
                if exitSlide {
                    controller.groundSliding = false
                }
            } else if enterSlide {
                controller.groundSliding = true
            }

            if !controller.groundSliding && gTanLen <= stickLimit {
                let v = body.linearVelocity
                let vTan = v - normalD * simd_dot(v, normalD)
                let downhillSpeed = simd_dot(vTan, gTanDirD)
                if downhillSpeed > 0 {
                    body.linearVelocity -= gTanDirD * downhillSpeed
                }
            } else {
                let slideAccelMag = max(gTanLen - state.material.muK * gNMag, 0)
                if slideAccelMag > 0 {
                    body.linearVelocity += gTanDirD * Double(slideAccelMag) * Double(dt)
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
        var remaining = body.linearVelocity * Double(dt)
        if wasGrounded && wasGroundedNear && remaining.y < 0 {
            remaining.y = 0
        }
        return f3(remaining)
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

public protocol ContactCachePolicy {
    mutating func decay(controller: inout CharacterControllerComponent)
    func cachedNormal(controller: CharacterControllerComponent, triangleIndex: Int) -> SIMD3<Float>?
    mutating func record(controller: inout CharacterControllerComponent,
                         triangleIndex: Int,
                         normal: SIMD3<Float>,
                         isSideContact: Bool)
}

public struct DefaultContactCachePolicy: ContactCachePolicy {
    public init() {}

    public mutating func decay(controller: inout CharacterControllerComponent) {
        if controller.sideContactFrames > 0 {
            controller.sideContactFrames -= 1
        }
        if controller.contactManifoldFrames > 0 {
            controller.contactManifoldFrames -= 1
            if controller.contactManifoldFrames == 0 {
                ContactManifoldCache.reset(controller: &controller)
                controller.sideContactNormal = .zero
            }
        }
    }

    public func cachedNormal(controller: CharacterControllerComponent, triangleIndex: Int) -> SIMD3<Float>? {
        ContactManifoldCache.normalFor(controller: controller, triangleIndex: triangleIndex)
    }

    public mutating func record(controller: inout CharacterControllerComponent,
                                triangleIndex: Int,
                                normal: SIMD3<Float>,
                                isSideContact: Bool) {
        ContactManifoldCache.update(controller: &controller,
                                    triangleIndex: triangleIndex,
                                    normal: normal)
        if isSideContact {
            controller.sideContactNormal = simd_normalize(normal)
            controller.sideContactFrames = 3
        }
    }
}

private struct SideContactOnlyCachePolicy: ContactCachePolicy {
    mutating func decay(controller: inout CharacterControllerComponent) {
        var policy = DefaultContactCachePolicy()
        policy.decay(controller: &controller)
    }

    func cachedNormal(controller: CharacterControllerComponent, triangleIndex: Int) -> SIMD3<Float>? {
        ContactManifoldCache.normalFor(controller: controller, triangleIndex: triangleIndex)
    }

    mutating func record(controller: inout CharacterControllerComponent,
                         triangleIndex: Int,
                         normal: SIMD3<Float>,
                         isSideContact: Bool) {
        guard isSideContact else { return }
        ContactManifoldCache.update(controller: &controller,
                                    triangleIndex: triangleIndex,
                                    normal: normal)
        controller.sideContactNormal = simd_normalize(normal)
        controller.sideContactFrames = 3
    }
}

private struct ContactManifoldCache {
    static let maxCount: Int = 4
    static let maxFrames: Int = 8

    static func reset(controller: inout CharacterControllerComponent) {
        controller.contactManifoldTriangles.removeAll(keepingCapacity: true)
        controller.contactManifoldNormals.removeAll(keepingCapacity: true)
        controller.contactManifoldFrames = 0
    }

    static func normalFor(controller: CharacterControllerComponent,
                          triangleIndex: Int) -> SIMD3<Float>? {
        for (i, idx) in controller.contactManifoldTriangles.enumerated() where idx == triangleIndex {
            return controller.contactManifoldNormals[i]
        }
        return nil
    }

    static func update(controller: inout CharacterControllerComponent,
                       triangleIndex: Int,
                       normal: SIMD3<Float>) {
        var n = normal
        if simd_length_squared(n) < 1e-8 {
            return
        }
        controller.contactManifoldFrames = maxFrames
        if let i = controller.contactManifoldTriangles.firstIndex(of: triangleIndex) {
            let cached = controller.contactManifoldNormals[i]
            if simd_dot(cached, n) < 0 {
                n = -n
            }
            let blend: Float = 0.25
            let combined = simd_normalize(cached * (1 - blend) + n * blend)
            controller.contactManifoldNormals[i] = combined
            controller.sideContactNormal = combined
            return
        }

        if controller.contactManifoldTriangles.count >= maxCount {
            controller.contactManifoldTriangles.removeLast()
            controller.contactManifoldNormals.removeLast()
        }
        controller.contactManifoldTriangles.insert(triangleIndex, at: 0)
        controller.contactManifoldNormals.insert(simd_normalize(n), at: 0)
        controller.sideContactNormal = controller.contactManifoldNormals[0]
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

    static func resolveHit(remaining: inout SIMD3<Float>,
                           len: Float,
                           hit: SlideHit,
                           controller: CharacterControllerComponent,
                           wasGrounded: Bool,
                           wasGroundedNear: Bool,
                           body: inout PhysicsBodyComponent,
                           position: inout SIMD3<Float>,
                           options: SlideOptions,
                           cachedSideNormal: SIMD3<Float>? = nil,
                           debugLabel: String = "") -> Bool {
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

        if hitIsStatic && slideNormal.y < controller.minGroundDot && controller.sideContactFrames > 0 {
            if let cached = cachedSideNormal {
                var cachedN = cached
                let dotC = simd_dot(cachedN, slideNormal)
                if dotC < 0 {
                    cachedN = -cachedN
                }
                slideNormal = cachedN
            } else {
                let cached = controller.sideContactNormal
                let cachedLen = simd_length_squared(cached)
                if cachedLen > 1e-6 {
                    let cachedN = cached / sqrt(cachedLen)
                    let dotC = simd_dot(cachedN, slideNormal)
                    if abs(dotC) > 0.5 {
                        slideNormal = dotC >= 0 ? cachedN : -cachedN
                    }
                }
            }
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
        let effectiveSkin: Float
        if hitToi <= contactSkin && into < -intoEps {
            effectiveSkin = min(contactSkin, hitToi * 0.5)
        } else {
            effectiveSkin = contactSkin
        }
        let stickyThreshold = contactSkin * 0.1
        if hitToi <= stickyThreshold && into < -intoEps {
            remaining -= slideNormal * into
            return false
        }
        if into >= -intoEps {
            if wasGroundedNear && hitIsStatic && !hitIsGroundLike && remaining.y < 0 {
                remaining.y = 0
            }
            position += remaining
            remaining = .zero
            return true
        }
        if hitToi <= effectiveSkin && abs(into) <= intoEps {
            position += remaining
            remaining = .zero
            return true
        }
        if into >= 0 {
            position += remaining
            remaining = .zero
            return true
        }

        let rawMoveDist = max(hitToi - effectiveSkin, 0)
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
            let vInto = simd_dot(body.linearVelocity, d3(slideNormal))
            if vInto < 0 {
                body.linearVelocity -= d3(slideNormal) * vInto
            }
        }

        return false
    }
}

private struct HitSelector {
    static func selectBestHit(staticHit: CapsuleCastHit?,
                              agentHit: CapsuleCapsuleHit?,
                              controller: CharacterControllerComponent) -> SlideResolver.SlideHit? {
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
}

/// Kinematic capsule sweep: move & slide with ground snap.
public final class KinematicMoveStopSystem: FixedStepSystem {
    private var query: CollisionQuery?
    private let gravity: SIMD3<Float>
    private var contactCachePolicy: any ContactCachePolicy

    public init(gravity: SIMD3<Float> = SIMD3<Float>(0, -98.0, 0),
                contactCachePolicy: any ContactCachePolicy = DefaultContactCachePolicy()) {
        self.gravity = gravity
        self.contactCachePolicy = contactCachePolicy
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

    private func collectAgentStates(bodies: [Entity],
                                    pStore: ComponentStore<PhysicsBodyComponent>,
                                    cStore: ComponentStore<CharacterControllerComponent>,
                                    aStore: ComponentStore<AgentCollisionComponent>,
                                    active: ActiveChunkComponent?) -> [AgentSweepState] {
        var agentStates: [AgentSweepState] = []
        agentStates.reserveCapacity(bodies.count)
        for e in bodies {
            if !isActive(e, active) { continue }
            guard let body = pStore[e], let controller = cStore[e] else { continue }
            guard let agent = aStore[e], agent.isSolid else { continue }
            let radius = agent.radiusOverride ?? controller.radius
            agentStates.append(AgentSweepState(entity: e,
                                               position: body.positionF,
                                               velocity: body.linearVelocityF,
                                               radius: radius,
                                               halfHeight: controller.halfHeight,
                                               filter: agent.filter))
        }
        return agentStates
    }

    private func decayContactCache(controller: inout CharacterControllerComponent,
                                   cachePolicy: inout any ContactCachePolicy) {
        cachePolicy.decay(controller: &controller)
    }

    private func applyPlatformDelta(position: inout SIMD3<Float>,
                                    controller: CharacterControllerComponent,
                                    platformEntities: [Entity],
                                    platBodies: ComponentStore<PhysicsBodyComponent>,
                                    platCols: ComponentStore<ColliderComponent>) {
        let platformDelta = PlatformCarry.computeDelta(position: position,
                                                       controller: controller,
                                                       platformEntities: platformEntities,
                                                       bodies: platBodies,
                                                       colliders: platCols)
        if simd_length_squared(platformDelta) > 1e-8 {
            position += platformDelta
        }
    }

    private func applyPreSweepDepenetration(position: inout SIMD3<Float>,
                                            body: inout PhysicsBodyComponent,
                                            controller: inout CharacterControllerComponent,
                                            remaining: inout SIMD3<Float>,
                                            query: CollisionQuery,
                                            cachePolicy: inout any ContactCachePolicy,
                                            entity: Entity) {
        if let depenNormal = DepenetrationResolver.resolve(position: &position,
                                                           body: &body,
                                                           controller: &controller,
                                                           radius: controller.radius,
                                                           halfHeight: controller.halfHeight,
                                                           skinWidth: controller.skinWidth,
                                                           query: query,
                                                           cachePolicy: &cachePolicy,
                                                           debugLabel: "pre-sweep \(entity.id)") {
            let into = simd_dot(remaining, depenNormal)
            if into < 0 {
                remaining -= depenNormal * into
            }
        }
    }

    private func resolveKinematicSweep(entity: Entity,
                                       position: inout SIMD3<Float>,
                                       remaining: inout SIMD3<Float>,
                                       body: inout PhysicsBodyComponent,
                                       controller: inout CharacterControllerComponent,
                                       wasGrounded: Bool,
                                       wasGroundedNear: Bool,
                                       selfAgent: AgentCollisionComponent?,
                                       selfRadius: Float,
                                       selfFilter: CollisionFilter,
                                       agentStates: [AgentSweepState],
                                       cachePolicy: inout any ContactCachePolicy,
                                       query: CollisionQuery,
                                       dt: Float) {
        let baseMove = body.linearVelocityF * dt
        let baseMoveLen = simd_length(baseMove)
        var lastSlideNormal: SIMD3<Float>? = nil
        for _ in 0..<controller.maxSlideIterations {
            let len = simd_length(remaining)
            if len < 1e-6 { break }

            var staticHit = query.capsuleCastBlocking(from: position,
                                                      delta: remaining,
                                                      radius: controller.radius,
                                                      halfHeight: controller.halfHeight)
            if var sHit = staticHit,
               sHit.normal.y < controller.minGroundDot,
               controller.sideContactFrames > 0,
               let cached = cachePolicy.cachedNormal(controller: controller,
                                                     triangleIndex: sHit.triangleIndex) {
                var cachedN = cached
                if simd_dot(cachedN, sHit.normal) < 0 {
                    cachedN = -cachedN
                }
                sHit.normal = cachedN
                staticHit = sHit
            }
            let agentHit = AgentSweepSolver.bestHit(position: position,
                                                    remaining: remaining,
                                                    remainingLen: len,
                                                    baseMoveLen: baseMoveLen,
                                                    dt: dt,
                                                    selfEntity: entity,
                                                    selfAgent: selfAgent,
                                                    selfRadius: selfRadius,
                                                    halfHeight: controller.halfHeight,
                                                    selfFilter: selfFilter,
                                                    agentStates: agentStates,
                                                    sweep: capsuleCapsuleSweep)

            if let hit = HitSelector.selectBestHit(staticHit: staticHit,
                                                   agentHit: agentHit,
                                                   controller: controller) {
                let hitNormal: SIMD3<Float>
                switch hit {
                case .staticHit(let sHit):
                    hitNormal = sHit.normal
                case .agentHit(let aHit):
                    hitNormal = aHit.normal
                }
                let options = SlideResolver.SlideOptions.kinematicMove
                let cachedSideNormal: SIMD3<Float>?
                if case .staticHit(let sHit) = hit,
                   sHit.normal.y < controller.minGroundDot,
                   controller.sideContactFrames > 0 {
                    cachedSideNormal = cachePolicy.cachedNormal(controller: controller,
                                                                triangleIndex: sHit.triangleIndex)
                } else {
                    cachedSideNormal = nil
                }
                let shouldBreak = SlideResolver.resolveHit(remaining: &remaining,
                                                           len: len,
                                                           hit: hit,
                                                           controller: controller,
                                                           wasGrounded: wasGrounded,
                                                           wasGroundedNear: wasGroundedNear,
                                                           body: &body,
                                                           position: &position,
                                                           options: options,
                                                           cachedSideNormal: cachedSideNormal,
                                                           debugLabel: "kinematic \(entity.id)")
                if case .staticHit(let sHit) = hit, sHit.normal.y < controller.minGroundDot {
                    cachePolicy.record(controller: &controller,
                                       triangleIndex: sHit.triangleIndex,
                                       normal: sHit.normal,
                                       isSideContact: true)
                }
                if let last = lastSlideNormal {
                    let dotN = simd_dot(last, hitNormal)
                    if abs(dotN) < 0.98 {
                        let axis = simd_cross(last, hitNormal)
                        let axisLen = simd_length(axis)
                        if axisLen > 1e-5 {
                            let axisN = axis / axisLen
                            remaining = axisN * simd_dot(remaining, axisN)
                        }
                    }
                }
                lastSlideNormal = hitNormal
                if shouldBreak {
                    break
                }
            } else {
                position += remaining
                remaining = .zero
                break
            }
        }
    }

    private func resolveGroundContact(position: inout SIMD3<Float>,
                                      body: inout PhysicsBodyComponent,
                                      controller: inout CharacterControllerComponent,
                                      query: CollisionQuery,
                                      wasGrounded: Bool,
                                      wasGroundedNear: Bool,
                                      dt: Float) -> GroundContactState {
        let probe = GroundProbe.resolve(position: position,
                                        body: body,
                                        controller: controller,
                                        query: query,
                                        wasGrounded: wasGrounded,
                                        wasGroundedNear: wasGroundedNear,
                                        prevNormal: controller.groundNormal,
                                        prevTriangleIndex: controller.groundTriangleIndex)
        let groundState = probe.state
        GroundSnap.apply(position: &position,
                         body: &body,
                         controller: controller,
                         result: probe)
        if groundState.grounded {
            let normalUpDelta = groundState.normal.y - controller.groundNormal.y
            if groundState.triangleIndex != controller.groundTriangleIndex && normalUpDelta > 0.02 {
                controller.groundTransitionFrames = 3
            }
        }

        SlopeFriction.apply(body: &body,
                            controller: &controller,
                            gravity: gravity,
                            dt: dt,
                            state: groundState)
        return groundState
    }

    private func writeBack(entity: Entity,
                           position: SIMD3<Float>,
                           body: PhysicsBodyComponent,
                           controller: CharacterControllerComponent,
                           groundState: GroundContactState,
                           pStore: ComponentStore<PhysicsBodyComponent>,
                           cStore: ComponentStore<CharacterControllerComponent>) {
        var nextBody = body
        var nextController = controller
        nextBody.position = d3(position)
        nextController.grounded = groundState.grounded
        nextController.groundedNear = groundState.groundedNear
        nextController.groundNormal = groundState.grounded ? groundState.normal : SIMD3<Float>(0, 1, 0)
        if groundState.grounded {
            nextController.groundTriangleIndex = groundState.triangleIndex
        }
        pStore[entity] = nextBody
        cStore[entity] = nextController
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }
        let agentStates = collectAgentStates(bodies: bodies,
                                             pStore: pStore,
                                             cStore: cStore,
                                             aStore: aStore,
                                             active: active)
        for e in bodies {
            if !isActive(e, active) { continue }
            guard var body = pStore[e], var controller = cStore[e] else { continue }
            if body.bodyType == .static { continue }

            var position = body.positionF
            decayContactCache(controller: &controller, cachePolicy: &contactCachePolicy)
            let selfAgent = aStore[e]
            let selfRadius = selfAgent?.radiusOverride ?? controller.radius
            let selfFilter = selfAgent?.filter ?? .default
            // Apply platform motion carry/push before character sweep.
            applyPlatformDelta(position: &position,
                               controller: controller,
                               platformEntities: platformEntities,
                               platBodies: platBodies,
                               platCols: platCols)
            let wasGrounded = controller.grounded
            let wasGroundedNear = controller.groundedNear
            var remaining = VelocityGate.apply(body: &body,
                                               wasGrounded: wasGrounded,
                                               wasGroundedNear: wasGroundedNear,
                                               dt: dt)
            applyPreSweepDepenetration(position: &position,
                                       body: &body,
                                       controller: &controller,
                                       remaining: &remaining,
                                       query: query,
                                       cachePolicy: &contactCachePolicy,
                                       entity: e)
            resolveKinematicSweep(entity: e,
                                  position: &position,
                                  remaining: &remaining,
                                  body: &body,
                                  controller: &controller,
                                  wasGrounded: wasGrounded,
                                  wasGroundedNear: wasGroundedNear,
                                  selfAgent: selfAgent,
                                  selfRadius: selfRadius,
                                  selfFilter: selfFilter,
                                  agentStates: agentStates,
                                  cachePolicy: &contactCachePolicy,
                                  query: query,
                                  dt: dt)

            let groundState = resolveGroundContact(position: &position,
                                                   body: &body,
                                                   controller: &controller,
                                                   query: query,
                                                   wasGrounded: wasGrounded,
                                                   wasGroundedNear: wasGroundedNear,
                                                   dt: dt)

            writeBack(entity: e,
                      position: position,
                      body: body,
                      controller: controller,
                      groundState: groundState,
                      pStore: pStore,
                      cStore: cStore)

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

    private struct AgentSeparationPostProcessor {
        static func apply(agent: Agent,
                          startPosition: SIMD3<Float>,
                          body: inout PhysicsBodyComponent,
                          query: CollisionQuery?) -> (SIMD3<Float>, CharacterControllerComponent) {
            var position = agent.position
            var controller = agent.controller
            guard let query = query else {
                return (position, controller)
            }

            // Agent separation should not depenetrate against static world; kinematic handles that.
            let delta = position - startPosition
            let len = simd_length(delta)
            var moved = false
            if len > 1e-6 {
                moved = true
                let slideIterations = 2
                var remaining = delta
                position = startPosition
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
                                                                options: options,
                                                                cachedSideNormal: nil,
                                                                debugLabel: "agent \(agent.entity.id)")
                        if done { break }
                    } else {
                        position += remaining
                        remaining = .zero
                        break
                    }
                }
            }

            if moved && body.linearVelocity.y <= 0 {
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
                        controller.groundNormal = hit.material.flattenGround
                            ? SIMD3<Float>(0, 1, 0)
                            : hit.triangleNormal
                        controller.groundTriangleIndex = hit.triangleIndex
                    }
                }
            }

            return (position, controller)
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        var agents: [Agent] = []
        agents.reserveCapacity(entities.count)
        var originalPositions: [SIMD3<Float>] = []
        originalPositions.reserveCapacity(entities.count)

        var maxRadius: Float = 0
        for e in entities {
            if !isActive(e, active) { continue }
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
                                position: body.positionF,
                                velocity: body.linearVelocityF,
                                radius: radius,
                                halfHeight: controller.halfHeight,
                                invWeight: invWeight,
                                filter: agent.filter,
                                controller: controller))
            originalPositions.append(body.positionF)
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
            let start = originalPositions[idx]
            let (position, controller) = AgentSeparationPostProcessor.apply(agent: agent,
                                                                            startPosition: start,
                                                                            body: &body,
                                                                            query: query)

            body.position = d3(position)
            body.linearVelocity = d3(agents[idx].velocity)
            pStore[agent.entity] = body
            cStore[agent.entity] = controller
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in bodies {
            if !isActive(e, active) { continue }
            guard var body = pStore[e] else { continue }
            if cStore.contains(e) { continue }
            if kStore.contains(e) { continue }

            switch body.bodyType {
            case .static:
                break
            case .kinematic, .dynamic:
                body.position += body.linearVelocity * Double(dt)
                let w = body.angularVelocity
                let wLen = simd_length(w)
                if wLen > 0.0001 {
                    let axis = w / wLen
                    let dq = simd_quatf(angle: Float(wLen * Double(dt)), axis: f3(axis))
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
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }

        for e in bodies {
            if !isActive(e, active) { continue }
            guard let body = pStore[e], var t = tStore[e] else { continue }
            t.translation = body.positionF
            t.rotation = body.rotation
            tStore[e] = t
        }
    }
}

/// Sync chunk/local world positions from current transforms/physics.
public final class WorldPositionSyncSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let entities = world.query(WorldPositionComponent.self, TransformComponent.self)
        guard !entities.isEmpty else { return }

        let wStore = world.store(WorldPositionComponent.self)
        let tStore = world.store(TransformComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }
        let originWorld = active.map { WorldPosition.toWorld(chunk: $0.originChunk, local: $0.originLocal) }
            ?? SIMD3<Double>(0, 0, 0)

        for e in entities {
            guard var w = wStore[e], let t = tStore[e] else { continue }
            w.prevChunk = w.chunk
            w.prevLocal = w.local
            if let p = pStore[e] {
                let worldPos = originWorld + p.position
                let (chunk, local) = WorldPosition.fromWorld(worldPos)
                w.chunk = chunk
                w.local = local
            } else {
                let worldPos = WorldPosition.toWorld(chunk: w.chunk, local: w.local)
                let localPos = worldPos - originWorld
                var tLocal = t
                tLocal.translation = SIMD3<Float>(Float(localPos.x),
                                                  Float(localPos.y),
                                                  Float(localPos.z))
                tStore[e] = tLocal
            }
            WorldPosition.canonicalize(chunk: &w.chunk, local: &w.local)
            wStore[e] = w
        }
    }
}

/// Convert world positions into physics-local space (relative to active origin).
public final class PhysicsLocalizeSystem: FixedStepSystem {
    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        let entities = world.query(WorldPositionComponent.self, TransformComponent.self)
        guard !entities.isEmpty else { return }

        let wStore = world.store(WorldPositionComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let tStore = world.store(TransformComponent.self)
        let kStore = world.store(KinematicPlatformComponent.self)
        let active = world.query(ActiveChunkComponent.self).first.flatMap { world.store(ActiveChunkComponent.self)[$0] }
        let originWorld = active.map { WorldPosition.toWorld(chunk: $0.originChunk, local: $0.originLocal) }
            ?? SIMD3<Double>(0, 0, 0)

        for e in entities {
            guard let w = wStore[e], var t = tStore[e] else { continue }
            let worldPos = WorldPosition.toWorld(chunk: w.chunk, local: w.local)
            let localPos = worldPos - originWorld
            t.translation = SIMD3<Float>(Float(localPos.x),
                                         Float(localPos.y),
                                         Float(localPos.z))
            tStore[e] = t
            if var p = pStore[e] {
                p.position = localPos
                pStore[e] = p
            }
            if var k = kStore[e] {
                let axisLen = simd_length(k.axis)
                let axis = axisLen > 1e-4 ? k.axis / axisLen : SIMD3<Float>(0, 1, 0)
                let offset = sin(k.time * k.speed + k.phase) * k.amplitude
                let originWorldPos = worldPos - d3(axis * offset)
                let localOrigin = originWorldPos - originWorld
                k.origin = SIMD3<Float>(Float(localOrigin.x),
                                        Float(localOrigin.y),
                                        Float(localOrigin.z))
                kStore[e] = k
            }
        }
    }
}

/// Builds a set of entities within a chunk radius around the player.
public final class ActiveChunkSystem: FixedStepSystem {
    private var activeEntity: Entity?

    public init() {}

    public func fixedUpdate(world: World, dt: Float) {
        _ = dt
        guard let player = world.query(PlayerTagComponent.self, WorldPositionComponent.self).first,
              let playerPos = world.store(WorldPositionComponent.self)[player] else {
            return
        }

        let entities = world.query(WorldPositionComponent.self)
        let wStore = world.store(WorldPositionComponent.self)
        let staticStore = world.store(StaticMeshComponent.self)

        let active = ensureActiveComponent(world: world)
        let radius = Int64(max(active.radiusChunks, 0))
        let center = playerPos.chunk

        var activeEntityIDs: Set<UInt32> = []
        var activeStaticIDs: Set<UInt32> = []
        activeEntityIDs.reserveCapacity(entities.count)

        for e in entities {
            guard let w = wStore[e] else { continue }
            let dx = abs(w.chunk.x - center.x)
            let dy = abs(w.chunk.y - center.y)
            let dz = abs(w.chunk.z - center.z)
            if max(dx, max(dy, dz)) <= radius {
                activeEntityIDs.insert(e.id)
                if staticStore.contains(e) {
                    activeStaticIDs.insert(e.id)
                }
            }
        }

        var next = active
        next.centerChunk = center
        next.originChunk = center
        next.originLocal = SIMD3<Double>(0, 0, 0)
        next.activeEntityIDs = activeEntityIDs
        next.activeStaticEntityIDs = activeStaticIDs
        world.store(ActiveChunkComponent.self)[activeEntity!] = next
    }

    private func ensureActiveComponent(world: World) -> ActiveChunkComponent {
        if let e = activeEntity, world.isAlive(e),
           let existing = world.store(ActiveChunkComponent.self)[e] {
            return existing
        }
        let e = world.createEntity()
        let component = ActiveChunkComponent()
        world.add(e, component)
        activeEntity = e
        return component
    }
}

/// Extract RenderItems from ECS.
/// This does NOT bump scene revision; it's per-frame derived output.
public final class RenderExtractSystem {
    public init() {}

    public func extract(world: World, camera: Camera) -> [RenderItem] {
        let tStore = world.store(TransformComponent.self)
        let rStore = world.store(RenderComponent.self)
        let skStore = world.store(SkinnedMeshComponent.self)
        let skGroupStore = world.store(SkinnedMeshGroupComponent.self)
        let poseStore = world.store(PoseComponent.self)
        let followStore = world.store(FollowTargetComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let wStore = world.store(WorldPositionComponent.self)
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
        let cameraWorld = WorldPosition.toWorld(chunk: camera.worldChunk, local: camera.worldLocal)
        let cameraWorldFloat = SIMD3<Float>(Float(cameraWorld.x),
                                            Float(cameraWorld.y),
                                            Float(cameraWorld.z))

        func interpolatedModelMatrix(for e: Entity) -> matrix_float4x4? {
            if let follow = followStore[e] {
                return interpolatedModelMatrix(forTarget: follow.target)
            }
            return interpolatedModelMatrix(forTarget: e)
        }

        func interpolatedModelMatrix(forTarget e: Entity) -> matrix_float4x4? {
            guard let t = tStore[e] else { return nil }
            let rot: simd_quatf = {
                if let p = pStore[e] {
                    return simd_slerp(p.prevRotation, p.rotation, alpha)
                }
                return t.rotation
            }()
            if let w = wStore[e] {
                let prevWorld = WorldPosition.toWorld(chunk: w.prevChunk, local: w.prevLocal)
                let currWorld = WorldPosition.toWorld(chunk: w.chunk, local: w.local)
                let interpWorld = prevWorld + (currWorld - prevWorld) * Double(alpha)
                let renderPos = interpWorld - cameraWorld
                let interp = TransformComponent(translation: SIMD3<Float>(Float(renderPos.x),
                                                                          Float(renderPos.y),
                                                                          Float(renderPos.z)),
                                                rotation: rot,
                                                scale: t.scale)
                return interp.modelMatrix
            }
            if let p = pStore[e] {
                let interpWorld = p.prevPosition + (p.position - p.prevPosition) * Double(alpha)
                let renderPos = interpWorld - cameraWorld
                let interp = TransformComponent(translation: SIMD3<Float>(Float(renderPos.x),
                                                                          Float(renderPos.y),
                                                                          Float(renderPos.z)),
                                                rotation: rot,
                                                scale: t.scale)
                return interp.modelMatrix
            }
            var renderT = t
            renderT.translation -= cameraWorldFloat
            return renderT.modelMatrix
        }

        // ✅ Stable ordering for deterministic draw-call order (picking/debug/sorting friendly)
        let skinnedEntities = world
            .query(TransformComponent.self, SkinnedMeshComponent.self, PoseComponent.self)
            .sorted { $0.id < $1.id }

        let skinnedGroupEntities = world
            .query(TransformComponent.self, SkinnedMeshGroupComponent.self, PoseComponent.self)
            .sorted { $0.id < $1.id }

        let skinnedSet = Set(skinnedEntities).union(skinnedGroupEntities)

        // ✅ Stable ordering for deterministic draw-call order (picking/debug/sorting friendly)
        let entities = world
            .query(TransformComponent.self, RenderComponent.self)
            .sorted { $0.id < $1.id }

        var items: [RenderItem] = []
        items.reserveCapacity(entities.count + skinnedEntities.count + skinnedGroupEntities.count)

        for e in skinnedEntities {
            guard let sk = skStore[e], let pose = poseStore[e] else { continue }
            guard let modelMatrix = interpolatedModelMatrix(for: e) else { continue }
            let palette: [matrix_float4x4]
            if let invBind = sk.mesh.invBindModel, invBind.count == pose.model.count {
                palette = zip(pose.model, invBind).map { simd_mul($0, $1) }
            } else {
                palette = pose.palette
            }
            items.append(RenderItem(mesh: nil,
                                    skinnedMesh: sk.mesh,
                                    skinningPalette: palette,
                                    material: sk.material,
                                    modelMatrix: modelMatrix))
        }

        for e in skinnedGroupEntities {
            guard let sk = skGroupStore[e], let pose = poseStore[e] else { continue }
            guard let modelMatrix = interpolatedModelMatrix(for: e) else { continue }
            let palette: [matrix_float4x4] = {
                if let invBind = sk.meshes.first?.invBindModel, invBind.count == pose.model.count {
                    return zip(pose.model, invBind).map { simd_mul($0, $1) }
                }
                return pose.palette
            }()
            let count = min(sk.meshes.count, sk.materials.count)
            if count == 0 { continue }
            for i in 0..<count {
                items.append(RenderItem(mesh: nil,
                                        skinnedMesh: sk.meshes[i],
                                        skinningPalette: palette,
                                        material: sk.materials[i],
                                        modelMatrix: modelMatrix))
            }
        }

        for e in entities {
            if skinnedSet.contains(e) { continue }
            guard let r = rStore[e] else { continue }
            guard let modelMatrix = interpolatedModelMatrix(for: e) else { continue }
            items.append(RenderItem(mesh: r.mesh, material: r.material, modelMatrix: modelMatrix))
        }
        return items
    }
}
