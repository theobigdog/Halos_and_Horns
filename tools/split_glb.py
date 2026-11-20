"""Turns a folder's .glb models into .gltf + .bin that all share one texture file.

The Dungeon pack ships every model with its own copy of the same texture inside; Godot would load
200 copies of it. Usage:  python tools/split_glb.py assets/kaykit/dungeon dungeon_texture.png
(the shared texture is written once, from the first model).
"""
import json
import os
import struct
import sys


def split(path, texture_name, folder):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    pos = 20 + jlen
    blen = struct.unpack("<I", data[pos:pos + 4])[0]
    binary = data[pos + 8:pos + 8 + blen]
    image_views = {img["bufferView"] for img in doc.get("images", []) if "bufferView" in img}
    tex_path = os.path.join(folder, texture_name)
    if not os.path.exists(tex_path):
        v = doc["bufferViews"][next(iter(image_views))]
        off = v.get("byteOffset", 0)
        open(tex_path, "wb").write(binary[off:off + v["byteLength"]])
    new_bin = bytearray()
    remap = {}
    views = []
    for i, v in enumerate(doc["bufferViews"]):
        if i in image_views:
            continue
        while len(new_bin) % 4:
            new_bin.append(0)
        off = v.get("byteOffset", 0)
        chunk = binary[off:off + v["byteLength"]]
        v = dict(v)
        v["byteOffset"] = len(new_bin)
        new_bin += chunk
        remap[i] = len(views)
        views.append(v)
    doc["bufferViews"] = views
    for a in doc.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
    for img in doc.get("images", []):
        img.pop("bufferView", None)
        img.pop("mimeType", None)
        img["uri"] = texture_name
    stem = os.path.basename(path).split(".")[0]
    doc["buffers"] = [{"byteLength": len(new_bin), "uri": stem + ".bin"}]
    open(os.path.join(folder, stem + ".bin"), "wb").write(new_bin)
    with open(os.path.join(folder, stem + ".gltf"), "w", newline="\n") as f:
        json.dump(doc, f)


def main():
    folder, texture_name = sys.argv[1], sys.argv[2]
    n = 0
    for name in sorted(os.listdir(folder)):
        if name.endswith(".glb"):
            split(os.path.join(folder, name), texture_name, folder)
            os.remove(os.path.join(folder, name))
            n += 1
    print("split %d models" % n)


if __name__ == "__main__":
    main()
