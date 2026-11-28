# The model catalog (KayKit props and structures), structures in a map, and the three bouncy pads.
#   godot --headless -s res://tests/test_models.gd
extends SceneTree

const Models = preload("res://scripts/models.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const MapData = preload("res://scripts/map_data.gd")
const Bouncy = preload("res://scripts/bouncy.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")

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


const PROP_TRIANGLES := 14000


# Triangles drawn for this node and everything under it (MultiMeshes count every copy). Spheres and rings
# still at Godot's default detail are noted in `defaults`.
func triangles(n: Node, defaults: Array, label: String) -> int:
	var total := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		total += m.get_faces().size() / 3
		if (m is SphereMesh and (m as SphereMesh).radial_segments >= 64) or (m is TorusMesh and (m as TorusMesh).rings >= 64):
			defaults.append(label)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			total += mm.mesh.get_faces().size() / 3 * mm.instance_count
	for c in n.get_children():
		total += triangles(c, defaults, label)
	return total


func mesh_box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.get_parent().has_meta("extra") or (mi.get_parent().get_parent() != null and mi.get_parent().get_parent().has_meta("extra")):
			continue   # (add-ons like a traffic light's street signs)
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

	# ---- Characters: mix and match parts, skins, the wardrobe ----
	const Characters = preload("res://scripts/characters.gd")
	var mixed := Characters.build("angel", {"crown": "halo_star", "head": "Mage", "upper": "Barbarian", "lower": "Rogue", "skin": "ocean", "trail": "feather"}, 1.7)
	root.add_child(mixed)
	var names: Array = mixed.find_children("*", "MeshInstance3D", true, false).map(func(m): return str(m.name))
	check("Mage_Head" in names and "Barbarian_Body" in names and "Rogue_LegLeft" in names and "Mage_Hat" in names,
		"a character mixes parts from different characters (%s)" % [names.filter(func(n): return n.contains("_")).slice(0, 6)])
	var head_mi: MeshInstance3D = mixed.find_children("Mage_Head", "MeshInstance3D", true, false)[0]
	check(head_mi.material_override is ShaderMaterial, "...with its skin recoloured")
	await frames(3)
	check(mixed.anim != null and mixed.anim.is_playing() and mixed.anim.current_animation == "Idle", "...and it's animated (standing about: %s)" % mixed.anim.current_animation)
	mixed.queue_free()
	# Coloured structures get their own tinted copy of the grime overlay; the shared one has no per-instance tint
	# (Ted, Nov 27: in v0.7.0 pieces turned solid red after a test round, reading their neighbours' values)
	var plain_row: Node3D = Models.make_row("city/streetlight")
	var tinted_row: Node3D = Models.make_row("city/streetlight")
	Models.tint(tinted_row, Color(0.2, 0.4, 1.0))
	var plain_mi: MeshInstance3D = plain_row.find_children("*", "MeshInstance3D", true, false)[0]
	var tinted_mi: MeshInstance3D = tinted_row.find_children("*", "MeshInstance3D", true, false)[0]
	check(not "instance uniform vec4 tint" in Models.GRIME_SHADER and plain_mi.material_overlay == Models.grime_material()
			and tinted_mi.material_overlay != Models.grime_material()
			and (tinted_mi.material_overlay as ShaderMaterial).get_shader_parameter("tint") == Color(0.2, 0.4, 1.0),
			"a coloured structure gets its own tinted overlay; the shared one has no per-piece tint")
	plain_row.free()
	tinted_row.free()

	# Horns root on the head (or the dome of its hat), never on a hat's spikes, stubs or brim (Ted, Nov 27: on the
	# Skeleton Warrior's helmet they stood on its horn stubs, way above it)
	var far_hats := []
	for hc in ["Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Minion"]:
		var bare_pts: PackedVector3Array = Characters.head_hull(hc, false)
		var hat_pts: PackedVector3Array = Characters.head_hull(hc, true)
		var hb := AABB(bare_pts[0], Vector3.ZERO)
		for v in bare_pts:
			hb = hb.expand(v)
		var skull := 0.0
		var furthest := 0.0
		for v in bare_pts:
			skull = maxf(skull, v.distance_to(hb.get_center()))
		for v in hat_pts:
			furthest = maxf(furthest, v.distance_to(hb.get_center()))
		if furthest > skull * 1.21:
			far_hats.append(hc)
	check(far_hats.is_empty(), "horns root on the head or its hat's dome, not on spikes or brims %s" % [far_hats])
	var junk := Characters.clean_outfit({"head": "Shrek", "skin": 7, "crown": "horns"}, "angel")
	check(junk["head"] == "Knight" and junk["skin"] == "natural" and junk["crown"] == "halo", "outfits from files or other players are checked (no Shrek heads, no horns on angels)")
	var cross_a := Characters.clean_outfit({"head": "Skeleton_Mage", "upper": "Knight", "skin": "zombie"}, "angel")
	var cross_d := Characters.clean_outfit({"head": "Knight", "upper": "Skeleton_Rogue", "skin": "gold"}, "demon")
	check(cross_a["head"] == "Knight" and cross_a["upper"] == "Knight" and cross_a["skin"] == "natural" and cross_d["head"] == "Skeleton_Warrior" and cross_d["upper"] == "Skeleton_Rogue" and cross_d["skin"] == "natural",
		"angels and demons each have their own wardrobe (no skeleton heads or zombie skin on angels, no knights on demons)")
	var demon_heads: Array = Characters.options("head", "demon").map(func(o): return o[0])
	check(demon_heads.all(func(h): return h.begins_with("Skeleton")) and Characters.matching_sets("demon").size() == 4 and Characters.matching_sets("angel").size() == 5,
		"...with matching sets for each (%d angel, %d demon)" % [Characters.matching_sets("angel").size(), Characters.matching_sets("demon").size()])
	check(player.visual_root.get_child(0).has_method("play_action"), "your own body is a character now, not a capsule")
	player.test_input = {"sneak": true}
	await frames(30)
	var crouch_amount: float = player.visual_root.get_child(0)._crouch.amount
	player.test_input = {}
	await frames(30)
	check(crouch_amount > 0.9 and player.visual_root.get_child(0)._crouch.amount < 0.1, "sneaking crouches you down, and you stand back up (%.2f)" % crouch_amount)
	main._open_wardrobe()
	await frames(2)
	main.wardrobe._set_team("demon")
	main.wardrobe._pick("crown", "horns_goat")
	main.wardrobe._name_edit.text = "Goaty"
	main.wardrobe._save_preset()
	check(main.outfits["demon"]["crown"] == "horns_goat" and main.wardrobe_presets.any(func(p): return p["name"] == "Goaty"),
		"the wardrobe changes your outfit and saves presets")
	main._close_wardrobe()
	main._load_settings()
	check(main.outfits["demon"]["crown"] == "horns_goat" and main.wardrobe_presets.any(func(p): return p["name"] == "Goaty"), "...and remembers them")
	main.wardrobe_presets = []
	main.set_outfits({})
	main._save_settings()

	# ---- Stepping up: low ledges and stairs, yes; props, no ----
	var walk_into := func(start: Vector3, frames_n: int) -> float:
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		player.pivot.rotation = Vector3.ZERO
		await frames(8)
		var y0: float = player.global_position.y
		player.test_input = {"dir": Vector2(0, -1)}
		var top := y0
		for k in frames_n:
			await frames(1)
			top = maxf(top, player.global_position.y)
		player.test_input = {}
		return top - y0
	var ledge: StaticBody3D = main._add_block(Vector3(22, 0.2, -6), Vector3(4, 0.4, 3), Color.GRAY)
	var rose: float = await walk_into.call(Vector3(22, 0.1, -2), 50)
	check(rose > 0.3, "walking into a 40 cm ledge steps up onto it (%.2f m)" % rose)
	ledge.queue_free()
	main._spawn_prop("crate", Vector3(22, 0, -5), Vector3.ZERO)
	var crate_rise: float = await walk_into.call(Vector3(22, 0.1, -2), 50)
	check(crate_rise < 0.2, "...but a crate still blocks you (%.2f m)" % crate_rise)
	main.props[main.props.size() - 1].queue_free()
	var stair := Models.make_structure("dungeon/stairs")
	main.world_root.add_child(stair)
	stair.position = Vector3(25.5, 0, -8)
	await frames(2)
	var climbed: float = await walk_into.call(Vector3(25.5, 0.1, -4), 130)
	check(climbed > 2.0, "...and you walk straight up stairs (%.1f m up)" % climbed)
	stair.queue_free()
	await frames(5)

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

	# ---- Lights: a daylight sensor (on at dusk), always-on, flicker ----
	var Lamp = load("res://scripts/lamp.gd")
	var keep_dark: float = Lamp.darkness
	var lamp_s: Node3D = main.make_lamp({"type": "light", "range": 8.0, "energy": 1.5}, Vector3(0, 50, 0), false)
	var lamp_a: Node3D = main.make_lamp({"type": "light", "range": 8.0, "energy": 1.5, "always": true}, Vector3(2, 50, 0), false)
	var lamp_f: Node3D = main.make_lamp({"type": "light", "range": 8.0, "energy": 1.5, "always": true, "flicker": 8.0}, Vector3(4, 50, 0), false)
	for l in [lamp_s, lamp_a, lamp_f]:
		root.add_child(l)
	Lamp.darkness = 0.0
	await process_frame
	await process_frame
	check(not lamp_s.light.visible and lamp_a.light.visible, "in daylight a sensor lamp is off, an always-on one lit")
	Lamp.darkness = 1.0
	var seen := []
	for k in 100:
		await process_frame
		seen.append(snappedf(lamp_f.light.light_energy, 0.01))
	await create_timer(1.6).timeout   # (past the sputter as it comes on)
	await process_frame
	check(lamp_s.light.visible and is_equal_approx(lamp_s.light.light_energy, 1.5), "...and at night the sensor lamp comes on")
	var lo_e: float = seen.min()
	var hi_e: float = seen.max()
	check(hi_e - lo_e > 0.2, "a flickering lamp flickers (energy %.2f..%.2f)" % [lo_e, hi_e])
	Lamp.darkness = keep_dark
	for l in [lamp_s, lamp_a, lamp_f]:
		l.queue_free()

	# ---- Snow tracks: people leave prints, a demon disguised as a prop never does ----
	var Tracks = load("res://scripts/snow_tracks.gd")
	var tracks: Node3D = Tracks.new()
	root.add_child(tracks)
	tracks.setup(20.0)
	var walker := Node3D.new()
	walker.set_script(load("res://tests/track_walker.gd"))
	walker.add_to_group("snow_walker")
	root.add_child(walker)
	walker.global_position = Vector3(5, 0, 5)
	walker.set("possessed_type", "barrel")
	await process_frame
	await create_timer(0.15).timeout
	var c: Vector2i = Vector2i(int((5.0 + 20.0) / 40.0 * tracks._res), int((5.0 + 20.0) / 40.0 * tracks._res))
	var hidden_print: float = tracks._img.get_pixelv(c).r
	walker.set("possessed_type", "")
	walker.global_position = Vector3(5.3, 0, 5)
	await create_timer(0.15).timeout
	var c2: Vector2i = Vector2i(int((5.3 + 20.0) / 40.0 * tracks._res), int((5.0 + 20.0) / 40.0 * tracks._res))
	var seen_print: float = tracks._img.get_pixelv(c2).r
	check(hidden_print < -1000.0 and seen_print > -1000.0, "snow: someone walking leaves prints, a disguised demon never does (%.0f, %.0f)" % [hidden_print, seen_print])
	tracks.queue_free()
	walker.queue_free()

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
	check(kinds["super"]._top.material_override is ShaderMaterial, "the super pad shows heaven and hell (its first look: Ted, Nov 27)")
	for b in kinds.values():
		b.queue_free()
	var normal := await bounce_peak(Vector3(-6, 0, 18))
	await frames(90)
	var high := await bounce_peak(Vector3(6, 0, 18))
	check(normal > 6.0, "a normal pad flings you up (%.1f m)" % normal)
	check(high > normal * 1.6, "a super-bouncy pad flings you much higher (%.1f m)" % high)
	# Thrown things: a one-use pad is used up by a blessing hitting it; a lasting pad flings it back up
	var used_ids := []
	var once := Bouncy.new()
	once.one_use = true
	once.bouncy_id = 77
	once.on_used = func(id): used_ids.append(id)
	main.world_root.add_child(once)
	once.position = Vector3(-14, 0, 22)
	var stays := Bouncy.new()
	main.world_root.add_child(stays)
	stays.position = Vector3(-18, 0, 22)
	await frames(3)
	var Proj = load("res://scripts/projectile.gd")
	var shots := []
	for at in [once.position, stays.position]:
		var pr: Node3D = Proj.new()
		main.world_root.add_child(pr)
		pr.global_position = at + Vector3(0, 2.0, 0)
		pr.velocity = Vector3(0, -8, 0)
		shots.append(pr)
	var flung_up := false
	for k in 40:
		await frames(1)
		if is_instance_valid(shots[1]) and shots[1].velocity.y > 5.0:
			flung_up = true
	check(used_ids == [77], "a blessing hitting a one-use pad uses it up (%s)" % [used_ids])
	check(flung_up, "...and one hitting a lasting pad is flung back up into the air")
	for n in [once, stays] + shots:
		if is_instance_valid(n):
			n.queue_free()

	# ---- Creative mode: place a structure, scale it, find things with the search box ----
	main.open_editor()
	await frames(5)
	var ed = main.editor
	var wi: int = ed.place("model:dungeon/wall_window_open", Vector3(3, 0, 3))
	check(ed.map["pieces"][wi]["type"] == "model" and ed.map["pieces"][wi]["model"] == "dungeon/wall_window_open", "Creative places a structure")
	# Grouping: Ctrl + click several, they move and change together; Ctrl + G makes it stick
	var ga: int = ed.place("block", Vector3(-30, 0, -30))
	var gb: int = ed.place("block", Vector3(-27, 0, -30))
	var gc: int = ed.place("block", Vector3(-24, 0, -30))
	ed.select(ga)
	ed.toggle_member(gb)
	ed.toggle_member(gc)
	var gx: Array = [ga, gb, gc].map(func(k): return float(ed.map["pieces"][k]["pos"][1]))
	ed.nudge(KEY_PAGEUP, false)
	var moved_all: bool = [ga, gb, gc].all(func(k): return float(ed.map["pieces"][k]["pos"][1]) > gx[0] + 0.001)
	ed.set_value(ga, "color", "#ff0000")
	var red_all: bool = [ga, gb, gc].all(func(k): return ed.map["pieces"][k]["color"] == "#ff0000")
	check(moved_all and red_all, "Ctrl + click selects several pieces: they move and get recoloured together")
	ed.group_selected()
	ed.select(-1)
	ed.select(gc)
	check(ed.members.size() == 2 and ed.map["pieces"][ga].has("group"), "...Ctrl + G groups them: clicking one selects the whole group")
	ed.ungroup_selected()
	ed.select(gb)
	check(ed.members.is_empty() and not ed.map["pieces"][gb].has("group"), "...and Ctrl + Shift + G ungroups them")
	ed.select(ga)
	ed.toggle_member(gb)
	ed.toggle_member(gc)
	var count_before: int = ed.map["pieces"].size()
	ed.delete_selected()
	check(ed.map["pieces"].size() == count_before - 3, "...deleting removes the whole selection")
	# A shared maps folder: saving there, it shows up in the lists, and someone else's newer save is never wiped
	var shared := ProjectSettings.globalize_path("user://test_shared_maps")
	DirAccess.make_dir_recursive_absolute(shared)
	var keep_shared: String = MapData.shared_dir
	var keep_name: String = ed.map["name"]
	var keep_p: String = ed.path
	MapData.shared_dir = shared
	ed.map["name"] = "Shared test map"
	ed.shared_save = true
	ed.path = ""
	ed.save()
	var shared_file: String = ed.path
	var listed: bool = MapData.list_maps().any(func(e): return e.get("shared", false) and e["path"] == shared_file)
	check(MapData.is_shared(shared_file) and FileAccess.file_exists(shared_file) and listed, "Creative saves into the shared maps folder, and it's listed (%s)" % shared_file.get_file())
	ed._disk_time -= 5   # (as if someone else saved it on their PC after we opened it)
	ed.dirty = true
	ed.save()
	check(ed.path != shared_file and ed.path.contains("copy") and FileAccess.file_exists(shared_file), "...and if someone else saved it meanwhile, ours goes in a copy (%s)" % ed.path.get_file())
	for f in DirAccess.get_files_at(shared):
		DirAccess.remove_absolute(shared.path_join(f))
	DirAccess.remove_absolute(shared)
	MapData.shared_dir = keep_shared
	ed.shared_save = false
	ed.map["name"] = keep_name
	ed.path = keep_p
	ed._remember_disk()
	ed.dirty = true
	# Autosave every 10 minutes (only if something changed; never over another map)
	var keep_path: String = ed.path
	var before := DirAccess.get_files_at(MapData.USER_DIR) if DirAccess.dir_exists_absolute(MapData.USER_DIR) else PackedStringArray()
	ed._autosave_tick(ed.AUTOSAVE_EVERY + 1.0)
	var saved_to: String = ed.path
	check(not ed.dirty and saved_to != "" and FileAccess.file_exists(saved_to), "Creative autosaves after 10 minutes (%s)" % saved_to)
	if not before.has(saved_to.get_file()):
		DirAccess.remove_absolute(saved_to)   # (only our own test file)
	ed.path = keep_path
	ed.dirty = true
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
	# Categories (Ted's wife, Nov 27): her list, things in more than one where they fit, "Other" for the rest
	var titles: Array = ed._palette_sections.map(func(s): return s[2])
	var PC = load("res://scripts/palette_cats.gd")
	check(PC.ORDER.all(func(c): return c in titles), "the palette has every category on her list %s" % [PC.ORDER.filter(func(c): return not c in titles)])
	check(PC.cats("halloween/candle").has("Lighting") and PC.cats("halloween/candle").has("Graveyard")
			and PC.cats("city/streetlight") == ["Lighting", "Street/Road"], "...and things go in every category they fit")
	ed._only_switchable = true
	ed._filter_palette("")
	var sw: Array = ed._palette_buttons.filter(func(e): return e[0].visible)
	check(not sw.is_empty() and sw.all(func(e): return e[3]) and sw.any(func(e): return "beehive" in e[1]), "the switchable-props tick shows only props that do something with E")
	ed._only_switchable = false
	ed._filter_palette("")
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
	# Lining (Ted, Nov 26): swinging the mouse out to the side while pulling turns a corner, starting a new run
	# of the same piece aimed at the mouse; swinging back in takes the corner away again
	var n_before: int = ed.map["pieces"].size()
	ed.select(fi)
	ed.pull_tab(0, 1)
	ed.drag_update(f0 + Vector3(step * 3.5, 30, step * 3.0), Vector3.DOWN, Vector2.ZERO)
	ed.drag_update(f0 + Vector3(step * 3.5, 30, step * 3.1), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	var cp: Dictionary = ed.map["pieces"][ed.map["pieces"].size() - 1]
	check(ed.map["pieces"].size() == n_before + 1 and cp.get("model", "") == "halloween/fence" and int(cp.get("repeat", 1)) == 3
			and is_equal_approx(float(cp["rot"][1]), -90.0) and ed.selected == ed.map["pieces"].size() - 1,
			"lining: swinging out sideways turns a corner (a new run of %s, turned %s, selected)" % [cp.get("repeat", 1), cp.get("rot", [])])
	check(int(ed.map["pieces"][fi].get("repeat", 1)) == 6, "...and the row itself stays as it was (%s)" % ed.map["pieces"][fi].get("repeat", 1))
	ed.select(fi)
	ed.pull_tab(0, 1)
	ed.drag_update(f0 + Vector3(step * 3.5, 30, step * 3.0), Vector3.DOWN, Vector2.ZERO)
	ed.drag_update(f0 + Vector3(step * 4.6, 30, 0.0), Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	check(ed.map["pieces"].size() == n_before + 1 and int(ed.map["pieces"][fi].get("repeat", 1)) == 7,
			"...and swinging back in takes that corner away again (%d pieces, %s in the row)" % [ed.map["pieces"].size() - n_before, ed.map["pieces"][fi].get("repeat", 1)])
	ed.undo()
	ed.undo()
	check(ed.map["pieces"].size() == n_before and int(ed.map["pieces"][fi].get("repeat", 1)) == 6, "...and undo takes the corner away")
	# Stairs extend upward: each flight starts at the top of the last
	var st_step: Vector3 = Models.row_step("dungeon/stairs")
	check(st_step.y > 2.5 and Vector2(st_step.x, st_step.z).length() > 2.5, "pulling out stairs continues the climb (each flight %s further on and up)" % st_step)
	var si: int = ed.place("model:dungeon/stairs", Vector3(-24, 0, 20))
	ed.select(si)
	ed.pull_tab(0, 1)
	var st_dir := Vector3(st_step.x, 0, st_step.z).normalized()
	ed.drag_update(Vector3(-24, 30, 20) + st_dir * Vector2(st_step.x, st_step.z).length() * 2.6, Vector3.DOWN, Vector2.ZERO)
	ed._end_drag(true)
	check(int(ed.map["pieces"][si].get("repeat", 1)) == 3, "...three flights (%s)" % ed.map["pieces"][si].get("repeat", 1))
	ed.undo()
	ed.undo()
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

	# ---- Triangle budget (Ted, Nov 26: keep an eye on polygon counts without anyone having to ask) ----
	# Every prop stays under PROP_TRIANGLES, and no sphere or ring anywhere is left at Godot's default detail
	# (64 x 32: about 4,000 triangles each; 324 of them were most of the Town map's 1.65 million).
	var heavy := []
	var defaults := []
	var biggest := ["", 0]
	for t in PropLib.type_names():
		var v := PropLib.make_visual(t)
		var tris := triangles(v, defaults, t)
		if tris > biggest[1]:
			biggest = [t, tris]
		if tris > PROP_TRIANGLES:
			heavy.append("%s (%d)" % [t, tris])
		v.free()
	for id in Models.ids("structure"):
		var s := Models.instance(id)
		triangles(s, defaults, id)
		s.free()
	print("  biggest prop: %s, %d triangles" % biggest)
	check(heavy.is_empty(), "every prop is under %d triangles %s" % [PROP_TRIANGLES, str(heavy)])
	check(defaults.is_empty(), "no sphere or ring is left at Godot's 4,000-triangle default %s" % str(defaults))

	# Road signs (Ted, Nov 27): every one builds, solid, in a handful of draw calls, and every speed is a look
	var RoadSigns = load("res://scripts/road_signs.gd")
	for kind in HollowBuildings.SIGNS:
		var sgn: Node3D = HollowBuildings.make(kind, 3)
		var meshes := sgn.find_children("*", "GeometryInstance3D", true, false).size()
		var solid := sgn.find_children("*", "CollisionShape3D", true, false).size()
		check(meshes <= 12 and solid >= 1 and HollowBuildings.size(kind).y > 2.5, "road sign %s builds (%d pieces, %d solid)" % [kind, meshes, solid])
		sgn.free()
	check(RoadSigns.looks("sign_speed").size() == 8 and MapData.clean({"pieces": [{"type": "building", "kind": "sign_speed", "pos": [0, 0, 0], "look": 7}]})["pieces"][0]["look"] == 7,
			"speed limit signs keep all 8 speeds")

	# Walk-in buildings: no two faces facing the same way lie in one plane and overlap (they flicker as the
	# camera moves: Ted's Nov 26 notes, three rounds of them)
	for kind in HollowBuildings.KINDS:
		for look in 4:
			var flick: Array = HollowBuildings.coplanar_faces(kind, look)
			check(flick.is_empty(), "walk-in %s (look %d) has no flickering faces %s" % [kind, look,
					str(flick.slice(0, 3).map(func(f): return f[0].snapped(Vector3.ONE * 0.01)))])

	print("\n%s: %d failure(s)" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(1 if failures > 0 else 0)
