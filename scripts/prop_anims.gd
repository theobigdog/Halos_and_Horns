# Animated props (Ted's prop list, Nov 26: "about 35% of props animatable"; his spreadsheet says which and
# what they do). A demon disguised as one presses E (the "animate" key) to make it do its thing: light or
# snuff a candle, take a bite, pop a cork, open a chest a crack, spill the coins...
#
# How it works: PropLib.make_visual() calls dress() on every prop it builds, real ones and disguises alike,
# so a lit candle looks the same either way. press() plays the n-th press on a visual (the demon's own, and
# on every other screen the host's "prop_anim" message). Toggles go by whether n is odd or even, so a missed
# message can't leave screens disagreeing for long. It's all visuals: nothing here changes a prop's shape,
# and it never runs on a real prop, only on a disguise (or a practice bot).
#
# The KayKit models are mostly one solid mesh, but their loose bits (coins, plates, corks, pillows, carrots,
# candle wicks) are separate "islands" of triangles. islands() finds them once per model (cached), and
# prop_animator.gd lifts the ones it needs out into their own MeshInstances to move them.
extends RefCounted

const Models = preload("res://scripts/models.gd")
const Animator = preload("res://scripts/prop_animator.gd")

# kind -> what the hint says ("E: <verb>")
const VERBS := {
	"light": "light it / put it out", "lamp": "switch it on / off", "lid": "peek out", "fridge": "open the door",
	"oven": "open / shut the door", "bite": "take a bite", "hop": "rattle the dishes", "spill": "spill the coins",
	"disarray": "mess it up", "dirty": "dirty / clean the dishes", "blood": "bloody it", "squirt": "squirt",
	"scribble": "scribble on it", "unroll": "unroll it", "burners": "light the burners", "drain": "pour some out",
	"cork": "pop the cork", "bed": "unmake / make the bed", "sofabed": "pull out the bed", "recline": "put your feet up",
	"picture": "change the picture", "ooze": "ooze", "rock": "rock", "fuse": "LIGHT THE FUSE (you'll blow up!)",
	"jack": "light / snuff the candle", "swarm": "stir up the bees",
}

# The explosives (Ted, Nov 26: "they result in the possessed demon exploding and dying as well... it could even
# stun the angels for a second or two"). First guesses.
const FUSE_TIME := 1.5       # s from pressing E to the bang
const KABOOM_RADIUS := 6.0   # m: angels this close are dazed
const KABOOM_DAZE := 1.5     # s they can't move or throw
const COOLDOWN := 0.5        # s between presses (the host allows a little less)

static var TABLE := _build()


