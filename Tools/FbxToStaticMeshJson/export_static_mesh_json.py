import json
import os
import sys

import bpy


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
        raise SystemExit("Usage: blender -b -P export_static_mesh_json.py -- <input.fbx> <output.json>")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2:
        raise SystemExit("Usage: blender -b -P export_static_mesh_json.py -- <input.fbx> <output.json>")
    return argv[0], argv[1]


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


def main():
    input_path, output_path = _parse_args()
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
