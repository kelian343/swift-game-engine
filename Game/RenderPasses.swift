//
//  RenderPasses.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

private func encodeItems(_ items: [RenderItem],
                         frame: FrameContext,
                         encoder: MTLRenderCommandEncoder) {
    for item in items {
        guard let mesh = item.mesh else { continue }
        encoder.setCullMode(item.material.cullMode)
        encoder.setFrontFacing(item.material.frontFacing)

        let u = frame.uniformRing.allocate()
        writeUniforms(u.pointer,
                      projection: frame.projection,
                      view: frame.viewMatrix,
                      model: item.modelMatrix,
                      baseColorFactor: item.material.baseColorFactor,
                      baseAlpha: item.material.alpha,
                      emissiveFactor: item.material.emissiveFactor,
                      unlit: item.material.unlit,
                      normalScale: item.material.normalScale,
                      occlusionStrength: item.material.occlusionStrength,
                      exposure: item.material.exposure,
                      toneMapEnabled: item.material.toneMapped,
                      cameraPosition: frame.cameraPosition,
                      worldOrigin: frame.cameraWorldOrigin)

        let tex = item.material.baseColorTexture?.texture ?? frame.fallbackWhite.texture
        let normalTex = item.material.normalTexture?.texture ?? frame.fallbackNormal.texture
        let emissiveTex = item.material.emissiveTexture?.texture ?? frame.fallbackEmissive.texture
        let occlusionTex = item.material.occlusionTexture?.texture ?? frame.fallbackOcclusion.texture
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: BufferIndex.meshVertices.rawValue)
        encoder.setVertexBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentTexture(tex, index: TextureIndex.baseColor.rawValue)
        encoder.setFragmentTexture(normalTex, index: TextureIndex.normal.rawValue)
        encoder.setFragmentTexture(emissiveTex, index: TextureIndex.emissive.rawValue)
        encoder.setFragmentTexture(occlusionTex, index: TextureIndex.occlusion.rawValue)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: mesh.indexType,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0
        )
    }
}

final class MainPass: RenderPass {
    let name = "Main Pass"

    func makeTarget(frame: FrameContext) -> RenderTargetSource? {
        .view
    }

    func readResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func writeResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func encode(frame: FrameContext, resources: RenderGraphResources, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.pipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encodeItems(frame.items, frame: frame, encoder: encoder)
    }
}

final class CompositePass: RenderPass {
    let name = "Composite Pass"

    func makeTarget(frame: FrameContext) -> RenderTargetSource? {
        frame.compositeItems.isEmpty ? nil : .view
    }

    func readResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func writeResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func configureRenderPassDescriptor(_ descriptor: MTLRenderPassDescriptor, frame: FrameContext) {
        if let color = descriptor.colorAttachments[0] {
            color.loadAction = .clear
            color.storeAction = .store
            color.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        if let depth = descriptor.depthAttachment {
            depth.loadAction = .dontCare
            depth.storeAction = .dontCare
        }
        if let stencil = descriptor.stencilAttachment {
            stencil.loadAction = .dontCare
            stencil.storeAction = .dontCare
        }
    }

    func encode(frame: FrameContext, resources: RenderGraphResources, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.pipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encodeItems(frame.compositeItems, frame: frame, encoder: encoder)
    }
}

final class UIPass: RenderPass {
    let name = "UI Pass"

    func makeTarget(frame: FrameContext) -> RenderTargetSource? {
        frame.overlayItems.isEmpty ? nil : .view
    }

    func readResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func writeResources(frame: FrameContext) -> [RenderResourceID] {
        []
    }

    func configureRenderPassDescriptor(_ descriptor: MTLRenderPassDescriptor, frame: FrameContext) {
        if let color = descriptor.colorAttachments[0] {
            color.loadAction = .load
            color.storeAction = .store
        }
        if let depth = descriptor.depthAttachment {
            depth.loadAction = .dontCare
            depth.storeAction = .dontCare
        }
        if let stencil = descriptor.stencilAttachment {
            stencil.loadAction = .dontCare
            stencil.storeAction = .dontCare
        }
    }

    func encode(frame: FrameContext, resources: RenderGraphResources, encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.pipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encodeItems(frame.overlayItems, frame: frame, encoder: encoder)
    }
}
