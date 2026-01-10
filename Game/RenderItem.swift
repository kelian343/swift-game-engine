//
//  RenderItem.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public struct RenderItem {
    public var mesh: GPUMesh?
    public var skinnedMesh: SkinnedMeshData?
    public var skinningPalette: [matrix_float4x4]?
    public var material: Material
    public var modelMatrix: matrix_float4x4

    public init(mesh: GPUMesh?,
                skinnedMesh: SkinnedMeshData? = nil,
                skinningPalette: [matrix_float4x4]? = nil,
                material: Material,
                modelMatrix: matrix_float4x4) {
        self.mesh = mesh
        self.skinnedMesh = skinnedMesh
        self.skinningPalette = skinningPalette
        self.material = material
        self.modelMatrix = modelMatrix
    }
}
