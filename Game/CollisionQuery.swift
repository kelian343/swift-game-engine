//
//  CollisionQuery.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

private func filteredEntities(world: World, activeEntityIDs: Set<UInt32>?) -> [Entity] {
    let entities = world.query(TransformComponent.self, StaticMeshComponent.self)
    let mStore = world.store(StaticMeshComponent.self)
    let activeIDs = activeEntityIDs
    return entities.filter { e in
        if let activeIDs, !activeIDs.contains(e.id) {
            return false
        }
        return mStore[e]?.collides ?? false
    }
}

private func filteredEntities(entities: [Entity],
                              activeEntityIDs: Set<UInt32>?) -> [Entity] {
    guard let activeEntityIDs else { return entities }
    return entities.filter { activeEntityIDs.contains($0.id) }
}

public struct RaycastHit {
    public var distance: Float
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var triangleIndex: Int
    public var material: SurfaceMaterial
}

public struct CapsuleCastHit {
    public var toi: Float
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var triangleNormal: SIMD3<Float>
    public var triangleIndex: Int
    public var material: SurfaceMaterial
}

public struct CapsuleOverlapHit {
    public var depth: Float
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var triangleNormal: SIMD3<Float>
    public var triangleIndex: Int
    public var material: SurfaceMaterial
}

public final class CollisionQuery {
    private var snapshot: CollisionWorldSnapshot

    public init(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        self.snapshot = CollisionWorldSnapshot(world: world, activeEntityIDs: activeEntityIDs)
    }

    public var stats: CollisionQueryStats {
        snapshot.stats
    }

    public func resetStats() {
        snapshot.resetStats()
    }

    public func updateStaticTransforms(world: World,
                                       entities: [Entity],
                                       activeEntityIDs: Set<UInt32>? = nil) {
        snapshot.updateStaticTransforms(world: world,
                                        entities: entities,
                                        activeEntityIDs: activeEntityIDs)
    }

    public func updateDynamicTransforms(world: World,
                                        entities: [Entity],
                                        activeEntityIDs: Set<UInt32>? = nil) {
        snapshot.updateDynamicTransforms(world: world,
                                         entities: entities,
                                         activeEntityIDs: activeEntityIDs)
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        maxDistance: Float) -> RaycastHit? {
        CollisionQueries.raycast(world: &snapshot,
                                 origin: origin,
                                 direction: direction,
                                 maxDistance: maxDistance)
    }

    public func capsuleCast(from: SIMD3<Float>,
                            delta: SIMD3<Float>,
                            radius: Float,
                            halfHeight: Float) -> CapsuleCastHit? {
        CollisionQueries.capsuleCast(world: &snapshot,
                                     from: from,
                                     delta: delta,
                                     radius: radius,
                                     halfHeight: halfHeight)
    }

    public func capsuleCastBlocking(from: SIMD3<Float>,
                                    delta: SIMD3<Float>,
                                    radius: Float,
                                    halfHeight: Float) -> CapsuleCastHit? {
        CollisionQueries.capsuleCastBlocking(world: &snapshot,
                                             from: from,
                                             delta: delta,
                                             radius: radius,
                                             halfHeight: halfHeight)
    }

    public func capsuleCastGround(from: SIMD3<Float>,
                                  delta: SIMD3<Float>,
                                  radius: Float,
                                  halfHeight: Float,
                                  minNormalY: Float) -> CapsuleCastHit? {
        CollisionQueries.capsuleCastGround(world: &snapshot,
                                           from: from,
                                           delta: delta,
                                           radius: radius,
                                           halfHeight: halfHeight,
                                           minNormalY: minNormalY)
    }

    public func capsuleOverlap(from: SIMD3<Float>,
                               radius: Float,
                               halfHeight: Float) -> CapsuleOverlapHit? {
        CollisionQueries.capsuleOverlap(world: &snapshot,
                                        from: from,
                                        radius: radius,
                                        halfHeight: halfHeight)
    }

    public func capsuleOverlapAll(from: SIMD3<Float>,
                                  radius: Float,
                                  halfHeight: Float,
                                  maxHits: Int = 8) -> [CapsuleOverlapHit] {
        CollisionQueries.capsuleOverlapAll(world: &snapshot,
                                           from: from,
                                           radius: radius,
                                           halfHeight: halfHeight,
                                           maxHits: max(1, maxHits))
    }
}

public struct CollisionWorldSnapshot {
    fileprivate var staticMesh: StaticTriMesh

    public init(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        self.staticMesh = StaticTriMesh(world: world, activeEntityIDs: activeEntityIDs)
    }

    public var stats: CollisionQueryStats {
        staticMesh.statsSnapshot
    }

    public mutating func resetStats() {
        staticMesh.resetStats()
    }

    public mutating func rebuildStatic(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        staticMesh.rebuildStatic(world: world, activeEntityIDs: activeEntityIDs)
    }

    public mutating func rebuildDynamic(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        staticMesh.rebuildDynamic(world: world, activeEntityIDs: activeEntityIDs)
    }

    public mutating func updateStaticTransforms(world: World,
                                                entities: [Entity],
                                                activeEntityIDs: Set<UInt32>? = nil) {
        staticMesh.updateStaticTransforms(world: world,
                                          entities: entities,
                                          activeEntityIDs: activeEntityIDs)
    }

    public mutating func updateDynamicTransforms(world: World,
                                                 entities: [Entity],
                                                 activeEntityIDs: Set<UInt32>? = nil) {
        staticMesh.updateDynamicTransforms(world: world,
                                           entities: entities,
                                           activeEntityIDs: activeEntityIDs)
    }
}

public struct CollisionQueries {
    public static func raycast(world: inout CollisionWorldSnapshot,
                               origin: SIMD3<Float>,
                               direction: SIMD3<Float>,
                               maxDistance: Float) -> RaycastHit? {
        world.staticMesh.raycast(origin: origin, direction: direction, maxDistance: maxDistance)
    }

    public static func capsuleCast(world: inout CollisionWorldSnapshot,
                                   from: SIMD3<Float>,
                                   delta: SIMD3<Float>,
                                   radius: Float,
                                   halfHeight: Float) -> CapsuleCastHit? {
        world.staticMesh.capsuleCast(from: from, delta: delta, radius: radius, halfHeight: halfHeight)
    }

    public static func capsuleCastBlocking(world: inout CollisionWorldSnapshot,
                                           from: SIMD3<Float>,
                                           delta: SIMD3<Float>,
                                           radius: Float,
                                           halfHeight: Float) -> CapsuleCastHit? {
        world.staticMesh.capsuleCastBlocking(from: from, delta: delta, radius: radius, halfHeight: halfHeight)
    }

