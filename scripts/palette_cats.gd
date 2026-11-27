# Creative's palette categories (Ted's wife, Nov 27: "Organize props and structures menus into the following
# categories... If some props fit in multiple places, list it in both"). cats() gives every category a prop or
# structure belongs in, from its name and the model pack it came from. Anything that fits nowhere is "Other".
extends RefCounted

const ORDER := ["Buildings", "Castle", "Decorations", "Dungeon", "Explosives", "Fences/pillars/walls", "Food",
		"Furniture", "Graveyard", "Ground", "Kitchen", "Lighting", "Plants/landscaping", "Signs", "Street/Road",
		"Weapons", "Other"]

# name fragment -> categories (checked against the name without its pack)
const WORDS := [
	[["tnt", "dynamite", "powder_keg"], ["Explosives"]],
	[["food_", "crate_buns", "crate_carrots", "crate_cheese", "crate_ham", "crate_lettuce", "crate_onions",
			"crate_potatoes", "crate_steak", "crate_tomatoes", "apple", "pickle", "plate_food", "ketchup", "mustard",
			"coconut", "pot_a_stew", "pot_b_stew"], ["Food"]],
	[["bowl", "plate", "pan_", "pot_", "lid_", "knife", "cuttingboard", "dishrack", "fridge", "oven", "stove",
			"kitchen", "jar_", "papertowel", "menu", "ketchup", "mustard", "extractorhood", "towelrail",
			"orderwindow", "floor_kitchen"], ["Kitchen"]],
	[["chair", "stool", "table", "bed_", "couch", "armchair", "cabinet", "shelves", "shelf", "bench", "pillow",
			"trunk", "chest", "kitchentable", "wall_shelves", "rocking"], ["Furniture"]],
	[["candle", "lamp", "lantern", "torch", "streetlight", "jack_o_lantern", "jackolantern"], ["Lighting"]],
	[["pictureframe", "rug_", "banner", "flag_", "book", "pillow", "plaque", "skull", "coin", "keyring", "key",
			"bottle", "shrine", "ribcage", "bone_", "jack_o_lantern", "jackolantern", "pumpkin", "keg_decorated",
			"snowman", "snowball"], ["Decorations"]],
	[["bush", "flower", "fern", "cactus", "tree_", "trees_", "oak", "birch", "waterlily", "waterplant", "hill", "mountain",
			"rock_", "hay", "wheelbarrow", "resource_stone", "beehive", "coconut", "snowball", "snowman"], ["Plants/landscaping"]],
	[["car_", "dumpster", "firehydrant", "road_", "streetlight", "trafficlight", "trash_", "wheelie", "parking",
			"sidewalk", "sign_"], ["Street/Road"]],
	[["sign_"], ["Signs"]],
	[["building_", "crypt", "tent", "watertower", "stairs", "ladder", "scaffold"], ["Buildings"]],
	[["fence", "pillar", "column", "wall", "barrier", "post", "arch_gate", "gate", "door_"], ["Fences/pillars/walls"]],
	[["weaponrack", "sword", "target", "projectile_catapult", "catapult"], ["Weapons"]],
	[["coffin", "grave", "crypt", "skull", "bone_", "ribcage", "pumpkin", "jack_o_lantern", "shrine", "tree_dead",
			"post_skull"], ["Graveyard"]],
	[["building_castle", "building_tower", "building_barracks", "building_archeryrange", "flag_", "banner",
			"wall_straight", "wall_corner_a", "wall_corner_b", "catapult", "target", "weaponrack"], ["Castle"]],
]

# Whole-pack extras: everything from the Halloween pack is graveyard-ish, the dungeon pack is the dungeon.
const PACKS := {"halloween": ["Graveyard"], "dungeon": ["Dungeon"], "city": ["Street/Road"]}


static func cats(id: String, is_ground := false) -> Array:
	var pack := id.get_slice("/", 0) if "/" in id else ""
	var name := (id.get_slice("/", 1) if "/" in id else id).to_lower()
	var out := []
	for rule in WORDS:
		for w in rule[0]:
			if w in name:
				for c in rule[1]:
					if not c in out:
						out.append(c)
				break
	for c in PACKS.get(pack, []):
		if not c in out and not (pack == "city" and (name.begins_with("building_") or name == "watertower") and c == "Street/Road"):
			out.append(c)
	if is_ground or name.begins_with("floor_") or name.begins_with("path_"):
		if not "Ground" in out:
			out.append("Ground")
		out.erase("Fences/pillars/walls")
	# a few that the words get wrong
	if name == "arch":
		out = ["Fences/pillars/walls", "Graveyard"]
	if name == "pot":
		out = ["Kitchen"]
	if name in ["bed_floor"]:
		out = ["Furniture", "Dungeon"]
	if name.begins_with("wall_orderwindow"):
		out = ["Kitchen", "Fences/pillars/walls"]
	if name == "key" or name.begins_with("keyring"):
		out.erase("Kitchen")
	if out.is_empty():
		out.append("Other")
	return out


# Sorted in ORDER.
static func sort(names: Array) -> Array:
	var out := names.duplicate()
	out.sort_custom(func(a, b): return ORDER.find(a) < ORDER.find(b))
	return out
