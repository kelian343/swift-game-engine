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
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

        let vfd = MTL4LibraryFunctionDescriptor()
        vfd.library = library
        vfd.name = "vertexShader"

        let ffd = MTL4LibraryFunctionDescriptor()
        ffd.library = library
        ffd.name = "fragmentShader"

        let pd = MTL4RenderPipelineDescriptor()
        pd.label = "RenderPipeline"
        pd.rasterSampleCount = view.sampleCount
        pd.vertexFunctionDescriptor = vfd
        pd.fragmentFunctionDescriptor = ffd
        pd.vertexDescriptor = vertexDescriptor
        pd.colorAttachments[0].pixelFormat = view.colorPixelFormat

        return try compiler.makeRenderPipelineState(descriptor: pd)
    }

    static func makeDepthState(device: MTLDevice) -> MTLDepthStencilState? {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .less
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }
}
