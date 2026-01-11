//
//  ProceduralTextures.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import simd

public enum ProceduralTextureFormat {
    case rgba8Unorm
}

public struct ProceduralTexture {
    public let width: Int
    public let height: Int
    public let format: ProceduralTextureFormat
    public let bytes: [UInt8]

    public init(width: Int, height: Int, format: ProceduralTextureFormat, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.format = format
        self.bytes = bytes
    }
}

public enum ProceduralTextureGenerator {
    public static let digitsAtlasCellWidth: Int = 8
    public static let digitsAtlasCellHeight: Int = 12

    public static func solid(width: Int, height: Int, color: SIMD4<UInt8>) -> ProceduralTexture {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i + 0] = color.x
            bytes[i + 1] = color.y
            bytes[i + 2] = color.z
            bytes[i + 3] = color.w
        }
        return ProceduralTexture(width: width,
                                 height: height,
                                 format: .rgba8Unorm,
                                 bytes: bytes)
    }

    public static func checkerboard(width: Int = 256,
                                    height: Int = 256,
                                    cell: Int = 32,
                                    colorA: UInt8 = 230,
                                    colorB: UInt8 = 40) -> ProceduralTexture {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let cx = (x / cell) % 2
                let cy = (y / cell) % 2
                let on = (cx ^ cy) == 0
                let c: UInt8 = on ? colorA : colorB
                let idx = (y * width + x) * 4
                bytes[idx + 0] = c
                bytes[idx + 1] = c
                bytes[idx + 2] = c
                bytes[idx + 3] = 255
            }
        }
        return ProceduralTexture(width: width,
                                 height: height,
                                 format: .rgba8Unorm,
                                 bytes: bytes)
    }

    /// Digits atlas (0-9) in a single row, alpha-masked for overlay text.
    public static func digitsAtlas() -> ProceduralTexture {
        let cellW = digitsAtlasCellWidth
        let cellH = digitsAtlasCellHeight
        let atlasW = cellW * 10
        let atlasH = cellH
        var bytes = [UInt8](repeating: 0, count: atlasW * atlasH * 4)

        let glyphs: [[String]] = [
            ["01110","10001","10011","10101","11001","10001","01110"], // 0
            ["00100","01100","00100","00100","00100","00100","01110"], // 1
            ["01110","10001","00001","00010","00100","01000","11111"], // 2
            ["11110","00001","00001","01110","00001","00001","11110"], // 3
            ["00010","00110","01010","10010","11111","00010","00010"], // 4
            ["11111","10000","11110","00001","00001","10001","01110"], // 5
            ["00110","01000","10000","11110","10001","10001","01110"], // 6
            ["11111","00001","00010","00100","01000","01000","01000"], // 7
            ["01110","10001","10001","01110","10001","10001","01110"], // 8
            ["01110","10001","10001","01111","00001","00010","11100"]  // 9
        ]

        let padX = max((cellW - 5) / 2, 0)
        let padY = max((cellH - 7) / 2, 0)

        for digit in 0..<10 {
            let originX = digit * cellW + padX
            let originY = padY
            let rows = glyphs[digit]
            for y in 0..<rows.count {
                let row = Array(rows[y])
                for x in 0..<row.count where row[x] == "1" {
                    let px = originX + x
                    let py = originY + y
                    if px < atlasW && py < atlasH {
                        let idx = (py * atlasW + px) * 4
                        bytes[idx + 0] = 255
                        bytes[idx + 1] = 255
                        bytes[idx + 2] = 255
                        bytes[idx + 3] = 255
                    }
                }
            }
        }

        return ProceduralTexture(width: atlasW,
                                 height: atlasH,
                                 format: .rgba8Unorm,
                                 bytes: bytes)
    }

    public static func flatNormal(width: Int = 4, height: Int = 4) -> ProceduralTexture {
        // (0.5, 0.5, 1.0) in 0-255
        return solid(width: width,
                     height: height,
                     color: SIMD4<UInt8>(128, 128, 255, 255))
    }

    public static func metallicRoughness(width: Int = 4,
                                         height: Int = 4,
                                         metallic: Float,
                                         roughness: Float) -> ProceduralTexture {
        let m = UInt8(max(0, min(255, Int(metallic * 255))))
        let r = UInt8(max(0, min(255, Int(roughness * 255))))
        // glTF convention: G = roughness, B = metallic
        return solid(width: width,
                     height: height,
                     color: SIMD4<UInt8>(0, r, m, 255))
    }

    public static func occlusion(width: Int = 4,
                                 height: Int = 4,
                                 occlusion: Float) -> ProceduralTexture {
        let o = UInt8(max(0, min(255, Int(occlusion * 255))))
        return solid(width: width,
                     height: height,
                     color: SIMD4<UInt8>(o, o, o, 255))
    }

    public static func emissive(width: Int = 4,
                                height: Int = 4,
                                color: SIMD3<Float>) -> ProceduralTexture {
        let r = UInt8(max(0, min(255, Int(color.x * 255))))
        let g = UInt8(max(0, min(255, Int(color.y * 255))))
        let b = UInt8(max(0, min(255, Int(color.z * 255))))
        return solid(width: width,
                     height: height,
                     color: SIMD4<UInt8>(r, g, b, 255))
    }

    public static func normalMapFromHeight(width: Int = 256,
                                           height: Int = 256,
                                           amplitude: Float = 1.0,
                                           frequency: Float = 6.0) -> ProceduralTexture {
        func heightFunc(_ u: Float, _ v: Float) -> Float {
            let s = sin(u * frequency * Float.pi * 2.0)
            let c = cos(v * frequency * Float.pi * 2.0)
            return s * c * 0.5 + 0.5
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let du = 1.0 / Float(width)
        let dv = 1.0 / Float(height)
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) * du
                let v = Float(y) * dv
                let hL = heightFunc(u - du, v)
                let hR = heightFunc(u + du, v)
                let hD = heightFunc(u, v - dv)
                let hU = heightFunc(u, v + dv)
                let dx = (hR - hL) * amplitude
                let dy = (hU - hD) * amplitude
                var n = SIMD3<Float>(-dx, -dy, 1.0)
                n = simd_normalize(n)
                let idx = (y * width + x) * 4
                bytes[idx + 0] = UInt8(max(0, min(255, Int((n.x * 0.5 + 0.5) * 255))))
                bytes[idx + 1] = UInt8(max(0, min(255, Int((n.y * 0.5 + 0.5) * 255))))
                bytes[idx + 2] = UInt8(max(0, min(255, Int((n.z * 0.5 + 0.5) * 255))))
                bytes[idx + 3] = 255
            }
        }

        return ProceduralTexture(width: width,
                                 height: height,
                                 format: .rgba8Unorm,
                                 bytes: bytes)
    }
}
