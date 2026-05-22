"""Optimiert ein Unity-Lager-GLB fuer Mobile-WebViews.

Unity exportiert das Lagermodell mit ~44.000 einzelnen Nodes, jeder Node ist
ein eigener Draw-Call. Desktop-Chrome rendert das noch, die Android-WebView
(in der `flutter_3d_controller` laeuft) bricht nach ein paar tausend Calls
ab und zeigt nur einen Streifen.

Dieses Script fasst alle Nodes pro Mesh in **einen** Node mit
`EXT_mesh_gpu_instancing` zusammen (siehe glTF-Extension). Damit werden aus
zehntausenden Draw-Calls drei Instanced-Draws.

Aufruf:
    python data/optimize_warehouse_glb.py [pfad/zur/datei.glb]
        ohne Argument: data/warehouse.model.glb
        Backup landet neben der Eingabe als <name>.original.glb
"""
from __future__ import annotations

import json
import shutil
import struct
import sys
from pathlib import Path

import numpy as np


DEFAULT_SRC = Path(__file__).parent / "warehouse.model.glb"


def quat_to_matrix(q: np.ndarray) -> np.ndarray:
    """qx, qy, qz, qw -> 3x3-Rotationsmatrix."""
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


def matrix_to_quat(m: np.ndarray) -> np.ndarray:
    """3x3-Rotationsmatrix -> qx, qy, qz, qw (Shepperd's Methode)."""
    trace = m[0, 0] + m[1, 1] + m[2, 2]
    if trace > 0.0:
        s = 0.5 / np.sqrt(trace + 1.0)
        return np.array(
            [
                (m[2, 1] - m[1, 2]) * s,
                (m[0, 2] - m[2, 0]) * s,
                (m[1, 0] - m[0, 1]) * s,
                0.25 / s,
            ],
            dtype=np.float64,
        )
    if m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = 2.0 * np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2])
        return np.array(
            [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s],
            dtype=np.float64,
        )
    if m[1, 1] > m[2, 2]:
        s = 2.0 * np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2])
        return np.array(
            [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s],
            dtype=np.float64,
        )
    s = 2.0 * np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1])
    return np.array(
        [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s],
        dtype=np.float64,
    )


def trs_to_matrix(translation, rotation, scale) -> np.ndarray:
    t = np.asarray(translation, dtype=np.float64)
    r = np.asarray(rotation, dtype=np.float64)
    s = np.asarray(scale, dtype=np.float64)
    rot = quat_to_matrix(r)
    m = np.eye(4, dtype=np.float64)
    m[:3, :3] = rot * s  # column-scale
    m[:3, 3] = t
    return m


def decompose_matrix(m: np.ndarray):
    translation = m[:3, 3].copy()
    cols = m[:3, :3]
    scale = np.linalg.norm(cols, axis=0)
    # Korrigiere Spiegelung (negativer Determinant) -> X-Scale flippen.
    if np.linalg.det(cols) < 0:
        scale[0] = -scale[0]
    rot_matrix = cols / np.where(scale == 0, 1.0, scale)
    rotation = matrix_to_quat(rot_matrix)
    # Normiere Quaternion.
    n = np.linalg.norm(rotation)
    if n > 0:
        rotation = rotation / n
    return translation, rotation, scale


def read_glb(path: Path):
    data = path.read_bytes()
    assert data[:4] == b"glTF", "kein GLB"
    version, total_len = struct.unpack("<II", data[4:12])
    assert version == 2
    json_chunk_len, json_type = struct.unpack("<I4s", data[12:20])
    assert json_type == b"JSON"
    json_start = 20
    json_end = json_start + json_chunk_len
    gltf = json.loads(data[json_start:json_end])
    bin_data = b""
    if json_end < total_len:
        bin_chunk_len, bin_type = struct.unpack("<I4s", data[json_end:json_end + 8])
        assert bin_type == b"BIN\x00"
        bin_data = data[json_end + 8:json_end + 8 + bin_chunk_len]
    return gltf, bin_data


