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

    init?(device: MTLDevice) {
        self.device = device
        self.rtScene = RayTracingScene(device: device)

        guard let rtBuffer = device.makeBuffer(length: MemoryLayout<RTFrameUniformsSwift>.stride,
                                               options: [.storageModeShared]) else {
            return nil
        }
        self.rtFrameBuffer = rtBuffer

        guard let dirBuf = device.makeBuffer(length: MemoryLayout<RTDirectionalLightSwift>.stride * 4,
                                             options: [.storageModeShared]) else {
            return nil
        }
        dirBuf.label = "RTDirectionalLights"
        self.dirLightBuffer = dirBuf

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

    func encode(commandBuffer: MTLCommandBuffer,
                outputTexture: MTLTexture,
                outputSize: CGSize,
                items: [RenderItem],
                camera: Camera,
                projection: matrix_float4x4,
                viewMatrix: matrix_float4x4) {
        let geometry = rtScene.buildGeometryBuffers(items: items)
        let tlas = rtScene.buildAccelerationStructures(items: items, commandBuffer: commandBuffer)

        let viewProj = simd_mul(projection, viewMatrix)
        let invViewProj = simd_inverse(viewProj)
        let width = max(Int(outputSize.width), 1)
        let height = max(Int(outputSize.height), 1)
        let (envSH0, envSH1) = RayTracingRenderer.makeHemisphereSH()

        var rtFrame = RTFrameUniformsSwift(
            invViewProj: invViewProj,
            cameraPosition: camera.position,
            imageSize: SIMD2<UInt32>(UInt32(width), UInt32(height)),
            ambientIntensity: 0.2,
            pad0: 0,
            textureCount: UInt32(geometry?.textures.count ?? 0),
            dirLightCount: 1,
            envSH0: envSH0,
            envSH1: envSH1,
            envSH2: .zero,
            envSH3: .zero,
            envSH4: .zero,
            envSH5: .zero,
            envSH6: .zero,
            envSH7: .zero,
            envSH8: .zero
        )
        memcpy(rtFrameBuffer.contents(), &rtFrame, MemoryLayout<RTFrameUniformsSwift>.stride)

        updateLightBuffers()

        encodeRaytracePass(commandBuffer: commandBuffer,
                           tlas: tlas,
                           geometry: geometry,
                           rtFrame: rtFrame,
                           outputTexture: outputTexture,
                           width: width,
                           height: height)
    }

    private func encodeRaytracePass(commandBuffer: MTLCommandBuffer,
                                    tlas: MTLAccelerationStructure?,
                                    geometry: RayTracingScene.GeometryBuffers?,
                                    rtFrame: RTFrameUniformsSwift,
                                    outputTexture: MTLTexture,
                                    width: Int,
                                    height: Int) {
        guard let tlas = tlas,
              let geometry = geometry,
              let enc = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        enc.setComputePipelineState(rtPipelineState)
        enc.setTexture(outputTexture, index: 0)
        enc.setBuffer(rtFrameBuffer, offset: 0, index: BufferIndex.rtFrame.rawValue)
        enc.setAccelerationStructure(tlas, bufferIndex: BufferIndex.rtAccel.rawValue)
        enc.setBuffer(geometry.staticVertexBuffer, offset: 0, index: BufferIndex.rtVertices.rawValue)
        enc.setBuffer(geometry.staticIndexBuffer, offset: 0, index: BufferIndex.rtIndices.rawValue)
        enc.setBuffer(geometry.instanceInfoBuffer, offset: 0, index: BufferIndex.rtInstances.rawValue)
        enc.setBuffer(geometry.staticUVBuffer, offset: 0, index: BufferIndex(rawValue: 7)!.rawValue)
        enc.setBuffer(dirLightBuffer, offset: 0, index: BufferIndex.rtDirLights.rawValue)
        enc.setBuffer(geometry.dynamicVertexBuffer, offset: 0, index: BufferIndex(rawValue: 9)!.rawValue)
        enc.setBuffer(geometry.dynamicIndexBuffer, offset: 0, index: BufferIndex(rawValue: 10)!.rawValue)
        enc.setBuffer(geometry.dynamicUVBuffer, offset: 0, index: BufferIndex(rawValue: 11)!.rawValue)

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
        dirPtr[0] = RTDirectionalLightSwift(direction: SIMD3<Float>(-0.2, -1.0, -0.4),
                                            intensity: 2.6,
                                            color: SIMD3<Float>(1.0, 0.95, 0.85),
                                            padding: 0)
    }

    private func dispatch(enc: MTLComputeCommandEncoder, width: Int, height: Int) {
        let tgW = 8
        let tgH = 8
        let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        enc.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    private static func makeHemisphereSH() -> (SIMD3<Float>, SIMD3<Float>) {
        let sky = SIMD3<Float>(0.7, 0.8, 1.0)
        let ground = SIMD3<Float>(0.3, 0.25, 0.2)
        let avg = (sky + ground) * 0.5
        let diff = (sky - ground) * 0.5
        let c0 = avg / 0.282095
        let c1 = diff / 0.488603
        return (c0, c1)
    }
}
