//
//  ProceduralMeshAPI.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

public enum MeshTopology {
    case triangles
}

public struct MeshBounds {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
}

public struct VertexStreams {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]?
    public var uvs: [SIMD2<Float>]?
    public var tangents: [SIMD4<Float>]?
    public var colors: [SIMD4<Float>]?
    public var uv2: [SIMD2<Float>]?

    public init(positions: [SIMD3<Float>],
                normals: [SIMD3<Float>]? = nil,
                uvs: [SIMD2<Float>]? = nil,
                tangents: [SIMD4<Float>]? = nil,
                colors: [SIMD4<Float>]? = nil,
                uv2: [SIMD2<Float>]? = nil) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.tangents = tangents
        self.colors = colors
        self.uv2 = uv2
    }

    public var vertexCount: Int { positions.count }

    public func validate() -> Bool {
        let count = positions.count
        if let n = normals, n.count != count { return false }
        if let u = uvs, u.count != count { return false }
        if let t = tangents, t.count != count { return false }
        if let c = colors, c.count != count { return false }
        if let u2 = uv2, u2.count != count { return false }
        return true
    }

    public func bounds() -> MeshBounds? {
        guard let first = positions.first else { return nil }
        var bmin = first
        var bmax = first
        for p in positions.dropFirst() {
            bmin = simd_min(bmin, p)
            bmax = simd_max(bmax, p)
        }
        return MeshBounds(min: bmin, max: bmax)
    }
}

public struct ProceduralMeshDescriptor {
    public var topology: MeshTopology
    public var streams: VertexStreams
    public var indices16: [UInt16]?
    public var indices32: [UInt32]?
    public var name: String?

    public init(topology: MeshTopology = .triangles,
                streams: VertexStreams,
                indices16: [UInt16]? = nil,
                indices32: [UInt32]? = nil,
                name: String? = nil) {
        self.topology = topology
        self.streams = streams
        self.indices16 = indices16
        self.indices32 = indices32
        self.name = name
    }

    public var indexCount: Int {
        return indices16?.count ?? indices32?.count ?? 0
    }

    public var bounds: MeshBounds? {
        streams.bounds()
    }

    public func validate() -> Bool {
        guard streams.validate() else { return false }
        let has16 = indices16 != nil
        let has32 = indices32 != nil
        if has16 && has32 { return false }
        if !has16 && !has32 { return false }
        return true
    }
}

public struct SkinnedVertexStreams {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var uvs: [SIMD2<Float>]
    public var boneIndices: [SIMD4<UInt16>]
    public var boneWeights: [SIMD4<Float>]

    public init(positions: [SIMD3<Float>],
                normals: [SIMD3<Float>],
                uvs: [SIMD2<Float>],
                boneIndices: [SIMD4<UInt16>],
                boneWeights: [SIMD4<Float>]) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.boneIndices = boneIndices
        self.boneWeights = boneWeights
    }

    public var vertexCount: Int { positions.count }

    public func validate() -> Bool {
        let count = positions.count
        return normals.count == count
            && uvs.count == count
            && boneIndices.count == count
            && boneWeights.count == count
    }

    public func bounds() -> MeshBounds? {
        guard let first = positions.first else { return nil }
        var bmin = first
        var bmax = first
        for p in positions.dropFirst() {
            bmin = simd_min(bmin, p)
            bmax = simd_max(bmax, p)
        }
        return MeshBounds(min: bmin, max: bmax)
    }
}

public struct SkinnedMeshDescriptor {
    public var topology: MeshTopology
    public var streams: SkinnedVertexStreams
    public var indices16: [UInt16]?
    public var indices32: [UInt32]?
    public var name: String?
    public var invBindModel: [matrix_float4x4]?

    public init(topology: MeshTopology = .triangles,
                streams: SkinnedVertexStreams,
                indices16: [UInt16]? = nil,
                indices32: [UInt32]? = nil,
                name: String? = nil,
                invBindModel: [matrix_float4x4]? = nil) {
        self.topology = topology
        self.streams = streams
        self.indices16 = indices16
        self.indices32 = indices32
        self.name = name
        self.invBindModel = invBindModel
    }

    public var indexCount: Int {
        return indices16?.count ?? indices32?.count ?? 0
    }

    public var bounds: MeshBounds? {
        streams.bounds()
    }

    public func validate() -> Bool {
        guard streams.validate() else { return false }
        let has16 = indices16 != nil
        let has32 = indices32 != nil
        if has16 && has32 { return false }
        if !has16 && !has32 { return false }
        return true
    }
}
