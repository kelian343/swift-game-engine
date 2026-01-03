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

    let rtCommandQueue: MTLCommandQueue
    let commandQueue: MTL4CommandQueue
    let commandBuffer: MTL4CommandBuffer
    let allocators: [MTL4CommandAllocator]

    let vertexTable: MTL4ArgumentTable
    let fragmentTable: MTL4ArgumentTable

    private(set) var residencySet: MTLResidencySet?

    init?(view: MTKView, maxFramesInFlight: Int) {
        guard let device = view.device else { return nil }
        self.device = device

        self.rtCommandQueue = device.makeCommandQueue()!
        self.commandQueue = device.makeMTL4CommandQueue()!
        self.commandBuffer = device.makeCommandBuffer()!
        self.allocators = (0...maxFramesInFlight).map { _ in device.makeCommandAllocator()! }

        let vDesc = MTL4ArgumentTableDescriptor()
        vDesc.maxBufferBindCount = 8
        self.vertexTable = try! device.makeArgumentTable(descriptor: vDesc)

        let fDesc = MTL4ArgumentTableDescriptor()
        fDesc.maxBufferBindCount = 8
        fDesc.maxTextureBindCount = 8
        self.fragmentTable = try! device.makeArgumentTable(descriptor: fDesc)
    }

    func prepareResidency(meshes: [GPUMesh], textures: [MTLTexture], uniforms: MTLBuffer) {
        let rsd = MTLResidencySetDescriptor()

        // capacity: vertex+index per mesh + textures + uniforms
        rsd.initialCapacity = meshes.count * 2 + textures.count + 1

        let set = try! device.makeResidencySet(descriptor: rsd)
        for m in meshes {
            set.addAllocations([m.vertexBuffer, m.indexBuffer])
        }
        if !textures.isEmpty {
            set.addAllocations(textures)
        }
        set.addAllocations([uniforms])
        set.commit()

        if let existing = residencySet {
            commandQueue.removeResidencySet(existing)
        }
        commandQueue.addResidencySet(set)
        self.residencySet = set
    }

    func currentRenderPassDescriptor(from view: MTKView) -> MTL4RenderPassDescriptor? {
        view.currentMTL4RenderPassDescriptor
    }

    func useViewResidencySetIfAvailable(for view: MTKView) {
        if let layer = view.layer as? CAMetalLayer {
            commandBuffer.useResidencySet(layer.residencySet)
        }
    }
}
