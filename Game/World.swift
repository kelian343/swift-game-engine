//
//  World.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import Foundation

// MARK: - ComponentStore

public final class ComponentStore<T> {
    // Using Dictionary keeps it simple; can be replaced by sparse-set later.
    fileprivate var data: [Entity: T] = [:]

    public subscript(_ e: Entity) -> T? {
        get { data[e] }
        set { data[e] = newValue }
    }

    public func remove(_ e: Entity) {
        data.removeValue(forKey: e)
    }

    public func contains(_ e: Entity) -> Bool {
        data[e] != nil
    }

    public var entities: Dictionary<Entity, T>.Keys { data.keys }
}

// MARK: - World

public final class World {
    private var nextID: UInt32 = 1
    private var alive: Set<Entity> = []

    // Stores by component type
    private var stores: [ObjectIdentifier: Any] = [:]

    public init() {}

    public func createEntity() -> Entity {
        let e = Entity(nextID)
        nextID &+= 1
        alive.insert(e)
        return e
    }

    public func destroyEntity(_ e: Entity) {
        guard alive.remove(e) != nil else { return }
        // Remove from all component stores
        for (key, anyStore) in stores {
            // Try cast to known store shapes by erasing through closures is heavy.
            // For minimal ECS, we just best-effort via reflection-free path:
            // We'll store remover closures later if needed. For now, do nothing here.
            _ = key
            _ = anyStore
        }
        // Minimal: systems should tolerate "dead" entities via alive checks.
    }

    public func isAlive(_ e: Entity) -> Bool {
        alive.contains(e)
    }

    // Get typed store
    public func store<T>(_ type: T.Type) -> ComponentStore<T> {
        let key = ObjectIdentifier(type)
        if let existing = stores[key] as? ComponentStore<T> {
            return existing
        }
        let created = ComponentStore<T>()
        stores[key] = created
        return created
    }

    // Component ops
    public func add<T>(_ e: Entity, _ component: T) {
        precondition(isAlive(e), "Entity must be alive")
        store(T.self)[e] = component
    }

    public func remove<T>(_ e: Entity, _ type: T.Type) {
        store(T.self).remove(e)
    }

    public func get<T>(_ e: Entity, _ type: T.Type) -> T? {
        store(T.self)[e]
    }

    public func set<T>(_ e: Entity, _ component: T) {
        precondition(isAlive(e), "Entity must be alive")
        store(T.self)[e] = component
    }

    // MARK: - Queries

    /// Query entities that have component A
    public func query<A>(_ a: A.Type) -> [Entity] {
        let sa = store(A.self)
        return sa.data.keys.filter { isAlive($0) }
    }

    /// Query entities that have both components A and B
    public func query<A, B>(_ a: A.Type, _ b: B.Type) -> [Entity] {
        let sa = store(A.self)
        let sb = store(B.self)

        // Iterate smaller set
        let aCount = sa.data.count
        let bCount = sb.data.count

        if aCount <= bCount {
            return sa.data.keys.filter { sb.contains($0) && isAlive($0) }
        } else {
            return sb.data.keys.filter { sa.contains($0) && isAlive($0) }
        }
    }

    /// Query entities that have components A, B, C
    public func query<A, B, C>(_ a: A.Type, _ b: B.Type, _ c: C.Type) -> [Entity] {
        let ab = query(A.self, B.self)
        let sc = store(C.self)
        return ab.filter { sc.contains($0) && isAlive($0) }
    }
}
