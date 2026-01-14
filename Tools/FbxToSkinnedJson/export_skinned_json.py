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


def _parse_args():
    if "--" not in sys.argv:
        raise SystemExit("Usage: blender -b -P export_skinned_json.py -- <input.fbx> <output.json>")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2:
        raise SystemExit("Usage: blender -b -P export_skinned_json.py -- <input.fbx> <output.json>")
    return argv[0], argv[1]


def _find_armature_and_meshes():
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]

    armature = armatures[0] if armatures else None
    if not meshes:
        return armature, []

    candidates = []
    selected = []
    for obj in meshes:
        has_armature = any(mod.type == "ARMATURE" for mod in obj.modifiers)
        vcount = len(obj.data.vertices)
        multi = 0
        for v in obj.data.vertices:
            if len(v.groups) >= 2:
                multi += 1
        candidates.append((has_armature, multi, vcount, obj.name, obj))
        if has_armature or len(obj.vertex_groups) > 0:
            selected.append(obj)

    candidates.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)
    print("Mesh candidates:")
    for has_armature, multi, vcount, name, _ in candidates:
        print(f"  {name}: verts={vcount} multiWeights={multi} armature={has_armature}")
    print("Selected meshes:", [obj.name for obj in selected])
    return armature, selected


def _collect_bone_map(armature_obj):
    bones = list(armature_obj.data.bones)
    bone_names = [b.name for b in bones]
    name_to_index = {}
    for i, name in enumerate(bone_names):
        key = name.lower()
        name_to_index[key] = i
        if ":" in name:
            short = name.split(":")[-1].lower()
            name_to_index[short] = i
    return bone_names, name_to_index


def _inverse_bind_matrices(armature_obj, bone_names):
    inv_bind = []
    for name in bone_names:
        bone = armature_obj.data.bones.get(name)
        if bone is None:
            inv_bind.append([1, 0, 0, 0,
                             0, 1, 0, 0,
                             0, 0, 1, 0,
                             0, 0, 0, 1])
            continue
        inv = bone.matrix_local.inverted()
        inv_bind.append([inv[0][0], inv[0][1], inv[0][2], inv[0][3],
                         inv[1][0], inv[1][1], inv[1][2], inv[1][3],
                         inv[2][0], inv[2][1], inv[2][2], inv[2][3],
                         inv[3][0], inv[3][1], inv[3][2], inv[3][3]])
    return inv_bind


def _vertex_weights(vertex, group_index_to_bone):
    weights = []
    for g in vertex.groups:
        bone_idx = group_index_to_bone.get(g.group)
        if bone_idx is None:
            continue
        weights.append((bone_idx, g.weight))
    weights.sort(key=lambda x: x[1], reverse=True)
    weights = weights[:4]
    if not weights:
        return [0, 0, 0, 0], [1.0, 0.0, 0.0, 0.0]

    joint_indices = [w[0] for w in weights]
    joint_weights = [w[1] for w in weights]
    while len(joint_indices) < 4:
        joint_indices.append(0)
        joint_weights.append(0.0)
    total = sum(joint_weights)
    if total > 0:
        joint_weights = [w / total for w in joint_weights]
    return joint_indices, joint_weights


def main():
    input_path, output_path = _parse_args()
    if not os.path.exists(input_path):
        raise SystemExit(f"FBX not found: {input_path}")

    _clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_path)

    armature_obj, mesh_objs = _find_armature_and_meshes()
    if not mesh_objs:
        raise SystemExit("No mesh found in FBX.")
    if armature_obj is None:
        raise SystemExit("No armature found in FBX.")

    bone_names, bone_name_to_index = _collect_bone_map(armature_obj)

    positions = []
    normals = []
    uvs = []
    joints = []
    weights = []
    indices = []
    vertex_map = {}
    submesh_indices = {}
    submesh_order = []

    def q(v):
        return int(round(v * 1000000.0))

    arm_inv = armature_obj.matrix_world.inverted()

    for mesh_obj in mesh_objs:
        mesh = mesh_obj.data
        if hasattr(mesh, "calc_loop_triangles"):
            mesh.calc_loop_triangles()
        uv_layer = mesh.uv_layers.active if mesh.uv_layers else None

        group_index_to_bone = {}
        for i, group in enumerate(mesh_obj.vertex_groups):
            key = group.name.lower()
            idx = bone_name_to_index.get(key)
            if idx is None and ":" in key:
                idx = bone_name_to_index.get(key.split(":")[-1])
            group_index_to_bone[i] = idx

        material_names = []
        for slot in mesh_obj.material_slots:
            mat = slot.material
            material_names.append(mat.name if mat else "Default")

        mesh_to_arm = arm_inv @ mesh_obj.matrix_world
        normal_mat = mesh_to_arm.to_3x3()

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
                p = mesh_to_arm @ v.co
                n = loop.normal if hasattr(loop, "normal") else v.normal
                n = normal_mat @ n

                j_idx, j_w = _vertex_weights(v, group_index_to_bone)
                key = (
                    q(p.x), q(p.y), q(p.z),
                    q(n.x), q(n.y), q(n.z),
                    q(uv[0]), q(uv[1]),
                    j_idx[0], j_idx[1], j_idx[2], j_idx[3],
                    q(j_w[0]), q(j_w[1]), q(j_w[2]), q(j_w[3])
                )
                idx = vertex_map.get(key)
                if idx is None:
                    idx = len(positions) // 3
                    vertex_map[key] = idx
                    positions.extend([p.x, p.y, p.z])
                    normals.extend([n.x, n.y, n.z])
                    uvs.extend([uv[0], uv[1]])
                    joints.extend(j_idx)
                    weights.extend(j_w)

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

    inv_bind = _inverse_bind_matrices(armature_obj, bone_names)
    bones = [{"name": name, "inverseBindMatrix": inv_bind[i]} for i, name in enumerate(bone_names)]

    payload = {
        "version": 1,
        "mesh": {
            "positions": positions,
            "normals": normals,
            "uvs": uvs,
            "joints": joints,
            "weights": weights,
            "indices": indices,
            "submeshes": submeshes,
        },
        "skin": {"bones": bones},
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f)

    print(f"Wrote skinned mesh JSON: {output_path}")


if __name__ == "__main__":
    main()
