import sys
import os

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
        raise SystemExit("Usage: blender -b -P export_gltf.py -- <input.fbx> <output.gltf>")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) != 2:
        raise SystemExit("Usage: blender -b -P export_gltf.py -- <input.fbx> <output.gltf>")
    return argv[0], argv[1]


def main():
    input_path, output_path = _parse_args()
    if not os.path.exists(input_path):
        raise SystemExit(f"FBX not found: {input_path}")

    _clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_path)

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLTF_SEPARATE",
        export_yup=True,
        export_normals=True,
        export_tangents=True,
        export_skins=True,
        export_materials="EXPORT",
    )

    print(f"Exported glTF: {output_path}")


if __name__ == "__main__":
    main()
