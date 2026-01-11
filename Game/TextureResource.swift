//
//  TextureResource.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Metal

public enum TextureSourceRGBA8 {
    /// raw RGBA8 pixels (width*height*4)
    case rgba8(width: Int, height: Int, bytes: [UInt8])
    /// solid color
    case solid(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8)
}

public final class TextureResource {
    public let texture: MTLTexture

    public init(texture: MTLTexture, label: String = "Texture") {
        self.texture = texture
        self.texture.label = label
    }

    public init(device: MTLDevice, source: TextureSourceRGBA8, label: String = "Texture") {
        let (w, h, bytes): (Int, Int, [UInt8]) = {
            switch source {
            case .rgba8(let w, let h, let b):
                return (w, h, b)
            case .solid(let w, let h, let r, let g, let b, let a):
                var arr = [UInt8](repeating: 0, count: w * h * 4)
                for i in stride(from: 0, to: arr.count, by: 4) {
                    arr[i+0] = r; arr[i+1] = g; arr[i+2] = b; arr[i+3] = a
                }
                return (w, h, arr)
            }
        }()

        precondition(bytes.count == w * h * 4, "RGBA8 bytes must be width*height*4")

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
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
