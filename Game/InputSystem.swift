//
//  InputSystem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import GameController
import simd

final class InputSystem: System {
    private weak var camera: Camera?
    private var player: Entity?
    private var controller: GCController?

    // Camera yaw/pitch (independent from facing)
    private var yaw: Float = 0
    private var pitch: Float = -0.1

    // Character facing (driven by LEFT stick direction)
    private var facingYaw: Float = 0
    private var lastJumpPressed: Bool = false
    public private(set) var exposureDelta: Float = 0

    var lookSpeed: Float = 2.5      // used for right stick rotation + pitch
    var turnSpeed: Float = 16.0
    var cameraDistance: Float = 8.0
    var cameraHeight: Float = 1.5
    var deadzone: Float = 0.12
    var pitchMin: Float = -0.6
    var pitchMax: Float = 0.6

    init(camera: Camera) {
        self.camera = camera

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        controller = GCController.controllers().first
    }

    func setPlayer(_ e: Entity) {
        player = e
    }

    @objc private func controllerDidConnect(_ note: Notification) {
        if let c = note.object as? GCController {
            controller = c
        }
    }

    @objc private func controllerDidDisconnect(_ note: Notification) {
        if let c = note.object as? GCController, c == controller {
            controller = nil
        }
    }

    func update(world: World, dt: Float) {
        guard let player = player else { return }

        if controller == nil {
            controller = GCController.controllers().first
        }
        let mStore = world.store(MoveIntentComponent.self)
        let mvStore = world.store(MovementComponent.self)
        guard let pad = controller?.extendedGamepad else {
            mStore[player] = MoveIntentComponent()
            lastJumpPressed = false
            exposureDelta = 0
            return
        }

        // RAW axes
        let rawLX = pad.leftThumbstick.xAxis.value
        let rawLY = pad.leftThumbstick.yAxis.value
        let rawRX = pad.rightThumbstick.xAxis.value
        let rawRY = pad.rightThumbstick.yAxis.value
        let jumpPressed = pad.buttonA.isPressed
        exposureDelta = 0

        // Match the "correct version" axis sign convention
        let lx = axis(-rawLX)
        let ly = axis(rawLY)
        let rx = axis(-rawRX)
        let ry = axis(-rawRY)

        // Right stick controls camera yaw.
        yaw = wrapAngle(yaw + rx * lookSpeed * dt)

        // Right stick Y controls camera pitch.
        pitch += ry * lookSpeed * dt
        pitch = min(max(pitch, pitchMin), pitchMax)

        // Movement is relative to camera yaw (third-person feel).
        let forward = forwardFromYaw(yaw)
        let right = SIMD3<Float>(forward.z, 0, -forward.x)

        let move = forward * ly + right * lx
        let moveLen = simd_length(move)

        var intent = mStore[player] ?? MoveIntentComponent()
        if moveLen > deadzone {
            let movement = mvStore[player] ?? MovementComponent()
            let dir = move / moveLen
            let runThreshold = max(movement.runThreshold, deadzone)
            let speed = moveLen >= runThreshold ? movement.runSpeed : movement.walkSpeed
            intent.desiredVelocity = dir * speed

            // Face toward left-stick move direction with turn speed limit.
            let targetYaw = wrapAngle(atan2f(-dir.x, -dir.z))
            facingYaw = approachAngle(current: facingYaw, target: targetYaw, maxDelta: turnSpeed * dt)
            intent.desiredFacingYaw = facingYaw
            intent.hasFacingYaw = true
        } else {
            intent.desiredVelocity = .zero
            intent.hasFacingYaw = false
        }
        if jumpPressed && !lastJumpPressed {
            intent.jumpRequested = true
        }
        lastJumpPressed = jumpPressed

        mStore[player] = intent
    }

    func updateCamera(world: World) {
        guard let player = player, let camera = camera else { return }
        let tStore = world.store(TransformComponent.self)
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
        let baseWorld: SIMD3<Double> = {
            if let w = wStore[player] {
                let prevWorld = WorldPosition.toWorld(chunk: w.prevChunk, local: w.prevLocal)
                let currWorld = WorldPosition.toWorld(chunk: w.chunk, local: w.local)
                return prevWorld + (currWorld - prevWorld) * Double(alpha)
            }
            if let p = pStore[player] {
                let pos = p.prevPosition + (p.position - p.prevPosition) * Double(alpha)
                return pos
            }
            let pos = tStore[player]?.translation ?? .zero
            return SIMD3<Double>(Double(pos.x), Double(pos.y), Double(pos.z))
        }()
        let targetWorld = baseWorld + SIMD3<Double>(0, Double(cameraHeight), 0)
        let dir = SIMD3<Float>(
            sinf(yaw) * cosf(pitch),
            sinf(pitch),
            cosf(yaw) * cosf(pitch)
        )
        let offset = SIMD3<Double>(Double(dir.x) * Double(cameraDistance),
                                   Double(dir.y) * Double(cameraDistance),
                                   Double(dir.z) * Double(cameraDistance))
        let cameraWorld = targetWorld + offset
        let (chunk, local) = WorldPosition.fromWorld(cameraWorld)
        camera.worldChunk = chunk
        camera.worldLocal = local
        let targetRender = targetWorld - cameraWorld
        camera.position = .zero
        camera.target = SIMD3<Float>(Float(targetRender.x),
                                     Float(targetRender.y),
                                     Float(targetRender.z))
    }

    // Same yaw convention as your correct version:
    // forward = (-sin(yaw), 0, -cos(yaw))
    private func forwardFromYaw(_ yaw: Float) -> SIMD3<Float> {
        SIMD3<Float>(-sinf(yaw), 0, -cosf(yaw))
    }

    private func axis(_ v: Float) -> Float {
        let a = abs(v)
        if a < deadzone { return 0 }
        return v
    }

    private func wrapAngle(_ a: Float) -> Float {
        var v = fmodf(a, 2 * .pi)
        if v < 0 { v += 2 * .pi }
        return v
    }

    // --- below are kept only because your old file had them; not used now ---
    private func approachAngle(current: Float, target: Float, maxDelta: Float) -> Float {
        let delta = shortestAngle(from: current, to: target)
        let step = max(-maxDelta, min(maxDelta, delta))
        return wrapAngle(current + step)
    }

    private func shortestAngle(from: Float, to: Float) -> Float {
        let diff = wrapAngle(to - from)
        return diff > .pi ? diff - 2 * .pi : diff
    }
}
