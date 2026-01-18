//
//  StaticMeshLoader.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Foundation
import simd

struct StaticMeshPart {
    let name: String
    let transform: matrix_float4x4
    let mesh: ProceduralMeshDescriptor
    let submeshes: [StaticMeshSubmesh]
    let collisionHulls: [ProceduralMeshDescriptor]
}

struct StaticMeshAsset {
    let parts: [StaticMeshPart]
}

struct StaticMeshSubmesh {
    let start: Int
    let count: Int
    let material: String
}

enum StaticMeshLoader {
    static func loadStaticMeshAsset(named name: String) -> StaticMeshAsset? {
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else {
            print("StaticMeshLoader: missing json:", name)
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(StaticMeshJSON.self, from: data)
            return buildAsset(from: decoded)
        } catch {
            print("StaticMeshLoader: failed to load json:", name, error)
            return nil
        }
    }

    private static func buildAsset(from json: StaticMeshJSON) -> StaticMeshAsset {
        var parts: [StaticMeshPart] = []
        parts.reserveCapacity(json.meshes.count)

        for entry in json.meshes {
            let mesh = entry.mesh
            let vCount = mesh.positions.count / 3
            guard vCount > 0,
                  mesh.positions.count == vCount * 3 else {
                print("StaticMeshLoader: invalid positions for mesh:", entry.name)
                continue
            }
            guard !mesh.indices.isEmpty else {
                print("StaticMeshLoader: missing indices for mesh:", entry.name)
                continue
            }

            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(vCount)

            var normals: [SIMD3<Float>] = []
            var uvs: [SIMD2<Float>] = []
            let hasNormals = mesh.normals.count == vCount * 3
            let hasUVs = mesh.uvs.count == vCount * 2
            if !mesh.normals.isEmpty && !hasNormals {
                print("StaticMeshLoader: normals count mismatch for mesh:", entry.name)
            }
            if !mesh.uvs.isEmpty && !hasUVs {
                print("StaticMeshLoader: uvs count mismatch for mesh:", entry.name)
            }
            if hasNormals { normals.reserveCapacity(vCount) }
            if hasUVs { uvs.reserveCapacity(vCount) }

            for i in 0..<vCount {
                let pi = i * 3
                positions.append(SIMD3<Float>(mesh.positions[pi],
                                              mesh.positions[pi + 1],
                                              mesh.positions[pi + 2]))
                if hasNormals {
                    normals.append(SIMD3<Float>(mesh.normals[pi],
                                                mesh.normals[pi + 1],
                                                mesh.normals[pi + 2]))
                }
                if hasUVs {
                    let ui = i * 2
                    uvs.append(SIMD2<Float>(mesh.uvs[ui], mesh.uvs[ui + 1]))
                }
            }

            let streams = VertexStreams(positions: positions,
                                        normals: hasNormals ? normals : nil,
                                        uvs: hasUVs ? uvs : nil)

            let maxIndex = mesh.indices.max() ?? 0
            let indices16: [UInt16]? = maxIndex <= UInt32(UInt16.max) ? mesh.indices.map { UInt16($0) } : nil
            let indices32: [UInt32]? = indices16 == nil ? mesh.indices : nil

            let desc = ProceduralMeshDescriptor(topology: .triangles,
                                                streams: streams,
                                                indices16: indices16,
                                                indices32: indices32,
                                                name: entry.name)

            let submeshesJSON = mesh.submeshes?.isEmpty == false ? mesh.submeshes! : [
                StaticMeshSubmeshJSON(start: 0, count: mesh.indices.count, material: "Default")
            ]
            let submeshes = submeshesJSON.map {
                StaticMeshSubmesh(start: $0.start, count: $0.count, material: $0.material)
            }
            let collisionHulls = buildCollisionHulls(entry.collisionHulls)

            let transform = entry.transform.count == 16 ? matrixFromArrayRowMajor(entry.transform) : matrix_identity_float4x4
            parts.append(StaticMeshPart(name: entry.name,
                                        transform: transform,
                                        mesh: desc,
                                        submeshes: submeshes,
                                        collisionHulls: collisionHulls))
        }

        return StaticMeshAsset(parts: parts)
    }

    private static func matrixFromArrayRowMajor(_ values: [Float]) -> matrix_float4x4 {
        return matrix_float4x4(columns: (
            SIMD4<Float>(values[0], values[4], values[8], values[12]),
            SIMD4<Float>(values[1], values[5], values[9], values[13]),
            SIMD4<Float>(values[2], values[6], values[10], values[14]),
            SIMD4<Float>(values[3], values[7], values[11], values[15])
        ))
    }

    private static func buildCollisionHulls(_ hulls: [StaticMeshHullJSON]?) -> [ProceduralMeshDescriptor] {
        guard let hulls = hulls, !hulls.isEmpty else { return [] }
        var descriptors: [ProceduralMeshDescriptor] = []
        descriptors.reserveCapacity(hulls.count)
        for hull in hulls {
            let vCount = hull.positions.count / 3
            guard vCount > 0,
                  hull.positions.count == vCount * 3 else { continue }
            guard !hull.indices.isEmpty else { continue }
            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(vCount)
            for i in 0..<vCount {
                let pi = i * 3
                positions.append(SIMD3<Float>(hull.positions[pi],
                                              hull.positions[pi + 1],
                                              hull.positions[pi + 2]))
            }
            let streams = VertexStreams(positions: positions)
            let maxIndex = hull.indices.max() ?? 0
            let indices16: [UInt16]? = maxIndex <= UInt32(UInt16.max) ? hull.indices.map { UInt16($0) } : nil
            let indices32: [UInt32]? = indices16 == nil ? hull.indices : nil
            let desc = ProceduralMeshDescriptor(topology: .triangles,
                                                streams: streams,
                                                indices16: indices16,
                                                indices32: indices32,
                                                name: "CollisionHull")
            descriptors.append(desc)
        }
        return descriptors
    }
}

private struct StaticMeshJSON: Codable {
    let version: Int
    let meshes: [StaticMeshEntryJSON]
}

private struct StaticMeshEntryJSON: Codable {
    let name: String
    let transform: [Float]
    let mesh: StaticMeshDataJSON
    let collisionHulls: [StaticMeshHullJSON]?
}

private struct StaticMeshDataJSON: Codable {
    let positions: [Float]
    let normals: [Float]
    let uvs: [Float]
    let indices: [UInt32]
    let submeshes: [StaticMeshSubmeshJSON]?
}

private struct StaticMeshSubmeshJSON: Codable {
    let start: Int
    let count: Int
    let material: String
}

private struct StaticMeshHullJSON: Codable {
    let positions: [Float]
    let indices: [UInt32]
}