    public static func capsuleCastGround(world: inout CollisionWorldSnapshot,
                                         from: SIMD3<Float>,
                                         delta: SIMD3<Float>,
                                         radius: Float,
                                         halfHeight: Float,
                                         minNormalY: Float) -> CapsuleCastHit? {
        world.staticMesh.capsuleCastGround(from: from,
                                           delta: delta,
                                           radius: radius,
                                           halfHeight: halfHeight,
                                           minNormalY: minNormalY)
    }

    public static func capsuleOverlap(world: inout CollisionWorldSnapshot,
                                      from: SIMD3<Float>,
                                      radius: Float,
                                      halfHeight: Float) -> CapsuleOverlapHit? {
        world.staticMesh.capsuleOverlap(from: from, radius: radius, halfHeight: halfHeight)
    }

    public static func capsuleOverlapAll(world: inout CollisionWorldSnapshot,
                                         from: SIMD3<Float>,
                                         radius: Float,
                                         halfHeight: Float,
                                         maxHits: Int) -> [CapsuleOverlapHit] {
        world.staticMesh.capsuleOverlapAll(from: from,
                                           radius: radius,
                                           halfHeight: halfHeight,
                                           maxHits: max(1, maxHits))
    }
}

public struct CollisionQueryStats {
    public var capsuleCandidateCount: Int = 0
    public var capsuleSweepCount: Int = 0
    public var capsuleSweepIterations: Int = 0
    public var capsuleSweepMaxIterations: Int = 0
    public var capsuleCellMin: SIMD3<Int> = SIMD3<Int>(0, 0, 0)
    public var capsuleCellMax: SIMD3<Int> = SIMD3<Int>(0, 0, 0)
    public var capsuleCellCount: Int64 = 0
    public var capsuleCandidatesClamped: Bool = false
    public var capsuleUsedCoarseGrid: Bool = false
}

private struct QueryStats {
    var capsuleCandidateCount: Int = 0
    var capsuleSweepCount: Int = 0
    var capsuleSweepIterations: Int = 0
    var capsuleSweepMaxIterations: Int = 0
    var capsuleCellMin: SIMD3<Int> = SIMD3<Int>(0, 0, 0)
    var capsuleCellMax: SIMD3<Int> = SIMD3<Int>(0, 0, 0)
    var capsuleCellCount: Int64 = 0
    var capsuleCandidatesClamped: Bool = false
    var capsuleUsedCoarseGrid: Bool = false

    mutating func reset() {
        self = QueryStats()
    }

    var publicStats: CollisionQueryStats {
        CollisionQueryStats(capsuleCandidateCount: capsuleCandidateCount,
                            capsuleSweepCount: capsuleSweepCount,
                            capsuleSweepIterations: capsuleSweepIterations,
                            capsuleSweepMaxIterations: capsuleSweepMaxIterations,
                            capsuleCellMin: capsuleCellMin,
                            capsuleCellMax: capsuleCellMax,
                            capsuleCellCount: capsuleCellCount,
                            capsuleCandidatesClamped: capsuleCandidatesClamped,
                            capsuleUsedCoarseGrid: capsuleUsedCoarseGrid)
    }
}

private struct TriangleMeshSet {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    var triangleAABBs: [StaticTriMesh.AABB] = []
    var triangleMaterials: [SurfaceMaterial] = []
    var slices: [Entity: StaticTriMesh.MeshSlice] = [:]
    var bvh: StaticTriMesh.BVH? = nil

    var hasTriangles: Bool { !triangleAABBs.isEmpty }

    mutating func rebuild(entities: [Entity],
                          tStore: ComponentStore<TransformComponent>,
                          mStore: ComponentStore<StaticMeshComponent>) {
        positions.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        triangleAABBs.removeAll(keepingCapacity: true)
        triangleMaterials.removeAll(keepingCapacity: true)
        slices.removeAll(keepingCapacity: true)

        let areaEps: Float = 1e-10
        for e in entities {
            guard let t = tStore[e], let m = mStore[e] else { continue }
            let collisionMesh = m.collisionMesh ?? m.mesh
            let baseVertex = positions.count
            let localPositions = collisionMesh.streams.positions
            positions.reserveCapacity(positions.count + localPositions.count)
            for pLocal in localPositions {
                let p = SIMD4<Float>(pLocal.x, pLocal.y, pLocal.z, 1)
                let wp = simd_mul(t.modelMatrix, p)
                positions.append(SIMD3<Float>(wp.x, wp.y, wp.z))
            }

            let localIndices: [UInt32]
            if let i16 = collisionMesh.indices16 {
                localIndices = i16.map { UInt32($0) }
            } else if let i32 = collisionMesh.indices32 {
                localIndices = i32
            } else {
                localIndices = []
            }

            let triCount = localIndices.count / 3
            let triSource: [SurfaceMaterial]
            if let perTri = m.triangleMaterials, perTri.count == triCount {
                triSource = perTri
            } else {
                triSource = Array(repeating: m.material, count: triCount)
            }

            let indexStart = indices.count
            let triStart = triangleAABBs.count
            var tri = 0
            var triLocal = 0
            while tri + 2 < localIndices.count {
                let i0 = Int(UInt32(baseVertex) + localIndices[tri])
                let i1 = Int(UInt32(baseVertex) + localIndices[tri + 1])
                let i2 = Int(UInt32(baseVertex) + localIndices[tri + 2])
                let p0 = positions[i0]
                let p1 = positions[i1]
                let p2 = positions[i2]
                let e1 = p1 - p0
                let e2 = p2 - p0
                if simd_length_squared(simd_cross(e1, e2)) <= areaEps {
                    tri += 3
                    triLocal += 1
                    continue
                }
                indices.append(UInt32(i0))
                indices.append(UInt32(i1))
                indices.append(UInt32(i2))
                let minP = simd_min(p0, simd_min(p1, p2))
                let maxP = simd_max(p0, simd_max(p1, p2))
                triangleAABBs.append(StaticTriMesh.AABB(min: minP, max: maxP))
                triangleMaterials.append(triSource[triLocal])
                tri += 3
                triLocal += 1
            }

            let indexEnd = indices.count
            let triEnd = triangleAABBs.count
            if indexEnd > indexStart && triEnd > triStart {
                slices[e] = StaticTriMesh.MeshSlice(entity: e,
                                                    vertexRange: baseVertex..<positions.count,
                                                    indexRange: indexStart..<indexEnd,
                                                    triangleRange: triStart..<triEnd)
            }
        }

        if triangleAABBs.isEmpty {
            bvh = nil
        } else {
            bvh = StaticTriMesh.BVH(triangleAABBs: triangleAABBs)
        }
    }

