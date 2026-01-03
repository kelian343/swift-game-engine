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

    // Main pipeline
    private let pipelineState: MTLRenderPipelineState
    // Shadow pipeline (depth only)
    private let shadowPipelineState: MTLRenderPipelineState

    private let depthState: MTLDepthStencilState
    private let fallbackWhite: TextureResource

    // Lighting & shadow modules (already created by you)
    private let shadowMap: ShadowMap
    private let lightSystem: LightSystem

    // Scene hook
    private var scene: RenderScene?
    private var sceneContext: SceneContext
    private var lastSceneRevision: UInt64 = 0

    private let shadowPass = ShadowPass()
    private let mainPass = MainPass()

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

        // IMPORTANT: use per-draw allocator ring (you already have beginFrame/allocate)
        guard let ring = UniformRingBuffer(device: device, maxFramesInFlight: maxBuffersInFlight) else { return nil }
        self.uniformRing = ring

        let vDesc = PipelineBuilder.makeMetalVertexDescriptor()

        // Main pipeline (Metal4 compiler path)
        do {
            self.pipelineState = try PipelineBuilder.makeRenderPipeline(device: device, view: metalKitView, vertexDescriptor: vDesc)
        } catch {
            print("Unable to compile main render pipeline state. Error info: \(error)")
            return nil
        }

        // Shadow pipeline (use classic MTLRenderPipelineDescriptor for SDK compatibility)
        do {
            self.shadowPipelineState = try Renderer.buildShadowPipeline(device: device, vertexDescriptor: vDesc)
        } catch {
            print("Unable to compile shadow render pipeline state. Error info: \(error)")
            return nil
        }

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds

        self.fallbackWhite = TextureResource(
            device: device,
            source: .solid(width: 1, height: 1, r: 255, g: 255, b: 255, a: 255),
            label: "FallbackWhite"
        )

        // Modules
        self.shadowMap = ShadowMap(device: device, size: 2048)
        self.lightSystem = LightSystem(device: device)

        super.init()
    }

    // External API: plug a scene
    func setScene(_ scene: RenderScene) {
        self.scene = scene
        scene.build(context: sceneContext)
        lastSceneRevision = 0 // force rebuild on next draw
    }

    // MARK: - Residency

    private func rebuildResidencyIfNeeded(items: [RenderItem]) {
        guard let scene = scene else { return }
        if scene.revision == lastSceneRevision { return }
        lastSceneRevision = scene.revision

        let meshes = items.map { $0.mesh }
        let textures = items.compactMap { $0.material.baseColorTexture?.texture }

        // include: base textures + fallback + shadow map + uniform buffer + light buffer
        context.prepareResidency(
            meshes: meshes,
            textures: textures + [fallbackWhite.texture, shadowMap.texture],
            uniforms: uniformRing.buffer
        )

        // If your residency model requires explicit add for buffers too:
        // (Most Metal4 setups still work without, but if you see validation issues,
        // we can extend RenderContext.prepareResidency to take extraBuffers.)
        // e.g. include lightSystem.buffer as well.
    }

    // MARK: - Shadow pipeline builder (SDK-stable)

    private static func buildShadowPipeline(device: MTLDevice,
                                            vertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()!
        let v = library.makeFunction(name: "shadowVertex")!

        let pd = MTLRenderPipelineDescriptor()
        pd.label = "ShadowPipeline"
        pd.vertexFunction = v
        pd.fragmentFunction = nil
        pd.vertexDescriptor = vertexDescriptor
        pd.depthAttachmentPixelFormat = .depth32Float

        return try device.makeRenderPipelineState(descriptor: pd)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let scene = scene else { return }
        guard let drawable = view.currentDrawable else { return }

        let now = CACurrentMediaTime()
        let dt = Float(max(0.0, min(now - lastTime, 0.1)))
        lastTime = now

        scene.update(dt: dt)

        let items = scene.renderItems
        rebuildResidencyIfNeeded(items: items)

        // Camera matrices
        let projection = scene.camera.projection
        let viewM = scene.camera.view

        // Light params + light view-projection
        let viewProj = simd_mul(projection, viewM)
        lightSystem.update(cameraPos: scene.camera.position,
                           cameraViewProj: viewProj,
                           shadowMapSize: shadowMap.size)
        let lightVP = lightSystem.lightViewProj()

        // Sync
        frameSync.waitIfNeeded(timeoutMS: 10)

        // Begin frame allocation (allocator slot)
        let frameSlot = uniformRing.beginFrame()
        let allocator = context.allocators[frameSlot]
        allocator.reset()
        context.commandBuffer.beginCommandBuffer(allocator: allocator)

        let frame = FrameContext(
            scene: scene,
            items: items,
            context: context,
            uniformRing: uniformRing,
            pipelineState: pipelineState,
            shadowPipelineState: shadowPipelineState,
            depthState: depthState,
            fallbackWhite: fallbackWhite,
            shadowMap: shadowMap,
            lightSystem: lightSystem,
            projection: projection,
            viewMatrix: viewM,
            lightViewProj: lightVP
        )

        let graph = RenderGraph()
        graph.addPass(shadowPass)
        graph.addPass(mainPass)
        graph.execute(frame: frame, view: view)

        context.useViewResidencySetIfAvailable(for: view)
        context.commandBuffer.endCommandBuffer()

        context.commandQueue.waitForDrawable(drawable)
        context.commandQueue.commit([context.commandBuffer])
        context.commandQueue.signalDrawable(drawable)

        frameSync.signalNextFrame(on: context.commandQueue)
        drawable.present()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}
