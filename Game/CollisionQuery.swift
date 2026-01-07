//
//  CollisionQuery.swift
//  Game
//
//  Created by 伈佊 on 1/2/26.
//

import simd

public struct RaycastHit {
    public var distance: Float
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var triangleIndex: Int
}

public struct CapsuleCastHit {
    public var toi: Float
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var triangleIndex: Int
}

public final class CollisionQuery {
    private let staticMesh: StaticTriMesh

    public init(world: World) {
        self.staticMesh = StaticTriMesh(world: world)
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        maxDistance: Float) -> RaycastHit? {
        staticMesh.raycast(origin: origin, direction: direction, maxDistance: maxDistance)
    }

    public func capsuleCast(from: SIMD3<Float>,
                            delta: SIMD3<Float>,
                            radius: Float,
                            halfHeight: Float) -> CapsuleCastHit? {
        staticMesh.capsuleCastApprox(from: from, delta: delta, radius: radius, halfHeight: halfHeight)
    }
}

public struct StaticTriMesh {
    public struct AABB {
        public var min: SIMD3<Float>
        public var max: SIMD3<Float>
    }

    private struct CellCoord: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    private struct UniformGrid {
        let origin: SIMD3<Float>
        let cellSize: Float
        let bounds: AABB
        let cells: [CellCoord: [Int]]
    }

    public private(set) var positions: [SIMD3<Float>]
    public private(set) var indices: [UInt32]
    public private(set) var triangleAABBs: [AABB]
    private let grid: UniformGrid?

    public init(world: World) {
        let entities = world.query(TransformComponent.self, StaticMeshComponent.self)
        let tStore = world.store(TransformComponent.self)
        let mStore = world.store(StaticMeshComponent.self)

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var triangleAABBs: [AABB] = []

        for e in entities {
            guard let t = tStore[e], let m = mStore[e] else { continue }
            let baseIndex = UInt32(positions.count)
            positions.reserveCapacity(positions.count + m.mesh.vertices.count)
            for v in m.mesh.vertices {
                let p = SIMD4<Float>(v.position.x, v.position.y, v.position.z, 1)
                let wp = simd_mul(t.modelMatrix, p)
                positions.append(SIMD3<Float>(wp.x, wp.y, wp.z))
            }

            let indexStart = indices.count
            if let i16 = m.mesh.indices16 {
                indices.reserveCapacity(indices.count + i16.count)
                for idx in i16 {
                    indices.append(baseIndex + UInt32(idx))
                }
            } else if let i32 = m.mesh.indices32 {
                indices.reserveCapacity(indices.count + i32.count)
                for idx in i32 {
                    indices.append(baseIndex + idx)
                }
            }

            let indexEnd = indices.count
            var tri = indexStart
            while tri + 2 < indexEnd {
                let i0 = Int(indices[tri])
                let i1 = Int(indices[tri + 1])
                let i2 = Int(indices[tri + 2])
                let p0 = positions[i0]
                let p1 = positions[i1]
                let p2 = positions[i2]
                let minP = simd_min(p0, simd_min(p1, p2))
                let maxP = simd_max(p0, simd_max(p1, p2))
                triangleAABBs.append(AABB(min: minP, max: maxP))
                tri += 3
            }
        }

        self.positions = positions
        self.indices = indices
        self.triangleAABBs = triangleAABBs
        self.grid = StaticTriMesh.buildGrid(positions: positions,
                                            triangleAABBs: triangleAABBs,
                                            cellSize: 4.0)
    }

    public func raycast(origin: SIMD3<Float>,
                        direction: SIMD3<Float>,
                        maxDistance: Float) -> RaycastHit? {
        if let grid {
            return raycastGrid(origin: origin, direction: direction, maxDistance: maxDistance, grid: grid)
        }
        return raycastBrute(origin: origin, direction: direction, maxDistance: maxDistance)
    }

    public func capsuleCastApprox(from: SIMD3<Float>,
                                  delta: SIMD3<Float>,
                                  radius: Float,
                                  halfHeight: Float) -> CapsuleCastHit? {
        _ = halfHeight
        let len = simd_length(delta)
        if len < 1e-6 { return nil }
        let dir = delta / len
        guard let hit = raycast(origin: from, direction: dir, maxDistance: len) else { return nil }
        let toi = max(0, hit.distance - radius)
        let position = from + dir * toi
        return CapsuleCastHit(toi: toi,
                              position: position,
                              normal: hit.normal,
                              triangleIndex: hit.triangleIndex)
    }
}

private extension StaticTriMesh {
    private static func buildGrid(positions: [SIMD3<Float>],
                                  triangleAABBs: [AABB],
                                  cellSize: Float) -> UniformGrid? {
        guard !positions.isEmpty, !triangleAABBs.isEmpty else { return nil }
        var minP = positions[0]
        var maxP = positions[0]
        for p in positions.dropFirst() {
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }
        let bounds = AABB(min: minP, max: maxP)
        let origin = bounds.min

        var cells: [CellCoord: [Int]] = [:]
        cells.reserveCapacity(triangleAABBs.count)

        for (triIndex, triBounds) in triangleAABBs.enumerated() {
            let minCell = cellCoord(position: triBounds.min, origin: origin, cellSize: cellSize)
            let maxCell = cellCoord(position: triBounds.max, origin: origin, cellSize: cellSize)
            for z in minCell.z...maxCell.z {
                for y in minCell.y...maxCell.y {
                    for x in minCell.x...maxCell.x {
                        let key = CellCoord(x: x, y: y, z: z)
                        cells[key, default: []].append(triIndex)
                    }
                }
            }
        }

        return UniformGrid(origin: origin, cellSize: cellSize, bounds: bounds, cells: cells)
    }

