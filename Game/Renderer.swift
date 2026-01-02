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

    // Main pipeline
    private let pipelineState: MTLRenderPipelineState
    // Shadow pipeline (depth only)
    private let shadowPipelineState: MTLRenderPipelineState

    private let depthState: MTLDepthStencilState
    private let fallbackWhite: TextureResource

    // Lighting & shadow modules (already created by you)
    private let shadowMap: ShadowMap
    private let lightSystem: LightSystem

    // Scene hook
    private var scene: RenderScene?
    private var sceneContext: SceneContext
    private var lastSceneRevision: UInt64 = 0

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

        // Shadow pipeline (use classic MTLRenderPipelineDescriptor for SDK compatibility)
        do {
            self.shadowPipelineState = try Renderer.buildShadowPipeline(device: device, vertexDescriptor: vDesc)
        } catch {
            print("Unable to compile shadow render pipeline state. Error info: \(error)")
            return nil
        }

        guard let ds = PipelineBuilder.makeDepthState(device: device) else { return nil }
        self.depthState = ds

        self.fallbackWhite = TextureResource(
            device: device,
            source: .solid(width: 1, height: 1, r: 255, g: 255, b: 255, a: 255),
            label: "FallbackWhite"
        )

        // Modules
        self.shadowMap = ShadowMap(device: device, size: 2048)
        self.lightSystem = LightSystem(device: device)

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

        // include: base textures + fallback + shadow map + uniform buffer + light buffer
        context.prepareResidency(
            meshes: meshes,
            textures: textures + [fallbackWhite.texture, shadowMap.texture],
            uniforms: uniformRing.buffer
        )

        // If your residency model requires explicit add for buffers too:
        // (Most Metal4 setups still work without, but if you see validation issues,
        // we can extend RenderContext.prepareResidency to take extraBuffers.)
        // e.g. include lightSystem.buffer as well.
    }

    // MARK: - Uniform packing

    private func writeUniforms(_ ptr: UnsafeMutablePointer<Uniforms>,
                               projection: matrix_float4x4,
                               view: matrix_float4x4,
                               model: matrix_float4x4,
                               lightViewProj: matrix_float4x4) {

        // NOTE: This matches the *updated* ShaderTypes.h layout I provided earlier.
        ptr[0].projectionMatrix = projection
        ptr[0].viewMatrix = view
        ptr[0].modelMatrix = model
        ptr[0].lightViewProjMatrix = lightViewProj

        let n3 = NormalMatrix.fromModel(model)
        ptr[0].normalMatrix0 = SIMD4<Float>(n3.columns.0, 0)
        ptr[0].normalMatrix1 = SIMD4<Float>(n3.columns.1, 0)
        ptr[0].normalMatrix2 = SIMD4<Float>(n3.columns.2, 0)
    }

    // MARK: - Shadow pipeline builder (SDK-stable)

    private static func buildShadowPipeline(device: MTLDevice,
                                            vertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()!
        let v = library.makeFunction(name: "shadowVertex")!

        let pd = MTLRenderPipelineDescriptor()
        pd.label = "ShadowPipeline"
        pd.vertexFunction = v
        pd.fragmentFunction = nil
        pd.vertexDescriptor = vertexDescriptor
        pd.depthAttachmentPixelFormat = .depth32Float

        return try device.makeRenderPipelineState(descriptor: pd)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        guard let scene = scene else { return }
        guard let drawable = view.currentDrawable else { return }
        guard let mainRPD = context.currentRenderPassDescriptor(from: view) else { return }

        let now = CACurrentMediaTime()
        let dt = Float(max(0.0, min(now - lastTime, 0.1)))
        lastTime = now

        scene.update(dt: dt)

        let items = scene.renderItems
        rebuildResidencyIfNeeded(items: items)

        // Camera matrices
        let projection = scene.camera.projection
        let viewM = scene.camera.view

        // Light params + light view-projection
        lightSystem.update(cameraPos: scene.camera.position)
        let lightVP = lightSystem.lightViewProj()

        // Sync
        frameSync.waitIfNeeded(timeoutMS: 10)

        // Begin frame allocation (allocator slot)
        let frameSlot = uniformRing.beginFrame()
        let allocator = context.allocators[frameSlot]
        allocator.reset()
        context.commandBuffer.beginCommandBuffer(allocator: allocator)

        // ---------------------------
        // Pass 1: Shadow (depth-only)
        // ---------------------------
        if let shadowEnc = context.commandBuffer.makeRenderCommandEncoder(descriptor: shadowMap.passDesc) {
            shadowEnc.label = "Shadow Pass"
            shadowEnc.setRenderPipelineState(shadowPipelineState)
            shadowEnc.setDepthStencilState(depthState)

            shadowEnc.setCullMode(.back)
            shadowEnc.setFrontFacing(.counterClockwise)

            shadowEnc.setArgumentTable(context.vertexTable, stages: .vertex)

            for item in items {
                let u = uniformRing.allocate()
                writeUniforms(u.pointer, projection: projection, view: viewM, model: item.modelMatrix, lightViewProj: lightVP)

                let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
                context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)

                context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress, index: BufferIndex.meshVertices.rawValue)

                shadowEnc.drawIndexedPrimitives(
                    primitiveType: .triangle,
                    indexCount: item.mesh.indexCount,
                    indexType: item.mesh.indexType,
                    indexBuffer: item.mesh.indexBuffer.gpuAddress,
                    indexBufferLength: item.mesh.indexBuffer.length
                )
            }

            shadowEnc.endEncoding()
        }

        // ---------------------------
        // Pass 2: Main
        // ---------------------------
        guard let enc = context.commandBuffer.makeRenderCommandEncoder(descriptor: mainRPD) else {
            fatalError("Failed to create main render command encoder")
        }

        enc.label = "Main Pass"
        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthState)

        enc.setArgumentTable(context.vertexTable, stages: .vertex)
        enc.setArgumentTable(context.fragmentTable, stages: .fragment)

        // Bind light buffer + shadow map once (bindless)
        context.fragmentTable.setAddress(lightSystem.buffer.gpuAddress, index: BufferIndex.light.rawValue)
        context.fragmentTable.setTexture(shadowMap.texture.gpuResourceID, index: TextureIndex.shadowMap.rawValue)

        for item in items {
            enc.setCullMode(item.material.cullMode)
            enc.setFrontFacing(item.material.frontFacing)

            let u = uniformRing.allocate()
            writeUniforms(u.pointer, projection: projection, view: viewM, model: item.modelMatrix, lightViewProj: lightVP)

            let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
            context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)
            context.fragmentTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)

            context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress, index: BufferIndex.meshVertices.rawValue)

            let tex = item.material.baseColorTexture?.texture ?? fallbackWhite.texture
            context.fragmentTable.setTexture(tex.gpuResourceID, index: TextureIndex.baseColor.rawValue)

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
        scene?.camera.updateProjection(width: Float(size.width), height: Float(size.height))
    }
}
