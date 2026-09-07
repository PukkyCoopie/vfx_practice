#!/usr/bin/env python3
"""Shrink GLB files: keep named clips, resize embedded textures, prune unused buffers."""

from __future__ import annotations

import json
import struct
from io import BytesIO
from pathlib import Path

from PIL import Image

MAX_TEXTURE = 1024
JPEG_QUALITY = 85


def load_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"Not a GLB: {path}")
    offset = 12
    gltf = None
    blob = b""
    while offset + 8 <= len(data):
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_len]
        offset += chunk_len
        if chunk_type.startswith(b"JSON"):
            gltf = json.loads(chunk)
        elif chunk_type.startswith(b"BIN"):
            blob = chunk
    if gltf is None:
        raise ValueError(f"Missing JSON chunk: {path}")
    return gltf, blob


def save_glb(path: Path, gltf: dict, blob: bytes) -> None:
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - (len(json_bytes) % 4)) % 4)
    bin_bytes = blob + (b"\x00" * ((4 - (len(blob) % 4)) % 4))
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    header = struct.pack("<4sII", b"glTF", 2, total)
    json_header = struct.pack("<I4s", len(json_bytes), b"JSON")
    bin_header = struct.pack("<I4s", len(bin_bytes), b"BIN\x00")
    path.write_bytes(header + json_header + json_bytes + bin_header + bin_bytes)


def view_bytes(blob: bytes, view: dict) -> bytes:
    start = view.get("byteOffset", 0)
    return blob[start : start + view["byteLength"]]


def encode_texture(image: Image.Image, force_png: bool = False) -> tuple[bytes, str]:
    image = image.copy()
    image.thumbnail((MAX_TEXTURE, MAX_TEXTURE), Image.Resampling.LANCZOS)
    alpha_used = False
    if image.mode in ("RGBA", "LA"):
        extrema = image.getchannel("A").getextrema()
        alpha_used = extrema is not None and extrema[0] < 250
    buf = BytesIO()
    if force_png or alpha_used:
        if image.mode not in ("RGBA", "RGB"):
            image = image.convert("RGBA" if alpha_used else "RGB")
        elif not alpha_used and image.mode == "RGBA":
            image = image.convert("RGB")
        image.save(buf, format="PNG", optimize=True)
        return buf.getvalue(), "image/png"
    if image.mode != "RGB":
        image = image.convert("RGB")
    image.save(buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    return buf.getvalue(), "image/jpeg"


def resize_images(gltf: dict, blob: bytes, force_png: bool = False) -> dict[int, bytes]:
    replacements: dict[int, bytes] = {}
    views = gltf.get("bufferViews", [])
    for image in gltf.get("images", []):
        view_index = image.get("bufferView")
        if view_index is None:
            continue
        raw = view_bytes(blob, views[view_index])
        decoded = Image.open(BytesIO(raw))
        decoded.load()
        payload, mime = encode_texture(decoded, force_png=force_png)
        replacements[view_index] = payload
        image["mimeType"] = mime
        image.pop("uri", None)
    return replacements


def add_accessor(used: set[int], index: int | None) -> None:
    if index is not None:
        used.add(index)


def used_accessors(gltf: dict) -> set[int]:
    used: set[int] = set()
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for index in prim.get("attributes", {}).values():
                add_accessor(used, index)
            add_accessor(used, prim.get("indices"))
            for target in prim.get("targets", []):
                for index in target.values():
                    add_accessor(used, index)
    for skin in gltf.get("skins", []):
        add_accessor(used, skin.get("inverseBindMatrices"))
    for anim in gltf.get("animations", []):
        for sampler in anim.get("samplers", []):
            add_accessor(used, sampler.get("input"))
            add_accessor(used, sampler.get("output"))
    accessors = gltf.get("accessors", [])
    extra: set[int] = set()
    for index in used:
        sparse = accessors[index].get("sparse")
        if not sparse:
            continue
        add_accessor(extra, sparse.get("indices", {}).get("bufferView"))
    return used


def used_buffer_views(gltf: dict, accessors_used: set[int], image_views: set[int]) -> set[int]:
    used = set(image_views)
    accessors = gltf.get("accessors", [])
    for index in accessors_used:
        acc = accessors[index]
        if "bufferView" in acc:
            used.add(acc["bufferView"])
        sparse = acc.get("sparse")
        if sparse:
            used.add(sparse["indices"]["bufferView"])
            used.add(sparse["values"]["bufferView"])
    return used


def compact(gltf: dict, blob: bytes, replacements: dict[int, bytes]) -> bytes:
    accessors = gltf.get("accessors", [])
    views = gltf.get("bufferViews", [])
    acc_used = sorted(used_accessors(gltf))
    image_views = {image["bufferView"] for image in gltf.get("images", []) if "bufferView" in image}
    view_used = sorted(used_buffer_views(gltf, set(acc_used), image_views))

    new_blob = bytearray()
    view_map: dict[int, int] = {}
    new_views: list[dict] = []
    for old_index in view_used:
        payload = replacements.get(old_index)
        if payload is None:
            payload = view_bytes(blob, views[old_index])
        while len(new_blob) % 4:
            new_blob.append(0)
        new_view = dict(views[old_index])
        new_view["buffer"] = 0
        new_view["byteOffset"] = len(new_blob)
        new_view["byteLength"] = len(payload)
        new_blob.extend(payload)
        view_map[old_index] = len(new_views)
        new_views.append(new_view)

    acc_map = {old: new for new, old in enumerate(acc_used)}
    new_accessors = []
    for old_index in acc_used:
        acc = dict(accessors[old_index])
        if "bufferView" in acc:
            acc["bufferView"] = view_map[acc["bufferView"]]
        sparse = acc.get("sparse")
        if sparse:
            sparse = {
                **sparse,
                "indices": {**sparse["indices"], "bufferView": view_map[sparse["indices"]["bufferView"]]},
                "values": {**sparse["values"], "bufferView": view_map[sparse["values"]["bufferView"]]},
            }
            acc["sparse"] = sparse
        new_accessors.append(acc)

    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            prim["attributes"] = {name: acc_map[index] for name, index in prim.get("attributes", {}).items()}
            if "indices" in prim:
                prim["indices"] = acc_map[prim["indices"]]
            for target in prim.get("targets", []):
                for name, index in list(target.items()):
                    target[name] = acc_map[index]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
    for anim in gltf.get("animations", []):
        for sampler in anim.get("samplers", []):
            sampler["input"] = acc_map[sampler["input"]]
            sampler["output"] = acc_map[sampler["output"]]
    for image in gltf.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]

    gltf["bufferViews"] = new_views
    gltf["accessors"] = new_accessors
    gltf["buffers"] = [{"byteLength": len(new_blob)}]
    return bytes(new_blob)


