//
//  SceneServices.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class SceneServices {
    public let collisionQuery = CollisionQueryService()

    public init() {}

    public func rebuildAll(world: World) {
        collisionQuery.rebuild(world: world)
    }
}

public final class CollisionQueryService {
    public private(set) var query: CollisionQuery?
    private var dirty: Bool = true

    public init() {}

    public func markDirty() {
        dirty = true
    }

    public func rebuild(world: World) {
        query = CollisionQuery(world: world)
        dirty = false
    }

    public func update(world: World) {
        if dirty || query == nil || hasMovedStaticMeshes(world: world) {
            rebuild(world: world)
        }
    }

    private func hasMovedStaticMeshes(world: World) -> Bool {
        let entities = world.query(PhysicsBodyComponent.self, StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)

        for e in entities {
            guard let body = pStore[e] else { continue }
            if body.bodyType == .static { continue }

            let delta = body.position - body.prevPosition
            if simd_length_squared(delta) > 1e-8 {
                return true
            }
            let rotDelta = body.rotation.vector - body.prevRotation.vector
            if simd_length_squared(rotDelta) > 1e-8 {
                return true
            }
        }

        return false
    }
}
