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


def _normalize_path(path, base_dir):
    if not path:
        return ""
    if path.startswith("//"):
        path = bpy.path.abspath(path)
    try:
        if base_dir and os.path.commonpath([base_dir, path]) == base_dir:
            rel = os.path.relpath(path, base_dir)
            return rel.replace("\\", "/")
    except ValueError:
        pass
    return path.replace("\\", "/")


def _image_path_from_node(node, base_dir):
    if node is None or node.type != "TEX_IMAGE":
        return ""
    image = node.image
    if image is None:
        return ""
    path = image.filepath or image.filepath_raw
    return _normalize_path(path, base_dir)


def _find_image_from_socket(socket, base_dir):
    if socket is None or not socket.is_linked:
        return ""
    link = socket.links[0]
    node = link.from_node
    if node.type == "TEX_IMAGE":
        return _image_path_from_node(node, base_dir)
    if node.type == "NORMAL_MAP":
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir)
    if node.type == "SEPARATE_RGB":
        color_input = node.inputs.get("Image") or node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir)
    if node.type == "SEPARATE_COLOR":
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir)
    if node.type in {"MIX_RGB", "MIX"}:
        in1 = node.inputs[1] if len(node.inputs) > 1 else None
        in2 = node.inputs[2] if len(node.inputs) > 2 else None
        return _find_image_from_socket(in1, base_dir) or _find_image_from_socket(in2, base_dir)
    if node.type in {"GAMMA", "BRIGHTCONTRAST", "HUE_SAT"}:
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir)
    if node.type in {"MATH", "RGBTOBW", "INVERT"}:
        in1 = node.inputs[0] if node.inputs else None
        return _find_image_from_socket(in1, base_dir)
    return ""


def _find_image_and_channel(socket, base_dir):
    if socket is None or not socket.is_linked:
        return "", ""
    link = socket.links[0]
    node = link.from_node
    if node.type == "SEPARATE_RGB":
        img = _find_image_from_socket(node.inputs.get("Image") or node.inputs.get("Color"), base_dir)
        channel = link.from_socket.name.upper()
        return img, channel
    if node.type == "SEPARATE_COLOR":
        img = _find_image_from_socket(node.inputs.get("Color"), base_dir)
        channel = link.from_socket.name.upper()
        return img, channel
    if node.type == "TEX_IMAGE":
        return _image_path_from_node(node, base_dir), ""
    return _find_image_from_socket(socket, base_dir), ""


def _extract_material(mat, base_dir):
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
    base_color_tex = ""
    normal_tex = ""
    metallic_tex = ""
    roughness_tex = ""
    metallic_channel = ""
    roughness_channel = ""
    emissive_tex = ""
    occlusion_tex = ""
    occlusion_channel = ""

    node = _find_principled_node(mat)
    if node:
        base_input = node.inputs.get("Base Color")
        if base_input:
            base_color = list(base_input.default_value)
            base_color_tex = _find_image_from_socket(base_input, base_dir)
        metallic_input = node.inputs.get("Metallic")
        if metallic_input:
            metallic = float(metallic_input.default_value)
            metallic_tex, metallic_channel = _find_image_and_channel(metallic_input, base_dir)
        rough_input = node.inputs.get("Roughness")
        if rough_input:
            roughness = float(rough_input.default_value)
            roughness_tex, roughness_channel = _find_image_and_channel(rough_input, base_dir)
        emissive_input = node.inputs.get("Emission") or node.inputs.get("Emission Color")
        if emissive_input:
            emissive = list(emissive_input.default_value)[:3]
            emissive_tex = _find_image_from_socket(emissive_input, base_dir)
        alpha_input = node.inputs.get("Alpha")
        if alpha_input:
            alpha = float(alpha_input.default_value)
        transmission_input = node.inputs.get("Transmission")
        if transmission_input:
            transmission = float(transmission_input.default_value)
        ior_input = node.inputs.get("IOR")
        if ior_input:
            ior = float(ior_input.default_value)
        normal_input = node.inputs.get("Normal")
        if normal_input:
            normal_tex = _find_image_from_socket(normal_input, base_dir)
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

    if not occlusion_tex and mat.use_nodes and mat.node_tree:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                name = (node.label or node.name or "").lower()
                if "occlusion" in name or name.endswith("_ao") or name.endswith("-ao") or name.endswith(" ao"):
                    occlusion_tex = _image_path_from_node(node, base_dir)
                    occlusion_channel = "R"
                    break

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
        "baseColorTexture": base_color_tex,
        "normalTexture": normal_tex,
        "metallicRoughnessTexture": metallic_tex or roughness_tex,
        "metallicChannel": metallic_channel,
        "roughnessChannel": roughness_channel,
        "emissiveTexture": emissive_tex,
        "occlusionTexture": occlusion_tex,
        "occlusionChannel": occlusion_channel,
    }


def main():
    input_path, output_path = _parse_args()
    if not os.path.exists(input_path):
        raise SystemExit(f"FBX not found: {input_path}")

    _clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_path)

    materials = []
    base_dir = os.path.dirname(os.path.abspath(input_path))
    seen = set()
    for mat in bpy.data.materials:
        if mat is None or mat.name in seen:
            continue
        seen.add(mat.name)
        materials.append(_extract_material(mat, base_dir))

    payload = {"version": 1, "materials": materials}
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    print(f"Wrote materials JSON: {output_path}")


if __name__ == "__main__":
    main()
