//
//  RenderContext.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit
import QuartzCore

final class RenderContext {
    let device: MTLDevice

    let commandQueue: MTLCommandQueue

    init?(view: MTKView, maxFramesInFlight: Int) {
        guard let device = view.device else { return nil }
        self.device = device

        _ = maxFramesInFlight
        self.commandQueue = device.makeCommandQueue()!
    }

    func prepareResidency(meshes: [GPUMesh], textures: [MTLTexture], uniforms: MTLBuffer) {
        _ = meshes
        _ = textures
        _ = uniforms
    }

    func currentRenderPassDescriptor(from view: MTKView) -> MTLRenderPassDescriptor? {
        view.currentRenderPassDescriptor
    }
}
