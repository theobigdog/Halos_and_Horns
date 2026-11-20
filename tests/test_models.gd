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
	var raw := {"name": "Model test", "size": 28, "ceiling": 60, "pieces": [
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

	# Time of day, lights, grime, round music
	var night := MapData.clean({"time": "night", "pieces": [{"type": "light", "pos": [0, 3, 0], "range": 999, "color": "#00ff00"}]})
	var lamp_p: Dictionary = night["pieces"].filter(func(q): return q["type"] == "light")[0]
	check(night["time"] == "night" and MapData.clean({"time": "noon"})["time"] == "day", "maps can be day, dusk or night (anything else is day)")
	check(lamp_p["range"] == 40.0 and lamp_p["color"] == "#00ff00", "a placed light keeps its colour, with its reach capped (%s)" % lamp_p["range"])
	main.load_map(night)
	await frames(2)
	check(main.graphics.time_of_day == "night" and main.graphics.sun.light_energy < 0.5, "a night map darkens the sky and sun")
	check(main.world_root.find_children("*", "OmniLight3D", true, false).size() >= 1, "...and its placed lights shine")
	check(main.world_root.find_children("*", "MeshInstance3D", true, false).filter(func(mi): return mi.get_parent() != null and mi.get_parent().get_child(0) is OmniLight3D).is_empty(),
		"...with no bulb showing outside Creative")
	var spot: Dictionary = MapData.clean({"pieces": [{"type": "light", "pos": [0, 3, 0], "spot": true, "angle": 200}]})["pieces"].filter(func(q): return q["type"] == "light")[0]
	check(spot.get("spot", false) and spot["angle"] == 85.0 and main.make_lamp(spot, Vector3.ZERO, false).get_child(0) is SpotLight3D, "lights can be spotlights (cone capped at %s degrees)" % spot["angle"])
	# Weather and the day cycle
	var wet := MapData.clean({"weather": "rain", "cycle": 10})
	check(wet["weather"] == "rain" and wet["cycle"] == 10 and MapData.clean({"weather": "hail", "cycle": 7})["weather"] == "sunny_cloudy", "maps have weather and a day cycle (junk falls back to the default)")
	main.load_map(MapData.clean({"weather": "snow", "pieces": []}))
	await frames(2)
	check(main.graphics.weather == "snow" and main.graphics._fall != null, "a snowy map has snow falling")
	main.load_map(MapData.clean({"weather": "clear", "cycle": 5, "pieces": []}))
	await frames(2)
	check(main.graphics._fall == null and main.graphics.day_cycle == 5.0, "...a clear one doesn't, and the day cycle runs")
	# Looks, the end crosswalk, cars and traffic lights
	var mossy := Models.instance("dungeon/wall", Vector3.ONE, 2)
	var mm: MeshInstance3D = mossy.find_children("*", "MeshInstance3D", true, false)[0]
	check(int(mm.get_instance_shader_parameter("look")) == 2 and MapData.clean({"pieces": [{"type": "model", "model": "dungeon/wall", "pos": [0, 0, 0], "look": 99}]})["pieces"][0]["look"] == MapData.LOOKS - 1,
		"structures can have a look (mossy, charred...), kept in range")
	mossy.free()
	var cross := Models.instance("city/road_crossing_end")
	check(Models.has("city/road_crossing_end") and cross.get_child_count() > 6, "there's a road with the crosswalk at one end")
	cross.free()
	var car := Models.car_lights("city/car_sedan")
	check(car.find_children("*", "SpotLight3D", true, false).size() == 1, "cars can have their lights on")
	car.free()
	# Ice: slippery, and you can fall
	var iced: Node3D = main.make_ice({"size": [4, 0.06, 4]})
	check(iced.is_in_group("ice"), "ice is a slippery sheet")
	iced.free()
	var lantern := Models.instance("halloween/lantern_standing")
	check(lantern.find_children("*", "OmniLight3D", true, false).size() == 1, "lit things (lanterns, torches, jack-o'-lanterns) give off light")
	var grimy: MeshInstance3D = lantern.find_children("*", "MeshInstance3D", true, false)[0]
	check(grimy.material_overlay != null, "models get a layer of grime on Medium graphics")
	lantern.free()
	main._reset_round_props(7)
	check(main.round_theme in main.ROUND_THEMES and main.round_theme == main.ROUND_THEMES[7 % main.ROUND_THEMES.size()], "each round picks its hunt music from the round seed (%s)" % main.round_theme)

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

	# ---- Ice: slide about, and running then turning hard makes you fall ----
	var ice_sheet: Node3D = main.make_ice({"size": [14, 0.06, 14]})
	ice_sheet.position = Vector3(14, 0.03, -2)
	main.world_root.add_child(ice_sheet)
	player.global_position = Vector3(14, 0.3, 3)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.pivot.rotation = Vector3.ZERO
	await frames(10)
	player.test_input = {"dir": Vector2(0, -1), "run": true}
	await frames(70)
	var on_ice: bool = player._on_ice
	player.test_input = {"dir": Vector2(0, 1), "run": true}
	var fell := false
	for k in 40:
		await frames(1)
		fell = fell or player.stunned > 0.0
	player.test_input = {}
	check(on_ice and fell, "running on ice then turning hard makes you slip and fall (on ice %s, fell %s)" % [on_ice, fell])
	ice_sheet.queue_free()
	player.stunned = 0.0
	await frames(30)

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
	# Pull tabs: dragging a fence's end tab adds whole copies end to end (posts and all), either end.
	var fi: int = ed.place("model:halloween/fence", Vector3(0, 0, 10))
	ed.select(fi)
	var step: float = Models.row_step("halloween/fence").length()
	var f0 := Vector3(0, 0, 10)
	check(ed._tabs().size() == 2, "a selected fence has a pull tab at each end (%d)" % ed._tabs().size())
	ed.pull_tab(0, 1)
	ed.drag_update(f0 + Vector3(step * 3.7, 30, 0), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	var fp: Dictionary = ed.map["pieces"][fi]
	check(int(fp.get("repeat", 1)) == 4 and fp["pos"] == [0.0, 0.0, 10.0], "pulling its far tab repeats it end to end (%s in a row)" % fp.get("repeat", 1))
	var posts: int = ed.nodes[fi].find_children("*", "StaticBody3D", true, false).size()
	check(posts == 4, "...each copy whole and solid (%d)" % posts)
	ed.pull_tab(0, -1)
	ed.drag_update(f0 + Vector3(-step * 2.4, 30, 0), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	fp = ed.map["pieces"][fi]
	check(int(fp.get("repeat", 1)) == 6 and is_equal_approx(fp["pos"][0], -step * 2.0), "...and pulling the near tab grows it the other way, the far end staying put (%s, from x %.2f)" % [fp.get("repeat", 1), fp["pos"][0]])
	# Floors pull out both ways, into a grid
	var fl: int = ed.place("model:dungeon/floor_wood_large", Vector3(-20, 0, -12))
	ed.select(fl)
	var fw: float = Models.row_step2("dungeon/floor_wood_large").length()
	check(ed._tabs().size() == 4, "a selected floor has tabs on all four sides (%d)" % ed._tabs().size())
	ed.pull_tab(1, 1)
	ed.drag_update(Vector3(-20, 30, -12) + Models.row_step2("dungeon/floor_wood_large").normalized() * fw * 2.7, Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	ed.pull_tab(0, 1)
	ed.drag_update(Vector3(-20, 30, -12) + Models.row_step("dungeon/floor_wood_large").normalized() * fw * 1.6, Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	var flp: Dictionary = ed.map["pieces"][fl]
	var tiles: int = ed.nodes[fl].find_children("*", "StaticBody3D", true, false).size()
	check(int(flp.get("repeat2", 1)) == 3 and int(flp.get("repeat", 1)) == 2 and tiles == 6, "...pulling two sides makes a 2 x 3 floor (%s x %s, %d tiles)" % [flp.get("repeat", 1), flp.get("repeat2", 1), tiles])
	check(MapData.clean({"pieces": [{"type": "model", "model": "dungeon/wall", "pos": [0, 0, 0], "repeat2": 5}]})["pieces"][0].get("repeat2", 1) == 1,
		"...but walls only ever repeat in a row")
	for u in 5:
		ed.undo()
	check(not ed.map["pieces"][fi].has("repeat"), "...undo takes it back")
	# Shift + wheel turns what you're about to place; arrow keys nudge the selected piece
	ed.placing = "model:dungeon/wall"
	ed.wheel_turn(15.0)
	ed.wheel_turn(15.0)
	ed.wheel_turn(15.0)
	var ti: int = ed.place("model:dungeon/wall", Vector3(-8, 0, 12))
	check(is_equal_approx(float(ed.map["pieces"][ti].get("rot", [0, 0, 0])[1]), 45.0), "Shift + wheel turns a piece before it's placed (%s)" % [ed.map["pieces"][ti].get("rot")])
	ed.placing = ""
	ed.place_yaw = 0.0
	ed.select(ti)
	ed.wheel_turn(-15.0)
	check(is_equal_approx(float(ed.map["pieces"][ti]["rot"][1]), 30.0), "...and turns a selected one too (%s)" % [ed.map["pieces"][ti]["rot"]])
	var before_n: Vector3 = MapData.vec(ed.map["pieces"][ti]["pos"])
	ed.nudge(KEY_UP, false)
	ed.nudge(KEY_PAGEUP, true)
	var moved_n: Vector3 = MapData.vec(ed.map["pieces"][ti]["pos"]) - before_n
	check(is_equal_approx(moved_n.length_squared(), ed.grid * ed.grid + 0.0001) and is_equal_approx(moved_n.y, 0.01),
		"arrow keys nudge it one snap step, Alt + Page Up a centimetre up (%s)" % moved_n)
	# The see-through preview of what you're about to place
	ed.placing = "model:halloween/crypt"
	ed._update_preview()
	check(is_instance_valid(ed._preview) and ed._preview.find_children("*", "CollisionObject3D", true, false).all(func(c): return c.collision_layer == 0),
		"picking a piece shows a see-through preview that nothing bumps into")
	ed.placing = ""
	ed._update_preview()
	check(ed._preview == null, "...gone once nothing's picked")
	var with_pics: int = ed._palette_buttons.filter(func(e): return e[0].icon != null).size()
	check(with_pics == ed._palette_buttons.size(), "every piece in the palette has a picture (%d of %d)" % [with_pics, ed._palette_buttons.size()])
	# Settings from Creative: the panel shows (it lives on the HUD layer Creative hides), and Esc closes it
	main.open_settings_from_editor()
	await frames(2)
	check(main.controls_panel.visible and main.controls_panel.is_visible_in_tree(), "Settings opens over Creative and can be seen")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	check(not main.controls_panel.visible and ed.ui.visible and not main.hud_layer.visible, "...and Esc goes back to building, everything still there")
	ed.dirty = false
	ed._try_exit()
	await frames(3)

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(1 if failures > 0 else 0)
