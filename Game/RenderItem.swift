//
//  RenderItem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public struct RenderItem {
    public var mesh: GPUMesh
    public var material: Material
    public var modelMatrix: matrix_float4x4

    public init(mesh: GPUMesh, material: Material, modelMatrix: matrix_float4x4) {
        self.mesh = mesh
        self.material = material
        self.modelMatrix = modelMatrix
    }
}
