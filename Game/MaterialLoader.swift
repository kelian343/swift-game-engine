//
//  MaterialLoader.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Foundation
import Metal
import simd

enum MaterialLoader {
    static func loadMaterials(named name: String,
                              device: MTLDevice) -> [String: Material] {
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else {
            print("MaterialLoader: missing json:", name)
            return [:]
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(MaterialsJSON.self, from: data)
            var materials: [String: Material] = [:]
            materials.reserveCapacity(decoded.materials.count)
            for entry in decoded.materials {
                let baseColor = vec3(entry.baseColorFactor, fallback: SIMD3<Float>(1, 1, 1))
                let emissive = vec3(entry.emissiveFactor, fallback: SIMD3<Float>(0, 0, 0))
                let desc = MaterialDescriptor(
                    baseColor: ProceduralTextureGenerator.solid(width: 4,
                                                               height: 4,
                                                               color: SIMD4<UInt8>(255, 255, 255, 255),
                                                               format: .rgba8UnormSrgb),
                    normal: ProceduralTextureGenerator.flatNormal(),
                    metallicRoughness: ProceduralTextureGenerator.metallicRoughness(metallic: entry.metallicFactor,
                                                                                    roughness: entry.roughnessFactor),
                    emissive: ProceduralTextureGenerator.emissive(color: emissive),
                    occlusion: ProceduralTextureGenerator.occlusion(occlusion: entry.occlusionStrength),
                    baseColorFactor: baseColor,
                    metallicFactor: entry.metallicFactor,
                    roughnessFactor: entry.roughnessFactor,
                    emissiveFactor: emissive,
                    occlusionStrength: entry.occlusionStrength,
                    alpha: entry.alpha,
                    transmissionFactor: entry.transmissionFactor,
                    ior: entry.ior,
                    unlit: entry.unlit,
                    normalScale: entry.normalScale,
                    exposure: 1.0,
                    toneMapped: false,
                    cullMode: .back,
                    frontFacing: .counterClockwise
                )
                materials[entry.name] = MaterialFactory.make(device: device,
                                                             descriptor: desc,
                                                             label: entry.name)
            }
            return materials
        } catch {
            print("MaterialLoader: failed to load json:", name, error)
            return [:]
        }
    }
}

private struct MaterialsJSON: Codable {
    let version: Int
    let materials: [MaterialJSON]
}

private struct MaterialJSON: Codable {
    let name: String
    let baseColorFactor: [Float]
    let metallicFactor: Float
    let roughnessFactor: Float
    let emissiveFactor: [Float]
    let occlusionStrength: Float
    let alpha: Float
    let transmissionFactor: Float
    let ior: Float
    let unlit: Bool
    let normalScale: Float
}

private func vec3(_ values: [Float], fallback: SIMD3<Float>) -> SIMD3<Float> {
    guard values.count >= 3 else { return fallback }
    return SIMD3<Float>(values[0], values[1], values[2])
}
