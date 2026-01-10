//
//  VertexLayouts.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal
import simd

/// Procedural-friendly CPU vertex layout (one buffer: position+normal+uv)
public struct VertexPNUT {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uv: SIMD2<Float>

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) {
        self.position = position
        self.normal = normal
        self.uv = uv
    }
}

/// CPU skinned vertex layout (position+normal+uv + 4 weights)
public struct VertexSkinnedPNUT4 {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uv: SIMD2<Float>
    public var boneIndices: SIMD4<UInt16>
    public var boneWeights: SIMD4<Float>

    public init(position: SIMD3<Float>,
                normal: SIMD3<Float>,
                uv: SIMD2<Float>,
                boneIndices: SIMD4<UInt16>,
                boneWeights: SIMD4<Float>) {
        self.position = position
        self.normal = normal
        self.uv = uv
        self.boneIndices = boneIndices
        self.boneWeights = boneWeights
    }
}

public enum IndexType {
    case uint16, uint32

    var mtl: MTLIndexType {
        switch self {
        case .uint16: return .uint16
        case .uint32: return .uint32
        }
    }
}

/// Metal vertex descriptor matching VertexPNUT and ShaderTypes.h attribute indices
public enum VertexDescriptorLibrary {
    public static func vertexPNUT() -> MTLVertexDescriptor {
        let d = MTLVertexDescriptor()

        // position
        d.attributes[VertexAttribute.position.rawValue].format = .float3
        d.attributes[VertexAttribute.position.rawValue].offset = 0
        d.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshVertices.rawValue

        // normal
        d.attributes[VertexAttribute.normal.rawValue].format = .float3
        d.attributes[VertexAttribute.normal.rawValue].offset = MemoryLayout<SIMD3<Float>>.stride
        d.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.meshVertices.rawValue

        // uv
        d.attributes[VertexAttribute.texcoord.rawValue].format = .float2
        d.attributes[VertexAttribute.texcoord.rawValue].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        d.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshVertices.rawValue

        d.layouts[BufferIndex.meshVertices.rawValue].stride = MemoryLayout<VertexPNUT>.stride
        d.layouts[BufferIndex.meshVertices.rawValue].stepFunction = .perVertex
        d.layouts[BufferIndex.meshVertices.rawValue].stepRate = 1

        return d
    }
}
