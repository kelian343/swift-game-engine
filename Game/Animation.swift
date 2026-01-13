//
//  Animation.swift
//  Game
//
//  Created by Codex on 1/9/26.
//

import Foundation
import simd

public struct MotionProfile: Decodable {
    public struct Channel: Decodable {
        public var x: [Float]?
        public var y: [Float]?
        public var z: [Float]?
    }

    public struct Bone: Decodable {
        public var translation: Channel
        public var rotation: Channel
    }

    public struct Phase: Decodable {
        public var mode: String
        public var cycleDuration: Float?

        private enum CodingKeys: String, CodingKey {
            case mode
            case cycleDuration = "cycle_duration"
        }
    }

    public struct Units: Decodable {
        public var rotation: String
        public var translation: String
    }

    public struct Contacts: Decodable {
        public var left: [Float]
        public var right: [Float]
        public var threshold: Float
    }

    public var version: Int
    public var name: String
    public var duration: Float
    public var order: Int
    public var sample_fps: Int
    public var phase: Phase?
    public var units: Units?
    public var bones: [String: Bone]
    public var contacts: Contacts?
}

public enum MotionProfileLoader {
    public static func load(path: String) -> MotionProfile? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(MotionProfile.self, from: data)
    }
}

public enum MotionProfileEvaluator {
    public static func evaluate(_ coeffs: [Float], phase: Float, order: Int) -> Float {
        guard !coeffs.isEmpty else { return 0 }
        let p = max(0, min(phase, 1))
        var result = coeffs[0]
        var index = 1
        for k in 1...order {
            if index + 1 >= coeffs.count { break }
            let angle = 2 * Float.pi * Float(k) * p
            result += coeffs[index] * cos(angle) + coeffs[index + 1] * sin(angle)
            index += 2
        }
        return result
    }

    public static func evaluateChannel(_ channel: MotionProfile.Channel,
                                       phase: Float,
                                       order: Int,
                                       defaultValue: SIMD3<Float>) -> SIMD3<Float> {
        let x = channel.x.map { evaluate($0, phase: phase, order: order) } ?? defaultValue.x
        let y = channel.y.map { evaluate($0, phase: phase, order: order) } ?? defaultValue.y
        let z = channel.z.map { evaluate($0, phase: phase, order: order) } ?? defaultValue.z
        return SIMD3<Float>(x, y, z)
    }
}
