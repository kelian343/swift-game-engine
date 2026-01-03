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

    // Ray tracing
    private let rtPipelineState: MTLComputePipelineState
    private let rtScene: RayTracingScene
    private let rtFrameBuffer: MTLBuffer
    private var rtFrameIndex: UInt32 = 0

    // Scene hook
    private var scene: RenderScene?
    private var sceneContext: SceneContext
    private var lastSceneRevision: UInt64 = 0

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

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds

        // Ray tracing pipeline
        do {
            let library = device.makeDefaultLibrary()
            guard let fn = library?.makeFunction(name: "raytraceKernel") else {
                print("Ray tracing kernel not found")
                return nil
            }
            self.rtPipelineState = try device.makeComputePipelineState(function: fn)
        } catch {
            print("Unable to compile ray tracing pipeline state. Error info: \(error)")
            return nil
        }

        self.fallbackWhite = TextureResource(
            device: device,
            source: .solid(width: 1, height: 1, r: 255, g: 255, b: 255, a: 255),
            label: "FallbackWhite"
        )

        self.rtScene = RayTracingScene(device: device)
        guard let rtBuffer = device.makeBuffer(length: MemoryLayout<RTFrameUniformsSwift>.stride,
                                               options: [.storageModeShared]) else {
            return nil
        }
        self.rtFrameBuffer = rtBuffer

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

        // include: base textures + fallback + uniform buffer
        context.prepareResidency(
            meshes: meshes,
            textures: textures + [fallbackWhite.texture],
            uniforms: uniformRing.buffer
        )
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

        let rtCommandBuffer = context.rtCommandQueue.makeCommandBuffer()!
        let tlas = rtScene.buildAccelerationStructures(items: items, commandBuffer: rtCommandBuffer)

        let invViewProj = simd_inverse(simd_mul(projection, viewM))
        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)
        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            cameraPosition: scene.camera.position,
            frameIndex: rtFrameIndex,
            imageSize: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            lightDirection: SIMD3<Float>(-0.5, -1.0, -0.3),
            lightIntensity: 1.0,
            lightColor: SIMD3<Float>(1.0, 1.0, 1.0),
            ambientIntensity: 0.12
        )
        rtFrameIndex &+= 1
        memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)

        if let tlas = tlas,
           let enc = rtCommandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(rtPipelineState)
            enc.setTexture(drawable.texture, index: 0)
            enc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            enc.setAccelerationStructure(tlas, bufferIndex: BufferIndex.rtAccel.rawValue)

            let tgW = 8
            let tgH = 8
            let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            enc.endEncoding()
        }

        rtCommandBuffer.present(drawable)
        rtCommandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}
