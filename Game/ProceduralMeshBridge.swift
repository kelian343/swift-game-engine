//
//  ProceduralMeshBridge.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

public enum ProceduralMeshBridge {
    /// Convert a descriptor to the existing MeshData (VertexPNUT only).
    /// If normals/uvs are missing and allowDefaults is true, they are filled with defaults.
    public static func toMeshDataPNUT(_ desc: ProceduralMeshDescriptor,
                                      allowDefaults: Bool = true) -> MeshData? {
        guard desc.topology == .triangles else { return nil }
        guard desc.validate() else { return nil }

        let positions = desc.streams.positions
        let normals: [SIMD3<Float>] = {
            if let n = desc.streams.normals { return n }
            return allowDefaults ? Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count) : []
        }()
        let uvs: [SIMD2<Float>] = {
            if let u = desc.streams.uvs { return u }
            return allowDefaults ? Array(repeating: SIMD2<Float>(0, 0), count: positions.count) : []
        }()

        if (!allowDefaults && (desc.streams.normals == nil || desc.streams.uvs == nil)) {
            return nil
        }

        var vertices: [VertexPNUT] = []
        vertices.reserveCapacity(positions.count)
        for i in 0..<positions.count {
            vertices.append(VertexPNUT(position: positions[i],
                                       normal: normals[i],
                                       uv: uvs[i]))
        }

        if let i16 = desc.indices16 {
            return MeshData(vertices: vertices, indices16: i16)
        }
        if let i32 = desc.indices32 {
            return MeshData(vertices: vertices, indices32: i32)
        }
        return nil
    }

    public static func toSkinnedMeshData(_ desc: SkinnedMeshDescriptor) -> SkinnedMeshData? {
        guard desc.topology == .triangles else { return nil }
        guard desc.validate() else { return nil }

        let streams = desc.streams
        var vertices: [VertexSkinnedPNUT4] = []
        vertices.reserveCapacity(streams.vertexCount)

        for i in 0..<streams.vertexCount {
            vertices.append(VertexSkinnedPNUT4(position: streams.positions[i],
                                               normal: streams.normals[i],
                                               uv: streams.uvs[i],
                                               boneIndices: streams.boneIndices[i],
                                               boneWeights: streams.boneWeights[i]))
        }

        if let i16 = desc.indices16 {
            return SkinnedMeshData(vertices: vertices, indices16: i16)
        }
        if let i32 = desc.indices32 {
            return SkinnedMeshData(vertices: vertices, indices32: i32)
        }
        return nil
    }
}
