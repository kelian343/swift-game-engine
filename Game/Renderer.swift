//
//  Renderer.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

// Our platform independent renderer class

import Metal
import MetalKit
import ModelIO
import simd

final class Renderer: NSObject, MTKViewDelegate {

    public let device: MTLDevice

    private let context: RenderContext
    private let frameSync: FrameSync
    private let uniformRing: UniformRingBuffer

    private var pipelineState: MTLRenderPipelineState
    private var depthState: MTLDepthStencilState

    private var colorMap: MTLTexture
    private var mesh: MTKMesh

    private var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    private var rotation: Float = 0

    @MainActor
    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device else { return nil }
        self.device = device

        // View formats (keep original)
        metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.sampleCount = 1

        // Context: Metal4 command infra + arg tables
        guard let ctx = RenderContext(view: metalKitView, maxFramesInFlight: maxBuffersInFlight) else { return nil }
        self.context = ctx

        // Sync: SharedEvent
        self.frameSync = FrameSync(device: device, maxFramesInFlight: maxBuffersInFlight)

        // Uniform ring buffer
        guard let ring = UniformRingBuffer(device: device, maxFramesInFlight: maxBuffersInFlight) else { return nil }
        self.uniformRing = ring

        // Pipeline + depth
        let mtlVertexDescriptor = PipelineBuilder.makeMetalVertexDescriptor()
        do {
            self.pipelineState = try PipelineBuilder.makeRenderPipeline(device: device,
                                                                        view: metalKitView,
                                                                        vertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state. Error info: \(error)")
            return nil
        }

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds

        // Mesh
        do {
            self.mesh = try MeshFactory.makeBox(device: device, vertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to build MetalKit Mesh. Error info: \(error)")
            return nil
        }

        // Texture
        do {
            self.colorMap = try TextureLoader.load(device: device, name: "ColorMap")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }

        // Residency
        context.prepareResidency(mesh: mesh, colorMap: colorMap, uniforms: uniformRing.buffer)

        super.init()
    }

    // MARK: - Per-frame update

    private func updateGameState(uniforms: UnsafeMutablePointer<Uniforms>) {
        uniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = SIMD3<Float>(1, 1, 0)
        let modelMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
        let viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0)
        uniforms[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)

        rotation += 0.01
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = context.currentRenderPassDescriptor(from: view) else { return }

        // Wait for in-flight frame budget
        frameSync.waitIfNeeded(timeoutMS: 10)

        // Allocate command recording space
        let uniformAllocation = uniformRing.next()
        let allocator = context.allocators[uniformAllocation.index]
        allocator.reset()

        // Begin command buffer using allocator (Metal4 pattern)
        context.commandBuffer.beginCommandBuffer(allocator: allocator)

        // Update CPU-side uniform data
        updateGameState(uniforms: uniformAllocation.pointer)

        // Create encoder
        guard let renderEncoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create render command encoder")
        }

        renderEncoder.label = "Primary Render Encoder"
        renderEncoder.pushDebugGroup("Draw Box")

        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)

        // Bind argument tables
        renderEncoder.setArgumentTable(context.vertexTable, stages: .vertex)
        renderEncoder.setArgumentTable(context.fragmentTable, stages: .fragment)

        // Uniforms address
        let uniformGPUAddress = uniformAllocation.buffer.gpuAddress + UInt64(uniformAllocation.offset)
        context.vertexTable.setAddress(uniformGPUAddress, index: BufferIndex.uniforms.rawValue)
        context.fragmentTable.setAddress(uniformGPUAddress, index: BufferIndex.uniforms.rawValue)

        // Mesh vertex buffers -> argument table addresses
        for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
            guard let layout = element as? MDLVertexBufferLayout else { return }
            if layout.stride != 0 {
                let vb = mesh.vertexBuffers[index]
                context.vertexTable.setAddress(vb.buffer.gpuAddress + UInt64(vb.offset), index: index)
            }
        }

        // Texture -> fragment table
        context.fragmentTable.setTexture(colorMap.gpuResourceID, index: TextureIndex.color.rawValue)

        // Draw submeshes
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(
                primitiveType: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer.gpuAddress + UInt64(submesh.indexBuffer.offset),
                indexBufferLength: submesh.indexBuffer.buffer.length
            )
        }

        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()

        // Match original residency usage + end command buffer
        context.useViewResidencySetIfAvailable(for: view)
        context.commandBuffer.endCommandBuffer()

        // Present/submit (original sequence)
        context.commandQueue.waitForDrawable(drawable)
        context.commandQueue.commit([context.commandBuffer])
        context.commandQueue.signalDrawable(drawable)

        // Signal end-of-frame event
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
