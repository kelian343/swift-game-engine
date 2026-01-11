//
//  FPSOverlaySystem.swift
//  Game
//
//  Created by Codex on 3/9/26.
//

import Metal
import simd

final class FPSOverlaySystem {
    private let device: MTLDevice
    private var viewportSize = SIMD2<Float>(1, 1)
    private var fpsSmoothed: Float = 0
    private let digitMeshes: [GPUMesh]
    private let material: Material
    private let digitPixelSize: SIMD2<Float>
    private let margin: Float = 12
    private let spacing: Float = 2

    init(device: MTLDevice) {
        self.device = device

        let atlas = ProceduralTextureGenerator.digitsAtlas()
        let mr = ProceduralTextureGenerator.metallicRoughness(width: 4,
                                                              height: 4,
                                                              metallic: 0.0,
                                                              roughness: 1.0)
        let desc = MaterialDescriptor(baseColor: atlas,
                                      metallicRoughness: mr,
                                      metallicFactor: 1.0,
                                      roughnessFactor: 1.0,
                                      alpha: 1.0)
        var mat = MaterialFactory.make(device: device, descriptor: desc, label: "FPSDigits")
        mat.cullMode = .none
        self.material = mat

        let cellW = ProceduralTextureGenerator.digitsAtlasCellWidth
        let cellH = ProceduralTextureGenerator.digitsAtlasCellHeight
        let atlasW = cellW * 10
        let atlasH = cellH
        let scale: Float = 2.0
        self.digitPixelSize = SIMD2<Float>(Float(cellW) * scale, Float(cellH) * scale)

        self.digitMeshes = (0..<10).map { digit in
            let u0 = Float(digit * cellW) / Float(atlasW)
            let u1 = Float((digit + 1) * cellW) / Float(atlasW)
            let v0: Float = 0
            let v1 = Float(cellH) / Float(atlasH)
            let desc = ProceduralMeshes.quad(QuadParams(uvMin: SIMD2<Float>(u0, v0),
                                                       uvMax: SIMD2<Float>(u1, v1)))
            return GPUMesh(device: device, descriptor: desc, label: "FPSDigit\(digit)")
        }
    }

    func viewportDidChange(size: SIMD2<Float>) {
        viewportSize = size
    }

    func update(dt: Float) -> [RenderItem] {
        guard dt > 0 else { return [] }

        let fpsInstant = 1.0 / dt
        if fpsSmoothed == 0 {
            fpsSmoothed = fpsInstant
        } else {
            fpsSmoothed = fpsSmoothed * 0.9 + fpsInstant * 0.1
        }

        let fpsValue = max(Int(fpsSmoothed.rounded()), 0)
        let digits = Array(String(fpsValue))
        let digitCount = digits.count
        let digitW = digitPixelSize.x
        let digitH = digitPixelSize.y
        let totalWidth = Float(digitCount) * digitW + Float(max(0, digitCount - 1)) * spacing

        let startX = max(margin, viewportSize.x - margin - totalWidth)
        let y = margin

        var items: [RenderItem] = []
        items.reserveCapacity(digitCount)

        var x = startX
        for ch in digits {
            guard let value = ch.wholeNumberValue else { continue }
            let mesh = digitMeshes[value]
            let t = TransformComponent(translation: SIMD3<Float>(x, y, 0),
                                       rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                                       scale: SIMD3<Float>(digitW, digitH, 1))
            items.append(RenderItem(mesh: mesh, material: material, modelMatrix: t.modelMatrix))
            x += digitW + spacing
        }
        return items
    }
}
