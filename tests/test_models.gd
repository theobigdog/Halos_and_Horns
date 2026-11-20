# The model catalog (KayKit props and structures), structures in a map, and the three bouncy pads.
#   godot --headless -s res://tests/test_models.gd
extends SceneTree

const Models = preload("res://scripts/models.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const MapData = preload("res://scripts/map_data.gd")
const Bouncy = preload("res://scripts/bouncy.gd")

var main: Node
var failures := 0


func _initialize() -> void:
	seed(20261119)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func mesh_box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b: AABB = (n.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func ray_hits(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return not main.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func bounce_peak(pad: Vector3) -> float:
	var player = main.player
	player.global_position = pad + Vector3(0, 0.1, -2.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.pivot.rotation = Vector3.ZERO
	await frames(10)
	player.test_input = {"dir": Vector2(0, 1)}
	var peak := 0.0
	for k in 150:
		await frames(1)
		peak = maxf(peak, player.global_position.y - pad.y)
		if peak > 1.0:
			player.test_input = {}
	player.test_input = {}
	return peak


func _run() -> void:
	await frames(5)

	# ---- The catalog ----
	var props := Models.ids("prop")
	var structures := Models.ids("structure")
	check(props.size() > 200 and structures.size() > 200, "the catalog has lots of props (%d) and structures (%d)" % [props.size(), structures.size()])
	var broken := []
	var off_centre := []
	for id in Models.ids():
		var n := Models.instance(id)
		root.add_child(n)
		var b := mesh_box(n)
		if n.find_children("*", "MeshInstance3D", true, false).is_empty():
			broken.append(id)
		elif absf(b.position.y) > 0.05 or absf(b.get_center().x) > 0.05 or absf(b.get_center().z) > 0.05:
			off_centre.append(id)
		n.free()
	check(broken.is_empty(), "every model loads and has something to see %s" % [broken.slice(0, 5)])
	check(off_centre.is_empty(), "every model stands on the ground, centred %s" % [off_centre.slice(0, 5)])
	check(PropLib.TYPES.has("halloween/coffin") and PropLib.TYPES.has("barrel"), "model props join the classic ones in the prop list")
	var gs: Dictionary = PropLib.TYPES["halloween/gravestone"]
	var coin: Dictionary = PropLib.TYPES["dungeon/coin"]
	check(coin["hp"] < gs["hp"] and coin["speed"] > gs["speed"] and coin["mass"] < gs["mass"],
		"small model props are fragile and quick, bigger ones tanky (coin %d hp, gravestone %d hp)" % [coin["hp"], gs["hp"]])
	check(PropLib.scatter_names().size() == PropLib.CLASSIC.size(), "random scatter still uses the classic props")

	# ---- Maps: structures go in, junk doesn't ----
	var raw := {"name": "Model test", "size": 28, "pieces": [
		{"type": "model", "model": "restaurant/wall_doorway", "pos": [0, 0, -10]},
		{"type": "model", "model": "dungeon/wall", "pos": [8, 0, -10]},
		{"type": "model", "model": "dungeon/stairs", "pos": [-12, 0, -10], "size": [1, 1, 1]},
		{"type": "model", "model": "halloween/crypt", "pos": [-14, 0, 12], "size": [50, 0, 1]},
		{"type": "model", "model": "nope/not_real", "pos": [0, 0, 0]},
		{"type": "prop", "prop": "halloween/coffin", "pos": [4, 0, 4]},
		{"type": "bouncy", "pos": [-6, 0, 18]},
		{"type": "bouncy_super", "pos": [6, 0, 18]},
		{"type": "angel_spawn", "pos": [0, 0.1, -20]}, {"type": "demon_spawn", "pos": [0, 0.1, 0]},
	]}
	var map: Dictionary = MapData.clean(raw)
	var models: Array = map["pieces"].filter(func(p): return p["type"] == "model")
	check(models.size() == 4, "a map keeps real structures and drops unknown ones (%d kept)" % models.size())
	var crypt = models.filter(func(p): return p["model"] == "halloween/crypt")[0]
	check(crypt["size"] == [10.0, 0.1, 1.0], "...and a structure's scale is kept sensible (%s)" % [crypt["size"]])
	check(map["pieces"].any(func(p): return p["type"] == "bouncy_super"), "super-bouncy pads are a map piece")
	check(MapData.clean(MapData.from_text(MapData.to_text(map))) == map, "a map with structures saves and loads unchanged")

	main.role = "demon"
	main.load_map(raw)
	main.start_practice()
	await frames(20)

	# ---- Structures are solid in their real shape ----
	check(not ray_hits(Vector3(0, 1.0, -12), Vector3(0, 1.0, -8)), "you can walk through an open doorway")
	check(ray_hits(Vector3(8, 1.0, -12), Vector3(8, 1.0, -8)), "...but not through a plain wall")
	var stairs_top: Vector3 = main.ground_below(Vector3(-12, 10, -10))
	check(stairs_top.y > 0.5, "stairs are something to stand on (%.1f m up)" % stairs_top.y)

	# ---- A demon can be a model prop ----
	var player = main.player
	player.force_possess("halloween/gravestone")
	await frames(3)
	var shape = player.shape_node.shape
	check(shape is BoxShape3D and (shape.size as Vector3).is_equal_approx(PropLib.TYPES["halloween/gravestone"]["size"]),
		"possessing a gravestone gives you its shape")
	check(player.visual_root.find_children("*", "MeshInstance3D", true, false).size() > 0, "...and its look")
	player.unpossess()
	await frames(3)

	# ---- Bouncy pads: wooden one-use, metal, and the magic super one ----
	var kinds := {}
	for kind in ["wood", "metal", "super"]:
		var b := Bouncy.new()
		b.one_use = kind == "wood"
		b.super_bouncy = kind == "super"
		root.add_child(b)
		kinds[kind] = b
	await frames(2)
	var wood_mat: StandardMaterial3D = kinds["wood"]._top.material_override
	var metal_mat: StandardMaterial3D = kinds["metal"]._top.material_override
	check(wood_mat.albedo_texture != null and wood_mat.metallic < 0.2, "the one-use pad is textured wood")
	check(metal_mat.albedo_texture != null and metal_mat.metallic >= 0.4, "the permanent pad is textured metal")
	check(kinds["super"]._magic != null and kinds["super"]._magic.emission_enabled, "the super pad glows with magic")
	for b in kinds.values():
		b.queue_free()
	var normal := await bounce_peak(Vector3(-6, 0, 18))
	await frames(90)
	var high := await bounce_peak(Vector3(6, 0, 18))
	check(normal > 6.0, "a normal pad flings you up (%.1f m)" % normal)
	check(high > normal * 1.6, "a super-bouncy pad flings you much higher (%.1f m)" % high)

	# ---- Creative mode: place a structure, scale it, find things with the search box ----
	main.open_editor()
	await frames(5)
	var ed = main.editor
	var wi: int = ed.place("model:dungeon/wall_window_open", Vector3(3, 0, 3))
	check(ed.map["pieces"][wi]["type"] == "model" and ed.map["pieces"][wi]["model"] == "dungeon/wall_window_open", "Creative places a structure")
	ed.select(wi)
	ed.begin("scale")
	ed.set_axis("x")
	ed.drag_update(Vector3.ZERO, Vector3.DOWN, ed._drag_mouse + Vector2(167, 0))
	ed._end_drag(true)
	var ws: Array = ed.map["pieces"][wi].get("size", [1, 1, 1])
	check(is_equal_approx(ws[0], 2.0) and is_equal_approx(ws[1], 1.0), "...and stretches it on one axis (%s)" % [ws])
	ed.place("bouncy_super", Vector3(-3, 0, 3))
	check(ed.map["pieces"].any(func(q): return q["type"] == "bouncy_super"), "...and super-bouncy pads")
	ed._filter_palette("coffin")
	var shown: Array = ed._palette_buttons.filter(func(e): return e[0].visible).map(func(e): return e[0].text.strip_edges())
	check(shown.size() >= 2 and shown.all(func(t): return "coffin" in t.to_lower()), "the palette search finds coffins %s" % [shown])
	ed._filter_palette("")
	check(ed._palette_buttons.all(func(e): return e[0].visible), "...and clearing it shows everything again")
	ed.dirty = false
	ed._try_exit()
	await frames(3)

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(1 if failures > 0 else 0)
