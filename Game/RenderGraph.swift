//
//  RenderGraph.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit
import simd

struct ColorAttachment {
    let texture: MTLTexture
    let loadAction: MTLLoadAction
    let storeAction: MTLStoreAction
    let clearColor: MTLClearColor
}

struct DepthAttachment {
    let texture: MTLTexture
    let loadAction: MTLLoadAction
    let storeAction: MTLStoreAction
    let clearDepth: Double
}

struct RenderTarget {
    let colorAttachments: [ColorAttachment]
    let depthAttachment: DepthAttachment?

    init(colorAttachments: [ColorAttachment] = [], depthAttachment: DepthAttachment? = nil) {
        self.colorAttachments = colorAttachments
        self.depthAttachment = depthAttachment
    }
}

enum RenderTargetSource {
    case view
    case offscreen(RenderTarget)
}

struct FrameContext {
    let scene: RenderScene
    let items: [RenderItem]

    let context: RenderContext
    let uniformRing: UniformRingBuffer

    let pipelineState: MTLRenderPipelineState
    let shadowPipelineState: MTLRenderPipelineState
    let depthState: MTLDepthStencilState

    let fallbackWhite: TextureResource
    let shadowMap: ShadowMap
    let lightSystem: LightSystem

    let projection: matrix_float4x4
    let viewMatrix: matrix_float4x4
    let lightViewProj: matrix_float4x4
}

protocol RenderPass {
    var name: String { get }
    func makeTarget(frame: FrameContext) -> RenderTargetSource?
    func encode(frame: FrameContext, encoder: MTL4RenderCommandEncoder)
}

final class RenderGraph {
    private var passes: [RenderPass] = []

    func addPass(_ pass: RenderPass) {
        passes.append(pass)
    }

    func execute(frame: FrameContext, view: MTKView) {
        for pass in passes {
            guard let target = pass.makeTarget(frame: frame) else { continue }
            guard let rpd = makeRenderPassDescriptor(target: target, frame: frame, view: view) else { continue }
            guard let enc = frame.context.commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            enc.label = pass.name
            pass.encode(frame: frame, encoder: enc)
            enc.endEncoding()
        }
    }

    private func makeRenderPassDescriptor(target: RenderTargetSource,
                                          frame: FrameContext,
                                          view: MTKView) -> MTL4RenderPassDescriptor? {
        switch target {
        case .view:
            return frame.context.currentRenderPassDescriptor(from: view)
        case .offscreen(let rt):
            let rpd = MTL4RenderPassDescriptor()
            for (index, color) in rt.colorAttachments.enumerated() {
                guard let att = rpd.colorAttachments[index] else { continue }
                att.texture = color.texture
                att.loadAction = color.loadAction
                att.storeAction = color.storeAction
                att.clearColor = color.clearColor
            }
            if let depth = rt.depthAttachment {
                rpd.depthAttachment.texture = depth.texture
                rpd.depthAttachment.loadAction = depth.loadAction
                rpd.depthAttachment.storeAction = depth.storeAction
                rpd.depthAttachment.clearDepth = depth.clearDepth
            }
            return rpd
        }
    }
}
