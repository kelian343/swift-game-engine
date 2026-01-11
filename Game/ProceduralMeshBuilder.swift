//
//  ProceduralMeshBuilder.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

public struct ProceduralMeshBuilder {
    private var topology: MeshTopology = .triangles
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var tangents: [SIMD4<Float>] = []
    private var colors: [SIMD4<Float>] = []
    private var uv2: [SIMD2<Float>] = []
    private var indices16: [UInt16]? = nil
    private var indices32: [UInt32]? = nil
    private var name: String? = nil

    public init() {}

    @discardableResult
    public mutating func setTopology(_ topology: MeshTopology) -> Self {
        self.topology = topology
        return self
    }

    @discardableResult
    public mutating func setName(_ name: String) -> Self {
        self.name = name
        return self
    }

    @discardableResult
    public mutating func setPositions(_ positions: [SIMD3<Float>]) -> Self {
        self.positions = positions
        return self
    }

    @discardableResult
    public mutating func setNormals(_ normals: [SIMD3<Float>]) -> Self {
        self.normals = normals
        return self
    }

    @discardableResult
    public mutating func setUVs(_ uvs: [SIMD2<Float>]) -> Self {
        self.uvs = uvs
        return self
    }

    @discardableResult
    public mutating func setTangents(_ tangents: [SIMD4<Float>]) -> Self {
        self.tangents = tangents
        return self
    }

    @discardableResult
    public mutating func setColors(_ colors: [SIMD4<Float>]) -> Self {
        self.colors = colors
        return self
    }

    @discardableResult
    public mutating func setUV2(_ uv2: [SIMD2<Float>]) -> Self {
        self.uv2 = uv2
        return self
    }

    @discardableResult
    public mutating func setIndices16(_ indices: [UInt16]) -> Self {
        self.indices16 = indices
        self.indices32 = nil
        return self
    }

    @discardableResult
    public mutating func setIndices32(_ indices: [UInt32]) -> Self {
        self.indices32 = indices
        self.indices16 = nil
        return self
    }

    public func build() -> ProceduralMeshDescriptor? {
        let streams = VertexStreams(positions: positions,
                                    normals: normals.isEmpty ? nil : normals,
                                    uvs: uvs.isEmpty ? nil : uvs,
                                    tangents: tangents.isEmpty ? nil : tangents,
                                    colors: colors.isEmpty ? nil : colors,
                                    uv2: uv2.isEmpty ? nil : uv2)
        let desc = ProceduralMeshDescriptor(topology: topology,
                                            streams: streams,
                                            indices16: indices16,
                                            indices32: indices32,
                                            name: name)
        return desc.validate() ? desc : nil
    }
}

public struct SkinnedMeshBuilder {
    private var topology: MeshTopology = .triangles
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var boneIndices: [SIMD4<UInt16>] = []
    private var boneWeights: [SIMD4<Float>] = []
    private var indices16: [UInt16]? = nil
    private var indices32: [UInt32]? = nil
    private var name: String? = nil

    public init() {}

    @discardableResult
    public mutating func setTopology(_ topology: MeshTopology) -> Self {
        self.topology = topology
        return self
    }

    @discardableResult
    public mutating func setName(_ name: String) -> Self {
        self.name = name
        return self
    }

    @discardableResult
    public mutating func setPositions(_ positions: [SIMD3<Float>]) -> Self {
        self.positions = positions
        return self
    }

    @discardableResult
    public mutating func setNormals(_ normals: [SIMD3<Float>]) -> Self {
        self.normals = normals
        return self
    }

    @discardableResult
    public mutating func setUVs(_ uvs: [SIMD2<Float>]) -> Self {
        self.uvs = uvs
        return self
    }

    @discardableResult
    public mutating func setBoneIndices(_ indices: [SIMD4<UInt16>]) -> Self {
        self.boneIndices = indices
        return self
    }

    @discardableResult
    public mutating func setBoneWeights(_ weights: [SIMD4<Float>]) -> Self {
        self.boneWeights = weights
        return self
    }

    @discardableResult
    public mutating func setIndices16(_ indices: [UInt16]) -> Self {
        self.indices16 = indices
        self.indices32 = nil
        return self
    }

    @discardableResult
    public mutating func setIndices32(_ indices: [UInt32]) -> Self {
        self.indices32 = indices
        self.indices16 = nil
        return self
    }

    public func build() -> SkinnedMeshDescriptor? {
        let streams = SkinnedVertexStreams(positions: positions,
                                            normals: normals,
                                            uvs: uvs,
                                            boneIndices: boneIndices,
                                            boneWeights: boneWeights)
        let desc = SkinnedMeshDescriptor(topology: topology,
                                         streams: streams,
                                         indices16: indices16,
                                         indices32: indices32,
                                         name: name)
        return desc.validate() ? desc : nil
    }
}
