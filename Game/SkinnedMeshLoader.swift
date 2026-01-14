//
//  SkinnedMeshLoader.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Foundation
import simd

struct SkinnedMeshAsset {
    let meshes: [SkinnedMeshDescriptor]
    let materialNames: [String]
}

enum SkinnedMeshLoader {
    static func loadSkinnedMesh(named name: String, skeleton: Skeleton) -> SkinnedMeshDescriptor? {
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else {
            print("SkinnedMeshLoader: missing json:", name)
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(SkinnedMeshJSON.self, from: data)
            return buildAsset(from: decoded, skeleton: skeleton).meshes.first
        } catch {
            print("SkinnedMeshLoader: failed to load json:", name, error)
            return nil
        }
    }

    static func loadSkinnedMeshAsset(named name: String, skeleton: Skeleton) -> SkinnedMeshAsset? {
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else {
            print("SkinnedMeshLoader: missing json:", name)
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(SkinnedMeshJSON.self, from: data)
            return buildAsset(from: decoded, skeleton: skeleton)
        } catch {
            print("SkinnedMeshLoader: failed to load json:", name, error)
            return nil
        }
    }

    private static func buildAsset(from json: SkinnedMeshJSON,
                                   skeleton: Skeleton) -> SkinnedMeshAsset {
        let mesh = json.mesh
        let vCount = mesh.positions.count / 3
        guard vCount > 0,
              mesh.positions.count == vCount * 3,
              mesh.normals.count == vCount * 3,
              mesh.uvs.count == vCount * 2,
              mesh.joints.count == vCount * 4,
              mesh.weights.count == vCount * 4 else {
            print("SkinnedMeshLoader: attribute counts do not match.")
            return SkinnedMeshAsset(meshes: [], materialNames: [])
        }

        let boneMap = makeBoneRemap(skinBones: json.skin.bones, skeleton: skeleton)
        let invBindModel = buildInvBindModel(skinBones: json.skin.bones,
                                             boneMap: boneMap,
                                             skeleton: skeleton)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var boneIndices: [SIMD4<UInt16>] = []
        var boneWeights: [SIMD4<Float>] = []

        positions.reserveCapacity(vCount)
        normals.reserveCapacity(vCount)
        uvs.reserveCapacity(vCount)
        boneIndices.reserveCapacity(vCount)
        boneWeights.reserveCapacity(vCount)

        for i in 0..<vCount {
            let pi = i * 3
            let ui = i * 2
            let bi = i * 4

            let scale = skeleton.unitScale
            positions.append(SIMD3<Float>(mesh.positions[pi] * scale,
                                          mesh.positions[pi + 1] * scale,
                                          mesh.positions[pi + 2] * scale))
            normals.append(SIMD3<Float>(mesh.normals[pi],
                                        mesh.normals[pi + 1],
                                        mesh.normals[pi + 2]))
            uvs.append(SIMD2<Float>(mesh.uvs[ui], mesh.uvs[ui + 1]))

            var remappedJoints = SIMD4<UInt16>(repeating: 0)
            var weights = SIMD4<Float>(mesh.weights[bi],
                                       mesh.weights[bi + 1],
                                       mesh.weights[bi + 2],
                                       mesh.weights[bi + 3])

            for j in 0..<4 {
                let srcIndex = Int(mesh.joints[bi + j])
                let mapped = srcIndex < boneMap.count ? boneMap[srcIndex] : nil
                if let dst = mapped {
                    remappedJoints[j] = UInt16(dst)
                } else {
                    weights[j] = 0
                    remappedJoints[j] = 0
                }
            }

            let sum = weights.x + weights.y + weights.z + weights.w
            if sum > 0 {
                weights /= sum
            }

            boneIndices.append(remappedJoints)
            boneWeights.append(weights)
        }

        let streams = SkinnedVertexStreams(positions: positions,
                                           normals: normals,
                                           uvs: uvs,
                                           boneIndices: boneIndices,
                                           boneWeights: boneWeights)

        let submeshes = mesh.submeshes?.isEmpty == false ? mesh.submeshes! : [
            SkinnedMeshSubmeshJSON(start: 0, count: mesh.indices.count, material: "Default")
        ]

        var descriptors: [SkinnedMeshDescriptor] = []
        var materialNames: [String] = []
        descriptors.reserveCapacity(submeshes.count)
        materialNames.reserveCapacity(submeshes.count)

        for sub in submeshes {
            let start = max(sub.start, 0)
            let end = min(start + sub.count, mesh.indices.count)
            if start >= end { continue }
            let slice = Array(mesh.indices[start..<end])
            let maxIndex = slice.max() ?? 0
            let indices16: [UInt16]? = maxIndex <= UInt32(UInt16.max) ? slice.map { UInt16($0) } : nil
            let indicesFinal32: [UInt32]? = indices16 == nil ? slice : nil
            let desc = SkinnedMeshDescriptor(topology: .triangles,
                                             streams: streams,
                                             indices16: indices16,
                                             indices32: indicesFinal32,
                                             name: "SkinnedMesh:\(sub.material)",
                                             invBindModel: invBindModel)
            descriptors.append(desc)
            materialNames.append(sub.material)
        }

        return SkinnedMeshAsset(meshes: descriptors, materialNames: materialNames)
    }

