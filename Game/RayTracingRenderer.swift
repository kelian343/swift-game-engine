//
//  RayTracingRenderer.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit
import simd

final class RayTracingRenderer {
    private let device: MTLDevice

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
    private var lastSceneRevision: UInt64 = 0

    private let dirLightBuffer: MTLBuffer
    private let pointLightBuffer: MTLBuffer
    private let areaLightBuffer: MTLBuffer

    init?(device: MTLDevice) {
        self.device = device
        self.rtScene = RayTracingScene(device: device)

        guard let rtBuffer = device.makeBuffer(length: MemoryLayout<RTFrameUniformsSwift>.stride,
                                               options: [.storageModeShared]) else {
            return nil
        }
        self.rtFrameBuffer = rtBuffer

        guard let blueNoise = RayTracingRenderer.makeBlueNoiseTexture(device: device) else {
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
    }

    func render(drawable: CAMetalDrawable,
                drawableSize: CGSize,
                items: [RenderItem],
                camera: Camera,
                projection: matrix_float4x4,
                viewMatrix: matrix_float4x4,
                sceneRevision: UInt64,
                dt: Float,
                commandQueue: MTLCommandQueue) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let tlas = rtScene.buildAccelerationStructures(items: items, commandBuffer: commandBuffer)
        let geometry = rtScene.buildGeometryBuffers(items: items)

        let viewProj = simd_mul(projection, viewMatrix)
        let invViewProj = simd_inverse(viewProj)
        let width = max(Int(drawableSize.width), 1)
        let height = max(Int(drawableSize.height), 1)

        let resetHistory = ensureRenderTargets(width: width, height: height)
            || !hasLastView
            || sceneRevision != lastSceneRevision

        if sceneRevision != lastSceneRevision {
            lastSceneRevision = sceneRevision
        }

        let prevViewProj = hasLastView ? lastViewProj : viewProj
        let prevCameraPosition = hasLastView ? lastCameraPosition : camera.position
        let camMove = simd_distance(camera.position, prevCameraPosition)
        let camSpeed = camMove / max(dt, 0.0001)
        let cameraMotion = min(max(camSpeed / 2.5, 0.0), 1.0)

        if resetHistory {
            rtFrameIndex = 0
        }

        lastViewProj = viewProj
        lastCameraPosition = camera.position
        hasLastView = true

        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            prevViewProj: prevViewProj,
            cameraPosition: camera.position,
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

        updateLightBuffers()

        encodeRaytracePass(commandBuffer: commandBuffer,
                           tlas: tlas,
                           geometry: geometry,
                           rtFrame: rtFrame,
                           width: width,
                           height: height)

        encodeDenoisePasses(commandBuffer: commandBuffer,
                            rtFrame: &rtFrame,
                            width: width,
                            height: height)

        encodeCombinePass(commandBuffer: commandBuffer,
                          rtFrame: rtFrame,
                          drawable: drawable,
                          width: width,
                          height: height)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func encodeRaytracePass(commandBuffer: MTLCommandBuffer,
                                    tlas: MTLAccelerationStructure?,
                                    geometry: RayTracingScene.GeometryBuffers?,
                                    rtFrame: RTFrameUniformsSwift,
                                    width: Int,
                                    height: Int) {
        guard let tlas = tlas,
              let geometry = geometry,
              let rtColor = rtColorTexture,
              let gNormal = gNormalTexture,
              let gDepth = gDepthTexture,
              let gRoughness = gRoughnessTexture,
              let gAlbedo = gAlbedoTexture,
              let gShadow = gShadowTexture,
              let rtDirect = rtDirectTexture,
              let rtIndirect = rtIndirectTexture,
              let enc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

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

        dispatch(enc: enc, width: width, height: height)
        enc.endEncoding()
    }

    private func encodeDenoisePasses(commandBuffer: MTLCommandBuffer,
                                     rtFrame: inout RTFrameUniformsSwift,
                                     width: Int,
                                     height: Int) {
        guard let gNormal = gNormalTexture,
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
              historyShadowTextures.count == 2 else {
            return
        }

        let prevIndex = historyIndex
        let nextIndex = 1 - historyIndex

        if let rtDirect = rtDirectTexture,
           let temporalEnc = commandBuffer.makeComputeCommandEncoder() {
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
            dispatch(enc: temporalEnc, width: width, height: height)
            temporalEnc.endEncoding()
        }

        if let rtIndirect = rtIndirectTexture,
           let temporalEnc = commandBuffer.makeComputeCommandEncoder() {
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
            dispatch(enc: temporalEnc, width: width, height: height)
            temporalEnc.endEncoding()
        }

        historyIndex = nextIndex

        let directSigma: Float = 2.5
        let indirectSigma: Float = 9.0

        var spatialFrame = rtFrame
        spatialFrame.atrousStep = 1.0

        spatialFrame.denoiseSigma = directSigma
        memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
        if let spatialEnc = commandBuffer.makeComputeCommandEncoder() {
            spatialEnc.setComputePipelineState(spatialPipelineState)
            spatialEnc.setTexture(temporalDirect, index: 0)
            spatialEnc.setTexture(gNormal, index: 1)
            spatialEnc.setTexture(gDepth, index: 2)
            spatialEnc.setTexture(gRoughness, index: 3)
            spatialEnc.setTexture(gAlbedo, index: 4)
            spatialEnc.setTexture(atrousDirect, index: 5)
            spatialEnc.setTexture(historyDirectMomentsTextures[nextIndex], index: 6)
            spatialEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            dispatch(enc: spatialEnc, width: width, height: height)
            spatialEnc.endEncoding()
        }

        spatialFrame.denoiseSigma = indirectSigma
        memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
        if let spatialEnc = commandBuffer.makeComputeCommandEncoder() {
            spatialEnc.setComputePipelineState(spatialPipelineState)
            spatialEnc.setTexture(temporalIndirect, index: 0)
            spatialEnc.setTexture(gNormal, index: 1)
            spatialEnc.setTexture(gDepth, index: 2)
            spatialEnc.setTexture(gRoughness, index: 3)
            spatialEnc.setTexture(gAlbedo, index: 4)
            spatialEnc.setTexture(atrousIndirect, index: 5)
            spatialEnc.setTexture(historyIndirectMomentsTextures[nextIndex], index: 6)
            spatialEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            dispatch(enc: spatialEnc, width: width, height: height)
            spatialEnc.endEncoding()
        }

        spatialFrame.atrousStep = 2.0
        spatialFrame.denoiseSigma = directSigma
        memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
        if let spatialEnc2 = commandBuffer.makeComputeCommandEncoder() {
            spatialEnc2.setComputePipelineState(spatialPipelineState)
            spatialEnc2.setTexture(atrousDirect, index: 0)
            spatialEnc2.setTexture(gNormal, index: 1)
            spatialEnc2.setTexture(gDepth, index: 2)
            spatialEnc2.setTexture(gRoughness, index: 3)
            spatialEnc2.setTexture(gAlbedo, index: 4)
            spatialEnc2.setTexture(temporalDirect, index: 5)
            spatialEnc2.setTexture(historyDirectMomentsTextures[nextIndex], index: 6)
            spatialEnc2.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            dispatch(enc: spatialEnc2, width: width, height: height)
            spatialEnc2.endEncoding()
        }

        spatialFrame.denoiseSigma = indirectSigma
        memcpy(rtFrameBuffer.contents(), &spatialFrame, MemoryLayout<RTFrameUniformsSwift>.stride)
        if let spatialEnc2 = commandBuffer.makeComputeCommandEncoder() {
            spatialEnc2.setComputePipelineState(spatialPipelineState)
            spatialEnc2.setTexture(atrousIndirect, index: 0)
            spatialEnc2.setTexture(gNormal, index: 1)
            spatialEnc2.setTexture(gDepth, index: 2)
            spatialEnc2.setTexture(gRoughness, index: 3)
            spatialEnc2.setTexture(gAlbedo, index: 4)
            spatialEnc2.setTexture(temporalIndirect, index: 5)
            spatialEnc2.setTexture(historyIndirectMomentsTextures[nextIndex], index: 6)
            spatialEnc2.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
            dispatch(enc: spatialEnc2, width: width, height: height)
            spatialEnc2.endEncoding()
        }
    }

    private func encodeCombinePass(commandBuffer: MTLCommandBuffer,
                                   rtFrame: RTFrameUniformsSwift,
                                   drawable: CAMetalDrawable,
                                   width: Int,
                                   height: Int) {
        guard let temporalDirect = temporalDirectTexture,
              let temporalIndirect = temporalIndirectTexture,
              let combineEnc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        combineEnc.setComputePipelineState(combinePipelineState)
        combineEnc.setTexture(temporalDirect, index: 0)
        combineEnc.setTexture(temporalIndirect, index: 1)
        combineEnc.setTexture(drawable.texture, index: 2)
        combineEnc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
        dispatch(enc: combineEnc, width: width, height: height)
        combineEnc.endEncoding()
    }

    private func ensureRenderTargets(width: Int, height: Int) -> Bool {
        if rtColorTexture != nil
            && rtColorTexture?.width == width
            && rtColorTexture?.height == height {
            return false
        }

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
        return true
    }

    private func updateLightBuffers() {
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
    }

    private func dispatch(enc: MTLComputeCommandEncoder, width: Int, height: Int) {
        let tgW = 8
        let tgH = 8
        let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}

private extension RayTracingRenderer {
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
