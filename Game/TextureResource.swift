//
//  TextureResource.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

public final class TextureResource {
    public let texture: MTLTexture

    public init(texture: MTLTexture, label: String = "Texture") {
        self.texture = texture
        self.texture.label = label
    }

    public init(device: MTLDevice, source: ProceduralTexture, label: String = "Texture") {
        let w = source.width
        let h = source.height
        let bytes = source.bytes

        let pixelFormat: MTLPixelFormat = {
            switch source.format {
            case .rgba8Unorm:
                return .rgba8Unorm
            }
        }()

        precondition(bytes.count == w * h * 4, "ProceduralTexture bytes must be width*height*4")

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                            width: w,
                                                            height: h,
                                                            mipmapped: false)
        desc.usage = [.shaderRead]
        // Keep it simple & always CPU-updatable for now:
        desc.storageMode = .shared

        self.texture = device.makeTexture(descriptor: desc)!
        self.texture.label = label

        bytes.withUnsafeBytes { raw in
            let region = MTLRegionMake2D(0, 0, w, h)
            self.texture.replace(region: region, mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: w * 4)
        }
    }
}