    private static func makeBoneRemap(skinBones: [SkinnedMeshBoneJSON],
                                      skeleton: Skeleton) -> [Int?] {
        var lookup: [String: Int] = [:]
        for (i, name) in skeleton.names.enumerated() {
            let key = name.lowercased()
            lookup[key] = i
            if let short = name.split(separator: ":").last {
                lookup[String(short).lowercased()] = i
            }
        }
        var map: [Int?] = Array(repeating: nil, count: skinBones.count)
        var missing = 0
        for (i, bone) in skinBones.enumerated() {
            let key = bone.name.lowercased()
            let idx = lookup[key] ?? (key.contains(":") ? lookup[String(key.split(separator: ":").last!).lowercased()] : nil)
            map[i] = idx
            if idx == nil {
                missing += 1
            }
        }
        if missing > 0 {
            print("SkinnedMeshLoader: missing bones:", missing, "of", skinBones.count)
        }
        return map
    }

    private static func buildInvBindModel(skinBones: [SkinnedMeshBoneJSON],
                                          boneMap: [Int?],
                                          skeleton: Skeleton) -> [matrix_float4x4] {
        var invBind = skeleton.invBindModel
        let scale = skeleton.unitScale
        for (i, bone) in skinBones.enumerated() {
            guard let dst = boneMap[i], bone.inverseBindMatrix.count == 16 else { continue }
            var m = matrixFromArrayRowMajor(bone.inverseBindMatrix)
            m.columns.3.x *= scale
            m.columns.3.y *= scale
            m.columns.3.z *= scale
            invBind[dst] = m
        }
        return invBind
    }

    private static func matrixFromArrayRowMajor(_ values: [Float]) -> matrix_float4x4 {
        return matrix_float4x4(columns: (
            SIMD4<Float>(values[0], values[4], values[8], values[12]),
            SIMD4<Float>(values[1], values[5], values[9], values[13]),
            SIMD4<Float>(values[2], values[6], values[10], values[14]),
            SIMD4<Float>(values[3], values[7], values[11], values[15])
        ))
    }
}

private struct SkinnedMeshJSON: Codable {
    let version: Int
    let mesh: SkinnedMeshDataJSON
    let skin: SkinnedMeshSkinJSON
}

private struct SkinnedMeshDataJSON: Codable {
    let positions: [Float]
    let normals: [Float]
    let uvs: [Float]
    let joints: [UInt16]
    let weights: [Float]
    let indices: [UInt32]
    let submeshes: [SkinnedMeshSubmeshJSON]?
}

private struct SkinnedMeshSkinJSON: Codable {
    let bones: [SkinnedMeshBoneJSON]
}

private struct SkinnedMeshBoneJSON: Codable {
    let name: String
    let inverseBindMatrix: [Float]
}

private struct SkinnedMeshSubmeshJSON: Codable {
    let start: Int
    let count: Int
    let material: String
}
