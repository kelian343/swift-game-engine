//
//  Skeleton.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public struct Skeleton {
    public enum SemanticBone: String, CaseIterable, Hashable {
        case pelvis
        case spine1
        case spine2
        case spine3
        case chest
        case neck
        case head
        case clavicleL
        case upperarmL
        case lowerarmL
        case handL
        case clavicleR
        case upperarmR
        case lowerarmR
        case handR
        case thighL
        case calfL
        case footL
        case ballL
        case thighR
        case calfR
        case footR
        case ballR
    }

    public struct RigProfile {
        public var aliases: [SemanticBone: [String]]

        public init(aliases: [SemanticBone: [String]]) {
            self.aliases = aliases
        }

        public func resolve(names: [String]) -> [SemanticBone: Int] {
            var table: [String: Int] = [:]
            table.reserveCapacity(names.count)
            for (i, name) in names.enumerated() {
                table[name.lowercased()] = i
            }

            var result: [SemanticBone: Int] = [:]
            result.reserveCapacity(aliases.count)
            for (semantic, list) in aliases {
                for alias in list {
                    if let index = table[alias.lowercased()] {
                        result[semantic] = index
                        break
                    }
                }
            }
            return result
        }

        public static func mixamo() -> RigProfile {
            let a: [SemanticBone: [String]] = [
                .pelvis: ["mixamorig:Hips", "Hips", "pelvis"],
                .spine1: ["mixamorig:Spine", "Spine", "spine_01"],
                .spine2: ["mixamorig:Spine1", "Spine1", "spine_02"],
                .spine3: ["mixamorig:Spine2", "Spine2", "spine_03"],
                .neck: ["mixamorig:Neck", "Neck", "neck_01"],
                .head: ["mixamorig:Head", "Head"],
                .clavicleL: ["mixamorig:LeftShoulder", "LeftShoulder", "clavicle_l"],
                .upperarmL: ["mixamorig:LeftArm", "LeftArm", "upperarm_l"],
                .lowerarmL: ["mixamorig:LeftForeArm", "LeftForeArm", "lowerarm_l"],
                .handL: ["mixamorig:LeftHand", "LeftHand", "hand_l"],
                .clavicleR: ["mixamorig:RightShoulder", "RightShoulder", "clavicle_r"],
                .upperarmR: ["mixamorig:RightArm", "RightArm", "upperarm_r"],
                .lowerarmR: ["mixamorig:RightForeArm", "RightForeArm", "lowerarm_r"],
                .handR: ["mixamorig:RightHand", "RightHand", "hand_r"],
                .thighL: ["mixamorig:LeftUpLeg", "LeftUpLeg", "thigh_l"],
                .calfL: ["mixamorig:LeftLeg", "LeftLeg", "calf_l"],
                .footL: ["mixamorig:LeftFoot", "LeftFoot", "foot_l"],
                .ballL: ["mixamorig:LeftToeBase", "LeftToeBase", "ball_l"],
                .thighR: ["mixamorig:RightUpLeg", "RightUpLeg", "thigh_r"],
                .calfR: ["mixamorig:RightLeg", "RightLeg", "calf_r"],
                .footR: ["mixamorig:RightFoot", "RightFoot", "foot_r"],
                .ballR: ["mixamorig:RightToeBase", "RightToeBase", "ball_r"]
            ]
            return RigProfile(aliases: a)
        }
    }

    public struct BoneMap {
        public var pelvis: Int
        public var spine: Int
        public var head: Int
        public var thighL: Int
        public var calfL: Int
        public var thighR: Int
        public var calfR: Int
        public var chest: Int

        public init(pelvis: Int,
                    spine: Int,
                    head: Int,
                    thighL: Int,
                    calfL: Int,
                    thighR: Int,
                    calfR: Int,
                    chest: Int) {
            self.pelvis = pelvis
            self.spine = spine
            self.head = head
            self.thighL = thighL
            self.calfL = calfL
            self.thighR = thighR
            self.calfR = calfR
            self.chest = chest
        }

        public func isValid(for boneCount: Int) -> Bool {
            let ids = [pelvis, spine, head, thighL, calfL, thighR, calfR, chest]
            return ids.allSatisfy { $0 >= 0 && $0 < boneCount }
        }
    }

    public let boneCount: Int
    public let parent: [Int]
    public let bindLocal: [matrix_float4x4]
    public let invBindModel: [matrix_float4x4]
    public let boneMap: BoneMap?
    public let names: [String]
    public let indexByName: [String: Int]
    public let semanticIndex: [SemanticBone: Int]
    public let restTranslation: [SIMD3<Float>]
    public let rawRestTranslation: [SIMD3<Float>]
    public let preRotationDegrees: [SIMD3<Float>]
    public let rootRotationFix: matrix_float4x4
    public let unitScale: Float

    public init(parent: [Int],
                bindLocal: [matrix_float4x4],
                boneMap: BoneMap? = nil,
                names: [String]? = nil,
                semanticIndex: [SemanticBone: Int] = [:],
                restTranslation: [SIMD3<Float>]? = nil,
                rawRestTranslation: [SIMD3<Float>]? = nil,
                preRotationDegrees: [SIMD3<Float>]? = nil,
                rootRotationFix: matrix_float4x4 = matrix_identity_float4x4,
                unitScale: Float = 1.0) {
        precondition(parent.count == bindLocal.count, "Skeleton parent/bindLocal count mismatch")
        self.parent = parent
        self.bindLocal = bindLocal
        self.boneCount = parent.count
        let model = Skeleton.buildModelTransforms(parent: parent, local: bindLocal)
        self.invBindModel = model.map { simd_inverse($0) }
        self.boneMap = boneMap
        let resolvedNames = names ?? (0..<parent.count).map { "bone_\($0)" }
        self.names = resolvedNames
        var index: [String: Int] = [:]
        index.reserveCapacity(resolvedNames.count)
        for (i, name) in resolvedNames.enumerated() {
            index[name] = i
        }
        self.indexByName = index
        self.semanticIndex = semanticIndex
        let fallbackTranslation = bindLocal.map { Skeleton.translation($0) }
        self.restTranslation = restTranslation ?? fallbackTranslation
        self.rawRestTranslation = rawRestTranslation ?? restTranslation ?? fallbackTranslation
        self.preRotationDegrees = preRotationDegrees ?? Array(repeating: SIMD3<Float>(0, 0, 0), count: parent.count)
        self.rootRotationFix = rootRotationFix
        self.unitScale = unitScale
    }

    public static func buildModelTransforms(parent: [Int],
                                            local: [matrix_float4x4]) -> [matrix_float4x4] {
        var model = Array(repeating: matrix_identity_float4x4, count: local.count)
        for i in 0..<local.count {
            let p = parent[i]
            if p < 0 {
                model[i] = local[i]
            } else {
                model[i] = simd_mul(model[p], local[i])
            }
        }
        return model
    }

    public static func buildModelTransforms(parent: [Int],
                                            local: [matrix_float4x4],
                                            into model: inout [matrix_float4x4]) {
        if model.count != local.count {
            model = Array(repeating: matrix_identity_float4x4, count: local.count)
        }
        for i in 0..<local.count {
            let p = parent[i]
            if p < 0 {
                model[i] = local[i]
            } else {
                model[i] = simd_mul(model[p], local[i])
            }
        }
    }

    public static func mixamoReference() -> Skeleton {
        if let skeleton = SkeletonLoader.loadSkeleton(named: "YBot.skeleton") {
            return skeleton
        }
        fatalError("Failed to load YBot.skeleton.json from bundle.")
    }

    public static func rotationXYZDegrees(_ degrees: SIMD3<Float>) -> matrix_float4x4 {
        let rx = matrix4x4_rotation(radians: radians_from_degrees(degrees.x), axis: SIMD3<Float>(1, 0, 0))
        let ry = matrix4x4_rotation(radians: radians_from_degrees(degrees.y), axis: SIMD3<Float>(0, 1, 0))
        let rz = matrix4x4_rotation(radians: radians_from_degrees(degrees.z), axis: SIMD3<Float>(0, 0, 1))
        return simd_mul(rz, simd_mul(ry, rx))
    }

    public static func translation(_ m: matrix_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    public func semantic(_ bone: SemanticBone) -> Int? {
        semanticIndex[bone]
    }
}
