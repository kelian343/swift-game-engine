//
//  RenderPasses.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

final class ShadowPass: RenderPass {
    let name = "Shadow Pass"

    func makeTarget(frame: FrameContext) -> RenderTargetSource? {
        let depth = DepthAttachment(
            texture: frame.shadowMap.texture,
            loadAction: .clear,
            storeAction: .store,
            clearDepth: 1.0
        )
        return .offscreen(RenderTarget(depthAttachment: depth))
    }

    func encode(frame: FrameContext, encoder: MTL4RenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.shadowPipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        encoder.setArgumentTable(frame.context.vertexTable, stages: .vertex)

        for item in frame.items {
            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix,
                          lightViewProj: frame.lightViewProj)

            let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
            frame.context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)
            frame.context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress,
                                                 index: BufferIndex.meshVertices.rawValue)

            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: item.mesh.indexType,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }
}

final class MainPass: RenderPass {
    let name = "Main Pass"

    func makeTarget(frame: FrameContext) -> RenderTargetSource? {
        .view
    }

    func encode(frame: FrameContext, encoder: MTL4RenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.pipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encoder.setArgumentTable(frame.context.vertexTable, stages: .vertex)
        encoder.setArgumentTable(frame.context.fragmentTable, stages: .fragment)

        frame.context.fragmentTable.setAddress(frame.lightSystem.buffer.gpuAddress,
                                               index: BufferIndex.light.rawValue)
        frame.context.fragmentTable.setTexture(frame.shadowMap.texture.gpuResourceID,
                                               index: TextureIndex.shadowMap.rawValue)

        for item in frame.items {
            encoder.setCullMode(item.material.cullMode)
            encoder.setFrontFacing(item.material.frontFacing)

            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix,
                          lightViewProj: frame.lightViewProj)

            let uAddr = u.buffer.gpuAddress + UInt64(u.offset)
            frame.context.vertexTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)
            frame.context.fragmentTable.setAddress(uAddr, index: BufferIndex.uniforms.rawValue)

            frame.context.vertexTable.setAddress(item.mesh.vertexBuffer.gpuAddress,
                                                 index: BufferIndex.meshVertices.rawValue)

            let tex = item.material.baseColorTexture?.texture ?? frame.fallbackWhite.texture
            frame.context.fragmentTable.setTexture(tex.gpuResourceID, index: TextureIndex.baseColor.rawValue)

            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: item.mesh.indexType,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }
}
