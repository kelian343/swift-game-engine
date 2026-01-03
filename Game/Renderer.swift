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
    private var accumulationTexture: MTLTexture?
    private var lastViewProj: matrix_float4x4 = matrix_identity_float4x4
    private var lastCameraPosition: SIMD3<Float> = .zero
    private var hasLastView = false
    private var lastSceneRevisionForRT: UInt64 = 0
    private let dirLightBuffer: MTLBuffer
    private let pointLightBuffer: MTLBuffer
    private let areaLightBuffer: MTLBuffer

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
        guard let dirBuf = device.makeBuffer(length: MemoryLayout<RTDirectionalLightSwift>.stride * 4,
                                             options: [.storageModeShared]),
              let pointBuf = device.makeBuffer(length: MemoryLayout<RTPointLightSwift>.stride * 8,
                                               options: [.storageModeShared]),
              let areaBuf = device.makeBuffer(length: MemoryLayout<RTAreaLightSwift>.stride * 4,
                                              options: [.storageModeShared]) else {
            return nil
        }
        dirBuf.label = "RTDirectionalLights"
        pointBuf.label = "RTPointLights"
        areaBuf.label = "RTAreaLights"
        self.dirLightBuffer = dirBuf
        self.pointLightBuffer = pointBuf
        self.areaLightBuffer = areaBuf

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
        let geometry = rtScene.buildGeometryBuffers(items: items)

        let viewProj = simd_mul(projection, viewM)
        let invViewProj = simd_inverse(viewProj)
        let width = max(Int(view.drawableSize.width), 1)
        let height = max(Int(view.drawableSize.height), 1)

        if accumulationTexture == nil
            || accumulationTexture?.width != width
            || accumulationTexture?.height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                                width: width,
                                                                height: height,
                                                                mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            accumulationTexture = device.makeTexture(descriptor: desc)
            accumulationTexture?.label = "RTAccumulation"
            rtFrameIndex = 0
            hasLastView = false
        }

        var resetAccum = false
        if !hasLastView || !matrixAlmostEqual(viewProj, lastViewProj, eps: 1e-5) {
            resetAccum = true
        }
        if simd_distance(scene.camera.position, lastCameraPosition) > 1e-4 {
            resetAccum = true
        }
        if scene.revision != lastSceneRevisionForRT {
            resetAccum = true
            lastSceneRevisionForRT = scene.revision
        }
        if resetAccum {
            rtFrameIndex = 0
        }
        lastViewProj = viewProj
        lastCameraPosition = scene.camera.position
        hasLastView = true
        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            cameraPosition: scene.camera.position,
            frameIndex: rtFrameIndex,
            imageSize: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            ambientIntensity: 0.12,
            historyWeight: 0.3,
            historyClamp: 0.5,
            samplesPerPixel: 4,
            dirLightCount: 1,
            pointLightCount: 1,
            areaLightCount: 1,
            areaLightSamples: 2
        )
        rtFrameIndex &+= 1
        memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)

        let dirPtr = dirLightBuffer.contents().bindMemory(to: RTDirectionalLightSwift.self, capacity: 4)
        dirPtr[0] = RTDirectionalLightSwift(direction: SIMD3<Float>(-0.5, -1.0, -0.3),
                                            intensity: 1.0,
                                            color: SIMD3<Float>(1.0, 1.0, 1.0),
                                            padding: 0)

        let pointPtr = pointLightBuffer.contents().bindMemory(to: RTPointLightSwift.self, capacity: 8)
        pointPtr[0] = RTPointLightSwift(position: SIMD3<Float>(0.0, 4.0, 0.0),
                                        intensity: 8.0,
                                        color: SIMD3<Float>(1.0, 0.95, 0.9),
                                        radius: 0.0)

        let areaPtr = areaLightBuffer.contents().bindMemory(to: RTAreaLightSwift.self, capacity: 4)
        areaPtr[0] = RTAreaLightSwift(position: SIMD3<Float>(0.0, 5.0, -2.0),
                                      intensity: 6.0,
                                      u: SIMD3<Float>(1.5, 0.0, 0.0),
                                      padding0: 0,
                                      v: SIMD3<Float>(0.0, 0.0, 1.0),
                                      padding1: 0,
                                      color: SIMD3<Float>(0.9, 0.95, 1.0),
                                      padding2: 0)

        if let tlas = tlas,
           let geometry = geometry,
           let accum = accumulationTexture,
           let enc = rtCommandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(rtPipelineState)
            enc.setTexture(drawable.texture, index: 0)
            enc.setTexture(accum, index: 1)
            enc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            enc.setAccelerationStructure(tlas, bufferIndex: BufferIndex.rtAccel.rawValue)
            enc.setBuffer(geometry.vertexBuffer, offset: 0, index: BufferIndex.rtVertices.rawValue)
            enc.setBuffer(geometry.indexBuffer, offset: 0, index: BufferIndex.rtIndices.rawValue)
            enc.setBuffer(geometry.instanceInfoBuffer, offset: 0, index: BufferIndex.rtInstances.rawValue)
            enc.setBuffer(dirLightBuffer, offset: 0, index: BufferIndex.rtDirLights.rawValue)
            enc.setBuffer(pointLightBuffer, offset: 0, index: BufferIndex.rtPointLights.rawValue)
            enc.setBuffer(areaLightBuffer, offset: 0, index: BufferIndex.rtAreaLights.rawValue)

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

private func matrixAlmostEqual(_ a: matrix_float4x4, _ b: matrix_float4x4, eps: Float) -> Bool {
    let da0 = abs(a.columns.0 - b.columns.0)
    let da1 = abs(a.columns.1 - b.columns.1)
    let da2 = abs(a.columns.2 - b.columns.2)
    let da3 = abs(a.columns.3 - b.columns.3)
    return max(da0.x, da0.y, da0.z, da0.w) <= eps
        && max(da1.x, da1.y, da1.z, da1.w) <= eps
        && max(da2.x, da2.y, da2.z, da2.w) <= eps
        && max(da3.x, da3.y, da3.z, da3.w) <= eps
}
