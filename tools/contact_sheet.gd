# Contact sheets: every prop or structure of a family in one labelled picture, each scaled to fit its cell, drawn
# with the game's own materials. For looking a whole set over at once (Nov 27 audit: is everything at the same
# standard?) and for before / after pictures of a change.
#   tools/render_hidden.ps1 -s res://tools/contact_sheet.gd '--' --set=props:restaurant --page=0 --out=kitchen0
# writes tools/previews/_s_kitchen0.png (the folder is git-ignored). It needs a real window to draw, so always
# run it through render_hidden.ps1: Ted games while Claude works.
#   --set=   props:<family>  structs:<family>  buildings  ground  anim  ids:<a,b,c>
#            (in an id list: "building:oak" for a walk-in building, "ground:paving", and "id@3" for a rug or
#            vehicle in its preset style 3)
#            (family: classic, extra, city, dungeon, medieval, restaurant, furniture, halloween; add "+r" or "+k"
#            for only the hand-built or only the KayKit ones; anim: the KayKit props that do something with E)
#   --page=N --per=24 --cols=6   which 24 of them, six to a row
#   --plain                      the KayKit models as they come (no rounding: model_smooth.gd)
#   --kaykit                     the KayKit models in place of the hand-built ones that replaced them
#   --press=N                    press E on every animated prop N times first, and let it play
#   --real                       real sizes, not scaled to fit
extends SceneTree

const Models = preload("res://scripts/models.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const Refined = preload("res://scripts/refined_models.gd")
const ExtraProps = preload("res://scripts/extra_props.gd")


func _initialize() -> void:
	_go.call_deferred()


func _pick(set_name: String) -> Array:
	var out := []
	var kind := set_name.get_slice(":", 0)
	var fam := set_name.get_slice(":", 1)
	var only := ""
	if fam.ends_with("+r") or fam.ends_with("+k"):
		only = fam.right(1)
		fam = fam.left(-2)
	match kind:
		"ids":
			for id in set_name.substr(4).split(",", false):   # (the whole rest: "building:oak" has a colon of its own)
				out.append(id)
		"anim":
			var PA = load("res://scripts/prop_anims.gd")
			for t in PA.TABLE:
				if "/" in t and not Refined.has(t) and PropLib.TYPES.has(t):
					out.append(t)
		"buildings":
			for k in HollowBuildings.KINDS:
				out.append("building:" + k)
		"ground":
			for k in GroundBlock.KINDS:
				out.append("ground:" + k)
		"props":
			for t in PropLib.type_names():
				if "#" in t:
					continue
				var f: String = t.get_slice("/", 0) if "/" in t else ("extra" if ExtraProps.has(t) else "classic")
				if f != fam:
					continue
				if only == "r" and not Refined.has(t):
					continue
				if only == "k" and Refined.has(t):
					continue
				out.append(t)
		"structs":
			for id in Models.ids("structure"):
				if id.get_slice("/", 0) != fam:
					continue
				if only == "r" and not Refined.has(id):
					continue
				if only == "k" and Refined.has(id):
					continue
				out.append(id)
	return out


func _make(id: String) -> Array:   # [node, size]
	if id.begins_with("building:"):
		return [HollowBuildings.make(id.substr(9), 0), HollowBuildings.size(id.substr(9))]
	if id.begins_with("ground:"):
		var gs: Vector3 = GroundBlock.DEFAULT_SIZES.get(id.substr(7), Vector3(4, 0.3, 4))
		return [GroundBlock.make(id.substr(7), gs), gs]
	if PropLib.TYPES.has(id):
		var d: Dictionary = PropLib.TYPES[id]
		var s: Vector3 = d["size"] if d["shape"] == "box" else Vector3(d["radius"] * 2.0, d["height"], d["radius"] * 2.0)
		return [PropLib.make_visual(id), s]
	# (a rug's or vehicle's preset style: "furniture/rug_oval_A@3"; add "-" for a rug with no fringe: "@3-")
	var style := {}
	if "@" in id:
		var tail := id.get_slice("@", 1)
		style = {"style": int(tail), "fringe": not tail.ends_with("-")}
		id = id.get_slice("@", 0)
	Models.set_style(style)
	var made := Models.instance(id)
	Models.set_style({})
	return [made, Models.size(id)]


func _go() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.has("kaykit"):   # the KayKit models the hand-built ones replaced
		Refined.disabled = true
	if args.has("plain"):
		Models.smooth_on = false
	var ids := _pick(str(args.get("set", "props:classic")))
	var per := int(args.get("per", "24"))
	var page := int(args.get("page", "0"))
	var total := ids.size()
	ids = ids.slice(page * per, page * per + per)
	var cols := int(args.get("cols", "6"))
	var cell := 4.0
	var vp := SubViewport.new()
	vp.size = Vector2i(int(args.get("w", "1920")), int(args.get("h", "1200")))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.82, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.64, 0.66)
	floor_mi.material_override = fm
	floor_mi.position.y = -0.005
	root.add_child(floor_mi)
	var rows := int(ceil(ids.size() / float(cols)))
	for i in ids.size():
		var id: String = ids[i]
		var made := _make(id)
		var n: Node3D = made[0]
		var s: Vector3 = made[1]
		var k: float = cell * 0.62 / maxf(maxf(s.x, s.y), maxf(s.z, 0.05))
		if args.has("real"):
			k = 1.0
		var holder := Node3D.new()
		holder.position = Vector3((i % cols) * cell, 0, (i / cols) * cell * 1.45)
		holder.rotation.y = float(args.get("yaw", "0.6"))
		holder.scale = Vector3.ONE * k
		if PropLib.TYPES.has(id):
			n.set_meta("anim_id", id)
		holder.add_child(n)
		root.add_child(holder)
		var tag := Label3D.new()
		tag.text = id.get_slice("/", 1) if "/" in id else id.get_slice(":", 1) if ":" in id else id
		tag.font_size = 44
		tag.outline_size = 10
		tag.pixel_size = 0.0075
		tag.modulate = Color(0.05, 0.05, 0.1)
		tag.outline_modulate = Color(1, 1, 1)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = holder.position + Vector3(0, 0.05, cell * 0.52)
		root.add_child(tag)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.current = true
	var cx := (cols - 1) * cell * 0.5
	var cz := (rows - 1) * cell * 1.45 * 0.5
	var dist := maxf(cols * 1.02, rows * 2.1) * cell * 1.0
	cam.position = Vector3(cx, dist * 0.8, cz + dist * 0.72)
	cam.look_at(Vector3(cx, 0.6, cz + 0.4))
	if args.has("press"):
		var PA = load("res://scripts/prop_anims.gd")
		for f in 5:
			await process_frame
		for h in root.get_children():
			if h.get_child_count() > 0 and h.get_child(0).has_meta("anim_id"):
				for k in int(args["press"]):
					PA.press(h.get_child(0), h.get_child(0).get_meta("anim_id"), k + 1)
		for f in 150:
			await process_frame
	for f in 30:
		await process_frame
	var name := str(args.get("out", "sheet"))
	vp.get_texture().get_image().save_png("res://tools/previews/_s_%s.png" % name)
	print("sheet %s: %d of %d" % [name, ids.size(), total])
	quit()
