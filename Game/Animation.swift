//
//  Animation.swift
//  Game
//
//  Created by Codex on 1/9/26.
//

import Foundation
import simd

public struct AnimationCurve {
    public var times: [Float]
    public var values: [Float]
    public var defaultValue: Float

    public init(times: [Float], values: [Float], defaultValue: Float = 0) {
        self.times = times
        self.values = values
        self.defaultValue = defaultValue
    }

    public func sample(at time: Float) -> Float {
        guard !times.isEmpty, times.count == values.count else {
            return defaultValue
        }
        if time <= times[0] { return values[0] }
        if time >= times[times.count - 1] { return values[values.count - 1] }

        var lo = 0
        var hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let t0 = times[lo]
        let t1 = times[hi]
        let v0 = values[lo]
        let v1 = values[hi]
        let span = max(t1 - t0, 0.000001)
        let a = (time - t0) / span
        return v0 + (v1 - v0) * a
    }
}

public struct VectorCurve {
    public var x: AnimationCurve?
    public var y: AnimationCurve?
    public var z: AnimationCurve?

    public init(x: AnimationCurve? = nil, y: AnimationCurve? = nil, z: AnimationCurve? = nil) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func sample(at time: Float, defaultValue: SIMD3<Float>) -> SIMD3<Float> {
        let sx = x?.sample(at: time) ?? defaultValue.x
        let sy = y?.sample(at: time) ?? defaultValue.y
        let sz = z?.sample(at: time) ?? defaultValue.z
        return SIMD3<Float>(sx, sy, sz)
    }
}

public struct BoneAnimation {
    public var translation: VectorCurve?
    public var rotation: VectorCurve?

    public init(translation: VectorCurve? = nil, rotation: VectorCurve? = nil) {
        self.translation = translation
        self.rotation = rotation
    }
}

public struct AnimationClip {
    public var name: String
    public var duration: Float
    public var boneAnimations: [String: BoneAnimation]

    public init(name: String, duration: Float, boneAnimations: [String: BoneAnimation]) {
        self.name = name
        self.duration = duration
        self.boneAnimations = boneAnimations
    }
}

public enum FBXAnimationLoader {
    private struct CurveNodeBinding {
        var boneName: String
        var channel: Channel
    }

    private enum Channel {
        case translation
        case rotation
    }

    private struct CurveBinding {
        var nodeId: Int
        var axis: Axis
    }

    private enum Axis: String {
        case x = "X"
        case y = "Y"
        case z = "Z"
    }

    private static let timeScale: Float = 46186158000.0

    public static func loadClip(path: String, name: String = "Walking") -> AnimationClip? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let modelIdToName = parseModelNames(text: text)
        let curveNodeBindings = parseCurveNodeBindings(text: text, modelIdToName: modelIdToName)
        let curveBindings = parseCurveBindings(text: text)
        let curves = parseCurves(text: text)

        var boneAnimations: [String: BoneAnimation] = [:]
        var maxTime: Float = 0

        for (curveId, binding) in curveBindings {
            guard let curve = curves[curveId] else { continue }
            guard let node = curveNodeBindings[binding.nodeId] else { continue }

            let times = curve.times
            if let last = times.last { maxTime = max(maxTime, last) }

            var anim = boneAnimations[node.boneName] ?? BoneAnimation()
            switch node.channel {
            case .translation:
                var vec = anim.translation ?? VectorCurve()
                apply(curve: curve, axis: binding.axis, to: &vec)
                anim.translation = vec
            case .rotation:
                var vec = anim.rotation ?? VectorCurve()
                apply(curve: curve, axis: binding.axis, to: &vec)
                anim.rotation = vec
            }
            boneAnimations[node.boneName] = anim
        }

        return AnimationClip(name: name, duration: max(maxTime, 0.001), boneAnimations: boneAnimations)
    }

    private static func apply(curve: AnimationCurve, axis: Axis, to vec: inout VectorCurve) {
        switch axis {
        case .x: vec.x = curve
        case .y: vec.y = curve
        case .z: vec.z = curve
        }
    }

    private static func parseModelNames(text: String) -> [Int: String] {
        let pattern = #"Model:\s+(\d+),\s+"Model::([^"]+)",\s+"LimbNode""#
        return matches(text: text, pattern: pattern).reduce(into: [:]) { dict, match in
            guard match.count >= 3, let id = Int(match[1]) else { return }
            dict[id] = match[2]
        }
    }

    private static func parseCurveNodeBindings(text: String, modelIdToName: [Int: String]) -> [Int: CurveNodeBinding] {
        let pattern = #"C:\s+"OP",(\d+),(\d+),\s+"Lcl (Translation|Rotation)""#
        return matches(text: text, pattern: pattern).reduce(into: [:]) { dict, match in
            guard match.count >= 4, let nodeId = Int(match[1]), let modelId = Int(match[2]) else { return }
            guard let boneName = modelIdToName[modelId] else { return }
            let channel: Channel = match[3] == "Translation" ? .translation : .rotation
            dict[nodeId] = CurveNodeBinding(boneName: boneName, channel: channel)
        }
    }

    private static func parseCurveBindings(text: String) -> [Int: CurveBinding] {
        let pattern = #"C:\s+"OP",(\d+),(\d+),\s+"d\|([XYZ])""#
        return matches(text: text, pattern: pattern).reduce(into: [:]) { dict, match in
            guard match.count >= 4, let curveId = Int(match[1]), let nodeId = Int(match[2]) else { return }
            guard let axis = Axis(rawValue: match[3]) else { return }
            dict[curveId] = CurveBinding(nodeId: nodeId, axis: axis)
        }
    }

    private static func parseCurves(text: String) -> [Int: AnimationCurve] {
        let pattern = #"AnimationCurve:\s+(\d+),.*?KeyTime:\s*\*\d+\s*\{\s*a:\s*([^\}]*)\}\s*KeyValueFloat:\s*\*\d+\s*\{\s*a:\s*([^\}]*)\}"#
        let results = matches(text: text, pattern: pattern, dotAll: true)
        var curves: [Int: AnimationCurve] = [:]
        curves.reserveCapacity(results.count)

        for match in results {
            guard match.count >= 4, let id = Int(match[1]) else { continue }
            let times = parseInt64List(match[2]).map { Float($0) / timeScale }
            let values = parseFloatList(match[3])
            curves[id] = AnimationCurve(times: times, values: values)
        }
        return curves
    }

    private static func matches(text: String, pattern: String, dotAll: Bool = false) -> [[String]] {
        let options: NSRegularExpression.Options = dotAll ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).compactMap { i in
                guard let r = Range(match.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    private static func parseFloatList(_ text: String) -> [Float] {
        let cleaned = text.replacingOccurrences(of: "\n", with: "")
        return cleaned.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func parseInt64List(_ text: String) -> [Int64] {
        let cleaned = text.replacingOccurrences(of: "\n", with: "")
        return cleaned.split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}
