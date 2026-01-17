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
    private var lastActiveEntityIDs: Set<UInt32>?

    public init() {}

    public func markDirty() {
        dirty = true
    }

    public func rebuild(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        query = CollisionQuery(world: world, activeEntityIDs: activeEntityIDs)
        dirty = false
        lastActiveEntityIDs = activeEntityIDs
        refreshStaticMeshCache(world: world, activeEntityIDs: activeEntityIDs)
    }

    public func update(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        if activeEntityIDs != lastActiveEntityIDs {
            rebuild(world: world, activeEntityIDs: activeEntityIDs)
            return
        }
        if dirty || query == nil {
            rebuild(world: world, activeEntityIDs: activeEntityIDs)
            return
        }
        let changeSet = staticMeshChanges(world: world, activeEntityIDs: activeEntityIDs)
        if changeSet.structuralChange {
            rebuild(world: world, activeEntityIDs: activeEntityIDs)
            return
        }
        if !changeSet.staticTransforms.isEmpty {
            query?.updateStaticTransforms(world: world,
                                          entities: changeSet.staticTransforms,
                                          activeEntityIDs: activeEntityIDs)
        }
        if !changeSet.dynamicTransforms.isEmpty {
            query?.updateDynamicTransforms(world: world,
                                           entities: changeSet.dynamicTransforms,
                                           activeEntityIDs: activeEntityIDs)
        }
        refreshStaticMeshCache(world: world, activeEntityIDs: activeEntityIDs)
    }

    private struct StaticMeshSnapshot {
        let translation: SIMD3<Float>
        let rotation: simd_quatf
        let scale: SIMD3<Float>
        let vertexCount: Int
        let indexCount: Int
        let bodyType: BodyType?
    }

    private struct StaticMeshChangeSet {
        var structuralChange: Bool
        var staticTransforms: [Entity]
        var dynamicTransforms: [Entity]
    }

    private func staticMeshChanges(world: World, activeEntityIDs: Set<UInt32>?) -> StaticMeshChangeSet {
        let entities = filterEntities(world: world, activeEntityIDs: activeEntityIDs)
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        if entities.count != staticMeshCache.count {
            return StaticMeshChangeSet(structuralChange: true,
                                       staticTransforms: [],
                                       dynamicTransforms: [])
        }

        let eps: Float = 1e-6
        var staticTransformSet = Set<Entity>()
        var dynamicTransformSet = Set<Entity>()
        for e in entities {
            guard let t = tStore[e], let m = mStore[e] else { continue }
            if m.dirty {
                return StaticMeshChangeSet(structuralChange: true,
                                           staticTransforms: [],
                                           dynamicTransforms: [])
            }
            guard let snapshot = staticMeshCache[e] else {
                return StaticMeshChangeSet(structuralChange: true,
                                           staticTransforms: [],
                                           dynamicTransforms: [])
            }
            let bodyType = pStore[e]?.bodyType
            if snapshot.bodyType != bodyType {
                return StaticMeshChangeSet(structuralChange: true,
                                           staticTransforms: [],
                                           dynamicTransforms: [])
            }
            let deltaPos = t.translation - snapshot.translation
            if simd_length_squared(deltaPos) > eps {
                if bodyType == .static || bodyType == nil {
                    staticTransformSet.insert(e)
                } else {
                    dynamicTransformSet.insert(e)
                }
            }
            let deltaRot = t.rotation.vector - snapshot.rotation.vector
            if simd_length_squared(deltaRot) > eps {
                if bodyType == .static || bodyType == nil {
                    staticTransformSet.insert(e)
                } else {
                    dynamicTransformSet.insert(e)
                }
            }
            let deltaScale = t.scale - snapshot.scale
            if simd_length_squared(deltaScale) > eps {
                if bodyType == .static || bodyType == nil {
                    staticTransformSet.insert(e)
                } else {
                    dynamicTransformSet.insert(e)
                }
            }
            let collisionMesh = m.collisionMesh ?? m.mesh
            let vertexCount = collisionMesh.streams.positions.count
            let indexCount = collisionMesh.indexCount
            if vertexCount != snapshot.vertexCount || indexCount != snapshot.indexCount {
                return StaticMeshChangeSet(structuralChange: true,
                                           staticTransforms: [],
                                           dynamicTransforms: [])
            }
        }

        return StaticMeshChangeSet(structuralChange: false,
                                   staticTransforms: Array(staticTransformSet),
                                   dynamicTransforms: Array(dynamicTransformSet))
    }

    private func refreshStaticMeshCache(world: World, activeEntityIDs: Set<UInt32>?) {
        let entities = filterEntities(world: world, activeEntityIDs: activeEntityIDs)
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        staticMeshCache.removeAll(keepingCapacity: true)

        for e in entities {
            guard let t = tStore[e], var m = mStore[e] else { continue }
            let bodyType = pStore[e]?.bodyType
            let collisionMesh = m.collisionMesh ?? m.mesh
            staticMeshCache[e] = StaticMeshSnapshot(translation: t.translation,
                                                    rotation: t.rotation,
                                                    scale: t.scale,
                                                    vertexCount: collisionMesh.streams.positions.count,
                                                    indexCount: collisionMesh.indexCount,
                                                    bodyType: bodyType)
            if m.dirty {
                m.dirty = false
                mStore[e] = m
            }
        }
    }

    private func filterEntities(world: World, activeEntityIDs: Set<UInt32>?) -> [Entity] {
        let entities = world.query(TransformComponent.self, StaticMeshComponent.self)
        guard let activeEntityIDs else { return entities }
        return entities.filter { activeEntityIDs.contains($0.id) }
    }
}
