import json
import os
import sys

import bpy

MAX_HULLS_PER_PART = 4
TARGET_FACES_PER_HULL = 64


def _clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block, do_unlink=True)
    for block in bpy.data.armatures:
        bpy.data.armatures.remove(block, do_unlink=True)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block, do_unlink=True)


def _parse_args():
    if "--" not in sys.argv:
        raise SystemExit("Usage: blender -b -P export_static_mesh_json.py -- <input.fbx> <output.json> [--flip-v|--no-flip-v]")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) < 2:
        raise SystemExit("Usage: blender -b -P export_static_mesh_json.py -- <input.fbx> <output.json> [--flip-v|--no-flip-v]")
    input_path = argv[0]
    output_path = argv[1]
    flip_v = True
    for arg in argv[2:]:
        if arg == "--flip-v":
            flip_v = True
        elif arg == "--no-flip-v":
            flip_v = False
        else:
            raise SystemExit(f"Unknown argument: {arg}")
    return input_path, output_path, flip_v


def _find_meshes():
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        return []
    candidates = [(obj.name, len(obj.data.vertices), obj) for obj in meshes]
    candidates.sort(key=lambda x: x[0].lower())
    print("Mesh candidates:")
    for name, vcount, _ in candidates:
        print(f"  {name}: verts={vcount}")
    return [obj for _, _, obj in candidates]


def _matrix_to_row_major(mat):
    return [
        mat[0][0], mat[0][1], mat[0][2], mat[0][3],
        mat[1][0], mat[1][1], mat[1][2], mat[1][3],
        mat[2][0], mat[2][1], mat[2][2], mat[2][3],
        mat[3][0], mat[3][1], mat[3][2], mat[3][3],
    ]

def _set_active(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def _mesh_positions_indices(mesh):
    if hasattr(mesh, "calc_loop_triangles"):
        mesh.calc_loop_triangles()
    positions = []
    indices = []
    for v in mesh.vertices:
        positions.extend([v.co.x, v.co.y, v.co.z])
    for tri in mesh.loop_triangles:
        indices.extend([int(tri.vertices[0]), int(tri.vertices[1]), int(tri.vertices[2])])
    return positions, indices


def _build_collision_hulls(mesh_obj):
    collision = []
    scene = bpy.context.scene

    tmp = mesh_obj.copy()
    tmp.data = mesh_obj.data.copy()
    scene.collection.objects.link(tmp)

    bpy.ops.object.select_all(action="DESELECT")
    _set_active(tmp)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")

    parts = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
    if not parts:
        parts = [tmp]

    if len(parts) > MAX_HULLS_PER_PART:
        parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
        print(f"Collision hulls capped to {MAX_HULLS_PER_PART} (had {len(parts)}): {mesh_obj.name}")
        parts = parts[:MAX_HULLS_PER_PART]

    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        _set_active(part)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.convex_hull(use_existing_faces=False)
        bpy.ops.object.mode_set(mode="OBJECT")

        face_count = len(part.data.polygons)
        if face_count > TARGET_FACES_PER_HULL:
            ratio = max(min(TARGET_FACES_PER_HULL / max(face_count, 1), 1.0), 0.01)
            mod = part.modifiers.new(name="Decimate", type="DECIMATE")
            mod.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=mod.name)

        positions, indices = _mesh_positions_indices(part.data)
        if positions and indices:
            collision.append({"positions": positions, "indices": indices})

    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        _set_active(part)
        bpy.ops.object.delete(use_global=False)
        for block in bpy.data.meshes:
            if block.users == 0:
                bpy.data.meshes.remove(block, do_unlink=True)

    return collision


def main():
    input_path, output_path, flip_v = _parse_args()
    if not os.path.exists(input_path):
        raise SystemExit(f"FBX not found: {input_path}")

    _clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_path)

    mesh_objs = _find_meshes()
    if not mesh_objs:
        raise SystemExit("No mesh found in FBX.")

    meshes_payload = []

    def q(v):
        return int(round(v * 1000000.0))

    for mesh_obj in mesh_objs:
        positions = []
        normals = []
        uvs = []
        indices = []
        vertex_map = {}
        submesh_indices = {}
        submesh_order = []

        mesh = mesh_obj.data
        if hasattr(mesh, "calc_loop_triangles"):
            mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active if mesh.uv_layers else None

        material_names = []
        for slot in mesh_obj.material_slots:
            mat = slot.material
            material_names.append(mat.name if mat else "Default")

        for tri in mesh.loop_triangles:
            loop_indices = tri.loops
            mat_name = material_names[tri.material_index] if tri.material_index < len(material_names) else "Default"
            if mat_name not in submesh_indices:
                submesh_indices[mat_name] = []
                submesh_order.append(mat_name)
            for li in loop_indices:
                loop = mesh.loops[li]
                v = mesh.vertices[loop.vertex_index]
                uv = uv_layer.data[li].uv if uv_layer else (0.0, 0.0)
                if flip_v:
                    uv = (uv[0], 1.0 - uv[1])
                p = v.co
                n = loop.normal if hasattr(loop, "normal") else v.normal
                if n.length > 0:
                    n = n.normalized()

                key = (
                    q(p.x), q(p.y), q(p.z),
                    q(n.x), q(n.y), q(n.z),
                    q(uv[0]), q(uv[1])
                )
                idx = vertex_map.get(key)
                if idx is None:
                    idx = len(positions) // 3
                    vertex_map[key] = idx
                    positions.extend([p.x, p.y, p.z])
                    normals.extend([n.x, n.y, n.z])
                    uvs.extend([uv[0], uv[1]])

                indices.append(idx)
                submesh_indices[mat_name].append(idx)

        submeshes = []
        index_cursor = 0
        indices = []
        for name in submesh_order:
            bucket = submesh_indices[name]
            if not bucket:
                continue
            start = index_cursor
            indices.extend(bucket)
            count = len(bucket)
            submeshes.append({"start": start, "count": count, "material": name})
            index_cursor += count

        meshes_payload.append({
            "name": mesh_obj.name,
            "transform": _matrix_to_row_major(mesh_obj.matrix_world),
            "mesh": {
                "positions": positions,
                "normals": normals,
                "uvs": uvs,
                "indices": indices,
                "submeshes": submeshes,
            },
            "collisionHulls": _build_collision_hulls(mesh_obj),
        })

    payload = {
        "version": 1,
        "meshes": meshes_payload,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f)

    print(f"Wrote static mesh JSON: {output_path}")


if __name__ == "__main__":
    main()
