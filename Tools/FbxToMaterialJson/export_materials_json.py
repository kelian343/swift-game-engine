import json
import os
import shutil
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


def _find_textures_dir(input_path):
    fbx_dir = os.path.dirname(os.path.abspath(input_path))
    parent_dir = os.path.dirname(fbx_dir)
    candidates = [
        os.path.join(fbx_dir, "textures"),
        os.path.join(parent_dir, "textures"),
    ]
    for path in candidates:
        if os.path.isdir(path):
            return path
    return ""


def _copy_used_textures(texture_dir, dest_dir, materials):
    if not texture_dir or not os.path.isdir(texture_dir):
        return
    os.makedirs(dest_dir, exist_ok=True)
    used_names = set()
    for mat in materials:
        for key in (
            "baseColorTexture",
            "normalTexture",
            "metallicRoughnessTexture",
            "emissiveTexture",
            "occlusionTexture",
        ):
            value = mat.get(key, "") or ""
            if not value:
                continue
            used_names.add(os.path.basename(value))
    for name in sorted(used_names):
        src = os.path.join(texture_dir, name)
        if not os.path.isfile(src):
            continue
        dst = os.path.join(dest_dir, name)
        shutil.copy2(src, dst)


def _scan_textures(texture_dir):
    if not texture_dir or not os.path.isdir(texture_dir):
        return []
    results = []
    for name in sorted(os.listdir(texture_dir)):
        path = os.path.join(texture_dir, name)
        if not os.path.isfile(path):
            continue
        results.append((name, name.lower()))
    return results


def _find_texture_by_keywords(textures, keywords):
    for name, lower in textures:
        for key in keywords:
            if key in lower:
                return name
    return ""


def _autofill_from_textures(materials, texture_dir):
    textures = _scan_textures(texture_dir)
    if not textures:
        return

    base_color = _find_texture_by_keywords(textures, ["basecolor", "base_color", "albedo", "diffuse"])
    normal = _find_texture_by_keywords(textures, ["normal", "norm"])
    roughness = _find_texture_by_keywords(textures, ["roughness", "rough"])
    metallic = _find_texture_by_keywords(textures, ["metallic", "metalness"])
    occlusion = _find_texture_by_keywords(textures, ["occlusion", "ambientocclusion", "_ao", "-ao", " ao"])
    emissive = _find_texture_by_keywords(textures, ["emissive", "emission", "glow"])
    packed = _find_texture_by_keywords(textures, [
        "ao_metallic_roughness",
        "metallic_roughness",
        "occlusionroughnessmetallic",
        "orm",
        "arm",
        "rma",
    ])

    for mat in materials:
        if not mat.get("baseColorTexture") and base_color:
            mat["baseColorTexture"] = base_color
        if not mat.get("normalTexture") and normal:
            mat["normalTexture"] = normal
        if not mat.get("emissiveTexture") and emissive:
            mat["emissiveTexture"] = emissive

        if not mat.get("metallicRoughnessTexture"):
            if packed:
                mat["metallicRoughnessTexture"] = packed
                mat["metallicChannel"] = mat.get("metallicChannel") or "B"
                mat["roughnessChannel"] = mat.get("roughnessChannel") or "G"
                if not mat.get("occlusionTexture"):
                    mat["occlusionTexture"] = packed
                mat["occlusionChannel"] = mat.get("occlusionChannel") or "R"
            elif metallic and not roughness:
                mat["metallicRoughnessTexture"] = metallic
            elif roughness and not metallic:
                mat["metallicRoughnessTexture"] = roughness
            elif metallic and roughness:
                mat["metallicRoughnessTexture"] = metallic

        if not mat.get("occlusionTexture") and occlusion:
            mat["occlusionTexture"] = occlusion
            mat["occlusionChannel"] = mat.get("occlusionChannel") or "R"


def _resolve_texture_source(path, base_dir, texture_dir):
    if not path:
        return ""
    if path.startswith("//"):
        path = bpy.path.abspath(path)
    candidates = []
    if os.path.isabs(path):
        candidates.append(path)
    else:
        candidates.append(os.path.join(base_dir, path))
        candidates.append(os.path.join(base_dir, os.path.basename(path)))
    if texture_dir:
        candidates.append(os.path.join(texture_dir, path))
        candidates.append(os.path.join(texture_dir, os.path.basename(path)))
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            return candidate
    return ""


def _is_within_dir(path, base_dir):
    if not path or not base_dir:
        return False
    try:
        return os.path.commonpath([os.path.abspath(path), os.path.abspath(base_dir)]) == os.path.abspath(base_dir)
    except ValueError:
        return False