    private static func cellCoord(position: SIMD3<Float>, origin: SIMD3<Float>, cellSize: Float) -> CellCoord {
        let rel = (position - origin) / cellSize
        return CellCoord(x: Int(floor(rel.x)),
                         y: Int(floor(rel.y)),
                         z: Int(floor(rel.z)))
    }

    func raycastBrute(origin: SIMD3<Float>,
                      direction: SIMD3<Float>,
                      maxDistance: Float) -> RaycastHit? {
        let eps: Float = 1e-6
        var closestT = maxDistance
        var hit: RaycastHit?

        var triIndex = 0
        var i = 0
        while i + 2 < indices.count {
            let i0 = Int(indices[i])
            let i1 = Int(indices[i + 1])
            let i2 = Int(indices[i + 2])

            let v0 = positions[i0]
            let v1 = positions[i1]
            let v2 = positions[i2]

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
                hit = RaycastHit(distance: t, position: position, normal: normal, triangleIndex: triIndex)
            }

            i += 3
            triIndex += 1
        }

        return hit
    }

    private func raycastGrid(origin: SIMD3<Float>,
                             direction: SIMD3<Float>,
                             maxDistance: Float,
                             grid: UniformGrid) -> RaycastHit? {
        guard let range = rayAABB(origin: origin, direction: direction, bounds: grid.bounds) else {
            return nil
        }
        let tEnter = max(range.0, 0)
        let tExit = min(range.1, maxDistance)
        if tExit < tEnter { return nil }

        let startPos = origin + direction * tEnter
        var cell = StaticTriMesh.cellCoord(position: startPos, origin: grid.origin, cellSize: grid.cellSize)

        let dir = direction
        let stepX = dir.x >= 0 ? 1 : -1
        let stepY = dir.y >= 0 ? 1 : -1
        let stepZ = dir.z >= 0 ? 1 : -1

        let cellSize = grid.cellSize
        let originGrid = grid.origin

        func boundary(_ c: Int, _ step: Int, _ axisOrigin: Float) -> Float {
            let edge = step > 0 ? Float(c + 1) : Float(c)
            return axisOrigin + edge * cellSize
        }

        var tMaxX = dir.x == 0 ? Float.greatestFiniteMagnitude :
            (boundary(cell.x, stepX, originGrid.x) - origin.x) / dir.x
        var tMaxY = dir.y == 0 ? Float.greatestFiniteMagnitude :
            (boundary(cell.y, stepY, originGrid.y) - origin.y) / dir.y
        var tMaxZ = dir.z == 0 ? Float.greatestFiniteMagnitude :
            (boundary(cell.z, stepZ, originGrid.z) - origin.z) / dir.z

        let tDeltaX = dir.x == 0 ? Float.greatestFiniteMagnitude : cellSize / abs(dir.x)
        let tDeltaY = dir.y == 0 ? Float.greatestFiniteMagnitude : cellSize / abs(dir.y)
        let tDeltaZ = dir.z == 0 ? Float.greatestFiniteMagnitude : cellSize / abs(dir.z)

        let eps: Float = 1e-6
        var closestT = maxDistance
        var hit: RaycastHit?
        var visited = Set<Int>()

        var t = tEnter
        while t <= tExit && t <= closestT {
            if let tris = grid.cells[cell] {
                for triIndex in tris {
                    if visited.contains(triIndex) { continue }
                    visited.insert(triIndex)

                    let base = triIndex * 3
                    let i0 = Int(indices[base])
                    let i1 = Int(indices[base + 1])
                    let i2 = Int(indices[base + 2])
                    let v0 = positions[i0]
                    let v1 = positions[i1]
                    let v2 = positions[i2]

                    if let tHit = rayTriangle(origin: origin,
                                              direction: direction,
                                              v0: v0,
                                              v1: v1,
                                              v2: v2,
                                              eps: eps),
                       tHit < closestT {
                        let n = simd_normalize(simd_cross(v1 - v0, v2 - v0))
                        let normal = simd_dot(n, direction) > 0 ? -n : n
                        let position = origin + direction * tHit
                        closestT = tHit
                        hit = RaycastHit(distance: tHit, position: position, normal: normal, triangleIndex: triIndex)
                    }
                }
            }

            let nextT = min(tMaxX, min(tMaxY, tMaxZ))
            if closestT <= nextT {
                break
            }

            if tMaxX < tMaxY {
                if tMaxX < tMaxZ {
                    cell = CellCoord(x: cell.x + stepX, y: cell.y, z: cell.z)
                    t = tMaxX
                    tMaxX += tDeltaX
                } else {
                    cell = CellCoord(x: cell.x, y: cell.y, z: cell.z + stepZ)
                    t = tMaxZ
                    tMaxZ += tDeltaZ
                }
            } else {
                if tMaxY < tMaxZ {
                    cell = CellCoord(x: cell.x, y: cell.y + stepY, z: cell.z)
                    t = tMaxY
                    tMaxY += tDeltaY
                } else {
                    cell = CellCoord(x: cell.x, y: cell.y, z: cell.z + stepZ)
                    t = tMaxZ
                    tMaxZ += tDeltaZ
                }
            }
        }

        return hit
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