    mutating func updateTransforms(entities: [Entity],
                                   tStore: ComponentStore<TransformComponent>,
                                   mStore: ComponentStore<StaticMeshComponent>) -> [Int] {
        guard !entities.isEmpty, !triangleAABBs.isEmpty else { return [] }
        var updatedTriangles: [Int] = []
        updatedTriangles.reserveCapacity(entities.count * 16)

        for e in entities {
            guard let slice = slices[e], let t = tStore[e], let m = mStore[e] else { continue }
            let collisionMesh = m.collisionMesh ?? m.mesh
            let localPositions = collisionMesh.streams.positions
            if localPositions.count != slice.vertexRange.count {
                continue
            }
            for i in 0..<localPositions.count {
                let pLocal = localPositions[i]
                let p = SIMD4<Float>(pLocal.x, pLocal.y, pLocal.z, 1)
                let wp = simd_mul(t.modelMatrix, p)
                positions[slice.vertexRange.lowerBound + i] = SIMD3<Float>(wp.x, wp.y, wp.z)
            }

            var triIndex = slice.triangleRange.lowerBound
            var i = slice.indexRange.lowerBound
            while i + 2 < slice.indexRange.upperBound {
                let i0 = Int(indices[i])
                let i1 = Int(indices[i + 1])
                let i2 = Int(indices[i + 2])
                let p0 = positions[i0]
                let p1 = positions[i1]
                let p2 = positions[i2]
                let minP = simd_min(p0, simd_min(p1, p2))
                let maxP = simd_max(p0, simd_max(p1, p2))
                triangleAABBs[triIndex] = StaticTriMesh.AABB(min: minP, max: maxP)
                updatedTriangles.append(triIndex)
                i += 3
                triIndex += 1
            }
        }

        if !updatedTriangles.isEmpty {
            bvh?.refit(updatedTriangles: updatedTriangles, triangleAABBs: triangleAABBs)
        }
        return updatedTriangles
    }

    func materialForTriangle(_ triangleIndex: Int) -> SurfaceMaterial {
        if triangleIndex >= 0 && triangleIndex < triangleMaterials.count {
            return triangleMaterials[triangleIndex]
        }
        return .default
    }
}

public struct StaticTriMesh {
    private static let leafTriangleLimit: Int = 4

    public struct AABB {
        public var min: SIMD3<Float>
        public var max: SIMD3<Float>
    }

    fileprivate struct MeshSlice {
        let entity: Entity
        let vertexRange: Range<Int>
        let indexRange: Range<Int>
        let triangleRange: Range<Int>
    }

    fileprivate struct BVHNode {
        var bounds: AABB
        var left: Int
        var right: Int
        var start: Int
        var count: Int
        var parent: Int
    }

    fileprivate struct BVH {
        var nodes: [BVHNode]
        var triOrder: [Int]
        var triLeaf: [Int]
        var root: Int

        init(triangleAABBs: [AABB]) {
            self.nodes = []
            self.triOrder = Array(0..<triangleAABBs.count)
            self.triLeaf = Array(repeating: -1, count: triangleAABBs.count)
            self.root = -1
            if !triangleAABBs.isEmpty {
                self.root = build(triangleAABBs: triangleAABBs,
                                  start: 0,
                                  count: triangleAABBs.count,
                                  parent: -1)
            }
        }

        mutating func rebuild(triangleAABBs: [AABB]) {
            nodes.removeAll(keepingCapacity: true)
            triOrder = Array(0..<triangleAABBs.count)
            triLeaf = Array(repeating: -1, count: triangleAABBs.count)
            root = -1
            if !triangleAABBs.isEmpty {
                root = build(triangleAABBs: triangleAABBs,
                             start: 0,
                             count: triangleAABBs.count,
                             parent: -1)
            }
        }

        mutating func refit(updatedTriangles: [Int], triangleAABBs: [AABB]) {
            guard !nodes.isEmpty else { return }
            var updatedLeaves = Set<Int>()
            for tri in updatedTriangles {
                let leaf = triLeaf[tri]
                if leaf >= 0 {
                    updatedLeaves.insert(leaf)
                }
            }
            for leaf in updatedLeaves {
                let node = nodes[leaf]
                let bounds = boundsForRange(triangleAABBs: triangleAABBs,
                                            start: node.start,
                                            count: node.count)
                nodes[leaf].bounds = bounds
            }
            var dirtyParents: [Int] = []
            dirtyParents.reserveCapacity(updatedLeaves.count * 2)
            var dirtySet = Set<Int>()
            for leaf in updatedLeaves {
                var parent = nodes[leaf].parent
                while parent >= 0 {
                    if dirtySet.insert(parent).inserted {
                        dirtyParents.append(parent)
                    }
                    parent = nodes[parent].parent
                }
            }
            if !dirtyParents.isEmpty {
                var depths: [Int] = Array(repeating: 0, count: dirtyParents.count)
                for i in dirtyParents.indices {
                    var depth = 0
                    var node = dirtyParents[i]
                    while node >= 0 {
                        depth += 1
                        node = nodes[node].parent
                    }
                    depths[i] = depth
                }
                let order = dirtyParents.indices.sorted { depths[$0] > depths[$1] }
                for i in order {
                    let parent = dirtyParents[i]
                    let left = nodes[parent].left
                    let right = nodes[parent].right
                    nodes[parent].bounds = merge(nodes[left].bounds, nodes[right].bounds)
                }
            }
        }

        private mutating func build(triangleAABBs: [AABB],
                                    start: Int,
                                    count: Int,
                                    parent: Int) -> Int {
            let nodeIndex = nodes.count
            let bounds = boundsForRange(triangleAABBs: triangleAABBs, start: start, count: count)
            nodes.append(BVHNode(bounds: bounds,
                                 left: -1,
                                 right: -1,
                                 start: start,
                                 count: count,
                                 parent: parent))
            if count <= StaticTriMesh.leafTriangleLimit {
                for i in 0..<count {
                    let tri = triOrder[start + i]
                    triLeaf[tri] = nodeIndex
                }
                return nodeIndex
            }

            let centroidBounds = centroidBoundsForRange(triangleAABBs: triangleAABBs,
                                                        start: start,
                                                        count: count)
            let extent = centroidBounds.max - centroidBounds.min
            let axis: Int
            if extent.x >= extent.y && extent.x >= extent.z {
                axis = 0
            } else if extent.y >= extent.z {
                axis = 1
            } else {
                axis = 2
            }

            let pivot: Float
            switch axis {
            case 0: pivot = (centroidBounds.min.x + centroidBounds.max.x) * 0.5
            case 1: pivot = (centroidBounds.min.y + centroidBounds.max.y) * 0.5
            default: pivot = (centroidBounds.min.z + centroidBounds.max.z) * 0.5
            }

            var i = start
            var j = start + count - 1
            while i <= j {
                let tri = triOrder[i]
                let c = centroid(triangleAABBs[tri])
                let value: Float
                switch axis {
                case 0: value = c.x
                case 1: value = c.y
                default: value = c.z
                }
                if value < pivot {
                    i += 1
                } else {
                    triOrder.swapAt(i, j)
                    j -= 1
                }
            }

            let end = start + count
            if i == start || i == end {
                let sorted = triOrder[start..<end].sorted { a, b in
                    let ca = centroid(triangleAABBs[a])
                    let cb = centroid(triangleAABBs[b])
                    switch axis {
                    case 0: return ca.x < cb.x
                    case 1: return ca.y < cb.y
                    default: return ca.z < cb.z
                    }
                }
                var idx = sorted.startIndex
                for k in 0..<count {
                    triOrder[start + k] = sorted[idx]
                    idx = sorted.index(after: idx)
                }
                i = start + count / 2
            }

            let mid = i
            let left = build(triangleAABBs: triangleAABBs,
                             start: start,
                             count: mid - start,
                             parent: nodeIndex)
            let right = build(triangleAABBs: triangleAABBs,
                              start: mid,
                              count: start + count - mid,
                              parent: nodeIndex)
            nodes[nodeIndex].left = left
            nodes[nodeIndex].right = right
            nodes[nodeIndex].start = 0
            nodes[nodeIndex].count = 0
            nodes[nodeIndex].bounds = merge(nodes[left].bounds, nodes[right].bounds)
            return nodeIndex
        }

        private func boundsForRange(triangleAABBs: [AABB], start: Int, count: Int) -> AABB {
            let first = triangleAABBs[triOrder[start]]
            var bmin = first.min
            var bmax = first.max
            if count > 1 {
                for i in 1..<count {
                    let bounds = triangleAABBs[triOrder[start + i]]
                    bmin = simd_min(bmin, bounds.min)
                    bmax = simd_max(bmax, bounds.max)
                }
            }
            return AABB(min: bmin, max: bmax)
        }

        private func centroidBoundsForRange(triangleAABBs: [AABB], start: Int, count: Int) -> AABB {
            let first = centroid(triangleAABBs[triOrder[start]])
            var bmin = first
            var bmax = first
            if count > 1 {
                for i in 1..<count {
                    let c = centroid(triangleAABBs[triOrder[start + i]])
                    bmin = simd_min(bmin, c)
                    bmax = simd_max(bmax, c)
                }
            }
            return AABB(min: bmin, max: bmax)
        }

        private func centroid(_ bounds: AABB) -> SIMD3<Float> {
            (bounds.min + bounds.max) * 0.5
        }

        private func merge(_ a: AABB, _ b: AABB) -> AABB {
            AABB(min: simd_min(a.min, b.min), max: simd_max(a.max, b.max))
        }
    }

