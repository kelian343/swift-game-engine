//
//  Entity.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation

/// Entity is just an opaque ID.
public struct Entity: Hashable, Sendable {
    public let id: UInt32
    public init(_ id: UInt32) { self.id = id }
}
