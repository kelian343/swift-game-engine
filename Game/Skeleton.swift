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

    public init(parent: [Int],
                bindLocal: [matrix_float4x4],
                boneMap: BoneMap? = nil,
                names: [String]? = nil,
                semanticIndex: [SemanticBone: Int] = [:]) {
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

    public static func humanoid8() -> Skeleton {
        let names = [
            "mixamorig:Hips",
            "mixamorig:Spine",
            "mixamorig:Spine1",
            "mixamorig:Spine2",
            "mixamorig:Neck",
            "mixamorig:Head",
            "mixamorig:HeadTop_End",
            "mixamorig:LeftShoulder",
            "mixamorig:LeftArm",
            "mixamorig:LeftForeArm",
            "mixamorig:LeftHand",
            "mixamorig:LeftHandThumb1",
            "mixamorig:LeftHandThumb2",
            "mixamorig:LeftHandThumb3",
            "mixamorig:LeftHandThumb4",
            "mixamorig:LeftHandIndex1",
            "mixamorig:LeftHandIndex2",
            "mixamorig:LeftHandIndex3",
            "mixamorig:LeftHandIndex4",
            "mixamorig:LeftHandMiddle1",
            "mixamorig:LeftHandMiddle2",
            "mixamorig:LeftHandMiddle3",
            "mixamorig:LeftHandMiddle4",
            "mixamorig:LeftHandRing1",
            "mixamorig:LeftHandRing2",
            "mixamorig:LeftHandRing3",
            "mixamorig:LeftHandRing4",
            "mixamorig:LeftHandPinky1",
            "mixamorig:LeftHandPinky2",
            "mixamorig:LeftHandPinky3",
            "mixamorig:LeftHandPinky4",
            "mixamorig:RightShoulder",
            "mixamorig:RightArm",
            "mixamorig:RightForeArm",
            "mixamorig:RightHand",
            "mixamorig:RightHandThumb1",
            "mixamorig:RightHandThumb2",
            "mixamorig:RightHandThumb3",
            "mixamorig:RightHandThumb4",
            "mixamorig:RightHandIndex1",
            "mixamorig:RightHandIndex2",
            "mixamorig:RightHandIndex3",
            "mixamorig:RightHandIndex4",
            "mixamorig:RightHandMiddle1",
            "mixamorig:RightHandMiddle2",
            "mixamorig:RightHandMiddle3",
            "mixamorig:RightHandMiddle4",
            "mixamorig:RightHandRing1",
            "mixamorig:RightHandRing2",
            "mixamorig:RightHandRing3",
            "mixamorig:RightHandRing4",
            "mixamorig:RightHandPinky1",
            "mixamorig:RightHandPinky2",
            "mixamorig:RightHandPinky3",
            "mixamorig:RightHandPinky4",
            "mixamorig:LeftUpLeg",
            "mixamorig:LeftLeg",
            "mixamorig:LeftFoot",
            "mixamorig:LeftToeBase",
            "mixamorig:LeftToe_End",
            "mixamorig:RightUpLeg",
            "mixamorig:RightLeg",
            "mixamorig:RightFoot",
            "mixamorig:RightToeBase",
            "mixamorig:RightToe_End"
        ]

        let parent: [Int] = [
            -1,
            0,
            1,
            2,
            3,
            4,
            5,
            3,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            10,
            15,
            16,
            17,
            10,
            19,
            20,
            21,
            10,
            23,
            24,
            25,
            10,
            27,
            28,
            29,
            3,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            34,
            39,
            40,
            41,
            34,
            43,
            44,
            45,
            34,
            47,
            48,
            49,
            34,
            51,
            52,
            53,
            0,
            55,
            56,
            57,
            58,
            0,
            60,
            61,
            62,
            63
        ]

        let scale: Float = 0.026
        let translations: [SIMD3<Float>] = [
            SIMD3<Float>(-0.000007, 99.791939, 0.000048),
            SIMD3<Float>(0.000860, 9.923462, -1.227335),
            SIMD3<Float>(0.000000, 11.731978, -0.000000),
            SIMD3<Float>(0.000000, 13.458837, 0.000000),
            SIMD3<Float>(0.000025, 15.027761, 0.877907),
            SIMD3<Float>(0.000003, 10.321838, 3.142429),
            SIMD3<Float>(0.000155, 18.474670, 6.636399),
            SIMD3<Float>(6.105825, 9.106292, 0.757062),
            SIMD3<Float>(0.000000, 12.922286, 0.000000),
            SIMD3<Float>(0.000000, 27.404682, -0.000000),
            SIMD3<Float>(-0.000013, 27.614464, 0.000000),
            SIMD3<Float>(-3.002975, 3.788809, 2.167149),
            SIMD3<Float>(-0.000000, 4.744971, 0.000000),
            SIMD3<Float>(-0.000000, 4.382129, 0.000000),
            SIMD3<Float>(-0.000005, 3.459078, 0.000000),
            SIMD3<Float>(-2.822044, 12.266617, 0.231825),
            SIMD3<Float>(-0.000000, 3.891968, -0.000000),
            SIMD3<Float>(0.000000, 3.415161, -0.000000),
            SIMD3<Float>(0.000001, 3.077988, 0.000000),
            SIMD3<Float>(-0.000018, 12.775528, -0.000001),
            SIMD3<Float>(-0.000000, 3.613968, -0.000000),
            SIMD3<Float>(0.000029, 3.459763, -0.000000),
            SIMD3<Float>(-0.000030, 3.680191, -0.000000),
            SIMD3<Float>(2.216631, 12.147010, -0.009996),
            SIMD3<Float>(0.000000, 3.601189, 0.000000),
            SIMD3<Float>(-0.000000, 3.307312, 0.000000),
            SIMD3<Float>(-0.000024, 3.660118, 0.000017),
            SIMD3<Float>(4.725831, 10.908194, 0.226132),
            SIMD3<Float>(-0.000000, 4.136657, 0.000000),
            SIMD3<Float>(0.000000, 2.594834, 0.000000),
            SIMD3<Float>(-0.000000, 2.923866, -0.000000),
            SIMD3<Float>(-6.105696, 9.106384, 0.757076),
            SIMD3<Float>(0.000000, 12.922287, -0.000000),
            SIMD3<Float>(0.000000, 27.404682, -0.000000),
            SIMD3<Float>(0.000013, 27.614464, 0.000015),
            SIMD3<Float>(3.002974, 3.788809, 2.167149),
            SIMD3<Float>(-0.000000, 4.744970, -0.000000),
            SIMD3<Float>(-0.000000, 4.382135, -0.000000),
            SIMD3<Float>(0.000011, 3.459071, -0.000023),
            SIMD3<Float>(2.822043, 12.266617, 0.231825),
            SIMD3<Float>(0.000000, 3.891968, -0.000000),
            SIMD3<Float>(-0.000000, 3.415161, 0.000000),
            SIMD3<Float>(-0.000001, 3.077988, 0.000000),
            SIMD3<Float>(0.000017, 12.775528, -0.000001),
            SIMD3<Float>(0.000000, 3.613968, -0.000000),
            SIMD3<Float>(-0.000029, 3.459763, 0.000000),
            SIMD3<Float>(0.000029, 3.680191, -0.000000),
            SIMD3<Float>(-2.216632, 12.147003, -0.009996),
            SIMD3<Float>(-0.000000, 3.601196, -0.000000),
            SIMD3<Float>(-0.000000, 3.307312, -0.000000),
            SIMD3<Float>(0.000024, 3.660118, -0.000000),
            SIMD3<Float>(-4.725833, 10.908194, 0.226132),
            SIMD3<Float>(-0.000000, 4.136650, -0.000000),
            SIMD3<Float>(-0.000000, 2.594841, -0.000000),
            SIMD3<Float>(0.000000, 2.923866, 0.000000),
            SIMD3<Float>(9.123874, -6.657189, -0.055403),
            SIMD3<Float>(-0.000000, 40.599436, 0.000000),
            SIMD3<Float>(-0.000000, 42.099026, 0.000000),
            SIMD3<Float>(0.000000, 15.721559, -0.000000),
            SIMD3<Float>(0.000000, 10.000000, 0.000000),
            SIMD3<Float>(-9.125032, -6.655601, -0.055353),
            SIMD3<Float>(0.000000, 40.599439, 0.000000),
            SIMD3<Float>(-0.000000, 42.099024, -0.000000),
            SIMD3<Float>(0.000000, 15.721559, 0.000000),
            SIMD3<Float>(0.000000, 10.000000, 0.000000)
        ]

        let preRotations: [SIMD3<Float>] = [
            SIMD3<Float>(0.000000, -0.000200, 0.005000),
            SIMD3<Float>(-6.963456, 0.000043, 0.000700),
            SIMD3<Float>(0.022471, 0.000000, -0.001068),
            SIMD3<Float>(6.616954, 0.000229, 0.000390),
            SIMD3<Float>(0.324032, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(-91.608217, 78.377263, 177.220898),
            SIMD3<Float>(-1.203888, -0.000000, 11.611489),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(27.311694, -12.920891, 23.413151),
            SIMD3<Float>(0.000796, 0.000000, 0.000092),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(2.141681, 14.317562, 8.601580),
            SIMD3<Float>(0.000064, -0.000000, 0.000558),
            SIMD3<Float>(0.000000, 0.000000, -0.000712),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000130, 0.458551, 0.002611),
            SIMD3<Float>(0.000064, -0.000000, 0.000024),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(-0.000496, 0.524765, -0.074962),
            SIMD3<Float>(0.000064, -0.000000, 0.000547),
            SIMD3<Float>(-0.000264, 0.000000, -0.000925),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.001626, 0.847580, 0.088338),
            SIMD3<Float>(0.000327, -0.000000, 0.016163),
            SIMD3<Float>(-0.000682, -0.000000, -0.042156),
            SIMD3<Float>(0.000419, 0.000000, 0.026334),
            SIMD3<Float>(-0.000390, 0.469814, -0.065900),
            SIMD3<Float>(-91.608226, -78.377379, -177.220476),
            SIMD3<Float>(-1.204301, -0.000001, -11.611368),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(27.311698, 12.920917, -23.413138),
            SIMD3<Float>(0.000969, 0.000000, -0.000045),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(2.169665, -14.488138, -8.639548),
            SIMD3<Float>(0.000064, -0.000001, -0.000544),
            SIMD3<Float>(0.000000, 0.000000, 0.000691),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(-0.009412, -0.768824, 0.157577),
            SIMD3<Float>(0.000064, -0.000001, -0.000042),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(-0.004600, -0.767228, -0.195736),
            SIMD3<Float>(0.000064, -0.000001, -0.000550),
            SIMD3<Float>(0.000000, 0.000000, 0.000925),
            SIMD3<Float>(0.000000, 0.000000, 0.000000),
            SIMD3<Float>(-0.006803, -0.872421, -0.034352),
            SIMD3<Float>(0.000064, -0.000001, -0.000359),
            SIMD3<Float>(0.000000, 0.000000, 0.001191),
            SIMD3<Float>(0.000000, 0.000000, -0.001195),
            SIMD3<Float>(-0.011577, -0.973884, 0.252909),
            SIMD3<Float>(-0.727685, -0.000160, -179.659696),
            SIMD3<Float>(-2.075948, 0.008620, -0.678670),
            SIMD3<Float>(65.468048, -0.161307, 3.295776),
            SIMD3<Float>(26.412131, -3.227114, -2.566812),
            SIMD3<Float>(0.000000, -0.000000, 0.000000),
            SIMD3<Float>(-0.725808, -0.000160, 179.649635),
            SIMD3<Float>(-2.079703, -0.008597, 0.678671),
            SIMD3<Float>(65.469923, 0.161415, -3.295765),
            SIMD3<Float>(26.412127, 3.185060, 2.544236),
            SIMD3<Float>(-0.000000, -0.000000, -0.000000)
        ]

        let localRotations: [SIMD3<Float>] = Array(repeating: SIMD3<Float>(0, 0, 0), count: names.count)

        let rootFacingFix = matrix4x4_rotation(radians: .pi, axis: SIMD3<Float>(0, 1, 0))
        let bindLocal: [matrix_float4x4] = zip(zip(translations, preRotations), localRotations).enumerated().map { index, pair in
            let ((t, pre), local) = pair
            let raw = index == 0 ? SIMD3<Float>(0, 0, 0) : t
            let scaled = SIMD3<Float>(raw.x * scale, raw.y * scale, raw.z * scale)
            var rot = simd_mul(rotationXYZDegrees(pre), rotationXYZDegrees(local))
            if index == 0 {
                rot = simd_mul(rootFacingFix, rot)
            }
            let trans = matrix4x4_translation(scaled.x, scaled.y, scaled.z)
            return simd_mul(trans, rot)
        }

        let semantic = RigProfile.mixamo().resolve(names: names)
        return Skeleton(parent: parent,
                        bindLocal: bindLocal,
                        boneMap: nil,
                        names: names,
                        semanticIndex: semantic)
    }

    private static func rotationXYZDegrees(_ degrees: SIMD3<Float>) -> matrix_float4x4 {
        let rx = matrix4x4_rotation(radians: radians_from_degrees(degrees.x), axis: SIMD3<Float>(1, 0, 0))
        let ry = matrix4x4_rotation(radians: radians_from_degrees(degrees.y), axis: SIMD3<Float>(0, 1, 0))
        let rz = matrix4x4_rotation(radians: radians_from_degrees(degrees.z), axis: SIMD3<Float>(0, 0, 1))
        return simd_mul(rz, simd_mul(ry, rx))
    }

    public func semantic(_ bone: SemanticBone) -> Int? {
        semanticIndex[bone]
    }
}
