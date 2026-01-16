//
//  SkeletonLoader.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Foundation
import simd

enum SkeletonLoader {
    static func loadSkeleton(named name: String,
                             rigProfile: Skeleton.RigProfile = .mixamo()) -> Skeleton? {
        guard let path = Bundle.main.path(forResource: name, ofType: "json") else {
            print("SkeletonLoader: missing json:", name)
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoded = try JSONDecoder().decode(SkeletonJSON.self, from: data)
            return buildSkeleton(from: decoded, rigProfile: rigProfile)
        } catch {
            print("SkeletonLoader: failed to load json:", name, error)
            return nil
        }
    }

    private static func buildSkeleton(from json: SkeletonJSON,
                                      rigProfile: Skeleton.RigProfile) -> Skeleton? {
        let boneCount = json.names.count
        guard boneCount > 0,
              json.parent.count == boneCount,
              json.translations.count == boneCount else {
            print("SkeletonLoader: skeleton arrays do not match.")
            return nil
        }

        let rawTranslations = vec3Array(json.translations, fallback: SIMD3<Float>(0, 0, 0))
        let preRotations: [SIMD3<Float>]
        if json.preRotationDegrees.isEmpty {
            preRotations = Array(repeating: SIMD3<Float>(0, 0, 0), count: boneCount)
        } else if json.preRotationDegrees.count == boneCount {
            preRotations = vec3Array(json.preRotationDegrees, fallback: SIMD3<Float>(0, 0, 0))
        } else {
            print("SkeletonLoader: preRotationDegrees count mismatch.")
            return nil
        }

        let rootFixDegrees = json.rootRotationFixDegrees
        let rootFix = Skeleton.rotationXYZDegrees(vec3(rootFixDegrees, fallback: SIMD3<Float>(0, 0, 0)))
        let rootZero = json.rootRestIsZero ?? false
        let scale = json.unitScale

        var restTranslation: [SIMD3<Float>] = []
        restTranslation.reserveCapacity(boneCount)
        for i in 0..<boneCount {
            let raw = (rootZero && i == 0) ? SIMD3<Float>(0, 0, 0) : rawTranslations[i]
            restTranslation.append(raw * scale)
        }

        let localRotations = Array(repeating: SIMD3<Float>(0, 0, 0), count: boneCount)
        let bindLocal: [matrix_float4x4] = zip(zip(restTranslation, preRotations), localRotations).enumerated().map { index, pair in
            let ((t, pre), local) = pair
            var rot = simd_mul(Skeleton.rotationXYZDegrees(pre), Skeleton.rotationXYZDegrees(local))
            if index == 0 {
                rot = simd_mul(rootFix, rot)
            }
            let trans = matrix4x4_translation(t.x, t.y, t.z)
            return simd_mul(trans, rot)
        }

        let semantic = rigProfile.resolve(names: json.names)
        return Skeleton(parent: json.parent,
                        bindLocal: bindLocal,
                        boneMap: nil,
                        names: json.names,
                        semanticIndex: semantic,
                        restTranslation: restTranslation,
                        rawRestTranslation: rawTranslations,
                        preRotationDegrees: preRotations,
                        rootRotationFix: rootFix,
                        unitScale: scale)
    }
}

private struct SkeletonJSON: Codable {
    let version: Int
    let name: String
    let unitScale: Float
    let rootRotationFixDegrees: [Float]
    let rootRestIsZero: Bool?
    let names: [String]
    let parent: [Int]
    let translations: [[Float]]
    let preRotationDegrees: [[Float]]
}

private func vec3Array(_ values: [[Float]], fallback: SIMD3<Float>) -> [SIMD3<Float>] {
    return values.map { vec3($0, fallback: fallback) }
}

private func vec3(_ values: [Float], fallback: SIMD3<Float>) -> SIMD3<Float> {
    guard values.count >= 3 else { return fallback }
    return SIMD3<Float>(values[0], values[1], values[2])
}
