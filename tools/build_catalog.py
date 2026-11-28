"""Builds assets/kaykit/catalog.json from tools/model_sizes.json (made by tools/measure_models.gd).

Every KayKit model becomes either a PROP (demons can possess it, it can be knocked around, its health,
speed and weight come from its size) or a STRUCTURE (solid scenery placed in Creative mode: walls with
real doorways, stairs, buildings, trees...). The rules below decide which, and how big each pack is
scaled to our metres. Run it after adding models:  python tools/build_catalog.py
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Each pack: the category shown in Creative mode, and how much to scale it so it fits our world
# (an angel is 1.7 m tall, a doorway about 2.1 m).
PACKS = {
    "halloween": ("Graveyard", 0.75),
    "furniture": ("Furniture", 0.75),
    "restaurant": ("Kitchen & food", 0.75),
    "dungeon": ("Dungeon & castle", 0.75),
    "city": ("Town", 4.5),
    "medieval": ("Village & nature", 6.0),
}

# Never shown: duplicates and things that make no sense here.
SKIP = [
    r"^city/building_[A-H]$",               # the versions with a sidewalk tile under them
    r"^city/base$",
    r"^medieval/cloud_",
    r"^dungeon/banner_(.*_)?(brown|green|white|yellow)$",   # keep red and blue banners only
    r"^medieval/(crate_|barrel$|bucket_|pallet$|sack$)",   # tiny duplicates of the dungeon ones
    r"^restaurant/stew_(bowl|pot)$",
]

# Always scenery, whatever the size: building parts, things that hang on walls, ground cover.
STRUCTURE = [
    r"wall", r"floor", r"stairs", r"building", r"tree", r"fence", r"road", r"path_", r"pillar", r"column",
    r"arch", r"crypt", r"rug_", r"mountain", r"hill", r"barrier", r"rubble", r"foundation", r"door",
    r"kitchencounter", r"kitchencabinet", r"extractorhood", r"countertop", r"banner", r"_mounted",
    r"_hanging", r"sword_shield", r"towelrail", r"shelf", r"pictureframe_(large|medium|small)", r"post",
    r"plaque", r"streetlight", r"trafficlight", r"watertower", r"ladder", r"waterlily", r"waterplant",
    r"trees_", r"lid$", r"crate_lid", r"firehydrant", r"dumpster",   # (Sara, Nov 25: structures, not props)
]

ROUND = [r"pumpkin", r"skull$", r"tomato$", r"onion$", r"^medieval/rock", r"coin$"]

PROP_MAX_WIDE = 2.6     # metres: anything bigger than this is scenery, not a disguise
PROP_MAX_TALL = 2.6

LABEL_FIX = {"seperate": "separate", "colum": "column", "jackolantern": "jack-o'-lantern",
             "Tsplit": "T split", "archedwindow": "arched window", "orderwindow": "order window",
             "papertowel": "paper towel", "cuttingboard": "cutting board", "dishrack": "dish rack",
             "firehydrant": "fire hydrant", "trafficlight": "traffic light", "streetlight": "street light",
             "watertower": "water tower", "kitchencounter": "kitchen counter", "kitchencabinet": "kitchen cabinet",
             "kitchentable": "kitchen table", "extractorhood": "extractor hood", "innercorner": "inner corner",
             "outercorner": "outer corner", "towelrail": "towel rail", "pictureframe": "picture frame",
             "vegetableburger": "veggie burger", "stationwagon": "station wagon", "weaponrack": "weapon rack",
             "gravemarker": "grave marker", "archeryrange": "archery range", "lumbermill": "lumber mill",
             "watermill": "water mill", "dirt": "dirt", "withoutBase": "", "backsplash": "with backsplash"}


def label(name):
    if re.match(r"building_[A-H]_", name):
        name = "town_" + name                 # city buildings are just lettered
    if name.startswith("building_"):
        name = re.sub(r"_blue$", "", name)   # (we only took the blue village)
    name = re.sub(r"^(food_ingredient_|food_|building_)", "", name)
    words = []
    for w in name.split("_"):
        w = LABEL_FIX.get(w, w)
        if w:
            words.append(w)
    text = " ".join(words)
    return text[:1].upper() + text[1:]


def main():
    sizes = json.load(open(os.path.join(HERE, "model_sizes.json")))
    out = []
    for path in sorted(sizes):
        rel = path.replace("res://assets/kaykit/", "")
        pack, fname = rel.split("/")
        name = fname.split(".")[0]
        key = pack + "/" + name
        if any(re.search(p, key) for p in SKIP):
            continue
        cat, scale = PACKS[pack]
        s = [v * scale for v in sizes[path]["size"]]
        lo = [v * scale for v in sizes[path]["pos"]]
        kind = "prop"
        if any(re.search(p, name) for p in STRUCTURE) or max(s[0], s[2]) > PROP_MAX_WIDE or s[1] > PROP_MAX_TALL:
            kind = "structure"
        entry = {
            "id": key, "path": path, "label": label(name), "cat": cat, "kind": kind, "scale": scale,
            "size": [round(v, 3) for v in s],
            # where the model's own origin sits relative to its bottom-centre (we stand everything on y = 0)
            "offset": [round(-(lo[0] + s[0] / 2), 3), round(-lo[1], 3), round(-(lo[2] + s[2] / 2), 3)],
        }
        if kind == "prop" and any(re.search(p, key) for p in ROUND):
            entry["round"] = True
        out.append(entry)
    # Our own variations on a model (built in models.gd): the road with the crosswalk at one end.
    for e in list(out):
        if e["id"] == "city/road_straight":
            extra = dict(e)
            extra.update({"id": "city/road_crossing_end", "label": "Road crossing (at the end)", "extra": "crosswalk_end"})
            out.append(extra)
        # vehicles built in code (vehicles.gd; Sara, Nov 27): pickup, motorcycle, bus, ambulance, fire truck
        if e["id"] == "city/car_sedan":
            for vid, vlabel, vsize in [("city/car_pickup", "Pickup truck", [2.4, 2.1, 4.9]), ("city/car_motorcycle", "Motorcycle", [0.7, 1.1, 2.1]),
                    ("city/car_bus", "Bus", [2.6, 3.0, 8.7]), ("city/car_ambulance", "Ambulance", [2.4, 2.6, 5.3]),
                    ("city/car_firetruck", "Fire truck", [2.6, 2.8, 7.3])]:
                extra = dict(e)
                extra.update({"id": vid, "label": vlabel, "size": vsize, "offset": [0.0, 0.0, 0.0], "extra": "built"})
                out.append(extra)
        # a lantern post standing on a stone base (refined_graveyard.gd; Sara, Nov 28, with a picture).
        # (NOTE: running this script puts the extras in a different order from the catalog in the repo, which
        # changes Creative's list order: this entry was put into catalog.json by hand, next to post_lantern.)
        if e["id"] == "halloween/post_lantern":
            extra = dict(e)
            extra.update({"id": "halloween/post_lantern_base", "label": "Post lantern (stone base)", "size": [0.5, 2.95, 1.2], "extra": "built"})
            out.append(extra)
        # a street light with a bad bulb that flickers (Ted's wife, Nov 27)
        if e["id"] == "city/streetlight":
            extra = dict(e)
            extra.update({"id": "city/streetlight_flicker", "label": "Street light (flickering)", "extra": "flicker"})
            out.append(extra)
        # green versions of the yellow (autumn) pines (Wife's notes, Nov 21)
        if e["id"].startswith("halloween/tree_pine_yellow_"):
            extra = dict(e)
            size_name = e["id"].rsplit("_", 1)[1]
            extra.update({"id": "halloween/tree_pine_green_" + size_name, "label": "Tree pine green " + size_name, "extra": "green"})
            out.append(extra)
    with open(os.path.join(ROOT, "assets", "kaykit", "catalog.json"), "w", newline="\n") as f:
        json.dump(out, f, indent=0)
    props = sum(1 for e in out if e["kind"] == "prop")
    print("%d models: %d props, %d structures" % (len(out), props, len(out) - props))


if __name__ == "__main__":
    main()
