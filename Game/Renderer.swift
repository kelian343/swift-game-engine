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
    private let combinePipelineState: MTLComputePipelineState
    private let rtScene: RayTracingScene
    private let rtFrameBuffer: MTLBuffer
    private let blueNoiseTexture: MTLTexture
    private var rtFrameIndex: UInt32 = 0
    private var rtColorTexture: MTLTexture?
    private var gNormalTexture: MTLTexture?
    private var gDepthTexture: MTLTexture?
    private var gRoughnessTexture: MTLTexture?
    private var gAlbedoTexture: MTLTexture?
    private var gShadowTexture: MTLTexture?
    private var temporalDirectTexture: MTLTexture?
    private var temporalIndirectTexture: MTLTexture?
    private var atrousDirectTexture: MTLTexture?
    private var atrousIndirectTexture: MTLTexture?
    private var rtDirectTexture: MTLTexture?
    private var rtIndirectTexture: MTLTexture?
    private var historyDirectColorTextures: [MTLTexture] = []
    private var historyDirectMomentsTextures: [MTLTexture] = []
    private var historyIndirectColorTextures: [MTLTexture] = []
    private var historyIndirectMomentsTextures: [MTLTexture] = []
    private var historyNormalTextures: [MTLTexture] = []
    private var historyDepthTextures: [MTLTexture] = []
    private var historyShadowTextures: [MTLTexture] = []
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
            guard let cn = library?.makeFunction(name: "combineKernel") else {
                print("Combine kernel not found")
                return nil
            }
            self.combinePipelineState = try device.makeComputePipelineState(function: cn)
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
        guard let blueNoise = Renderer.makeBlueNoiseTexture(device: device) else {
            return nil
        }
        self.blueNoiseTexture = blueNoise
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
            gShadowTexture = makeTex(.r16Float, [.shaderRead, .shaderWrite], "GBufferShadow")
            temporalDirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "TemporalDirect")
            temporalIndirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "TemporalIndirect")
            atrousDirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "AtrousDirect")
            atrousIndirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "AtrousIndirect")
            rtDirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "RTDirect")
            rtIndirectTexture = makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "RTIndirect")
            historyDirectColorTextures = [
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryDirectColorA"),
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryDirectColorB")
            ]
            historyDirectMomentsTextures = [
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryDirectMomentsA"),
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryDirectMomentsB")
            ]
            historyIndirectColorTextures = [
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryIndirectColorA"),
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryIndirectColorB")
            ]
            historyIndirectMomentsTextures = [
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryIndirectMomentsA"),
                makeTex(.rg16Float, [.shaderRead, .shaderWrite], "HistoryIndirectMomentsB")
            ]
            historyNormalTextures = [
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryNormalA"),
                makeTex(.rgba16Float, [.shaderRead, .shaderWrite], "HistoryNormalB")
            ]
            historyDepthTextures = [
                makeTex(.r32Float, [.shaderRead, .shaderWrite], "HistoryDepthA"),
                makeTex(.r32Float, [.shaderRead, .shaderWrite], "HistoryDepthB")
            ]
            historyShadowTextures = [
                makeTex(.r16Float, [.shaderRead, .shaderWrite], "HistoryShadowA"),
                makeTex(.r16Float, [.shaderRead, .shaderWrite], "HistoryShadowB")
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
        let camMove = simd_distance(scene.camera.position, prevCameraPosition)
        let camSpeed = camMove / max(dt, 0.0001)
        let cameraMotion = min(max(camSpeed / 2.5, 0.0), 1.0)

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
            cameraMotion: cameraMotion,
            exposure: 1.7,
            shadowConsistency: 0.0,
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
           let gShadow = gShadowTexture,
           let rtDirect = rtDirectTexture,
           let rtIndirect = rtIndirectTexture,
           let enc = rtCommandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(rtPipelineState)
            enc.setTexture(rtColor, index: 0)
            enc.setTexture(gNormal, index: 1)
            enc.setTexture(gDepth, index: 2)
            enc.setTexture(gRoughness, index: 3)
            enc.setTexture(gAlbedo, index: 4)
            enc.setTexture(gShadow, index: 5)
            enc.setTexture(rtDirect, index: 6)
            enc.setTexture(rtIndirect, index: 7)
            enc.setTexture(blueNoiseTexture, index: 8)
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
                enc.__setTextures(texArray, with: NSRange(location: 9, length: count))
            }

            let tgW = 8
            let tgH = 8
            let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            enc.endEncoding()
        }

        if let gNormal = gNormalTexture,
           let gDepth = gDepthTexture,
           let gRoughness = gRoughnessTexture,
           let gAlbedo = gAlbedoTexture,
           let gShadow = gShadowTexture,
           let temporalDirect = temporalDirectTexture,
           let temporalIndirect = temporalIndirectTexture,
           let atrousDirect = atrousDirectTexture,
           let atrousIndirect = atrousIndirectTexture,
           historyDirectColorTextures.count == 2,
           historyDirectMomentsTextures.count == 2,
           historyIndirectColorTextures.count == 2,
           historyIndirectMomentsTextures.count == 2,
           historyNormalTextures.count == 2,
           historyDepthTextures.count == 2,
           historyShadowTextures.count == 2 {
            let prevIndex = historyIndex
            let nextIndex = 1 - historyIndex

            if let rtDirect = rtDirectTexture,
               let temporalEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                rtFrame.shadowConsistency = 1.0
                memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
                temporalEnc.setComputePipelineState(temporalPipelineState)
                temporalEnc.setTexture(rtDirect, index: 0)
                temporalEnc.setTexture(gNormal, index: 1)
                temporalEnc.setTexture(gDepth, index: 2)
                temporalEnc.setTexture(gRoughness, index: 3)
                temporalEnc.setTexture(historyDirectColorTextures[prevIndex], index: 4)
                temporalEnc.setTexture(historyDirectMomentsTextures[prevIndex], index: 5)
                temporalEnc.setTexture(historyNormalTextures[prevIndex], index: 6)
                temporalEnc.setTexture(historyDepthTextures[prevIndex], index: 7)
                temporalEnc.setTexture(historyDirectColorTextures[nextIndex], index: 8)
                temporalEnc.setTexture(historyDirectMomentsTextures[nextIndex], index: 9)
                temporalEnc.setTexture(historyNormalTextures[nextIndex], index: 10)
                temporalEnc.setTexture(historyDepthTextures[nextIndex], index: 11)
                temporalEnc.setTexture(temporalDirect, index: 12)
                temporalEnc.setTexture(gShadow, index: 13)
                temporalEnc.setTexture(historyShadowTextures[prevIndex], index: 14)
                temporalEnc.setTexture(historyShadowTextures[nextIndex], index: 15)
                temporalEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                temporalEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                temporalEnc.endEncoding()
            }

            if let rtIndirect = rtIndirectTexture,
               let temporalEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                rtFrame.shadowConsistency = 0.0
                memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
                temporalEnc.setComputePipelineState(temporalPipelineState)
                temporalEnc.setTexture(rtIndirect, index: 0)
                temporalEnc.setTexture(gNormal, index: 1)
                temporalEnc.setTexture(gDepth, index: 2)
                temporalEnc.setTexture(gRoughness, index: 3)
                temporalEnc.setTexture(historyIndirectColorTextures[prevIndex], index: 4)
                temporalEnc.setTexture(historyIndirectMomentsTextures[prevIndex], index: 5)
                temporalEnc.setTexture(historyNormalTextures[prevIndex], index: 6)
                temporalEnc.setTexture(historyDepthTextures[prevIndex], index: 7)
                temporalEnc.setTexture(historyIndirectColorTextures[nextIndex], index: 8)
                temporalEnc.setTexture(historyIndirectMomentsTextures[nextIndex], index: 9)
                temporalEnc.setTexture(historyNormalTextures[nextIndex], index: 10)
                temporalEnc.setTexture(historyDepthTextures[nextIndex], index: 11)
                temporalEnc.setTexture(temporalIndirect, index: 12)
                temporalEnc.setTexture(gShadow, index: 13)
                temporalEnc.setTexture(historyShadowTextures[prevIndex], index: 14)
                temporalEnc.setTexture(historyShadowTextures[nextIndex], index: 15)
                temporalEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                temporalEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                temporalEnc.endEncoding()
            }

            historyIndex = nextIndex

            let directSigma: Float = 2.5
            let indirectSigma: Float = 9.0

            var spatialFrame = rtFrame
            spatialFrame.atrousStep = 1.0

            spatialFrame.denoiseSigma = directSigma
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
            if let spatialEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc.setComputePipelineState(spatialPipelineState)
                spatialEnc.setTexture(temporalDirect, index: 0)
                spatialEnc.setTexture(gNormal, index: 1)
                spatialEnc.setTexture(gDepth, index: 2)
                spatialEnc.setTexture(gRoughness, index: 3)
                spatialEnc.setTexture(gAlbedo, index: 4)
                spatialEnc.setTexture(atrousDirect, index: 5)
                spatialEnc.setTexture(historyDirectMomentsTextures[nextIndex], index: 6)
                spatialEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc.endEncoding()
            }

            spatialFrame.denoiseSigma = indirectSigma
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
            if let spatialEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc.setComputePipelineState(spatialPipelineState)
                spatialEnc.setTexture(temporalIndirect, index: 0)
                spatialEnc.setTexture(gNormal, index: 1)
                spatialEnc.setTexture(gDepth, index: 2)
                spatialEnc.setTexture(gRoughness, index: 3)
                spatialEnc.setTexture(gAlbedo, index: 4)
                spatialEnc.setTexture(atrousIndirect, index: 5)
                spatialEnc.setTexture(historyIndirectMomentsTextures[nextIndex], index: 6)
                spatialEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc.endEncoding()
            }

            spatialFrame.atrousStep = 2.0
            spatialFrame.denoiseSigma = directSigma
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
            if let spatialEnc2 = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc2.setComputePipelineState(spatialPipelineState)
                spatialEnc2.setTexture(atrousDirect, index: 0)
                spatialEnc2.setTexture(gNormal, index: 1)
                spatialEnc2.setTexture(gDepth, index: 2)
                spatialEnc2.setTexture(gRoughness, index: 3)
                spatialEnc2.setTexture(gAlbedo, index: 4)
                spatialEnc2.setTexture(temporalDirect, index: 5)
                spatialEnc2.setTexture(historyDirectMomentsTextures[nextIndex], index: 6)
                spatialEnc2.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc2.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc2.endEncoding()
            }

            spatialFrame.denoiseSigma = indirectSigma
            memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
            if let spatialEnc2 = rtCommandBuffer.makeComputeCommandEncoder() {
                spatialEnc2.setComputePipelineState(spatialPipelineState)
                spatialEnc2.setTexture(atrousIndirect, index: 0)
                spatialEnc2.setTexture(gNormal, index: 1)
                spatialEnc2.setTexture(gDepth, index: 2)
                spatialEnc2.setTexture(gRoughness, index: 3)
                spatialEnc2.setTexture(gAlbedo, index: 4)
                spatialEnc2.setTexture(temporalIndirect, index: 5)
                spatialEnc2.setTexture(historyIndirectMomentsTextures[nextIndex], index: 6)
                spatialEnc2.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                spatialEnc2.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                spatialEnc2.endEncoding()
            }

            if let combineEnc = rtCommandBuffer.makeComputeCommandEncoder() {
                combineEnc.setComputePipelineState(combinePipelineState)
                combineEnc.setTexture(temporalDirect, index: 0)
                combineEnc.setTexture(temporalIndirect, index: 1)
                combineEnc.setTexture(drawable.texture, index: 2)
                combineEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
                let tgW = 8
                let tgH = 8
                let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
                let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
                combineEnc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                combineEnc.endEncoding()
            }
        }

        rtCommandBuffer.present(drawable)
        rtCommandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}

private extension Renderer {
    static func makeBlueNoiseTexture(device: MTLDevice,
                                     width: Int = 128,
                                     height: Int = 128) -> MTLTexture? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let n0 = interleavedGradientNoise(x: x, y: y, seed: 0)
                    let n1 = interleavedGradientNoise(x: x, y: y, seed: 1)
                    let idx = (y * width + x) * 4
                    ptr[idx + 0] = UInt8(clamping: Int(n0 * 255.0))
                    ptr[idx + 1] = UInt8(clamping: Int(n1 * 255.0))
                    ptr[idx + 2] = 0
                    ptr[idx + 3] = 255
                }
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.label = "BlueNoise"
        bytes.withUnsafeBytes { raw in
            let region = MTLRegionMake2D(0, 0, width, height)
            tex.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: raw.baseAddress!,
                        bytesPerRow: width * 4)
        }
        return tex
    }

    static func interleavedGradientNoise(x: Int, y: Int, seed: Int) -> Float {
        let xf = Float(x + seed * 19)
        let yf = Float(y + seed * 7)
        let v = 0.06711056 * xf + 0.00583715 * yf
        return fract(52.9829189 * fract(v))
    }

    static func fract(_ x: Float) -> Float {
        x - floor(x)
    }
}