def _image_path_from_node(node, base_dir, texture_dir, output_dir):
    if node is None or node.type != "TEX_IMAGE":
        return ""
    image = node.image
    if image is None:
        return ""
    path = image.filepath or image.filepath_raw
    resolved = _resolve_texture_source(path, base_dir, texture_dir)
    if resolved:
        if texture_dir and _is_within_dir(resolved, texture_dir):
            return os.path.basename(resolved)
        if output_dir and _is_within_dir(resolved, output_dir):
            return os.path.basename(resolved)
        return _normalize_path(resolved, base_dir)
    return _normalize_path(path, base_dir)


def _find_image_from_socket(socket, base_dir, texture_dir, output_dir):
    if socket is None or not socket.is_linked:
        return ""
    link = socket.links[0]
    node = link.from_node
    if node.type == "TEX_IMAGE":
        return _image_path_from_node(node, base_dir, texture_dir, output_dir)
    if node.type == "NORMAL_MAP":
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir, texture_dir, output_dir)
    if node.type == "SEPARATE_RGB":
        color_input = node.inputs.get("Image") or node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir, texture_dir, output_dir)
    if node.type == "SEPARATE_COLOR":
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir, texture_dir, output_dir)
    if node.type in {"MIX_RGB", "MIX"}:
        in1 = node.inputs[1] if len(node.inputs) > 1 else None
        in2 = node.inputs[2] if len(node.inputs) > 2 else None
        return _find_image_from_socket(in1, base_dir, texture_dir, output_dir) or _find_image_from_socket(in2, base_dir, texture_dir, output_dir)
    if node.type in {"GAMMA", "BRIGHTCONTRAST", "HUE_SAT"}:
        color_input = node.inputs.get("Color")
        return _find_image_from_socket(color_input, base_dir, texture_dir, output_dir)
    if node.type in {"MATH", "RGBTOBW", "INVERT"}:
        in1 = node.inputs[0] if node.inputs else None
        return _find_image_from_socket(in1, base_dir, texture_dir, output_dir)
    return ""


def _find_image_and_channel(socket, base_dir, texture_dir, output_dir):
    if socket is None or not socket.is_linked:
        return "", ""
    link = socket.links[0]
    node = link.from_node
    if node.type == "SEPARATE_RGB":
        img = _find_image_from_socket(node.inputs.get("Image") or node.inputs.get("Color"), base_dir, texture_dir, output_dir)
        channel = link.from_socket.name.upper()
        return img, channel
    if node.type == "SEPARATE_COLOR":
        img = _find_image_from_socket(node.inputs.get("Color"), base_dir, texture_dir, output_dir)
        channel = link.from_socket.name.upper()
        return img, channel
    if node.type == "TEX_IMAGE":
        return _image_path_from_node(node, base_dir, texture_dir, output_dir), ""
    return _find_image_from_socket(socket, base_dir, texture_dir, output_dir), ""


def _extract_material(mat, base_dir, texture_dir, output_dir):
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
            base_color_tex = _find_image_from_socket(base_input, base_dir, texture_dir, output_dir)
        metallic_input = node.inputs.get("Metallic")
        if metallic_input:
            metallic = float(metallic_input.default_value)
            metallic_tex, metallic_channel = _find_image_and_channel(metallic_input, base_dir, texture_dir, output_dir)
        rough_input = node.inputs.get("Roughness")
        if rough_input:
            roughness = float(rough_input.default_value)
            roughness_tex, roughness_channel = _find_image_and_channel(rough_input, base_dir, texture_dir, output_dir)
        emissive_input = node.inputs.get("Emission") or node.inputs.get("Emission Color")
        if emissive_input:
            emissive = list(emissive_input.default_value)[:3]
            emissive_tex = _find_image_from_socket(emissive_input, base_dir, texture_dir, output_dir)
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
            normal_tex = _find_image_from_socket(normal_input, base_dir, texture_dir, output_dir)
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
                    occlusion_tex = _image_path_from_node(node, base_dir, texture_dir, output_dir)
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
    textures_dir = _find_textures_dir(input_path)
    output_dir = "/Users/karpellus/Desktop/Game/Game"
    seen = set()
    for mat in bpy.data.materials:
        if mat is None or mat.name in seen:
            continue
        seen.add(mat.name)
        materials.append(_extract_material(mat, base_dir, textures_dir, output_dir))
    _autofill_from_textures(materials, textures_dir)
    _copy_used_textures(textures_dir, output_dir, materials)

    payload = {"version": 1, "materials": materials}
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    print(f"Wrote materials JSON: {output_path}")


if __name__ == "__main__":
    main()