    private var stats: QueryStats = QueryStats()
    private var staticSet: TriangleMeshSet = TriangleMeshSet()
    private var dynamicSet: TriangleMeshSet = TriangleMeshSet()

    public var statsSnapshot: CollisionQueryStats {
        stats.publicStats
    }

    public init(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let entities = filteredEntities(world: world, activeEntityIDs: activeEntityIDs)
        let (staticEntities, dynamicEntities) = StaticTriMesh.partitionEntities(entities: entities,
                                                                               pStore: pStore)
        staticSet.rebuild(entities: staticEntities, tStore: tStore, mStore: mStore)
        dynamicSet.rebuild(entities: dynamicEntities, tStore: tStore, mStore: mStore)
    }

    public mutating func resetStats() {
        stats.reset()
    }

    public mutating func rebuildStatic(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let entities = filteredEntities(world: world, activeEntityIDs: activeEntityIDs)
        let (staticEntities, _) = StaticTriMesh.partitionEntities(entities: entities, pStore: pStore)
        staticSet.rebuild(entities: staticEntities, tStore: tStore, mStore: mStore)
    }

    public mutating func rebuildDynamic(world: World, activeEntityIDs: Set<UInt32>? = nil) {
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let pStore = world.store(PhysicsBodyComponent.self)
        let entities = filteredEntities(world: world, activeEntityIDs: activeEntityIDs)
        let (_, dynamicEntities) = StaticTriMesh.partitionEntities(entities: entities, pStore: pStore)
        dynamicSet.rebuild(entities: dynamicEntities, tStore: tStore, mStore: mStore)
    }

    public mutating func updateStaticTransforms(world: World,
                                                entities: [Entity],
                                                activeEntityIDs: Set<UInt32>? = nil) {
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let filtered = filteredEntities(entities: entities, activeEntityIDs: activeEntityIDs)
        _ = staticSet.updateTransforms(entities: filtered, tStore: tStore, mStore: mStore)
    }