def filter_animations(gltf: dict, keep_names: set[str]) -> None:
    if not keep_names:
        return
    keep_lower = {name.lower() for name in keep_names}
    kept = [anim for anim in gltf.get("animations", []) if str(anim.get("name", "")).lower() in keep_lower]
    found = {str(anim.get("name", "")).lower() for anim in kept}
    missing = keep_lower - found
    if missing:
        raise SystemExit(f"Missing animations: {sorted(missing)}")
    gltf["animations"] = kept


def slim(path: Path, keep_names: set[str], force_png: bool = False) -> None:
    before = path.stat().st_size
    gltf, blob = load_glb(path)
    replacements = resize_images(gltf, blob, force_png=force_png)
    filter_animations(gltf, keep_names)
    blob = compact(gltf, blob, replacements)
    save_glb(path, gltf, blob)
    after = path.stat().st_size
    names = [anim.get("name") for anim in gltf.get("animations", [])]
    print(f"{path.name}: {before / 1024 / 1024:.2f} MB -> {after / 1024 / 1024:.2f} MB  clips={names}")


def resize_png(path: Path) -> None:
    before = path.stat().st_size
    image = Image.open(path)
    image.load()
    payload, _mime = encode_texture(image, force_png=True)
    path.write_bytes(payload)
    after = path.stat().st_size
    print(f"{path.name}: {before / 1024 / 1024:.2f} MB -> {after / 1024 / 1024:.2f} MB")


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "godot" / "assets" / "models"
    slim(root / "player_red_robe.glb", {"spelling_idle", "standing_2h_magic_attack_03"})
    slim(root / "scarecrow.glb", {"idle"}, force_png=True)
    for png in root.glob("*.png"):
        resize_png(png)


if __name__ == "__main__":
    main()
