//
//  Renderer.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {

    public let device: MTLDevice

    private let context: RenderContext
    private let frameSync: FrameSync
    private let uniformRing: UniformRingBuffer

    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private let fallbackWhite: TextureResource

    // Scene hook
    private var scene: RenderScene?
    private var sceneContext: SceneContext
    private var lastSceneRevision: UInt64 = 0

    // time
    private var lastTime: Double = CACurrentMediaTime()

    @MainActor
    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device else { return nil }
        self.device = device
        self.sceneContext = SceneContext(device: device)

        metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.sampleCount = 1

        guard let ctx = RenderContext(view: metalKitView, maxFramesInFlight: maxBuffersInFlight) else { return nil }
        self.context = ctx

        self.frameSync = FrameSync(device: device, maxFramesInFlight: maxBuffersInFlight)

        guard let ring = UniformRingBuffer(device: device, maxFramesInFlight: maxBuffersInFlight) else { return nil }
        self.uniformRing = ring

        let vDesc = PipelineBuilder.makeMetalVertexDescriptor()
        do {
            self.pipelineState = try PipelineBuilder.makeRenderPipeline(device: device, view: metalKitView, vertexDescriptor: vDesc)
        } catch {
            print("Unable to compile render pipeline state. Error info: \(error)")
            return nil
        }

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds

        self.fallbackWhite = TextureResource(
            device: device,
            source: .solid(width: 1, height: 1, r: 255, g: 255, b: 255, a: 255),
            label: "FallbackWhite"
        )

        super.init()
    }

    // External API: plug a scene
    func setScene(_ scene: RenderScene) {
        self.scene = scene
        scene.build(context: sceneContext)
        lastSceneRevision = 0 // force rebuild on next draw
    }

    private func rebuildResidencyIfNeeded(items: [RenderItem]) {
        guard let scene = scene else { return }
        if scene.revision == lastSceneRevision { return }
        lastSceneRevision = scene.revision

        let meshes = items.map { $0.mesh }
        let textures = items.compactMap { $0.material.baseColorTexture?.texture }
        context.prepareResidency(
            meshes: meshes,
            textures: textures + [fallbackWhite.texture],
            uniforms: uniformRing.buffer
        )
    }

    private func writeUniforms(_ ptr: UnsafeMutablePointer<Uniforms>,
                               projection: matrix_float4x4,
                               view: matrix_float4x4,
                               model: matrix_float4x4) {
        ptr[0].projectionMatrix = projection
        ptr[0].modelViewMatrix = simd_mul(view, model)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let scene = scene else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let rpd = context.currentRenderPassDescriptor(from: view) else { return }

        let now = CACurrentMediaTime()
        let dt = Float(max(0.0, min(now - lastTime, 0.1))) // clamp
        lastTime = now

        scene.update(dt: dt)

        let items = scene.renderItems
        rebuildResidencyIfNeeded(items: items)

        frameSync.waitIfNeeded(timeoutMS: 10)

        // ✅ 每帧开始：拿 frameSlot 选 allocator，并 beginCommandBuffer
        let frameSlot = uniformRing.beginFrame()
        let allocator = context.allocators[frameSlot]
        allocator.reset()
        context.commandBuffer.beginCommandBuffer(allocator: allocator)

        guard let enc = context.commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            fatalError("Failed to create render command encoder")
        }

        enc.label = "Primary Render Encoder"
        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)

        enc.setArgumentTable(context.vertexTable, stages: .vertex)
        enc.setArgumentTable(context.fragmentTable, stages: .fragment)

        // ✅ 纯 protocol：不再特判 DemoScene
        let projection = scene.camera.projection
        let viewM = scene.camera.view

        for item in items {
            enc.setCullMode(item.material.cullMode)
            enc.setFrontFacing(item.material.frontFacing)

            // ✅ 每个 draw call 单独 allocate 一份 uniforms
            let u = uniformRing.allocate()

            writeUniforms(u.pointer, projection: projection, view: viewM, model: item.modelMatrix)

            let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
            context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)
            context.fragmentTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)

            context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress, index: BufferIndex.meshVertices.rawValue)

            let tex = item.material.baseColorTexture?.texture ?? fallbackWhite.texture
            context.fragmentTable.setTexture(tex.gpuResourceID, index: TextureIndex.baseColor.rawValue)

            enc.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: item.mesh.indexType,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }

        enc.endEncoding()

        context.useViewResidencySetIfAvailable(for: view)
        context.commandBuffer.endCommandBuffer()

        context.commandQueue.waitForDrawable(drawable)
        context.commandQueue.commit([context.commandBuffer])
        context.commandQueue.signalDrawable(drawable)

        frameSync.signalNextFrame(on: context.commandQueue)
        drawable.present()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // ✅ 纯 protocol：不再特判 DemoScene
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}
