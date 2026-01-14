import json
import os
import sys

import numpy as np
from pygltflib import GLTF2


COMPONENT_DTYPE = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}

TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT4": 16,
}


def _load_buffers(gltf, base_dir):
    blobs = []
    for buffer in gltf.buffers:
        if buffer.uri is None:
            blobs.append(gltf.binary_blob())
            continue
        if buffer.uri.startswith("data:"):
            blobs.append(gltf.get_data_from_buffer_uri(buffer.uri))
            continue
        path = os.path.join(base_dir, buffer.uri)
        with open(path, "rb") as f:
            blobs.append(f.read())
    return blobs


def _read_accessor(gltf, blobs, accessor_index):
    accessor = gltf.accessors[accessor_index]
    buffer_view = gltf.bufferViews[accessor.bufferView]
    blob = blobs[buffer_view.buffer]

    dtype = COMPONENT_DTYPE[accessor.componentType]
    num_comp = TYPE_COMPONENTS[accessor.type]
    comp_size = np.dtype(dtype).itemsize
    stride = buffer_view.byteStride or (num_comp * comp_size)
    offset = (buffer_view.byteOffset or 0) + (accessor.byteOffset or 0)
    count = accessor.count

    if stride == num_comp * comp_size:
        raw = np.frombuffer(blob, dtype=dtype, count=count * num_comp, offset=offset)
        data = raw.reshape((count, num_comp))
    else:
        data = np.empty((count, num_comp), dtype=dtype)
        for i in range(count):
            start = offset + i * stride
            data[i] = np.frombuffer(blob, dtype=dtype, count=num_comp, offset=start)

    if accessor.normalized and np.issubdtype(dtype, np.integer):
        max_val = np.iinfo(dtype).max
        data = data.astype(np.float32) / float(max_val)

    return data


def _find_skinned_mesh(gltf, skin_index):
    for node in gltf.nodes:
        if node.skin == skin_index and node.mesh is not None:
            return gltf.meshes[node.mesh]
    return gltf.meshes[0] if gltf.meshes else None


def _collect_primitives(gltf, blobs, mesh):
    positions = []
    normals = []
    uvs = []
    joints = []
    weights = []
    indices = []
    submeshes = []
    base_vertex = 0

    for prim in mesh.primitives:
        attrs = prim.attributes
        if attrs.POSITION is None or attrs.NORMAL is None or attrs.TEXCOORD_0 is None:
            raise RuntimeError("Missing POSITION/NORMAL/TEXCOORD_0 on primitive.")
        if attrs.JOINTS_0 is None or attrs.WEIGHTS_0 is None:
            raise RuntimeError("Missing JOINTS_0/WEIGHTS_0 on primitive.")

        pos = _read_accessor(gltf, blobs, attrs.POSITION)
        nor = _read_accessor(gltf, blobs, attrs.NORMAL)
        uv = _read_accessor(gltf, blobs, attrs.TEXCOORD_0)
        jnt = _read_accessor(gltf, blobs, attrs.JOINTS_0).astype(np.uint16)
        wgt = _read_accessor(gltf, blobs, attrs.WEIGHTS_0).astype(np.float32)

        if pos.shape[1] != 3 or nor.shape[1] != 3 or uv.shape[1] != 2:
            raise RuntimeError("Unexpected attribute sizes on primitive.")
        if jnt.shape[1] != 4 or wgt.shape[1] != 4:
            raise RuntimeError("JOINTS_0/WEIGHTS_0 must be VEC4.")

        if prim.indices is not None:
            idx = _read_accessor(gltf, blobs, prim.indices).reshape(-1)
        else:
            idx = np.arange(pos.shape[0], dtype=np.uint32)

        idx = idx.astype(np.uint32) + base_vertex
        start = len(indices)
        indices.extend(idx.tolist())
        submeshes.append(
            {
                "start": start,
                "count": len(idx),
                "material": prim.material if prim.material is not None else -1,
            }
        )

        positions.append(pos)
        normals.append(nor)
        uvs.append(uv)
        joints.append(jnt)
        weights.append(wgt)
        base_vertex += pos.shape[0]

    positions = np.concatenate(positions, axis=0) if positions else np.zeros((0, 3), dtype=np.float32)
    normals = np.concatenate(normals, axis=0) if normals else np.zeros((0, 3), dtype=np.float32)
    uvs = np.concatenate(uvs, axis=0) if uvs else np.zeros((0, 2), dtype=np.float32)
    joints = np.concatenate(joints, axis=0) if joints else np.zeros((0, 4), dtype=np.uint16)
    weights = np.concatenate(weights, axis=0) if weights else np.zeros((0, 4), dtype=np.float32)

    return positions, normals, uvs, joints, weights, indices, submeshes


def _collect_skin(gltf, blobs, skin):
    bone_names = []
    for node_index in skin.joints:
        name = gltf.nodes[node_index].name or f"joint_{node_index}"
        bone_names.append(name)

    if skin.inverseBindMatrices is not None:
        ibm = _read_accessor(gltf, blobs, skin.inverseBindMatrices).astype(np.float32)
    else:
        ibm = np.eye(4, dtype=np.float32).reshape((1, 16))
        ibm = np.repeat(ibm, len(bone_names), axis=0)

    if ibm.shape[1] != 16:
        raise RuntimeError("inverseBindMatrices must be MAT4.")

    bones = []
    for i, name in enumerate(bone_names):
        bones.append({"name": name, "inverseBindMatrix": ibm[i].tolist()})

    return bones


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: python convert_gltf_to_skinned_json.py <input.gltf> <output.json>")
    input_path, output_path = sys.argv[1], sys.argv[2]
    gltf = GLTF2().load(input_path)

    base_dir = os.path.dirname(os.path.abspath(input_path))
    blobs = _load_buffers(gltf, base_dir)

    if not gltf.skins:
        raise RuntimeError("No skins found in glTF.")
    skin = gltf.skins[0]

    mesh = _find_skinned_mesh(gltf, 0)
    if mesh is None:
        raise RuntimeError("No mesh found in glTF.")

    positions, normals, uvs, joints, weights, indices, submeshes = _collect_primitives(gltf, blobs, mesh)

    # Normalize weights per vertex.
    weight_sum = weights.sum(axis=1)
    nonzero = weight_sum > 0
    weights[nonzero] = (weights[nonzero].T / weight_sum[nonzero]).T

    bones = _collect_skin(gltf, blobs, skin)

    payload = {
        "version": 1,
        "mesh": {
            "positions": positions.reshape(-1).tolist(),
            "normals": normals.reshape(-1).tolist(),
            "uvs": uvs.reshape(-1).tolist(),
            "joints": joints.reshape(-1).tolist(),
            "weights": weights.reshape(-1).tolist(),
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