def write_glb(path: Path, gltf: dict, bin_data: bytes):
    # JSON-Chunk auf 4 Byte padden (Spaces).
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_pad = (4 - (len(json_bytes) % 4)) % 4
    json_bytes += b" " * json_pad

    # BIN-Chunk auf 4 Byte padden (Nullen).
    bin_pad = (4 - (len(bin_data) % 4)) % 4
    bin_data_padded = bin_data + b"\x00" * bin_pad

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_data_padded)
    header = struct.pack("<4sII", b"glTF", 2, total)
    json_chunk = struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes
    bin_chunk = struct.pack("<I4s", len(bin_data_padded), b"BIN\x00") + bin_data_padded
    path.write_bytes(header + json_chunk + bin_chunk)


def world_transforms(gltf: dict):
    """Berechne World-Matrix fuer jeden Node ueber Hierarchie-Traversal."""
    nodes = gltf["nodes"]
    parent_of = [-1] * len(nodes)
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent_of[c] = i

    local_mats = []
    for n in nodes:
        if "matrix" in n:
            m = np.array(n["matrix"], dtype=np.float64).reshape(4, 4, order="F")
        else:
            t = n.get("translation", [0.0, 0.0, 0.0])
            r = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
            s = n.get("scale", [1.0, 1.0, 1.0])
            m = trs_to_matrix(t, r, s)
        local_mats.append(m)

    world = [None] * len(nodes)

    def compute(i: int) -> np.ndarray:
        if world[i] is not None:
            return world[i]
        if parent_of[i] == -1:
            world[i] = local_mats[i]
        else:
            world[i] = compute(parent_of[i]) @ local_mats[i]
        return world[i]

    sys.setrecursionlimit(max(sys.getrecursionlimit(), 100_000))
    for i in range(len(nodes)):
        compute(i)
    return world, parent_of


