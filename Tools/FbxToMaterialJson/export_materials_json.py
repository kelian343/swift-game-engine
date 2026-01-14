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
        raise SystemExit("Usage: blender -b -P export_materials_json.py -- <input.fbx> <output.json>")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2:
        raise SystemExit("Usage: blender -b -P export_materials_json.py -- <input.fbx> <output.json>")
    return argv[0], argv[1]


def _find_principled_node(mat):
    if not mat.use_nodes or not mat.node_tree:
        return None
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return None


def _extract_material(mat):
    base_color = [1.0, 1.0, 1.0, 1.0]
    metallic = 0.0
    roughness = 0.5
    emissive = [0.0, 0.0, 0.0]
    alpha = 1.0
    occlusion = 1.0
    transmission = 0.0
    ior = 1.5
    unlit = False
    normal_scale = 1.0

    node = _find_principled_node(mat)
    if node:
        base_input = node.inputs.get("Base Color")
        if base_input:
            base_color = list(base_input.default_value)
        metallic_input = node.inputs.get("Metallic")
        if metallic_input:
            metallic = float(metallic_input.default_value)
        rough_input = node.inputs.get("Roughness")
        if rough_input:
            roughness = float(rough_input.default_value)
        emissive_input = node.inputs.get("Emission") or node.inputs.get("Emission Color")
        if emissive_input:
            emissive = list(emissive_input.default_value)[:3]
        alpha_input = node.inputs.get("Alpha")
        if alpha_input:
            alpha = float(alpha_input.default_value)
        transmission_input = node.inputs.get("Transmission")
        if transmission_input:
            transmission = float(transmission_input.default_value)
        ior_input = node.inputs.get("IOR")
        if ior_input:
            ior = float(ior_input.default_value)
    else:
        if hasattr(mat, "diffuse_color"):
            base_color = list(mat.diffuse_color)
            alpha = base_color[3] if len(base_color) > 3 else 1.0
        if hasattr(mat, "metallic"):
            metallic = float(mat.metallic)
        if hasattr(mat, "roughness"):
            roughness = float(mat.roughness)
        if hasattr(mat, "emission_color"):
            emissive = list(mat.emission_color)[:3]

    return {
        "name": mat.name,
        "baseColorFactor": [base_color[0], base_color[1], base_color[2]],
        "metallicFactor": metallic,
        "roughnessFactor": roughness,
        "emissiveFactor": emissive,
        "occlusionStrength": occlusion,
        "alpha": alpha,
        "transmissionFactor": transmission,
        "ior": ior,
        "unlit": unlit,
        "normalScale": normal_scale,
    }


def main():
    input_path, output_path = _parse_args()
    if not os.path.exists(input_path):
        raise SystemExit(f"FBX not found: {input_path}")

    _clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_path)

    materials = []
    seen = set()
    for mat in bpy.data.materials:
        if mat is None or mat.name in seen:
            continue
        seen.add(mat.name)
        materials.append(_extract_material(mat))

    payload = {"version": 1, "materials": materials}
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    print(f"Wrote materials JSON: {output_path}")


if __name__ == "__main__":
    main()
