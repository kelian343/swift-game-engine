//
//  SceneServices.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class SceneServices {
    public let collisionQuery: CollisionQueryService
    private var services: [ObjectIdentifier: Any] = [:]

    public init() {
        let collisionQuery = CollisionQueryService()
        self.collisionQuery = collisionQuery
        register(collisionQuery)
    }

    public func rebuildAll(world: World) {
        collisionQuery.rebuild(world: world)
    }

    public func register<T>(_ service: T) {
        services[ObjectIdentifier(T.self)] = service
    }

    public func resolve<T>(_ type: T.Type = T.self) -> T? {
        services[ObjectIdentifier(type)] as? T
    }
}

public final class CollisionQueryService {
    public private(set) var query: CollisionQuery?
    private var dirty: Bool = true
    private var staticMeshCache: [Entity: StaticMeshSnapshot] = [:]

    public init() {}

    public func markDirty() {
        dirty = true
    }

    public func rebuild(world: World) {
        query = CollisionQuery(world: world)
        dirty = false
        refreshStaticMeshCache(world: world)
    }

    public func update(world: World) {
        if dirty || query == nil || staticMeshesChanged(world: world) {
            rebuild(world: world)
        }
    }

    private struct StaticMeshSnapshot {
        let translation: SIMD3<Float>
        let rotation: simd_quatf
        let scale: SIMD3<Float>
        let vertexCount: Int
        let indexCount: Int
    }

    private func staticMeshesChanged(world: World) -> Bool {
        let entities = world.query(TransformComponent.self, StaticMeshComponent.self)
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        if entities.count != staticMeshCache.count {
            return true
        }

        let eps: Float = 1e-6
        for e in entities {
            guard let t = tStore[e], let m = mStore[e] else { continue }
            if m.dirty {
                return true
            }
            guard let snapshot = staticMeshCache[e] else { return true }
            let deltaPos = t.translation - snapshot.translation
            if simd_length_squared(deltaPos) > eps {
                return true
            }
            let deltaRot = t.rotation.vector - snapshot.rotation.vector
            if simd_length_squared(deltaRot) > eps {
                return true
            }
            let deltaScale = t.scale - snapshot.scale
            if simd_length_squared(deltaScale) > eps {
                return true
            }
            let vertexCount = m.mesh.streams.positions.count
            let indexCount = m.mesh.indexCount
            if vertexCount != snapshot.vertexCount || indexCount != snapshot.indexCount {
                return true
            }
        }

        return false
    }

    private func refreshStaticMeshCache(world: World) {
        let entities = world.query(TransformComponent.self, StaticMeshComponent.self)
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        staticMeshCache.removeAll(keepingCapacity: true)

        for e in entities {
            guard let t = tStore[e], var m = mStore[e] else { continue }
            staticMeshCache[e] = StaticMeshSnapshot(translation: t.translation,
                                                    rotation: t.rotation,
                                                    scale: t.scale,
                                                    vertexCount: m.mesh.streams.positions.count,
                                                    indexCount: m.mesh.indexCount)
            if m.dirty {
                m.dirty = false
                mStore[e] = m
            }
        }
    }
}
