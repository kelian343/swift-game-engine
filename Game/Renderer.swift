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

    // Main pipeline (still available for raster fallback)
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let fallbackWhite: TextureResource
    private let fallbackNormal: TextureResource
    private let fallbackEmissive: TextureResource
    private let fallbackOcclusion: TextureResource

    private let rayTracing: RayTracingRenderer

    // Scene hook
    private var scene: RenderScene?
    private var sceneContext: SceneContext
    private var lastSceneRevision: UInt64 = 0

    private let compositePass = CompositePass()
    private let uiPass = UIPass()
    private let renderGraph = RenderGraph()
    private let uiDepthState: MTLDepthStencilState
    private let compositeMesh: GPUMesh
    private var compositeItems: [RenderItem] = []
    private var compositeMaterial: Material?
    private var rtColorResource: TextureResource?
    private var rtColorTexture: MTLTexture?

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

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds
        guard let uiDs = PipelineBuilder.makeUIDepthState(device: device) else { return nil }
        self.uiDepthState = uiDs

        self.fallbackWhite = TextureResource(
            device: device,
            source: ProceduralTextureGenerator.solid(width: 1,
                                                     height: 1,
                                                     color: SIMD4<UInt8>(255, 255, 255, 255)),
            label: "FallbackWhite"
        )
        self.fallbackNormal = TextureResource(
            device: device,
            source: ProceduralTextureGenerator.flatNormal(width: 1, height: 1),
            label: "FallbackNormal"
        )
        self.fallbackEmissive = TextureResource(
            device: device,
            source: ProceduralTextureGenerator.solid(width: 1,
                                                     height: 1,
                                                     color: SIMD4<UInt8>(0, 0, 0, 255)),
            label: "FallbackEmissive"
        )
        self.fallbackOcclusion = TextureResource(
            device: device,
            source: ProceduralTextureGenerator.occlusion(width: 1,
                                                         height: 1,
                                                         occlusion: 1.0),
            label: "FallbackOcclusion"
        )
        guard let rt = RayTracingRenderer(device: device) else { return nil }
        self.rayTracing = rt
        self.renderGraph.addPass(compositePass)
        self.renderGraph.addPass(uiPass)

        let quadDesc = ProceduralMeshes.quad(QuadParams(width: 1, height: 1))
        self.compositeMesh = GPUMesh(device: device, descriptor: quadDesc, label: "CompositeQuad")

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

        let meshes = items.compactMap { $0.mesh }
        let textures = items.flatMap { item in
            [
                item.material.baseColorTexture?.texture,
                item.material.normalTexture?.texture,
                item.material.metallicRoughnessTexture?.texture,
                item.material.emissiveTexture?.texture,
                item.material.occlusionTexture?.texture
            ].compactMap { $0 }
        }

        // include: base textures + fallback + uniform buffer
        context.prepareResidency(
            meshes: meshes,
            textures: textures + [fallbackWhite.texture, fallbackNormal.texture, fallbackEmissive.texture, fallbackOcclusion.texture],
            uniforms: uniformRing.buffer
        )
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let scene = scene else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }

        let now = CACurrentMediaTime()
        let dt = Float(max(0.0, min(now - lastTime, 0.1)))
        lastTime = now

        scene.update(dt: dt)

        let items = scene.renderItems
        let overlayItems = scene.overlayItems
        rebuildResidencyIfNeeded(items: items)

        // Camera matrices
        let projection = scene.camera.projection
        let viewM = scene.camera.view

        updateRTTargetIfNeeded(view: view)
        if let rtTarget = rtColorTexture {
            rayTracing.encode(commandBuffer: commandBuffer,
                              outputTexture: rtTarget,
                              outputSize: view.drawableSize,
                              items: items,
                              camera: scene.camera,
                              projection: projection,
                              viewMatrix: viewM)
        }

        _ = uniformRing.beginFrame()

        let overlayProjection = orthoRH(left: 0,
                                        right: Float(view.drawableSize.width),
                                        bottom: Float(view.drawableSize.height),
                                        top: 0,
                                        near: -1,
                                        far: 1)
        let overlayView = matrix_identity_float4x4
        let compositeItems = makeCompositeItems(size: view.drawableSize,
                                               exposure: scene.toneMappingExposure,
                                               toneMapped: scene.toneMappingEnabled)
        let frame = FrameContext(scene: scene,
                                 items: [],
                                 compositeItems: compositeItems,
                                 overlayItems: overlayItems,
                                 context: context,
                                 uniformRing: uniformRing,
                                 pipelineState: pipelineState,
                                 depthState: uiDepthState,
                                 fallbackWhite: fallbackWhite,
                                 fallbackNormal: fallbackNormal,
                                 fallbackEmissive: fallbackEmissive,
                                 fallbackOcclusion: fallbackOcclusion,
                                 projection: overlayProjection,
                                 viewMatrix: overlayView,
                                 cameraPosition: scene.camera.position)
        renderGraph.execute(frame: frame, view: view, commandBuffer: commandBuffer)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
        scene?.viewportDidChange(size: SIMD2<Float>(Float(size.width), Float(size.height)))
    }

    private func updateRTTargetIfNeeded(view: MTKView) {
        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)
        let format = view.colorPixelFormat

        if let existing = rtColorTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == format {
            return
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = "RTColor"
        rtColorTexture = tex
        if let tex = tex {
            rtColorResource = TextureResource(texture: tex, label: "RTColorResource")
            compositeMaterial = nil
            compositeItems.removeAll(keepingCapacity: true)
        }
    }

    private func makeCompositeItems(size: CGSize,
                                    exposure: Float,
                                    toneMapped: Bool) -> [RenderItem] {
        guard let rtResource = rtColorResource else { return [] }
        if compositeMaterial == nil {
            var mat = Material(baseColorTexture: rtResource,
                               roughnessFactor: 1.0,
                               alpha: 1.0)
            mat.cullMode = .none
            mat.unlit = true
            mat.toneMapped = toneMapped
            mat.exposure = exposure
            compositeMaterial = mat
        }
        guard var mat = compositeMaterial else { return [] }
        mat.toneMapped = toneMapped
        mat.exposure = exposure
        compositeMaterial = mat

        let scale = SIMD3<Float>(Float(size.width), Float(size.height), 1)
        let t = TransformComponent(translation: SIMD3<Float>(0, 0, 0),
                                   rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                                   scale: scale)
        if compositeItems.isEmpty {
            compositeItems = [RenderItem(mesh: compositeMesh, material: mat, modelMatrix: t.modelMatrix)]
        } else {
            compositeItems[0].modelMatrix = t.modelMatrix
            compositeItems[0].material = mat
        }
        return compositeItems
    }
}
