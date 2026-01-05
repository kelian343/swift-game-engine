//
//  PhysicsWorld.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class PhysicsWorld {
    public typealias ProxyHandle = Int

    public struct Pair: Hashable {
        public let a: Entity
        public let b: Entity

        public init(a: Entity, b: Entity) {
            if a.id <= b.id {
                self.a = a
                self.b = b
            } else {
                self.a = b
                self.b = a
            }
        }
    }

    public struct Proxy {
        public var entity: Entity
        public var aabbMin: SIMD3<Float>
        public var aabbMax: SIMD3<Float>
        public var bodyType: BodyType
        public var collider: ColliderComponent
        public var position: SIMD3<Float>
        public var rotation: simd_quatf
    }

    public enum ContactEventType {
        case enter
        case stay
        case exit
    }

    public struct ContactEvent {
        public var pair: Pair
        public var type: ContactEventType
    }

    public struct ContactManifold {
        public var pair: Pair
        // TODO: add contact points, normal, penetration depth, friction, restitution.
    }

    private var proxies: [Proxy?] = []
    private var freeProxies: [ProxyHandle] = []
    private(set) var proxyByEntity: [Entity: ProxyHandle] = [:]
    private(set) var dirtyProxies: Set<ProxyHandle> = []

    private(set) var broadphasePairs: [Pair] = []
    private(set) var broadphaseProxyPairs: [(ProxyHandle, ProxyHandle)] = []
    private(set) var manifolds: [ContactManifold] = []
    private(set) var contactEvents: [ContactEvent] = []
    private var contactPairs: Set<Pair> = []

    public init() {}

    public func sync(world: World) {
        let entities = world.query(TransformComponent.self, ColliderComponent.self)
        let tStore = world.store(TransformComponent.self)
        let cStore = world.store(ColliderComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)

        let entitySet = Set(entities)
        for e in entities {
            guard let t = tStore[e], let c = cStore[e] else { continue }

            let body = pStore[e]
            let pos = body?.position ?? t.translation
            let rot = body?.rotation ?? t.rotation
            let bodyType = body?.bodyType ?? .static

            if let handle = proxyByEntity[e] {
                updateProxy(handle: handle,
                            entity: e,
                            position: pos,
                            rotation: rot,
                            bodyType: bodyType,
                            collider: c)
            } else {
                _ = createProxy(entity: e,
                                position: pos,
                                rotation: rot,
                                bodyType: bodyType,
                                collider: c)
            }
        }

        // Remove proxies whose entities no longer have colliders.
        for (entity, handle) in proxyByEntity where !entitySet.contains(entity) {
            removeProxy(handle: handle, entity: entity)
        }
    }

    public func buildBroadphasePairs() {
        broadphasePairs.removeAll(keepingCapacity: true)
        broadphaseProxyPairs.removeAll(keepingCapacity: true)

        let activeHandles: [ProxyHandle] = proxies.indices.compactMap { idx in
            proxies[idx] == nil ? nil : idx
        }
        guard activeHandles.count > 1 else { return }

        let order = activeHandles.sorted {
            let a = proxies[$0]!
            let b = proxies[$1]!
            return a.aabbMin.x < b.aabbMin.x
        }

        for i in 0..<order.count {
            let a = proxies[order[i]]!
            for j in (i + 1)..<order.count {
                let b = proxies[order[j]]!
                if b.aabbMin.x > a.aabbMax.x { break }
                if !a.collider.filter.canCollide(with: b.collider.filter) { continue }
                if overlaps(a, b) {
                    broadphasePairs.append(Pair(a: a.entity, b: b.entity))
                    broadphaseProxyPairs.append((order[i], order[j]))
                }
            }
        }
    }

    public func updateContactCache(from pairs: [Pair]) {
        let newPairs = Set(pairs)
        contactEvents.removeAll(keepingCapacity: true)

        for p in newPairs {
            if contactPairs.contains(p) {
                contactEvents.append(ContactEvent(pair: p, type: .stay))
            } else {
                contactEvents.append(ContactEvent(pair: p, type: .enter))
            }
        }

        for p in contactPairs where !newPairs.contains(p) {
            contactEvents.append(ContactEvent(pair: p, type: .exit))
        }

        contactPairs = newPairs
    }

    public func setManifolds(_ newManifolds: [ContactManifold]) {
        manifolds = newManifolds
    }

    public func clearManifolds(keepingCapacity: Bool = true) {
        manifolds.removeAll(keepingCapacity: keepingCapacity)
    }

    private func overlaps(_ a: Proxy, _ b: Proxy) -> Bool {
        if a.aabbMax.x < b.aabbMin.x || a.aabbMin.x > b.aabbMax.x { return false }
        if a.aabbMax.y < b.aabbMin.y || a.aabbMin.y > b.aabbMax.y { return false }
        if a.aabbMax.z < b.aabbMin.z || a.aabbMin.z > b.aabbMax.z { return false }
        return true
    }

    // MARK: - Proxy Management

    private func createProxy(entity: Entity,
                             position: SIMD3<Float>,
                             rotation: simd_quatf,
                             bodyType: BodyType,
                             collider: ColliderComponent) -> ProxyHandle {
        let aabb = ColliderComponent.computeAABB(position: position, rotation: rotation, collider: collider)
        let proxy = Proxy(entity: entity,
                          aabbMin: aabb.min,
                          aabbMax: aabb.max,
                          bodyType: bodyType,
                          collider: collider,
                          position: position,
                          rotation: rotation)

        let handle: ProxyHandle
        if let reused = freeProxies.popLast() {
            handle = reused
            proxies[handle] = proxy
        } else {
            handle = proxies.count
            proxies.append(proxy)
        }

        proxyByEntity[entity] = handle
        dirtyProxies.insert(handle)
        return handle
    }

    private func updateProxy(handle: ProxyHandle,
                             entity: Entity,
                             position: SIMD3<Float>,
                             rotation: simd_quatf,
                             bodyType: BodyType,
                             collider: ColliderComponent) {
        guard var proxy = proxies[handle] else {
            _ = createProxy(entity: entity,
                            position: position,
                            rotation: rotation,
                            bodyType: bodyType,
                            collider: collider)
            return
        }

        let posChanged = simd_length(proxy.position - position) > 0.00001
        let rotChanged = simd_length(proxy.rotation.vector - rotation.vector) > 0.00001
        let colChanged = proxy.collider != collider
        let bodyChanged = proxy.bodyType != bodyType

        if posChanged || rotChanged || colChanged || bodyChanged {
            let aabb = ColliderComponent.computeAABB(position: position, rotation: rotation, collider: collider)
            proxy.aabbMin = aabb.min
            proxy.aabbMax = aabb.max
            proxy.position = position
            proxy.rotation = rotation
            proxy.collider = collider
            proxy.bodyType = bodyType
            proxies[handle] = proxy
            dirtyProxies.insert(handle)
        }
    }

    private func removeProxy(handle: ProxyHandle, entity: Entity) {
        proxies[handle] = nil
        freeProxies.append(handle)
        dirtyProxies.remove(handle)
        proxyByEntity.removeValue(forKey: entity)
    }
}