static func _build() -> Dictionary:
	var t := {}
	# Lights. "on": lit to begin with (otherwise: lit if the model has a flame of its own).
	# "at": where a flame goes when the model has no wick to put it on.
	t["lamp"] = {"kind": "lamp", "classic": true, "on": true}
	for id in ["furniture/lamp_standing", "furniture/lamp_table"]:
		t[id] = {"kind": "lamp", "on": false}
	for id in ["halloween/candle", "halloween/candle_melted", "halloween/candle_thin", "halloween/candle_triple",
			"dungeon/candle", "dungeon/candle_lit", "dungeon/candle_melted", "dungeon/candle_thin",
			"dungeon/candle_thin_lit", "dungeon/candle_triple", "dungeon/table_small_decorated_A", "dungeon/torch_lit"]:
		t[id] = {"kind": "light"}
	t["dungeon/torch"] = {"kind": "light", "at": [Vector3(0.0, 0.7, 0.0)], "flame": 2.6}
	t["halloween/skull_candle"] = {"kind": "light", "on": true}
	t["halloween/shrine_candles"] = {"kind": "light", "on": true}
	t["halloween/lantern_standing"] = {"kind": "light", "on": true, "at": [Vector3(0.0, 0.3, 0.0)], "flame": 1.4}
	t["halloween/bench_decorated"] = {"kind": "light", "on": false, "at": [Vector3(-0.44, 0.62, 0.0)], "flame": 1.4}
	# Chests and trunks: the lid lifts a crack and drops shut.
	for id in ["dungeon/chest", "dungeon/chest_gold"]:
		t[id] = {"kind": "lid", "node": "chest_lid"}
	for size in ["large", "medium", "small"]:
		for v in ["A", "B", "C"]:
			t["dungeon/trunk_%s_%s" % [size, v]] = {"kind": "lid", "seam": 0.56}
	for id in ["restaurant/fridge_A", "restaurant/fridge_A_decorated", "restaurant/fridge_B"]:
		t[id] = {"kind": "fridge"}
	t["restaurant/oven"] = {"kind": "oven"}
	# Food. "food": which islands can be bitten (colourful ones, unless "dull"), "min_y" above the table/plate,
	# "max_h" skips tall things (bottles), "r": bite size.
	t["restaurant/food_dinner"] = {"kind": "bite", "r": 0.12}
	t["restaurant/food_ingredient_ham_cooked"] = {"kind": "bite", "r": 0.16}
	t["restaurant/food_ingredient_ham_trash"] = {"kind": "bite", "r": 0.16, "dull": true, "gag": true}
	t["restaurant/table_round_A_decorated"] = {"kind": "bite", "r": 0.13, "min_y": 0.83, "max_h": 0.35}
	t["dungeon/plate_food_A"] = {"kind": "bite", "r": 0.13}
	t["restaurant/dishrack_plates"] = {"kind": "hop", "pick": [Color("d3dadd")]}
	t["dungeon/plate_stack"] = {"kind": "hop"}
	for id in ["dungeon/coin_stack_large", "dungeon/coin_stack_medium", "dungeon/coin_stack_small"]:
		t[id] = {"kind": "spill"}
	t["dungeon/table_small_decorated_B"] = {"kind": "spill", "min_y": 0.74}
	t["restaurant/kitchentable_A_large_decorated"] = {"kind": "disarray", "min_y": 0.74}
	t["restaurant/kitchentable_sink_large_decorated"] = {"kind": "dirty", "min_y": 0.48}
	t["restaurant/knife"] = {"kind": "blood"}
	t["restaurant/ketchup"] = {"kind": "squirt", "color": Color(0.75, 0.05, 0.03)}
	t["restaurant/mustard"] = {"kind": "squirt", "color": Color(0.95, 0.72, 0.08)}
	t["restaurant/menu"] = {"kind": "scribble"}
	t["restaurant/papertowel"] = {"kind": "unroll"}
	for id in ["restaurant/stove_multi", "restaurant/stove_multi_decorated", "restaurant/stove_single"]:
		t[id] = {"kind": "burners"}
	t["dungeon/keg"] = {"kind": "drain"}
	for b in ["A_brown", "A_green", "A_labeled_brown", "A_labeled_green", "B_brown", "B_green", "C_brown", "C_green"]:
		t["dungeon/bottle_" + b] = {"kind": "cork"}
	for id in ["furniture/bed_double_B", "furniture/bed_single_B"]:
		t[id] = {"kind": "bed", "pillow": Color("dee4e6"), "blanket": Color("5f9bcd")}
	for id in ["dungeon/bed_decorated", "dungeon/bed_frame"]:
		t[id] = {"kind": "bed", "pillow": Color("d6c7b8"), "blanket": Color("8d837c")}
	t["furniture/couch_pillows"] = {"kind": "sofabed"}
	t["furniture/armchair_pillows"] = {"kind": "recline"}
	for id in ["furniture/pictureframe_standing_A", "furniture/pictureframe_standing_B"]:
		t[id] = {"kind": "picture"}
	# (the pickle has no E action: it just leaves its slime trail when it moves, slime_trail.gd; Ted, Nov 27)
	# New props (extra_props.gd)
	t["rocking_chair"] = {"kind": "rock"}
	t["beehive"] = {"kind": "swarm"}   # (Ted's wife, Nov 27)
	for id in ["tnt_crate", "dynamite_bundle", "powder_keg"]:
		t[id] = {"kind": "fuse"}
	for id in ["jack_o_lantern_grin", "jack_o_lantern_scary", "jack_o_lantern_goofy"]:
		t[id] = {"kind": "jack", "on": true}
	return t


static func entry(type_name: String) -> Dictionary:
	return TABLE.get(type_name.get_slice("!", 0).get_slice("#", 0).get_slice("@", 0), {})


static func kind(type_name: String) -> String:
	return entry(type_name).get("kind", "")


static func can_animate(type_name: String) -> bool:
	return kind(type_name) != ""


# Kinds that stay the way they were left (a lit candle, an open oven, a messy table): a prop placed on a map
# can start the round in either state (Ted, Nov 26), set in Creative. Everything starts "off".
const STATEFUL := ["light", "lamp", "jack", "oven", "spill", "disarray", "dirty", "blood", "bed", "sofabed",
		"recline", "picture", "swarm"]
