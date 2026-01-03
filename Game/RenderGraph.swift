//
//  RenderGraph.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import MetalKit

enum RenderTargetSize: Hashable {
    case view
    case absolute(width: Int, height: Int)
}

struct TemporaryTextureDescriptor {
    let pixelFormat: MTLPixelFormat
    let size: RenderTargetSize
    let usage: MTLTextureUsage
    let storageMode: MTLStorageMode
    let label: String?
}

struct TemporaryTexture {
    let id: Int
    let desc: TemporaryTextureDescriptor
}

enum AttachmentResource {
    case external(MTLTexture)
    case temporary(TemporaryTexture)
}

enum RenderResourceKind: Hashable {
    case external(ObjectIdentifier)
    case temporary(Int)
}

struct RenderResourceID: Hashable {
    let kind: RenderResourceKind
}

func resourceID(for texture: MTLTexture) -> RenderResourceID {
    RenderResourceID(kind: .external(ObjectIdentifier(texture)))
}

func resourceID(for temp: TemporaryTexture) -> RenderResourceID {
    RenderResourceID(kind: .temporary(temp.id))
}

struct ColorAttachment {
    let resource: AttachmentResource
    let loadAction: MTLLoadAction
    let storeAction: MTLStoreAction
    let clearColor: MTLClearColor
}

struct DepthAttachment {
    let resource: AttachmentResource
    let loadAction: MTLLoadAction
    let storeAction: MTLStoreAction
    let clearDepth: Double
}

struct StencilAttachment {
    let resource: AttachmentResource
    let loadAction: MTLLoadAction
    let storeAction: MTLStoreAction
    let clearStencil: UInt32
}

struct RenderTarget {
    let colorAttachments: [ColorAttachment]
    let depthAttachment: DepthAttachment?
    let stencilAttachment: StencilAttachment?

    init(colorAttachments: [ColorAttachment] = [],
         depthAttachment: DepthAttachment? = nil,
         stencilAttachment: StencilAttachment? = nil) {
        self.colorAttachments = colorAttachments
        self.depthAttachment = depthAttachment
        self.stencilAttachment = stencilAttachment
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
    let depthState: MTLDepthStencilState

    let fallbackWhite: TextureResource

    let projection: matrix_float4x4
    let viewMatrix: matrix_float4x4
}

final class RenderGraphResources {
    private let device: MTLDevice
    private let view: MTKView
    private var temporaryTextures: [Int: MTLTexture] = [:]

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        self.view = view
    }

    func resolveTexture(_ resource: AttachmentResource) -> MTLTexture {
        switch resource {
        case .external(let tex):
            return tex
        case .temporary(let temp):
            if let tex = temporaryTextures[temp.id] {
                return tex
            }
            let tex = makeTemporaryTexture(temp.desc)
            temporaryTextures[temp.id] = tex
            return tex
        }
    }

    func texture(for temp: TemporaryTexture) -> MTLTexture {
        resolveTexture(.temporary(temp))
    }

    private func makeTemporaryTexture(_ desc: TemporaryTextureDescriptor) -> MTLTexture {
        let size = resolveSize(desc.size)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: desc.pixelFormat,
                                                          width: size.width,
                                                          height: size.height,
                                                          mipmapped: false)
        td.usage = desc.usage
        td.storageMode = desc.storageMode
        let tex = device.makeTexture(descriptor: td)!
        tex.label = desc.label
        return tex
    }

    private func resolveSize(_ size: RenderTargetSize) -> (width: Int, height: Int) {
        switch size {
        case .view:
            let w = max(Int(view.drawableSize.width), 1)
            let h = max(Int(view.drawableSize.height), 1)
            return (w, h)
        case .absolute(let width, let height):
            return (max(width, 1), max(height, 1))
        }
    }
}

protocol RenderPass {
    var name: String { get }
    func makeTarget(frame: FrameContext) -> RenderTargetSource?
    func readResources(frame: FrameContext) -> [RenderResourceID]
    func writeResources(frame: FrameContext) -> [RenderResourceID]
    func encode(frame: FrameContext, resources: RenderGraphResources, encoder: MTL4RenderCommandEncoder)
}

final class RenderGraph {
    private var passes: [RenderPass] = []
    private var nextTempID: Int = 0

    func addPass(_ pass: RenderPass) {
        passes.append(pass)
    }

    func makeTemporaryTexture(_ desc: TemporaryTextureDescriptor) -> TemporaryTexture {
        defer { nextTempID += 1 }
        return TemporaryTexture(id: nextTempID, desc: desc)
    }

