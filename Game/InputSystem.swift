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

    private var yaw: Float = 0
    private var pitch: Float = -0.1
    private var facingYaw: Float = 0

    var moveSpeed: Float = 5.0
    var lookSpeed: Float = 2.5
    var turnSpeed: Float = 3.0
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
        guard let pad = controller?.extendedGamepad else {
            world.store(MoveIntentComponent.self)[player] = MoveIntentComponent()
            return
        }

        let lx = axis(pad.leftThumbstick.xAxis.value)
        let ly = axis(-pad.leftThumbstick.yAxis.value)
        let rx = axis(-pad.rightThumbstick.xAxis.value)
        let ry = axis(-pad.rightThumbstick.yAxis.value)

        yaw += rx * lookSpeed * dt
        pitch += ry * lookSpeed * dt
        pitch = min(max(pitch, pitchMin), pitchMax)

        let forward = SIMD3<Float>(sinf(yaw), 0, cosf(yaw))
        let right = SIMD3<Float>(cosf(yaw), 0, -sinf(yaw))

        let move = forward * ly + right * lx
        let moveLen = simd_length(move)
        var intent = MoveIntentComponent()
        if moveLen > deadzone {
            let dir = move / moveLen
            let targetYaw = atan2f(dir.x, dir.z)
            facingYaw = approachAngle(current: facingYaw, target: targetYaw, maxDelta: turnSpeed * dt)
            intent.desiredVelocity = dir * moveSpeed
            intent.desiredFacingYaw = facingYaw
            intent.hasFacingYaw = true
        }
        world.store(MoveIntentComponent.self)[player] = intent

        let tStore = world.store(TransformComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let basePos = pStore[player]?.position ?? tStore[player]?.translation ?? .zero
        if let camera = camera {
            let target = basePos + SIMD3<Float>(0, cameraHeight, 0)
            let dir = SIMD3<Float>(sinf(yaw) * cosf(pitch),
                                   sinf(pitch),
                                   cosf(yaw) * cosf(pitch))
            camera.position = target + dir * cameraDistance
            camera.target = target
        }
    }

    private func axis(_ v: Float) -> Float {
        let a = abs(v)
        if a < deadzone { return 0 }
        return v
    }

    private func approachAngle(current: Float, target: Float, maxDelta: Float) -> Float {
        let delta = shortestAngle(from: current, to: target)
        let step = max(-maxDelta, min(maxDelta, delta))
        return wrapAngle(current + step)
    }

    private func shortestAngle(from: Float, to: Float) -> Float {
        let diff = wrapAngle(to - from)
        return diff > .pi ? diff - 2 * .pi : diff
    }

    private func wrapAngle(_ a: Float) -> Float {
        var v = fmodf(a, 2 * .pi)
        if v < 0 { v += 2 * .pi }
        return v
    }
}
