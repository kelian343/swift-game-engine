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

    func encode(frame: FrameContext, resources: RenderGraphResources, encoder: MTL4RenderCommandEncoder) {
        encoder.setRenderPipelineState(frame.pipelineState)
        encoder.setDepthStencilState(frame.depthState)

        encoder.setArgumentTable(frame.context.vertexTable, stages: .vertex)
        encoder.setArgumentTable(frame.context.fragmentTable, stages: .fragment)

        for item in frame.items {
            encoder.setCullMode(item.material.cullMode)
            encoder.setFrontFacing(item.material.frontFacing)

            let u = frame.uniformRing.allocate()
            writeUniforms(u.pointer,
                          projection: frame.projection,
                          view: frame.viewMatrix,
                          model: item.modelMatrix)

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