    func execute(frame: FrameContext, view: MTKView) {
        let passInfos = buildPassInfos(frame: frame)
        let livePasses = pruneUnusedPasses(passInfos: passInfos)
        let orderedPasses = sortPasses(passInfos: livePasses)

        let resources = RenderGraphResources(device: frame.context.device, view: view)

        for info in orderedPasses {
            guard let target = info.pass.makeTarget(frame: frame) else { continue }
            guard let rpd = makeRenderPassDescriptor(target: target,
                                                     frame: frame,
                                                     view: view,
                                                     resources: resources) else { continue }
            guard let enc = frame.context.commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            enc.label = info.pass.name
            info.pass.encode(frame: frame, resources: resources, encoder: enc)
            enc.endEncoding()
        }
    }

    private func makeRenderPassDescriptor(target: RenderTargetSource,
                                          frame: FrameContext,
                                          view: MTKView,
                                          resources: RenderGraphResources) -> MTL4RenderPassDescriptor? {
        switch target {
        case .view:
            return frame.context.currentRenderPassDescriptor(from: view)
        case .offscreen(let rt):
            let rpd = MTL4RenderPassDescriptor()
            for (index, color) in rt.colorAttachments.enumerated() {
                guard let att = rpd.colorAttachments[index] else { continue }
                att.texture = resources.resolveTexture(color.resource)
                att.loadAction = color.loadAction
                att.storeAction = color.storeAction
                att.clearColor = color.clearColor
            }
            if let depth = rt.depthAttachment {
                rpd.depthAttachment.texture = resources.resolveTexture(depth.resource)
                rpd.depthAttachment.loadAction = depth.loadAction
                rpd.depthAttachment.storeAction = depth.storeAction
                rpd.depthAttachment.clearDepth = depth.clearDepth
            }
            if let stencil = rt.stencilAttachment {
                rpd.stencilAttachment.texture = resources.resolveTexture(stencil.resource)
                rpd.stencilAttachment.loadAction = stencil.loadAction
                rpd.stencilAttachment.storeAction = stencil.storeAction
                rpd.stencilAttachment.clearStencil = stencil.clearStencil
            }
            return rpd
        }
    }

    private struct PassInfo {
        let pass: RenderPass
        let index: Int
        let reads: Set<RenderResourceID>
        let writes: Set<RenderResourceID>
        let target: RenderTargetSource?
    }

    private func buildPassInfos(frame: FrameContext) -> [PassInfo] {
        passes.enumerated().map { index, pass in
            PassInfo(
                pass: pass,
                index: index,
                reads: Set(pass.readResources(frame: frame)),
                writes: Set(pass.writeResources(frame: frame)),
                target: pass.makeTarget(frame: frame)
            )
        }
    }

    private func pruneUnusedPasses(passInfos: [PassInfo]) -> [PassInfo] {
        var writers: [RenderResourceID: [Int]] = [:]
        for info in passInfos {
            for res in info.writes {
                writers[res, default: []].append(info.index)
            }
        }

        var live: Set<Int> = []
        var queue: [Int] = []

        for info in passInfos {
            let writesExternal = info.writes.contains { res in
                if case .external = res.kind { return true }
                return false
            }
            if case .view = info.target {
                live.insert(info.index)
                queue.append(info.index)
            } else if writesExternal {
                live.insert(info.index)
                queue.append(info.index)
            }
        }

        while let current = queue.first {
            queue.removeFirst()
            let info = passInfos[current]
            for res in info.reads {
                if let ws = writers[res] {
                    for w in ws where !live.contains(w) {
                        live.insert(w)
                        queue.append(w)
                    }
                }
            }
        }

        return passInfos.filter { live.contains($0.index) }
    }

    private func sortPasses(passInfos: [PassInfo]) -> [PassInfo] {
        var writers: [RenderResourceID: [Int]] = [:]
        for info in passInfos {
            for res in info.writes {
                writers[res, default: []].append(info.index)
            }
        }

        var edges: [Int: Set<Int>] = [:]
        var indegree: [Int: Int] = [:]

        for info in passInfos {
            indegree[info.index] = 0
        }

        for info in passInfos {
            for res in info.reads {
                guard let ws = writers[res] else {
                    if case .temporary = res.kind {
                        assertionFailure("RenderGraph: missing writer for temporary resource")
                    }
                    continue
                }
                for w in ws where w != info.index {
                    if edges[w, default: []].insert(info.index).inserted {
                        indegree[info.index, default: 0] += 1
                    }
                }
            }
        }

        var queue: [Int] = passInfos.map { $0.index }.filter { (indegree[$0] ?? 0) == 0 }
        var ordered: [Int] = []

        while let n = queue.first {
            queue.removeFirst()
            ordered.append(n)
            for m in edges[n] ?? [] {
                indegree[m, default: 0] -= 1
                if indegree[m] == 0 {
                    queue.append(m)
                }
            }
        }

        if ordered.count != passInfos.count {
            assertionFailure("RenderGraph: cycle detected, falling back to insertion order")
            return passInfos.sorted { $0.index < $1.index }
        }

        let lookup = Dictionary(uniqueKeysWithValues: passInfos.map { ($0.index, $0) })
        return ordered.compactMap { lookup[$0] }
    }
}
