//
//  ShadowMap.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

final class ShadowMap {
    let size: Int
    let texture: MTLTexture

    init(device: MTLDevice, size: Int) {
        self.size = size

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                          width: size,
                                                          height: size,
                                                          mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .private

        self.texture = device.makeTexture(descriptor: td)!
        self.texture.label = "ShadowMapDepth"

    }
}
