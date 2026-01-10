//
//  MeshData.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

/// Pure CPU mesh data (no Metal dependency).
public struct MeshData {
    public var vertices: [VertexPNUT]
    public var indices16: [UInt16]?
    public var indices32: [UInt32]?

    public init(vertices: [VertexPNUT], indices16: [UInt16]) {
        self.vertices = vertices
        self.indices16 = indices16
        self.indices32 = nil
    }

    public init(vertices: [VertexPNUT], indices32: [UInt32]) {
        self.vertices = vertices
        self.indices16 = nil
        self.indices32 = indices32
    }

    public var indexType: IndexType {
        return indices16 != nil ? .uint16 : .uint32
    }

    public var indexCount: Int {
        return indices16?.count ?? indices32?.count ?? 0
    }
}

/// Skinned CPU mesh data (position/normal/uv + bone indices/weights).
public struct SkinnedMeshData {
    public var vertices: [VertexSkinnedPNUT4]
    public var indices16: [UInt16]?
    public var indices32: [UInt32]?

    public init(vertices: [VertexSkinnedPNUT4], indices16: [UInt16]) {
        self.vertices = vertices
        self.indices16 = indices16
        self.indices32 = nil
    }

    public init(vertices: [VertexSkinnedPNUT4], indices32: [UInt32]) {
        self.vertices = vertices
        self.indices16 = nil
        self.indices32 = indices32
    }

    public var indexType: IndexType {
        return indices16 != nil ? .uint16 : .uint32
    }

    public var indexCount: Int {
        return indices16?.count ?? indices32?.count ?? 0
    }
}
