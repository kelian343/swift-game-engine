//
//  RenderPasses.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

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

        for item in frame.items {
            guard let mesh = item.mesh else { continue }
            encoder.setCullMode(item.material.cullMode)
            encoder.setFrontFacing(item.material.frontFacing)

            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix)

            let tex = item.material.baseColorTexture?.texture ?? frame.fallbackWhite.texture
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: BufferIndex.meshVertices.rawValue)
            encoder.setVertexBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentTexture(tex, index: TextureIndex.baseColor.rawValue)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: mesh.indexType,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
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

        for item in frame.compositeItems {
            guard let mesh = item.mesh else { continue }
            encoder.setCullMode(item.material.cullMode)
            encoder.setFrontFacing(item.material.frontFacing)

            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix)

            let tex = item.material.baseColorTexture?.texture ?? frame.fallbackWhite.texture
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: BufferIndex.meshVertices.rawValue)
            encoder.setVertexBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentTexture(tex, index: TextureIndex.baseColor.rawValue)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: mesh.indexType,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
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

        for item in frame.overlayItems {
            guard let mesh = item.mesh else { continue }
            encoder.setCullMode(item.material.cullMode)
            encoder.setFrontFacing(item.material.frontFacing)

            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix)

            let tex = item.material.baseColorTexture?.texture ?? frame.fallbackWhite.texture
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: BufferIndex.meshVertices.rawValue)
            encoder.setVertexBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentBuffer(u.buffer, offset: u.offset, index: BufferIndex.uniforms.rawValue)
            encoder.setFragmentTexture(tex, index: TextureIndex.baseColor.rawValue)

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: mesh.indexType,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }
}
