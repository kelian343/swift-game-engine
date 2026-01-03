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
    private let temporalPipelineState: MTLComputePipelineState
    private let spatialPipelineState: MTLComputePipelineState
    private let rtScene: RayTracingScene
    private let rtFrameBuffer: MTLBuffer
    private var rtFrameIndex: UInt32 = 0
    private var rtColorTexture: MTLTexture?
    private var gNormalTexture: MTLTexture?
    private var gDepthTexture: MTLTexture?
    private var gRoughnessTexture: MTLTexture?
    private var gAlbedoTexture: MTLTexture?
    private var temporalColorTexture: MTLTexture?
    private var atrousTexture: MTLTexture?
    private var historyColorTextures: [MTLTexture] = []
    private var historyMomentsTextures: [MTLTexture] = []
    private var historyNormalTextures: [MTLTexture] = []
    private var historyDepthTextures: [MTLTexture] = []
    private var historyIndex: Int = 0
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
            guard let tn = library?.makeFunction(name: "temporalReprojectKernel") else {
                print("Temporal kernel not found")
                return nil
            }
            self.temporalPipelineState = try device.makeComputePipelineState(function: tn)
            guard let sn = library?.makeFunction(name: "spatialDenoiseKernel") else {
                print("Spatial denoise kernel not found")
                return nil
            }
            self.spatialPipelineState = try device.makeComputePipelineState(function: sn)
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

        var resetHistory = false
        if rtColorTexture == nil
            || rtColorTexture?.width != width
            || rtColorTexture?.height != height {
            let makeTex: (MTLPixelFormat, MTLTextureUsage, String) -> MTLTexture = { format, usage, label in
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                                    width: width,
                                                                    height: height,
                                                                    mipmapped: false)
                desc.usage = usage
                desc.storageMode = .private
                let tex = self.device.makeTexture(descriptor: desc)!
                tex.label = label
                return tex
            }

            rtColorTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "RTColor")
            gNormalTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "GBufferNormal")
            gDepthTexture = makeTex(.r32Float, [.shaderRead, .shaderWrite], "GBufferDepth")
            gRoughnessTexture = makeTex(.r16Float, [.shaderRead, .shaderWrite], "GBufferRoughness")
            gAlbedoTexture = makeTex(.rgba8Unorm, [.shaderRead, .shaderWrite], "GBufferAlbedo")
            temporalColorTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "TemporalColor")
            atrousTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "AtrousColor")
            historyColorTextures = [
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryColorA"),
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryColorB")
            ]
            historyMomentsTextures = [
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryMomentsA"),
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryMomentsB")
            ]
            historyNormalTextures = [
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryNormalA"),
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryNormalB")
            ]
            historyDepthTextures = [
                makeTex(.r32Float, [.shaderRead, .shaderWrite], "HistoryDepthA"),
                makeTex(.r32Float, [.shaderRead, .shaderWrite], "HistoryDepthB")
            ]
            historyIndex = 0
            resetHistory = true
        }

        if !hasLastView {
            resetHistory = true
        }
        if scene.revision != lastSceneRevisionForRT {
            resetHistory = true
            lastSceneRevisionForRT = scene.revision
        }

        let prevViewProj = hasLastView ? lastViewProj : viewProj
        let prevCameraPosition = hasLastView ? lastCameraPosition : scene.camera.position

        if resetHistory {
            rtFrameIndex = 0
        }

        lastViewProj = viewProj
        lastCameraPosition = scene.camera.position
        hasLastView = true
        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            prevViewProj: prevViewProj,
            cameraPosition: scene.camera.position,
            frameIndex: rtFrameIndex,
            prevCameraPosition: prevCameraPosition,
            resetHistory: resetHistory ? 1 : 0,
            imageSize: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            ambientIntensity: 0.12,
            historyWeight: 0.2,
            historyClamp: 2.5,
            samplesPerPixel: 2,
            dirLightCount: 1,
            pointLightCount: 1,
            areaLightCount: 1,
            areaLightSamples: 2,
            textureCount: UInt32(geometry?.textures.count ?? 0),
            denoiseSigma: 6.0,
            atrousStep: 1.0,
            padding: .zero
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
           let rtColor = rtColorTexture,
           let gNormal = gNormalTexture,
           let gDepth = gDepthTexture,
           let gRoughness = gRoughnessTexture,
           let gAlbedo = gAlbedoTexture,
           let enc = rtCommandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(rtPipelineState)
            enc.setTexture(rtColor, index: 0)
            enc.setTexture(gNormal, index: 1)
            enc.setTexture(gDepth, index: 2)
            enc.setTexture(gRoughness, index: 3)
            enc.setTexture(gAlbedo, index: 4)
            enc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            enc.setAccelerationStructure(tlas, bufferIndex: BufferIndex.rtAccel.rawValue)
            enc.setBuffer(geometry.vertexBuffer, offset: 0, index: BufferIndex.rtVertices.rawValue)
            enc.setBuffer(geometry.indexBuffer, offset: 0, index: BufferIndex.rtIndices.rawValue)
            enc.setBuffer(geometry.instanceInfoBuffer, offset: 0, index: BufferIndex.rtInstances.rawValue)
            enc.setBuffer(geometry.uvBuffer, offset: 0, index: BufferIndex(rawValue: 7)!.rawValue)
            enc.setBuffer(dirLightBuffer, offset: 0, index: BufferIndex.rtDirLights.rawValue)
            enc.setBuffer(pointLightBuffer, offset: 0, index: BufferIndex.rtPointLights.rawValue)
            enc.setBuffer(areaLightBuffer, offset: 0, index: BufferIndex.rtAreaLights.rawValue)

            if !geometry.textures.isEmpty {
                let count = min(geometry.textures.count, maxRTTextures)
                let texArray: [MTLTexture?] = Array(geometry.textures.prefix(count))
                enc.__setTextures(texArray, with: NSRange(location: 5, length: count))
            }

            let tgW = 8
            let tgH = 8
            let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            enc.endEncoding()
        }

        if let rtColor = rtColorTexture,
           let gNormal = gNormalTexture,
           let gDepth = gDepthTexture,
           let gRoughness = gRoughnessTexture,
           let temporal = temporalColorTexture,
           historyColorTextures.count == 2,
           historyMomentsTextures.count == 2,
           historyNormalTextures.count == 2,
           historyDepthTextures.count == 2,
           let temporalEnc = rtCommandBuffer.makeComputeCommandEncoder() {
            let prevIndex = historyIndex
            let nextIndex = 1 - historyIndex
            temporalEnc.setComputePipelineState(temporalPipelineState)
            temporalEnc.setTexture(rtColor, index: 0)
            temporalEnc.setTexture(gNormal, index: 1)
            temporalEnc.setTexture(gDepth, index: 2)
            temporalEnc.setTexture(gRoughness, index: 3)
            temporalEnc.setTexture(historyColorTextures[prevIndex], index: 4)
            temporalEnc.setTexture(historyMomentsTextures[prevIndex], index: 5)
            temporalEnc.setTexture(historyNormalTextures[prevIndex], index: 6)
            temporalEnc.setTexture(historyDepthTextures[prevIndex], index: 7)
            temporalEnc.setTexture(historyColorTextures[nextIndex], index: 8)
            temporalEnc.setTexture(historyMomentsTextures[nextIndex], index: 9)
            temporalEnc.setTexture(historyNormalTextures[nextIndex], index: 10)
            temporalEnc.setTexture(historyDepthTextures[nextIndex], index: 11)
            temporalEnc.setTexture(temporal, index: 12)
            temporalEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            let tgW = 8
            let tgH = 8
            let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            temporalEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            temporalEnc.endEncoding()
            historyIndex = nextIndex
        }

        if let temporal = temporalColorTexture,
           let gNormal = gNormalTexture,
           let gDepth = gDepthTexture,
           let gRoughness = gRoughnessTexture,
           let gAlbedo = gAlbedoTexture,
           let atrous = atrousTexture {
            var spatialFrame = rtFrame
            spatialFrame.atrousStep = 1.0
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)

            if let spatialEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc.setComputePipelineState(spatialPipelineState)
                spatialEnc.setTexture(temporal, index: 0)
                spatialEnc.setTexture(gNormal, index: 1)
                spatialEnc.setTexture(gDepth, index: 2)
                spatialEnc.setTexture(gRoughness, index: 3)
                spatialEnc.setTexture(gAlbedo, index: 4)
                spatialEnc.setTexture(atrous, index: 5)
                spatialEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc.endEncoding()
            }

            spatialFrame.atrousStep = 2.0
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
            if let spatialEnc2 = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc2.setComputePipelineState(spatialPipelineState)
                spatialEnc2.setTexture(atrous, index: 0)
                spatialEnc2.setTexture(gNormal, index: 1)
                spatialEnc2.setTexture(gDepth, index: 2)
                spatialEnc2.setTexture(gRoughness, index: 3)
                spatialEnc2.setTexture(gAlbedo, index: 4)
                spatialEnc2.setTexture(drawable.texture, index: 5)
                spatialEnc2.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc2.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc2.endEncoding()
            }
        }

        rtCommandBuffer.present(drawable)
        rtCommandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}