    public mutating func updateDynamicTransforms(world: World,
                                                 entities: [Entity],
                                                 activeEntityIDs: Set<UInt32>? = nil) {
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)
        let filtered = filteredEntities(entities: entities, activeEntityIDs: activeEntityIDs)
        _ = dynamicSet.updateTransforms(entities: filtered, tStore: tStore, mStore: mStore)
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        maxDistance: Float) -> RaycastHit? {
        let staticHit = raycastBVH(origin: origin,
                                   direction: direction,
                                   maxDistance: maxDistance,
                                   set: staticSet,
                                   triangleIndexOffset: 0)
        let dynamicHit = raycastBVH(origin: origin,
                                    direction: direction,
                                    maxDistance: maxDistance,
                                    set: dynamicSet,
                                    triangleIndexOffset: staticSet.triangleAABBs.count)
        return chooseNearest(staticHit, dynamicHit)
    }

    public mutating func capsuleCast(from: SIMD3<Float>,
                                     delta: SIMD3<Float>,
                                     radius: Float,
                                     halfHeight: Float) -> CapsuleCastHit? {
        capsuleCastCombined(from: from,
                            delta: delta,
                            radius: radius,
                            halfHeight: halfHeight,
                            blockingOnly: false,
                            minNormalY: nil)
    }

    public mutating func capsuleCastBlocking(from: SIMD3<Float>,
                                             delta: SIMD3<Float>,
                                             radius: Float,
                                             halfHeight: Float) -> CapsuleCastHit? {
        capsuleCastCombined(from: from,
                            delta: delta,
                            radius: radius,
                            halfHeight: halfHeight,
                            blockingOnly: true,
                            minNormalY: nil)
    }

    public mutating func capsuleCastGround(from: SIMD3<Float>,
                                           delta: SIMD3<Float>,
                                           radius: Float,
                                           halfHeight: Float,
                                           minNormalY: Float) -> CapsuleCastHit? {
        capsuleCastCombined(from: from,
                            delta: delta,
                            radius: radius,
                            halfHeight: halfHeight,
                            blockingOnly: false,
                            minNormalY: minNormalY)
    }

    public func capsuleOverlap(from: SIMD3<Float>,
                               radius: Float,
                               halfHeight: Float) -> CapsuleOverlapHit? {
        let staticHit = capsuleOverlapBVH(from: from,
                                          radius: radius,
                                          halfHeight: halfHeight,
                                          set: staticSet,
                                          triangleIndexOffset: 0)
        let dynamicHit = capsuleOverlapBVH(from: from,
                                           radius: radius,
                                           halfHeight: halfHeight,
                                           set: dynamicSet,
                                           triangleIndexOffset: staticSet.triangleAABBs.count)
        if let a = staticHit, let b = dynamicHit {
            return a.depth >= b.depth ? a : b
        }
        return staticHit ?? dynamicHit
    }

    public func capsuleOverlapAll(from: SIMD3<Float>,
                                  radius: Float,
                                  halfHeight: Float,
                                  maxHits: Int) -> [CapsuleOverlapHit] {
        var hits: [CapsuleOverlapHit] = []
        let staticHits = capsuleOverlapBVHAll(from: from,
                                              radius: radius,
                                              halfHeight: halfHeight,
                                              set: staticSet,
                                              triangleIndexOffset: 0,
                                              maxHits: maxHits)
        hits.append(contentsOf: staticHits)
        let remaining = max(0, maxHits - hits.count)
        if remaining > 0 {
            let dynamicHits = capsuleOverlapBVHAll(from: from,
                                                   radius: radius,
                                                   halfHeight: halfHeight,
                                                   set: dynamicSet,
                                                   triangleIndexOffset: staticSet.triangleAABBs.count,
                                                   maxHits: remaining)
            hits.append(contentsOf: dynamicHits)
        }
        if hits.count > maxHits {
            hits.sort { $0.depth > $1.depth }
            hits = Array(hits.prefix(maxHits))
        }
        return hits
    }
}

private extension StaticTriMesh {
    static func partitionEntities(entities: [Entity],
                                  pStore: ComponentStore<PhysicsBodyComponent>) -> ([Entity], [Entity]) {
        var statics: [Entity] = []
        var dynamics: [Entity] = []
        statics.reserveCapacity(entities.count)
        dynamics.reserveCapacity(entities.count)
        for e in entities {
            if let body = pStore[e], body.bodyType != .static {
                dynamics.append(e)
            } else {
                statics.append(e)
            }
        }
        return (statics, dynamics)
    }

    func chooseNearest(_ a: RaycastHit?, _ b: RaycastHit?) -> RaycastHit? {
        if let a = a, let b = b {
            return a.distance <= b.distance ? a : b
        }
        return a ?? b
    }

    func chooseNearest(_ a: CapsuleCastHit?, _ b: CapsuleCastHit?) -> CapsuleCastHit? {
        if let a = a, let b = b {
            return a.toi <= b.toi ? a : b
        }
        return a ?? b
    }

