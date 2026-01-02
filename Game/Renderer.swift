//
//  Renderer.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

// Our platform independent renderer class

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

    private var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    private var rotation: Float = 0

    // Scene / draw calls
    private var items: [RenderItem] = []

    // Fallback texture if material has no texture
    private let fallbackWhite: TextureResource

    @MainActor
    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device else { return nil }
        self.device = device

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

        // Fallback: 1x1 white
        self.fallbackWhite = TextureResource(device: device, source: .solid(width: 1, height: 1, r: 255, g: 255, b: 255, a: 255), label: "FallbackWhite")

        super.init()

        // Default demo scene (procedural mesh + procedural texture)
        let demoMesh = GPUMesh(device: device, data: ProceduralMeshes.box(size: 4), label: "DemoBox")
        let demoTex = TextureResource(device: device, source: ProceduralTextures.checkerboard(), label: "Checkerboard")
        let demoMat = Material(baseColorTexture: demoTex)
        let demoItem = RenderItem(mesh: demoMesh, material: demoMat, modelMatrix: matrix_identity_float4x4)
        self.items = [demoItem]

        // Residency: include current meshes/textures/uniform ring
        rebuildResidency()
    }

    /// External API: set draw calls (your scene/system will call this)
    func setItems(_ newItems: [RenderItem]) {
        self.items = newItems
        rebuildResidency()
    }

    private func rebuildResidency() {
        let meshes = items.map { $0.mesh }
        let textures = items.compactMap { $0.material.baseColorTexture?.texture }
        context.prepareResidency(meshes: meshes,
                                textures: textures + [fallbackWhite.texture],
                                uniforms: uniformRing.buffer)
    }

    private func writeUniforms(_ ptr: UnsafeMutablePointer<Uniforms>, modelMatrix: matrix_float4x4) {
        ptr[0].projectionMatrix = projectionMatrix

        let viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0)
        ptr[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let rpd = context.currentRenderPassDescriptor(from: view) else { return }

        frameSync.waitIfNeeded(timeoutMS: 10)

        let u = uniformRing.next()
        let allocator = context.allocators[u.index]
        allocator.reset()

        context.commandBuffer.beginCommandBuffer(allocator: allocator)

        guard let enc = context.commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            fatalError("Failed to create render command encoder")
        }

        enc.label = "Primary Render Encoder"
        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)

        // Bind argument tables once
        enc.setArgumentTable(context.vertexTable, stages: .vertex)
        enc.setArgumentTable(context.fragmentTable, stages: .fragment)

        // Per-frame: rotate demo / (you can move this logic outside later)
        rotation += 0.01

        for item in items {
            // Material state (culling, winding)
            enc.setCullMode(item.material.cullMode)
            enc.setFrontFacing(item.material.frontFacing)

            // Per-item uniforms
            let rotAxis = SIMD3<Float>(1, 1, 0)
            let rotM = matrix4x4_rotation(radians: rotation, axis: rotAxis)
            let model = simd_mul(item.modelMatrix, rotM)

            writeUniforms(u.pointer, modelMatrix: model)

            let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
            context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)
            context.fragmentTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)

            // Mesh buffers (single vertex buffer layout)
            context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress, index: BufferIndex.meshVertices.rawValue)

            // Texture
            let tex = item.material.baseColorTexture?.texture ?? fallbackWhite.texture
            context.fragmentTable.setTexture(tex.gpuResourceID, index: TextureIndex.baseColor.rawValue)

            // Draw
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
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(
            fovyRadians: radians_from_degrees(65),
            aspectRatio: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )
    }
}
