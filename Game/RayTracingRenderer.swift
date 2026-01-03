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
    private let rtScene: RayTracingScene
    private let rtFrameBuffer: MTLBuffer

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
                commandQueue: MTLCommandQueue) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let tlas = rtScene.buildAccelerationStructures(items: items, commandBuffer: commandBuffer)
        let geometry = rtScene.buildGeometryBuffers(items: items)

        let viewProj = simd_mul(projection, viewMatrix)
        let invViewProj = simd_inverse(viewProj)
        let width = max(Int(drawableSize.width), 1)
        let height = max(Int(drawableSize.height), 1)

        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            cameraPosition: camera.position,
            imageSize: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            ambientIntensity: 0.2,
            dirLightCount: 1,
            pointLightCount: 1,
            areaLightCount: 1,
            textureCount: UInt32(geometry?.textures.count ?? 0),
            pad0: 0
        )
        memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)

        updateLightBuffers()

        encodeRaytracePass(commandBuffer: commandBuffer,
                           tlas: tlas,
                           geometry: geometry,
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
                                    drawable: CAMetalDrawable,
                                    width: Int,
                                    height: Int) {
        guard let tlas = tlas,
              let geometry = geometry,
              let enc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        enc.setComputePipelineState(rtPipelineState)
        enc.setTexture(drawable.texture, index: 0)
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
            enc.__setTextures(texArray, with: NSRange(location: 1, length: count))
        }

        dispatch(enc: enc, width: width, height: height)
        enc.endEncoding()
    }

    private func updateLightBuffers() {
        let dirPtr = dirLightBuffer.contents().bindMemory(to: RTDirectionalLightSwift.self, capacity: 4)
        dirPtr[0] = RTDirectionalLightSwift(direction: SIMD3<Float>(-0.5, -1.0, -0.3),
                                            intensity: 1.2,
                                            color: SIMD3<Float>(1.0, 1.0, 1.0),
                                            padding: 0)

        let pointPtr = pointLightBuffer.contents().bindMemory(to: RTPointLightSwift.self, capacity: 8)
        pointPtr[0] = RTPointLightSwift(position: SIMD3<Float>(0.0, 4.0, 0.0),
                                        intensity: 9.6,
                                        color: SIMD3<Float>(1.0, 0.95, 0.9),
                                        radius: 0.0)

        let areaPtr = areaLightBuffer.contents().bindMemory(to: RTAreaLightSwift.self, capacity: 4)
        areaPtr[0] = RTAreaLightSwift(position: SIMD3<Float>(0.0, 5.0, -2.0),
                                      intensity: 7.2,
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
