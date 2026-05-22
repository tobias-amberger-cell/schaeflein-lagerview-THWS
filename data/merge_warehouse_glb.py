"""Merged ein Unity-Lager-GLB zu wenigen grossen Meshes.

Alternative zu `optimize_warehouse_glb.py` (das `EXT_mesh_gpu_instancing`
verwendet — wird von einigen Android-WebViews nicht unterstuetzt; dann
fehlen alle instanzierten Nodes und nur der Boden bleibt sichtbar).

Hier werden alle Instanzen pro Mesh in einen einzigen grossen Vertex-Buffer
gemergt. Geht ohne Extensions, dafuer wird die Datei groesser.

Aufruf:
    python data/merge_warehouse_glb.py [pfad/zur/original.glb]
        ohne Argument: data/SampleScene.original.glb
        Output: data/<name>.glb (ueberschreibt instanced Version)
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

import numpy as np

# TANGENT + TEXCOORD_1 droppen wir, sonst wird die Datei doppelt so gross.
# Tangenten werden vom Renderer bei Bedarf on-the-fly aus POSITION + NORMAL + UV
# berechnet (gltf-Spec). TEXCOORD_1 wird vom Material in unserer Szene nicht
# semantisch unterschiedlich genutzt.
KEEP_ATTRS = ("POSITION", "NORMAL", "TEXCOORD_0")


def read_glb(path: Path):
    data = path.read_bytes()
    assert data[:4] == b"glTF"
    version, total_len = struct.unpack("<II", data[4:12])
    assert version == 2
    json_chunk_len, json_type = struct.unpack("<I4s", data[12:20])
    assert json_type == b"JSON"
    gltf = json.loads(data[20:20 + json_chunk_len])
    bin_data = b""
    after = 20 + json_chunk_len
    if after < total_len:
        bin_chunk_len, bin_type = struct.unpack("<I4s", data[after:after + 8])
        assert bin_type == b"BIN\x00"
        bin_data = data[after + 8:after + 8 + bin_chunk_len]
    return gltf, bin_data


def write_glb(path: Path, gltf: dict, bin_data: bytes):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    bin_pad = (4 - (len(bin_data) % 4)) % 4
    bin_data_padded = bin_data + b"\x00" * bin_pad

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_data_padded)
    header = struct.pack("<4sII", b"glTF", 2, total)
    json_chunk = struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes
    bin_chunk = struct.pack("<I4s", len(bin_data_padded), b"BIN\x00") + bin_data_padded
    path.write_bytes(header + json_chunk + bin_chunk)


def quat_to_matrix(q):
    x, y, z, w = q
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return np.array(
        [
            [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy)],
            [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx)],
            [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)],
        ],
        dtype=np.float64,
    )


def trs_to_matrix(t, r, s):
    rot = quat_to_matrix(r)
    m = np.eye(4, dtype=np.float64)
    m[:3, :3] = rot * np.asarray(s, dtype=np.float64)  # column-scale
    m[:3, 3] = np.asarray(t, dtype=np.float64)
    return m


def world_transforms(gltf):
    nodes = gltf["nodes"]
    parent = [-1] * len(nodes)
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    locals_ = []
    for n in nodes:
        if "matrix" in n:
            m = np.array(n["matrix"], dtype=np.float64).reshape(4, 4, order="F")
        else:
            t = n.get("translation", [0.0, 0.0, 0.0])
            r = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
            s = n.get("scale", [1.0, 1.0, 1.0])
            m = trs_to_matrix(t, r, s)
        locals_.append(m)

    world = [None] * len(nodes)
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 100_000))

    def compute(i):
        if world[i] is not None:
            return world[i]
        if parent[i] == -1:
            world[i] = locals_[i]
        else:
            world[i] = compute(parent[i]) @ locals_[i]
        return world[i]

    for i in range(len(nodes)):
        compute(i)
    return world


def read_accessor(gltf, bin_data, idx):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    comp = acc["componentType"]
    type_ = acc["type"]
    comp_map = {
        5120: (np.int8, 1),
        5121: (np.uint8, 1),
        5122: (np.int16, 2),
        5123: (np.uint16, 2),
        5125: (np.uint32, 4),
        5126: (np.float32, 4),
    }
    dt, dt_size = comp_map[comp]
    elems = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[type_]
    total = count * elems
    arr = np.frombuffer(bin_data, dtype=dt, count=total, offset=offset)
    if elems > 1:
        arr = arr.reshape(count, elems)
    return arr.copy()  # entkoppeln vom Read-only-Buffer


def append_view_and_accessor(new_bin, new_gltf, arr, component_type, type_, mins=None, maxs=None):
    offset = len(new_bin)
    raw = arr.tobytes()
    new_bin.extend(raw)
    # 4-byte align
    pad = (4 - (len(new_bin) % 4)) % 4
    new_bin.extend(b"\x00" * pad)
    new_gltf["bufferViews"].append({
        "buffer": 0,
        "byteOffset": offset,
        "byteLength": len(raw),
    })
    bv_idx = len(new_gltf["bufferViews"]) - 1
    acc = {
        "bufferView": bv_idx,
        "componentType": component_type,
        "count": int(arr.shape[0]),
        "type": type_,
    }
    if mins is not None:
        acc["min"] = mins
        acc["max"] = maxs
    new_gltf["accessors"].append(acc)
    return len(new_gltf["accessors"]) - 1


def main():
    src = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
        Path(__file__).parent / "SampleScene.original.glb"
    )
    dst = src.with_name(src.name.replace(".original", ""))
    if not src.exists():
        sys.exit(f"GLB nicht gefunden: {src}")
    print(f"Eingabe: {src.name} -> Ausgabe: {dst.name}")

    gltf, bin_data = read_glb(src)
    world = world_transforms(gltf)
    nodes = gltf["nodes"]

    # Sammle Welt-Matrizen pro Mesh-Index.
    per_mesh: dict[int, list[np.ndarray]] = {}
    for i, n in enumerate(nodes):
        if "mesh" in n:
            per_mesh.setdefault(n["mesh"], []).append(world[i])

    new_gltf = {
        "asset": gltf.get("asset", {"version": "2.0"}),
        "scene": 0,
        "scenes": [{"nodes": []}],
        "nodes": [],
        "meshes": [],
        "materials": gltf.get("materials", []),
        "accessors": [],
        "bufferViews": [],
        "buffers": [{}],
    }
    for k in ("textures", "images", "samplers"):
        if k in gltf:
            new_gltf[k] = gltf[k]
    # Behalte einfache Material-Extensions, droppe Instancing-Stuff.
    used = []
    required = []
    for e in gltf.get("extensionsUsed", []):
        if e in ("KHR_materials_transmission", "KHR_materials_ior", "KHR_lights_punctual"):
            used.append(e)
    if used:
        new_gltf["extensionsUsed"] = used
    if required:
        new_gltf["extensionsRequired"] = required

    new_bin = bytearray()
    scene_nodes = new_gltf["scenes"][0]["nodes"]

    # Directional Light beibehalten.
    for i, n in enumerate(nodes):
        if n.get("extensions", {}).get("KHR_lights_punctual"):
            new_gltf["nodes"].append({
                "name": n.get("name", "Directional Light"),
                "rotation": n.get("rotation", [0.0, 0.0, 0.0, 1.0]),
                "extensions": n["extensions"],
            })
            scene_nodes.append(len(new_gltf["nodes"]) - 1)
            if "extensions" in gltf and "KHR_lights_punctual" in gltf["extensions"]:
                new_gltf["extensions"] = {"KHR_lights_punctual": gltf["extensions"]["KHR_lights_punctual"]}
            break

    # Pro Mesh-Index alle Instanzen in einen einzigen grossen Buffer mergen.
    for mesh_idx in sorted(per_mesh.keys()):
        mesh = gltf["meshes"][mesh_idx]
        prim = mesh["primitives"][0]
        attrs = prim["attributes"]
        material = prim.get("material")

        # Lade Source-Vertices.
        positions = read_accessor(gltf, bin_data, attrs["POSITION"]).astype(np.float64)
        normals = read_accessor(gltf, bin_data, attrs["NORMAL"]).astype(np.float64) if "NORMAL" in attrs else None
        uvs = read_accessor(gltf, bin_data, attrs["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in attrs else None
        indices = read_accessor(gltf, bin_data, prim["indices"]).astype(np.uint32) if "indices" in prim else None

        instances = per_mesh[mesh_idx]
        n_inst = len(instances)
        n_verts = positions.shape[0]
        n_idx = indices.shape[0] if indices is not None else 0

        print(f"  Mesh {mesh_idx} ({mesh.get('name','?')}): {n_inst} Instanzen "
              f"-> {n_inst * n_verts} Vertices, {n_inst * n_idx} Indices")

        merged_pos = np.empty((n_inst * n_verts, 3), dtype=np.float32)
        merged_nrm = np.empty((n_inst * n_verts, 3), dtype=np.float32) if normals is not None else None
        merged_uv = np.empty((n_inst * n_verts, 2), dtype=np.float32) if uvs is not None else None
        merged_idx = np.empty(n_inst * n_idx, dtype=np.uint32) if indices is not None else None

        pos_h = np.concatenate([positions, np.ones((n_verts, 1))], axis=1)  # (n,4)

        for k, world_mat in enumerate(instances):
            # Position: vollstaendige Transform.
            transformed = pos_h @ world_mat.T  # (n,4)
            merged_pos[k * n_verts:(k + 1) * n_verts] = transformed[:, :3].astype(np.float32)
            # Normal: inverse-transpose der oberen 3x3.
            if normals is not None:
                M = world_mat[:3, :3]
                # Sichere inv-transpose; bei Spiegelung normalisieren wir spaeter.
                try:
                    nm = np.linalg.inv(M).T
                except np.linalg.LinAlgError:
                    nm = M
                nrm_t = normals @ nm.T
                norms = np.linalg.norm(nrm_t, axis=1, keepdims=True)
                nrm_t = nrm_t / np.where(norms == 0, 1.0, norms)
                merged_nrm[k * n_verts:(k + 1) * n_verts] = nrm_t.astype(np.float32)
            if uvs is not None:
                merged_uv[k * n_verts:(k + 1) * n_verts] = uvs
            if indices is not None:
                base = k * n_verts
                merged_idx[k * n_idx:(k + 1) * n_idx] = indices + base

        # Accessoren / BufferViews anhaengen.
        new_attrs = {}
        new_attrs["POSITION"] = append_view_and_accessor(
            new_bin, new_gltf, merged_pos, 5126, "VEC3",
            mins=merged_pos.min(axis=0).tolist(),
            maxs=merged_pos.max(axis=0).tolist(),
        )
        if merged_nrm is not None:
            new_attrs["NORMAL"] = append_view_and_accessor(
                new_bin, new_gltf, merged_nrm, 5126, "VEC3",
            )
        if merged_uv is not None:
            new_attrs["TEXCOORD_0"] = append_view_and_accessor(
                new_bin, new_gltf, merged_uv, 5126, "VEC2",
            )
        idx_acc = None
        if merged_idx is not None:
            idx_acc = append_view_and_accessor(
                new_bin, new_gltf, merged_idx, 5125, "SCALAR",
            )

        new_prim = {"attributes": new_attrs}
        if idx_acc is not None:
            new_prim["indices"] = idx_acc
        if material is not None:
            new_prim["material"] = material

        new_gltf["meshes"].append({
            "name": f"{mesh.get('name','mesh')}_merged",
            "primitives": [new_prim],
        })
        new_mesh_idx = len(new_gltf["meshes"]) - 1
        new_gltf["nodes"].append({
            "name": new_gltf["meshes"][new_mesh_idx]["name"],
            "mesh": new_mesh_idx,
        })
        scene_nodes.append(len(new_gltf["nodes"]) - 1)

    new_gltf["buffers"][0]["byteLength"] = len(new_bin)
    write_glb(dst, new_gltf, bytes(new_bin))
    print(f"Geschrieben: {dst.name} ({dst.stat().st_size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
