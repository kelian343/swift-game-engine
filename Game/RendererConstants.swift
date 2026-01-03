//
//  RendererConstants.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

let maxRTTextures = 32

nonisolated enum RendererError: Error {
    case badVertexDescriptor
}