def main():
    src = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        sys.exit(f"GLB nicht gefunden: {src}")
    backup = src.with_suffix(".original.glb")
    dst = src
    if not backup.exists():
        shutil.copy2(src, backup)
        print(f"Backup angelegt: {backup.name}")

    gltf, bin_data = read_glb(backup)
    nodes = gltf["nodes"]
    print(f"Eingelesen: {len(nodes)} Nodes, BIN={len(bin_data)} Bytes")

    world, _ = world_transforms(gltf)

    # Pro Mesh-Index die World-TRS aller Nodes sammeln, die diesen Mesh nutzen.
    per_mesh: dict[int, list[tuple[np.ndarray, np.ndarray, np.ndarray]]] = {}
    floor_world = None
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        mesh_idx = n["mesh"]
        t, r, s = decompose_matrix(world[i])
        # Sonderfall: Den ersten/einzigen Floor-Node (Mesh 0) lassen wir als
        # normalen Node stehen (kein Instancing noetig).
        if mesh_idx == 0 and floor_world is None:
            floor_world = (t, r, s)
            continue
        per_mesh.setdefault(mesh_idx, []).append((t, r, s))

    for mesh_idx, lst in sorted(per_mesh.items()):
        print(f"  Mesh {mesh_idx} ({gltf['meshes'][mesh_idx].get('name','?')}): {len(lst)} Instanzen")

    # Neuen JSON-Baum aufbauen: behalte die Original-BufferViews/Accessors
    # (sie referenzieren die Mesh-Geometrie im BIN-Chunk) und haenge neue
    # BufferViews/Accessors fuer die Instancing-Attribute an.
    new_gltf = {
        "asset": gltf.get("asset", {"version": "2.0"}),
        "extensionsUsed": list(set(gltf.get("extensionsUsed", []) + ["EXT_mesh_gpu_instancing"])),
        "extensionsRequired": list(set(gltf.get("extensionsRequired", []) + ["EXT_mesh_gpu_instancing"])),
        "scenes": [{"nodes": []}],
        "scene": 0,
        "meshes": gltf["meshes"],
        "materials": gltf.get("materials", []),
        "accessors": list(gltf.get("accessors", [])),
        "bufferViews": list(gltf.get("bufferViews", [])),
        "buffers": [{"byteLength": len(bin_data)}],
        "nodes": [],
    }
    # Optionale Bloecke uebernehmen, falls vorhanden.
    for key in ("textures", "images", "samplers"):
        if key in gltf:
            new_gltf[key] = gltf[key]

    new_bin = bytearray(bin_data)
    new_nodes = new_gltf["nodes"]
    scene_nodes = new_gltf["scenes"][0]["nodes"]

    # Directional Light beibehalten (falls vorhanden).
    light_node_idx = None
    for i, n in enumerate(nodes):
        if n.get("extensions", {}).get("KHR_lights_punctual"):
            light_node_idx = i
            break
    if light_node_idx is not None:
        light = nodes[light_node_idx]
        new_nodes.append({
            "name": light.get("name", "Directional Light"),
            "rotation": light.get("rotation", [0.0, 0.0, 0.0, 1.0]),
            "extensions": light["extensions"],
        })
        scene_nodes.append(len(new_nodes) - 1)
        if "extensions" not in new_gltf:
            new_gltf["extensions"] = {}
        if "KHR_lights_punctual" in gltf.get("extensions", {}):
            new_gltf["extensions"]["KHR_lights_punctual"] = gltf["extensions"]["KHR_lights_punctual"]
        if "KHR_lights_punctual" not in new_gltf["extensionsUsed"]:
            new_gltf["extensionsUsed"].append("KHR_lights_punctual")

    # Floor-Node (Mesh 0) als einzelner Node.
    if floor_world is not None:
        t, r, s = floor_world
        new_nodes.append({
            "name": "WarehouseFloor",
            "mesh": 0,
            "translation": [float(v) for v in t],
            "rotation": [float(v) for v in r],
            "scale": [float(v) for v in s],
        })
        scene_nodes.append(len(new_nodes) - 1)

    def append_buffer_view(arr: np.ndarray) -> int:
        offset = len(new_bin)
        new_bin.extend(arr.tobytes())
        new_gltf["bufferViews"].append({
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": arr.nbytes,
        })
        return len(new_gltf["bufferViews"]) - 1

    def append_accessor(buffer_view: int, count: int, type_: str, mins=None, maxs=None) -> int:
        acc = {
            "bufferView": buffer_view,
            "componentType": 5126,  # FLOAT
            "count": count,
            "type": type_,
        }
        if mins is not None:
            acc["min"] = mins
            acc["max"] = maxs
        new_gltf["accessors"].append(acc)
        return len(new_gltf["accessors"]) - 1

    # Instanced Nodes pro Mesh erzeugen.
    for mesh_idx, instances in sorted(per_mesh.items()):
        count = len(instances)
        translations = np.array([t for t, _, _ in instances], dtype=np.float32)
        rotations = np.array([r for _, r, _ in instances], dtype=np.float32)
        scales = np.array([s for _, _, s in instances], dtype=np.float32)

        bv_t = append_buffer_view(translations)
        bv_r = append_buffer_view(rotations)
        bv_s = append_buffer_view(scales)

        acc_t = append_accessor(
            bv_t, count, "VEC3",
            mins=translations.min(axis=0).tolist(),
            maxs=translations.max(axis=0).tolist(),
        )
        acc_r = append_accessor(bv_r, count, "VEC4")
        acc_s = append_accessor(bv_s, count, "VEC3")

        new_nodes.append({
            "name": f"{gltf['meshes'][mesh_idx].get('name','mesh')}_instanced",
            "mesh": mesh_idx,
            "extensions": {
                "EXT_mesh_gpu_instancing": {
                    "attributes": {
                        "TRANSLATION": acc_t,
                        "ROTATION": acc_r,
                        "SCALE": acc_s,
                    }
                }
            },
        })
        scene_nodes.append(len(new_nodes) - 1)

    new_gltf["buffers"][0]["byteLength"] = len(new_bin)

    write_glb(dst, new_gltf, bytes(new_bin))
    print(f"Geschrieben: {dst.name} ({dst.stat().st_size/1024:.1f} KB)")
    print(f"Nodes vorher: {len(nodes)}  ->  jetzt: {len(new_nodes)}")
    print(f"Tip: Falls etwas falsch aussieht, Original aus {backup.name} wiederherstellen.")


if __name__ == "__main__":
    main()