    private func raycastBVH(origin: SIMD3<Float>,
                            direction: SIMD3<Float>,
                            maxDistance: Float,
                            set: TriangleMeshSet,
                            triangleIndexOffset: Int) -> RaycastHit? {
        guard let bvh = set.bvh, bvh.root >= 0 else { return nil }
        let eps: Float = 1e-6
        var closestT = maxDistance
        var hit: RaycastHit?
        var stack: [Int] = [bvh.root]

        while let nodeIndex = stack.popLast() {
            let node = bvh.nodes[nodeIndex]
            guard let range = rayAABB(origin: origin, direction: direction, bounds: node.bounds) else {
                continue
            }
            if range.0 > closestT {
                continue
            }

            if node.left < 0 {
                let start = node.start
                let end = start + node.count
                for i in start..<end {
                    let triIndex = bvh.triOrder[i]
                    let base = triIndex * 3
                    if base + 2 >= set.indices.count { continue }
                    let i0 = Int(set.indices[base])
                    let i1 = Int(set.indices[base + 1])
                    let i2 = Int(set.indices[base + 2])
                    let v0 = set.positions[i0]
                    let v1 = set.positions[i1]
                    let v2 = set.positions[i2]
                    if let t = rayTriangle(origin: origin,
                                           direction: direction,
                                           v0: v0,
                                           v1: v1,
                                           v2: v2,
                                           eps: eps),
                       t < closestT {
                        let n = simd_normalize(simd_cross(v1 - v0, v2 - v0))
                        let normal = simd_dot(n, direction) > 0 ? -n : n
                        let position = origin + direction * t
                        closestT = t
                        hit = RaycastHit(distance: t,
                                         position: position,
                                         normal: normal,
                                         triangleIndex: triIndex + triangleIndexOffset,
                                         material: set.materialForTriangle(triIndex))
                    }
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }

        return hit
    }

    private mutating func capsuleCastCombined(from: SIMD3<Float>,
                                              delta: SIMD3<Float>,
                                              radius: Float,
                                              halfHeight: Float,
                                              blockingOnly: Bool,
                                              minNormalY: Float?) -> CapsuleCastHit? {
        let len = simd_length(delta)
        if len < 1e-6 { return nil }
        resetStats()
        let staticHit = capsuleCastBVH(from: from,
                                       delta: delta,
                                       radius: radius,
                                       halfHeight: halfHeight,
                                       set: staticSet,
                                       triangleIndexOffset: 0,
                                       blockingOnly: blockingOnly,
                                       minNormalY: minNormalY)
        let dynamicHit = capsuleCastBVH(from: from,
                                        delta: delta,
                                        radius: radius,
                                        halfHeight: halfHeight,
                                        set: dynamicSet,
                                        triangleIndexOffset: staticSet.triangleAABBs.count,
                                        blockingOnly: blockingOnly,
                                        minNormalY: minNormalY)
        return chooseNearest(staticHit, dynamicHit)
    }

    private mutating func capsuleCastBVH(from: SIMD3<Float>,
                                         delta: SIMD3<Float>,
                                         radius: Float,
                                         halfHeight: Float,
                                         set: TriangleMeshSet,
                                         triangleIndexOffset: Int,
                                         blockingOnly: Bool,
                                         minNormalY: Float?) -> CapsuleCastHit? {
        guard let bvh = set.bvh, bvh.root >= 0 else { return nil }
        let len = simd_length(delta)
        if len < 1e-6 { return nil }
        let dir = delta / len

        let up = SIMD3<Float>(0, 1, 0)
        let a0 = from + up * halfHeight
        let b0 = from - up * halfHeight
        let a1 = a0 + delta
        let b1 = b0 + delta

        var minP = simd_min(simd_min(a0, b0), simd_min(a1, b1))
        var maxP = simd_max(simd_max(a0, b0), simd_max(a1, b1))
        let ext = SIMD3<Float>(repeating: radius)
        minP -= ext
        maxP += ext

        var bestHit: CapsuleCastHit?
        var bestT = len
        var sweepTests = 0
        var sweepIterations = 0
        var sweepMaxIterations = 0
        var candidateCount = 0
        var stack: [Int] = [bvh.root]

        while let nodeIndex = stack.popLast() {
            let node = bvh.nodes[nodeIndex]
            if node.bounds.max.x < minP.x || node.bounds.min.x > maxP.x ||
                node.bounds.max.y < minP.y || node.bounds.min.y > maxP.y ||
                node.bounds.max.z < minP.z || node.bounds.min.z > maxP.z {
                continue
            }
            if node.left < 0 {
                let start = node.start
                let end = start + node.count
                for i in start..<end {
                    let triIndex = bvh.triOrder[i]
                    let triBounds = set.triangleAABBs[triIndex]
                    if triBounds.max.x < minP.x || triBounds.min.x > maxP.x ||
                        triBounds.max.y < minP.y || triBounds.min.y > maxP.y ||
                        triBounds.max.z < minP.z || triBounds.min.z > maxP.z {
                        continue
                    }
                    candidateCount += 1
                    let base = triIndex * 3
                    if base + 2 >= set.indices.count { continue }
                    let v0 = set.positions[Int(set.indices[base])]
                    let v1 = set.positions[Int(set.indices[base + 1])]
                    let v2 = set.positions[Int(set.indices[base + 2])]
                    sweepTests += 1
                    var iterCount = 0
                    if var hit = sweepCapsuleTriangle(from: from,
                                                      dir: dir,
                                                      maxDistance: len,
                                                      radius: radius,
                                                      halfHeight: halfHeight,
                                                      v0: v0,
                                                      v1: v1,
                                                      v2: v2,
                                                      triangleIndex: triIndex,
                                                      iterations: &iterCount),
                       hit.toi < bestT {
                        hit.material = set.materialForTriangle(triIndex)
                        hit.triangleIndex = triIndex + triangleIndexOffset
                        if blockingOnly {
                            if simd_dot(delta, hit.normal) >= 0 {
                                continue
                            }
                            if simd_dot(delta, hit.triangleNormal) >= 0 {
                                continue
                            }
                        }
                        if let minY = minNormalY, hit.triangleNormal.y < minY {
                            continue
                        }
                        bestT = hit.toi
                        bestHit = hit
                    }
                    sweepIterations += iterCount
                    if iterCount > sweepMaxIterations {
                        sweepMaxIterations = iterCount
                    }
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }

        stats.capsuleCandidateCount += candidateCount
        stats.capsuleSweepCount += sweepTests
        stats.capsuleSweepIterations += sweepIterations
        stats.capsuleSweepMaxIterations = max(stats.capsuleSweepMaxIterations, sweepMaxIterations)
        return bestHit
    }

    private func capsuleOverlapBVH(from: SIMD3<Float>,
                                   radius: Float,
                                   halfHeight: Float,
                                   set: TriangleMeshSet,
                                   triangleIndexOffset: Int) -> CapsuleOverlapHit? {
        guard let bvh = set.bvh, bvh.root >= 0 else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        let a0 = from + up * halfHeight
        let b0 = from - up * halfHeight
        var minP = simd_min(a0, b0)
        var maxP = simd_max(a0, b0)
        let ext = SIMD3<Float>(repeating: radius)
        minP -= ext
        maxP += ext

        var bestHit: CapsuleOverlapHit?
        var bestDepth: Float = 0
        var stack: [Int] = [bvh.root]

        while let nodeIndex = stack.popLast() {
            let node = bvh.nodes[nodeIndex]
            if node.bounds.max.x < minP.x || node.bounds.min.x > maxP.x ||
                node.bounds.max.y < minP.y || node.bounds.min.y > maxP.y ||
                node.bounds.max.z < minP.z || node.bounds.min.z > maxP.z {
                continue
            }
            if node.left < 0 {
                let start = node.start
                let end = start + node.count
                for i in start..<end {
                    let triIndex = bvh.triOrder[i]
                    let triBounds = set.triangleAABBs[triIndex]
                    if triBounds.max.x < minP.x || triBounds.min.x > maxP.x ||
                        triBounds.max.y < minP.y || triBounds.min.y > maxP.y ||
                        triBounds.max.z < minP.z || triBounds.min.z > maxP.z {
                        continue
                    }
                    let base = triIndex * 3
                    if base + 2 >= set.indices.count { continue }
                    let v0 = set.positions[Int(set.indices[base])]
                    let v1 = set.positions[Int(set.indices[base + 1])]
                    let v2 = set.positions[Int(set.indices[base + 2])]
                    let (dist, segPoint, triPoint) = segmentTriangleDistance(center: from,
                                                                             halfHeight: halfHeight,
                                                                             v0: v0,
                                                                             v1: v1,
                                                                             v2: v2)
                    if dist >= radius { continue }
                    let depth = radius - dist
                    if depth <= bestDepth { continue }
                    let triNormal = simd_normalize(simd_cross(v1 - v0, v2 - v0))
                    let n: SIMD3<Float>
                    if dist < 1e-6 {
                        n = triNormal
                    } else {
                        n = simd_normalize(segPoint - triPoint)
                    }
                    var triN = triNormal
                    if simd_dot(triN, n) < 0 {
                        triN = -triN
                    }
                    bestDepth = depth
                    bestHit = CapsuleOverlapHit(depth: depth,
                                                position: triPoint,
                                                normal: n,
                                                triangleNormal: triN,
                                                triangleIndex: triIndex + triangleIndexOffset,
                                                material: set.materialForTriangle(triIndex))
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }

        return bestHit
    }

    private func capsuleOverlapBVHAll(from: SIMD3<Float>,
                                      radius: Float,
                                      halfHeight: Float,
                                      set: TriangleMeshSet,
                                      triangleIndexOffset: Int,
                                      maxHits: Int) -> [CapsuleOverlapHit] {
        guard let bvh = set.bvh, bvh.root >= 0 else { return [] }
        let up = SIMD3<Float>(0, 1, 0)
        let a0 = from + up * halfHeight
        let b0 = from - up * halfHeight
        var minP = simd_min(a0, b0)
        var maxP = simd_max(a0, b0)
        let ext = SIMD3<Float>(repeating: radius)
        minP -= ext
        maxP += ext

        var hits: [CapsuleOverlapHit] = []
        hits.reserveCapacity(maxHits)
        var stack: [Int] = [bvh.root]

        while let nodeIndex = stack.popLast() {
            let node = bvh.nodes[nodeIndex]
            if node.bounds.max.x < minP.x || node.bounds.min.x > maxP.x ||
                node.bounds.max.y < minP.y || node.bounds.min.y > maxP.y ||
                node.bounds.max.z < minP.z || node.bounds.min.z > maxP.z {
                continue
            }
            if node.left < 0 {
                let start = node.start
                let end = start + node.count
                for i in start..<end {
                    let triIndex = bvh.triOrder[i]
                    let triBounds = set.triangleAABBs[triIndex]
                    if triBounds.max.x < minP.x || triBounds.min.x > maxP.x ||
                        triBounds.max.y < minP.y || triBounds.min.y > maxP.y ||
                        triBounds.max.z < minP.z || triBounds.min.z > maxP.z {
                        continue
                    }
                    let base = triIndex * 3
                    if base + 2 >= set.indices.count { continue }
                    let v0 = set.positions[Int(set.indices[base])]
                    let v1 = set.positions[Int(set.indices[base + 1])]
                    let v2 = set.positions[Int(set.indices[base + 2])]
                    let (dist, segPoint, triPoint) = segmentTriangleDistance(center: from,
                                                                             halfHeight: halfHeight,
                                                                             v0: v0,
                                                                             v1: v1,
                                                                             v2: v2)
                    if dist >= radius { continue }
                    let depth = radius - dist
                    let triNormal = simd_normalize(simd_cross(v1 - v0, v2 - v0))
                    let n: SIMD3<Float>
                    if dist < 1e-6 {
                        n = triNormal
                    } else {
                        n = simd_normalize(segPoint - triPoint)
                    }
                    var triN = triNormal
                    if simd_dot(triN, n) < 0 {
                        triN = -triN
                    }
                    hits.append(CapsuleOverlapHit(depth: depth,
                                                  position: triPoint,
                                                  normal: n,
                                                  triangleNormal: triN,
                                                  triangleIndex: triIndex + triangleIndexOffset,
                                                  material: set.materialForTriangle(triIndex)))
                    if hits.count >= maxHits {
                        return hits
                    }
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }

        return hits
    }

    private func sweepCapsuleTriangle(from: SIMD3<Float>,
                                      dir: SIMD3<Float>,
                                      maxDistance: Float,
                                      radius: Float,
                                      halfHeight: Float,
                                      v0: SIMD3<Float>,
                                      v1: SIMD3<Float>,
                                      v2: SIMD3<Float>,
                                      triangleIndex: Int,
                                      iterations: inout Int) -> CapsuleCastHit? {
        let minAdvance = max(radius * 0.02, 1e-4)
        let maxIter = min(256, Int(ceil(maxDistance / minAdvance)) + 1)
        let contactEps: Float = 1e-5
        let triNormal = simd_normalize(simd_cross(v1 - v0, v2 - v0))

        var t: Float = 0
        var lastSafeT: Float = 0

        for _ in 0..<maxIter {
            iterations += 1
            if t > maxDistance {
                return nil
            }
            let center = from + dir * t
            let (dist, _, _) = segmentTriangleDistance(center: center,
                                                       halfHeight: halfHeight,
                                                       v0: v0,
                                                       v1: v1,
                                                       v2: v2)
            if dist <= radius + contactEps {
                let tHit = refineTOI(from: from,
                                     dir: dir,
                                     radius: radius,
                                     halfHeight: halfHeight,
                                     v0: v0,
                                     v1: v1,
                                     v2: v2,
                                     t0: lastSafeT,
                                     t1: t,
                                     maxDistance: maxDistance)
                let hitCenter = from + dir * tHit
                let (hitDist, hitSeg, hitTri) = segmentTriangleDistance(center: hitCenter,
                                                                        halfHeight: halfHeight,
                                                                        v0: v0,
                                                                        v1: v1,
                                                                        v2: v2)
                let n: SIMD3<Float>
                if hitDist < 1e-6 {
                    n = simd_dot(triNormal, dir) > 0 ? -triNormal : triNormal
                } else {
                    n = simd_normalize(hitSeg - hitTri)
                }
                var triN = triNormal
                if simd_dot(triN, n) < 0 {
                    triN = -triN
                }
                return CapsuleCastHit(toi: tHit,
                                      position: hitTri,
                                      normal: n,
                                      triangleNormal: triN,
                                      triangleIndex: triangleIndex,
                                      material: .default)
            }

            lastSafeT = t
            let advance = max(dist - radius, minAdvance)
            if advance <= 0 {
                t += minAdvance
            } else {
                t += advance
            }
        }

        return nil
    }

    private func refineTOI(from: SIMD3<Float>,
                           dir: SIMD3<Float>,
                           radius: Float,
                           halfHeight: Float,
                           v0: SIMD3<Float>,
                           v1: SIMD3<Float>,
                           v2: SIMD3<Float>,
                           t0: Float,
                           t1: Float,
                           maxDistance: Float) -> Float {
        let clampT0 = max(0, min(t0, maxDistance))
        let clampT1 = max(0, min(t1, maxDistance))
        var lo = min(clampT0, clampT1)
        var hi = max(clampT0, clampT1)
        if hi - lo < 1e-5 {
            return hi
        }
        let refineIterations = 10
        for _ in 0..<refineIterations {
            let mid = 0.5 * (lo + hi)
            let center = from + dir * mid
            let (dist, _, _) = segmentTriangleDistance(center: center,
                                                       halfHeight: halfHeight,
                                                       v0: v0,
                                                       v1: v1,
                                                       v2: v2)
            if dist <= radius {
                hi = mid
            } else {
                lo = mid
            }
        }
        return hi
    }

    private func segmentTriangleDistance(center: SIMD3<Float>,
                                         halfHeight: Float,
                                         v0: SIMD3<Float>,
                                         v1: SIMD3<Float>,
                                         v2: SIMD3<Float>) -> (Float, SIMD3<Float>, SIMD3<Float>) {
        let up = SIMD3<Float>(0, 1, 0)
        let a = center + up * halfHeight
        let b = center - up * halfHeight

        if let hit = segmentTriangleIntersect(a: a, b: b, v0: v0, v1: v1, v2: v2) {
            return (0, hit, hit)
        }

        var bestDistSq = Float.greatestFiniteMagnitude
        var bestSeg = a
        var bestTri = v0

        let (d0, p0) = closestPointOnTriangle(p: a, a: v0, b: v1, c: v2)
        if d0 < bestDistSq {
            bestDistSq = d0
            bestSeg = a
            bestTri = p0
        }

        let (d1, p1) = closestPointOnTriangle(p: b, a: v0, b: v1, c: v2)
        if d1 < bestDistSq {
            bestDistSq = d1
            bestSeg = b
            bestTri = p1
        }

        let edges = [(v0, v1), (v1, v2), (v2, v0)]
        for (e0, e1) in edges {
            let (d, s, t) = segmentSegmentDistanceSq(p1: a, q1: b, p2: e0, q2: e1)
            if d < bestDistSq {
                bestDistSq = d
                bestSeg = s
                bestTri = t
            }
        }

        return (sqrt(max(bestDistSq, 0)), bestSeg, bestTri)
    }

    private func segmentTriangleIntersect(a: SIMD3<Float>,
                                          b: SIMD3<Float>,
                                          v0: SIMD3<Float>,
                                          v1: SIMD3<Float>,
                                          v2: SIMD3<Float>) -> SIMD3<Float>? {
        let dir = b - a
        let eps: Float = 1e-6
        let e1 = v1 - v0
        let e2 = v2 - v0
        let pvec = simd_cross(dir, e2)
        let det = simd_dot(e1, pvec)
        if abs(det) < eps { return nil }
        let invDet = 1.0 / det
        let tvec = a - v0
        let u = simd_dot(tvec, pvec) * invDet
        if u < 0 || u > 1 { return nil }
        let qvec = simd_cross(tvec, e1)
        let v = simd_dot(dir, qvec) * invDet
        if v < 0 || (u + v) > 1 { return nil }
        let t = simd_dot(e2, qvec) * invDet
        if t < 0 || t > 1 { return nil }
        return a + dir * t
    }

    private func closestPointOnTriangle(p: SIMD3<Float>,
                                        a: SIMD3<Float>,
                                        b: SIMD3<Float>,
                                        c: SIMD3<Float>) -> (Float, SIMD3<Float>) {
        let ab = b - a
        let ac = c - a
        let ap = p - a
        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 {
            return (simd_length_squared(p - a), a)
        }

        let bp = p - b
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 {
            return (simd_length_squared(p - b), b)
        }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v = d1 / (d1 - d3)
            let point = a + ab * v
            return (simd_length_squared(p - point), point)
        }

        let cp = p - c
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 {
            return (simd_length_squared(p - c), c)
        }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w = d2 / (d2 - d6)
            let point = a + ac * w
            return (simd_length_squared(p - point), point)
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            let point = b + (c - b) * w
            return (simd_length_squared(p - point), point)
        }

        let denom = 1.0 / (va + vb + vc)
        let v = vb * denom
        let w = vc * denom
        let point = a + ab * v + ac * w
        return (simd_length_squared(p - point), point)
    }

    private func segmentSegmentDistanceSq(p1: SIMD3<Float>,
                                          q1: SIMD3<Float>,
                                          p2: SIMD3<Float>,
                                          q2: SIMD3<Float>) -> (Float, SIMD3<Float>, SIMD3<Float>) {
        let d1 = q1 - p1
        let d2 = q2 - p2
        let r = p1 - p2
        let a = simd_dot(d1, d1)
        let e = simd_dot(d2, d2)
        let f = simd_dot(d2, r)

        var s: Float = 0
        var t: Float = 0

        let eps: Float = 1e-6
        if a <= eps && e <= eps {
            return (simd_length_squared(p1 - p2), p1, p2)
        }
        if a <= eps {
            t = clamp(f / e, 0, 1)
            let c2 = p2 + d2 * t
            return (simd_length_squared(p1 - c2), p1, c2)
        }
        let c = simd_dot(d1, r)
        if e <= eps {
            s = clamp(-c / a, 0, 1)
            let c1 = p1 + d1 * s
            return (simd_length_squared(c1 - p2), c1, p2)
        }
        let b = simd_dot(d1, d2)
        let denom = a * e - b * b
        if denom != 0 {
            s = clamp((b * f - c * e) / denom, 0, 1)
        } else {
            s = 0
        }
        let tNom = b * s + f
        if tNom < 0 {
            t = 0
            s = clamp(-c / a, 0, 1)
        } else if tNom > e {
            t = 1
            s = clamp((b - c) / a, 0, 1)
        } else {
            t = tNom / e
        }

        let c1 = p1 + d1 * s
        let c2 = p2 + d2 * t
        return (simd_length_squared(c1 - c2), c1, c2)
    }

    private func clamp(_ v: Float, _ minV: Float, _ maxV: Float) -> Float {
        return min(max(v, minV), maxV)
    }

    private func rayTriangle(origin: SIMD3<Float>,
                             direction: SIMD3<Float>,
                             v0: SIMD3<Float>,
                             v1: SIMD3<Float>,
                             v2: SIMD3<Float>,
                             eps: Float) -> Float? {
        let e1 = v1 - v0
        let e2 = v2 - v0
        let pvec = simd_cross(direction, e2)
        let det = simd_dot(e1, pvec)
        if abs(det) < eps {
            return nil
        }
        let invDet = 1.0 / det
        let tvec = origin - v0
        let u = simd_dot(tvec, pvec) * invDet
        if u < 0 || u > 1 {
            return nil
        }
        let qvec = simd_cross(tvec, e1)
        let v = simd_dot(direction, qvec) * invDet
        if v < 0 || (u + v) > 1 {
            return nil
        }
        let t = simd_dot(e2, qvec) * invDet
        return t >= 0 ? t : nil
    }

    private func rayAABB(origin: SIMD3<Float>,
                         direction: SIMD3<Float>,
                         bounds: AABB) -> (Float, Float)? {
        let invX = direction.x != 0 ? 1.0 / direction.x : Float.greatestFiniteMagnitude
        let invY = direction.y != 0 ? 1.0 / direction.y : Float.greatestFiniteMagnitude
        let invZ = direction.z != 0 ? 1.0 / direction.z : Float.greatestFiniteMagnitude

        var tmin = (bounds.min.x - origin.x) * invX
        var tmax = (bounds.max.x - origin.x) * invX
        if tmin > tmax { swap(&tmin, &tmax) }

        var tymin = (bounds.min.y - origin.y) * invY
        var tymax = (bounds.max.y - origin.y) * invY
        if tymin > tymax { swap(&tymin, &tymax) }

        if tmin > tymax || tymin > tmax { return nil }
        tmin = max(tmin, tymin)
        tmax = min(tmax, tymax)

        var tzmin = (bounds.min.z - origin.z) * invZ
        var tzmax = (bounds.max.z - origin.z) * invZ
        if tzmin > tzmax { swap(&tzmin, &tzmax) }

        if tmin > tzmax || tzmin > tmax { return nil }
        tmin = max(tmin, tzmin)
        tmax = min(tmax, tzmax)

        return (tmin, tmax)
    }
}
