//
//  PipelineBuilder.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit

enum PipelineBuilder {

    static func makeMetalVertexDescriptor() -> MTLVertexDescriptor {
        VertexDescriptorLibrary.vertexPNUT()
    }

    @MainActor
    static func makeRenderPipeline(device: MTLDevice,
                                   view: MTKView,
                                   vertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {

        let library = device.makeDefaultLibrary()
        guard let vertexFunction = library?.makeFunction(name: "vertexShader"),
              let fragmentFunction = library?.makeFunction(name: "fragmentShader") else {
            throw RendererError.badVertexDescriptor
        }

        let pd = MTLRenderPipelineDescriptor()
        pd.label = "RenderPipeline"
        pd.rasterSampleCount = view.sampleCount
        pd.vertexFunction = vertexFunction
        pd.fragmentFunction = fragmentFunction
        pd.vertexDescriptor = vertexDescriptor
        pd.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pd.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pd.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
        if let color = pd.colorAttachments[0] {
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .sourceAlpha
            color.sourceAlphaBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        return try device.makeRenderPipelineState(descriptor: pd)
    }

    static func makeDepthState(device: MTLDevice) -> MTLDepthStencilState? {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .less
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }

    static func makeUIDepthState(device: MTLDevice) -> MTLDepthStencilState? {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .always
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }
}
