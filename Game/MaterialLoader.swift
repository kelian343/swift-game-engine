//
//  MaterialLoader.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Foundation
import Metal
import MetalKit
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
            let baseDir = (path as NSString).deletingLastPathComponent
            for entry in decoded.materials {
                let baseColor = vec3(entry.baseColorFactor, fallback: SIMD3<Float>(1, 1, 1))
                let emissive = vec3(entry.emissiveFactor, fallback: SIMD3<Float>(0, 0, 0))
                let baseColorTex = loadTexture(path: entry.baseColorTexture,
                                               device: device,
                                               baseDir: baseDir,
                                               srgb: true,
                                               label: "\(entry.name).baseColor")
                let normalTex = loadTexture(path: entry.normalTexture,
                                            device: device,
                                            baseDir: baseDir,
                                            srgb: false,
                                            label: "\(entry.name).normal")
                let mrTex = loadTexture(path: entry.metallicRoughnessTexture,
                                        device: device,
                                        baseDir: baseDir,
                                        srgb: false,
                                        label: "\(entry.name).metallicRoughness")
                let emissiveTex = loadTexture(path: entry.emissiveTexture,
                                              device: device,
                                              baseDir: baseDir,
                                              srgb: true,
                                              label: "\(entry.name).emissive")
                let occlusionTex = loadTexture(path: entry.occlusionTexture,
                                               device: device,
                                               baseDir: baseDir,
                                               srgb: false,
                                               label: "\(entry.name).occlusion")

                materials[entry.name] = Material(baseColorTexture: baseColorTex,
                                                 normalTexture: normalTex,
                                                 metallicRoughnessTexture: mrTex,
                                                 emissiveTexture: emissiveTex,
                                                 occlusionTexture: occlusionTex,
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
                                                 frontFacing: .counterClockwise)
            }
            return materials
        } catch {
            print("MaterialLoader: failed to load json:", name, error)
            return [:]
        }
    }
}

private func loadTexture(path: String?,
                         device: MTLDevice,
                         baseDir: String,
                         srgb: Bool,
                         label: String) -> TextureResource? {
    guard let path = path, !path.isEmpty else { return nil }
    let url = resolveTextureURL(path: path, baseDir: baseDir)
    guard let url = url else {
        print("MaterialLoader: missing texture:", path)
        return nil
    }
    let loader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option: Any] = [
        .SRGB: srgb
    ]
    do {
        let tex = try loader.newTexture(URL: url, options: options)
        return TextureResource(texture: tex, label: label)
    } catch {
        print("MaterialLoader: failed to load texture:", url.path, error)
        return nil
    }
}

private func resolveTextureURL(path: String, baseDir: String) -> URL? {
    let nsPath = path as NSString
    if nsPath.isAbsolutePath {
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    let relativeURL = URL(fileURLWithPath: baseDir).appendingPathComponent(path)
    if FileManager.default.fileExists(atPath: relativeURL.path) {
        return relativeURL
    }
    if let bundleRoot = Bundle.main.resourceURL {
        let bundleURL = bundleRoot.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
    }
    return nil
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
    let baseColorTexture: String?
    let normalTexture: String?
    let metallicRoughnessTexture: String?
    let metallicChannel: String?
    let roughnessChannel: String?
    let emissiveTexture: String?
    let occlusionTexture: String?
    let occlusionChannel: String?
}

private func vec3(_ values: [Float], fallback: SIMD3<Float>) -> SIMD3<Float> {
    guard values.count >= 3 else { return fallback }
    return SIMD3<Float>(values[0], values[1], values[2])
}