const PICTURES := 4   # (the pictures "picture" goes through, after the one it came with)


static func has_state(type_name: String) -> bool:
	return kind(type_name) in STATEFUL


# How many states it has: 2 for on/off, more for the picture.
static func state_count(type_name: String) -> int:
	return PICTURES + 1 if kind(type_name) == "picture" else (2 if has_state(type_name) else 1)


# What a placed prop's state is called in Creative.
static func state_name(type_name: String, n: int) -> String:
	match kind(type_name):
		"light", "lamp", "jack": return "lit" if n % 2 == 1 else "out"
		"oven", "sofabed": return "open" if n % 2 == 1 else "shut"
		"recline": return "reclined" if n % 2 == 1 else "upright"
		"bed": return "unmade" if n % 2 == 1 else "made"
		"swarm": return "swarming" if n % 2 == 1 else "quiet"
		"spill": return "spilled" if n % 2 == 1 else "stacked"
		"disarray": return "messy" if n % 2 == 1 else "tidy"
		"dirty": return "dirty" if n % 2 == 1 else "clean"
		"blood": return "bloody" if n % 2 == 1 else "clean"
		"picture": return "its own picture" if n == 0 else "picture %d" % ((n - 1) % PICTURES + 1)
	return ""


# Put a prop straight into its n-th state (quietly: no sounds as a round starts).
static func set_state(visual: Node3D, type_name: String, n: int) -> void:
	if n <= 0 or not has_state(type_name) or not is_instance_valid(visual):
		return
	var a := _animator(visual, type_name)
	a.quiet = true
	a.press(n)
	a.quiet = false


static func is_explosive(type_name: String) -> bool:
	return kind(type_name) == "fuse"


static func verb(type_name: String) -> String:
	return VERBS.get(kind(type_name), "")


# Called on every prop visual as it's built: things that look different from the start (a lit candle gets
# its flame, a jack-o'-lantern glows) are set up here, so real props and disguises match.
static func dress(visual: Node3D, type_name: String) -> void:
	var e := entry(type_name)
	if e.is_empty():
		return
	if e["kind"] in ["light", "lamp", "jack"]:
		_animator(visual, type_name)


# The n-th press of E on this visual (n = 1, 2, 3...).
static func press(visual: Node3D, type_name: String, n: int) -> void:
	if not is_instance_valid(visual) or not can_animate(type_name):
		return
	_animator(visual, type_name).press(n)


static func _animator(visual: Node3D, type_name: String) -> Node3D:
	var a := visual.get_node_or_null("PropAnim")
	if a == null:
		a = Animator.new()
		a.name = "PropAnim"
		a.setup(type_name.get_slice("!", 0).get_slice("#", 0).get_slice("@", 0), entry(type_name), visual)
		visual.add_child(a)
	return a


# ---------- islands: each model's loose pieces ----------

# [{mi: path from the holder, s: surface, tris: PackedInt32Array (triangle numbers), box: AABB (holder space),
#   col: Color (texture colour under it), top: Vector3 (its highest point)}], cached per model.
static var _islands := {}


static func islands(id: String, holder: Node3D) -> Array:
	if _islands.has(id):
		return _islands[id]
	var out := []
	for c in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if not mi.mesh is ArrayMesh or mi.get_parent() is Animator:
			continue
		var xf := Models._to_holder(mi, holder)
		var mesh: ArrayMesh = mi.mesh
		for si in mesh.get_surface_count():
			out.append_array(_surface_islands(mesh, si, xf, holder.get_path_to(mi)))
	_islands[id] = out
	return out


