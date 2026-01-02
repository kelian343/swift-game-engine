//
//  RenderContext.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit
import QuartzCore

/// Owns Metal4 command infrastructure + argument tables + residency set management.
final class RenderContext {
    let device: MTLDevice

    let commandQueue: MTL4CommandQueue
    let commandBuffer: MTL4CommandBuffer
    let allocators: [MTL4CommandAllocator]

    let vertexTable: MTL4ArgumentTable
    let fragmentTable: MTL4ArgumentTable

    private(set) var residencySet: MTLResidencySet?

    init?(view: MTKView, maxFramesInFlight: Int) {
        guard let device = view.device else { return nil }
        self.device = device

        self.commandQueue = device.makeMTL4CommandQueue()!
        self.commandBuffer = device.makeCommandBuffer()!

        // Keep original behavior (0...maxBuffersInFlight) to avoid changing count semantics
        self.allocators = (0...maxFramesInFlight).map { _ in device.makeCommandAllocator()! }

        // Safer: separate descriptors for vertex/fragment (avoid shared-mutation hazards)
        let vDesc = MTL4ArgumentTableDescriptor()
        vDesc.maxBufferBindCount = 4
        self.vertexTable = try! device.makeArgumentTable(descriptor: vDesc)

        let fDesc = MTL4ArgumentTableDescriptor()
        fDesc.maxBufferBindCount = 4
        fDesc.maxTextureBindCount = 1
        self.fragmentTable = try! device.makeArgumentTable(descriptor: fDesc)
    }

    func prepareResidency(mesh: MTKMesh, colorMap: MTLTexture, uniforms: MTLBuffer) {
        let residencySetDesc = MTLResidencySetDescriptor()
        residencySetDesc.initialCapacity = mesh.vertexBuffers.count + mesh.submeshes.count + 2 // color map + uniforms

        let set = try! device.makeResidencySet(descriptor: residencySetDesc)
        set.addAllocations(mesh.vertexBuffers.map { $0.buffer })
        set.addAllocations(mesh.submeshes.map { $0.indexBuffer.buffer })
        set.addAllocations([colorMap, uniforms])
        set.commit()

        commandQueue.addResidencySet(set)
        self.residencySet = set
    }

    func currentRenderPassDescriptor(from view: MTKView) -> MTL4RenderPassDescriptor? {
        return view.currentMTL4RenderPassDescriptor
    }

    func useViewResidencySetIfAvailable(for view: MTKView) {
        // Mirrors original: commandBuffer.useResidencySet((view.layer as! CAMetalLayer).residencySet);
        if let layer = view.layer as? CAMetalLayer {
            commandBuffer.useResidencySet(layer.residencySet)
        }
    }
}
