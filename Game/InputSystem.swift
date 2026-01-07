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
    var debugLogs: Bool = false

    // Camera yaw/pitch (yaw will be kept aligned to facingYaw)
    private var yaw: Float = 0
    private var pitch: Float = -0.1

    // Character facing (driven only by RIGHT stick X)
    private var facingYaw: Float = 0
    private var lastJumpPressed: Bool = false

    var moveSpeed: Float = 10.0
    var lookSpeed: Float = 2.5      // used for right stick rotation + pitch
    var turnSpeed: Float = 3.0      // (kept, but no longer used for auto-turn; can be removed)
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
        guard let pad = controller?.extendedGamepad else {
            mStore[player] = MoveIntentComponent()
            lastJumpPressed = false
            return
        }

        // RAW axes
        let rawLX = pad.leftThumbstick.xAxis.value
        let rawLY = pad.leftThumbstick.yAxis.value
        let rawRX = pad.rightThumbstick.xAxis.value
        let rawRY = pad.rightThumbstick.yAxis.value
        let jumpPressed = pad.buttonA.isPressed

        // Match the "correct version" axis sign convention
        let lx = axis(-rawLX)
        let ly = axis(rawLY)
        let rx = axis(-rawRX)
        let ry = axis(-rawRY)

        // Right stick X rotates character; camera yaw stays aligned with facing.
        facingYaw = wrapAngle(facingYaw + rx * lookSpeed * dt)
        yaw = facingYaw

        // Right stick Y controls camera pitch.
        pitch += ry * lookSpeed * dt
        pitch = min(max(pitch, pitchMin), pitchMax)

        // Movement is relative to facing (third-person feel).
        let forward = forwardFromYaw(facingYaw)
        let right = SIMD3<Float>(forward.z, 0, -forward.x)

        let move = forward * ly + right * lx
        let moveLen = simd_length(move)

        var intent = mStore[player] ?? MoveIntentComponent()
        if moveLen > deadzone {
            let dir = move / moveLen
            intent.desiredVelocity = dir * moveSpeed
        } else {
            intent.desiredVelocity = .zero
        }

        // Always apply facing yaw from right stick (allows backpedal/strafe).
        intent.desiredFacingYaw = facingYaw
        intent.hasFacingYaw = true
        if jumpPressed && !lastJumpPressed {
            intent.jumpRequested = true
            if debugLogs {
                print("JumpInput requested")
            }
        }
        lastJumpPressed = jumpPressed

        mStore[player] = intent

        // Camera follow (simple version, no interpolation)
        let tStore = world.store(TransformComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let basePos = pStore[player]?.position ?? tStore[player]?.translation ?? .zero

        if let camera = camera {
            let target = basePos + SIMD3<Float>(0, cameraHeight, 0)
            let dir = SIMD3<Float>(
                sinf(yaw) * cosf(pitch),
                sinf(pitch),
                cosf(yaw) * cosf(pitch)
            )
            camera.position = target + dir * cameraDistance
            camera.target = target
        }
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