static func _surface_islands(mesh: ArrayMesh, si: int, xf: Transform3D, path: NodePath) -> Array:
	var mat := mesh.surface_get_material(si) as StandardMaterial3D
	var img: Image = Models._image_of(mat.albedo_texture) if mat != null and mat.albedo_texture != null else null
	var arr := mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	var idx = arr[Mesh.ARRAY_INDEX]
	var n: int = idx.size() if idx != null else verts.size()
	var vi := func(k: int) -> int: return idx[k] if idx != null else k
	# weld vertices by position, then join each triangle's corners (union-find)
	var key_of := {}
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	for i in verts.size():
		var k := Vector3i((verts[i] * 2000.0).round())
		if not key_of.has(k):
			key_of[k] = key_of.size()
		weld[i] = key_of[k]
	var parent := PackedInt32Array()
	parent.resize(key_of.size())
	for i in parent.size():
		parent[i] = i
	for t in n / 3:
		var a := _root(parent, weld[vi.call(t * 3)])
		for j in [1, 2]:
			var b := _root(parent, weld[vi.call(t * 3 + j)])
			if a != b:
				parent[b] = a
	var by_root := {}
	for t in n / 3:
		var r := _root(parent, weld[vi.call(t * 3)])
		if not by_root.has(r):
			by_root[r] = {"mi": path, "s": si, "tris": PackedInt32Array(), "box": AABB(xf * verts[vi.call(t * 3)], Vector3.ZERO),
					"csum": Color(0, 0, 0, 0), "top": xf * verts[vi.call(t * 3)]}
		var d: Dictionary = by_root[r]
		d["tris"].append(t)
		for j in 3:
			var p: Vector3 = xf * verts[vi.call(t * 3 + j)]
			d["box"] = (d["box"] as AABB).expand(p)
			if p.y > d["top"].y:
				d["top"] = p
		if img != null and uvs != null:
			var uv: Vector2 = (uvs[vi.call(t * 3)] + uvs[vi.call(t * 3 + 1)] + uvs[vi.call(t * 3 + 2)]) / 3.0
			d["csum"] += _texel(img, uv)
	var out := []
	for d in by_root.values():
		d["col"] = (d["csum"] / float(d["tris"].size())) if d["csum"].a > 0.0 else Color(0.5, 0.5, 0.5)
		d.erase("csum")
		out.append(d)
	return out


static func _root(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


static func _texel(img: Image, uv: Vector2) -> Color:
	return img.get_pixelv(Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
			clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)))


# Per-triangle detail for one island (centre and colour in holder space), for finer cuts (a cork, a blade).
static func triangles(holder: Node3D, isl: Dictionary) -> Array:
	var mi: MeshInstance3D = holder.get_node(isl["mi"])
	var xf := Models._to_holder(mi, holder)
	var mesh: ArrayMesh = mi.mesh
	var mat := mesh.surface_get_material(isl["s"]) as StandardMaterial3D
	var img: Image = Models._image_of(mat.albedo_texture) if mat != null and mat.albedo_texture != null else null
	var arr := mesh.surface_get_arrays(isl["s"])
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	var idx = arr[Mesh.ARRAY_INDEX]
	var out := []
	for t in isl["tris"]:
		var k := [idx[t * 3] if idx != null else t * 3, idx[t * 3 + 1] if idx != null else t * 3 + 1, idx[t * 3 + 2] if idx != null else t * 3 + 2]
		var c: Vector3 = xf * ((verts[k[0]] + verts[k[1]] + verts[k[2]]) / 3.0)
		var col := Color(0.5, 0.5, 0.5)
		if img != null and uvs != null:
			col = _texel(img, (uvs[k[0]] + uvs[k[1]] + uvs[k[2]]) / 3.0)
		out.append({"t": t, "c": c, "col": col, "v": [xf * verts[k[0]], xf * verts[k[1]], xf * verts[k[2]]]})
	return out


# A copy of a surface keeping only (or dropping) the given triangles. Cached by key.
static var _meshes := {}


# mats: the material each surface really draws with (its MeshInstance's override, baked in, since surfaces
# that end up empty are dropped and the numbering shifts).
static func sub_mesh(src: ArrayMesh, keep: Dictionary, mats: Array, key: String) -> ArrayMesh:
	for m in mats:
		key += ":%d" % (m.get_instance_id() if m != null else 0)
	if _meshes.has(key):
		return _meshes[key]
	# keep: surface -> PackedInt32Array of triangle numbers to keep (surfaces not listed are dropped)
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		if not keep.has(si) or (keep[si] as PackedInt32Array).is_empty():
			continue
		var arr := src.surface_get_arrays(si)
		var idx = arr[Mesh.ARRAY_INDEX]
		var ni := PackedInt32Array()
		for t in keep[si]:
			for j in 3:
				ni.append(idx[t * 3 + j] if idx != null else t * 3 + j)
		arr[Mesh.ARRAY_INDEX] = ni
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mats[si])
	_meshes[key] = out
	return out


static func colour_near(a: Color, b: Color, tol := 0.07) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol
