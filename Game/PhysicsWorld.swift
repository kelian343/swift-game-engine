//
//  PhysicsWorld.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public final class PhysicsWorld {
    public struct Pair: Hashable {
        public let a: Entity
        public let b: Entity
    }

    public struct Proxy {
        public var entity: Entity
        public var aabbMin: SIMD3<Float>
        public var aabbMax: SIMD3<Float>
        public var bodyType: BodyType
        public var collider: ColliderComponent
    }

    private(set) var proxies: [Proxy] = []
    private var proxyIndexForEntity: [Entity: Int] = [:]
    private(set) var broadphasePairs: [Pair] = []

    public init() {}

    public func sync(world: World) {
        proxies.removeAll(keepingCapacity: true)
        proxyIndexForEntity.removeAll(keepingCapacity: true)
        broadphasePairs.removeAll(keepingCapacity: true)

        let entities = world.query(TransformComponent.self, ColliderComponent.self)
        let tStore = world.store(TransformComponent.self)
        let cStore = world.store(ColliderComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)

        proxies.reserveCapacity(entities.count)

        for e in entities {
            guard let t = tStore[e], let c = cStore[e] else { continue }

            let body = pStore[e]
            let pos = body?.position ?? t.translation
            let rot = body?.rotation ?? t.rotation
            let bodyType = body?.bodyType ?? .static

            let aabb = ColliderComponent.computeAABB(position: pos, rotation: rot, collider: c)
            let proxy = Proxy(entity: e,
                              aabbMin: aabb.min,
                              aabbMax: aabb.max,
                              bodyType: bodyType,
                              collider: c)
            proxyIndexForEntity[e] = proxies.count
            proxies.append(proxy)
        }
    }

    public func buildBroadphasePairs() {
        broadphasePairs.removeAll(keepingCapacity: true)
        guard proxies.count > 1 else { return }

        let order = proxies.indices.sorted { proxies[$0].aabbMin.x < proxies[$1].aabbMin.x }

        for i in 0..<order.count {
            let a = proxies[order[i]]
            for j in (i + 1)..<order.count {
                let b = proxies[order[j]]
                if b.aabbMin.x > a.aabbMax.x { break }
                if overlaps(a, b) {
                    broadphasePairs.append(Pair(a: a.entity, b: b.entity))
                }
            }
        }
    }

    private func overlaps(_ a: Proxy, _ b: Proxy) -> Bool {
        if a.aabbMax.x < b.aabbMin.x || a.aabbMin.x > b.aabbMax.x { return false }
        if a.aabbMax.y < b.aabbMin.y || a.aabbMin.y > b.aabbMax.y { return false }
        if a.aabbMax.z < b.aabbMin.z || a.aabbMin.z > b.aabbMax.z { return false }
        return true
    }
}
