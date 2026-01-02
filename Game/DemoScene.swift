//
//  DemoScene.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class DemoScene: RenderScene {

    public private(set) var renderItems: [RenderItem] = []
    public private(set) var revision: UInt64 = 0

    public let camera = Camera()

    private var angle: Float = 0

    public init() {}

    public func build(context: SceneContext) {
        let device = context.device

        let mesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 4), label: "SceneBox")
        let tex = TextureResource(device: device, source: ProceduralTextures.checkerboard(), label: "SceneChecker")
        let mat = Material(baseColorTexture: tex)

        let item = RenderItem(mesh: mesh, material: mat, modelMatrix: matrix_identity_float4x4)
        renderItems = [item]

        revision &+= 1
    }

    public func update(dt: Float) {
        angle += dt * 1.0  // rad/s feel free adjust

        // Update model matrix (rotate)
        let axis = SIMD3<Float>(1, 1, 0)
        let rot = matrix4x4_rotation(radians: angle, axis: axis)

        if !renderItems.isEmpty {
            renderItems[0].modelMatrix = rot
            // renderItems changed (model matrix) does NOT require residency rebuild.
            // So we do NOT bump revision here.
        }

        camera.updateView()
    }
}
