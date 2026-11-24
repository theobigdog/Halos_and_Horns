# Renders structures/props with the game's sky and lighting, to check how they look.
#   godot --resolution 1280x720 -s res://tools/look_preview.gd -- --ids=medieval/mountain_A_grass,halloween/tree_pine_yellow_large [--tag=_v1] [--time=day|dusk|night] [--weather=clear|sunny_cloudy|snow|rain...] [--close] [--quality=0|1|2]
#   (or --match=<text> for every model whose id contains the text, up to 12)
# Writes tools/previews/look<tag>_overview.png (all of them in a row, seen from a few metres away,
# like in a game) and with --close also look<tag>_<n>_<id>.png close-ups of each.
extends SceneTree

const Models = preload("res://scripts/models.gd")
const Graphics = preload("res://scripts/graphics.gd")
const Effects = preload("res://scripts/effects.gd")
const Surfaces = preload("res://scripts/surfaces.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var q := int(args.get("quality", "2"))
	Graphics.quality = q
	Effects.quality = q
	_go.call_deferred()


func _go() -> void:
	var g := Graphics.new()
	root.add_child(g)
	g.set_time_of_day(args.get("time", "day"))
	g.set_weather(args.get("weather", "clear"))
	var ids: Array = []
	if args.has("ids"):
		ids = Array(args["ids"].split(",", false))
	elif args.has("match"):
		for id in Models.ids():
			if (id as String).contains(args["match"]) and ids.size() < 12:
				ids.append(id)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.5, 0.3)
	Surfaces.apply(gm, "ground")
	ground.material_override = gm
	root.add_child(ground)
	var x := 0.0
	var spots := []
	var widest := 1.0
	var tallest := 1.0
	for id in ids:
		if not Models.has(id):
			print("unknown id ", id)
			continue
		var s := Models.size(id)
		var n: Node3D = Models.make_structure(id) if Models.is_structure(id) else Models.instance(id)
		root.add_child(n)
		x += s.x * 0.5
		n.position = Vector3(x, 0, 0)
		spots.append([id, n.position, s])
		x += s.x * 0.5 + 1.0
		widest = maxf(widest, maxf(s.x, s.z))
		tallest = maxf(tallest, s.y)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 50.0
	var mid := Vector3(x * 0.5, tallest * 0.45, 0)
	var dist := maxf(x * 0.75, tallest * 1.6) + 3.0
	cam.position = mid + Vector3(0, dist * 0.35, dist)
	cam.look_at(mid)
	var tag: String = args.get("tag", "")
	DirAccess.make_dir_recursive_absolute("res://tools/previews")
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tools/previews/look%s_overview.png" % tag)
	if args.has("close"):
		for k in spots.size():
			var sp: Array = spots[k]
			var s: Vector3 = sp[2]
			var c: Vector3 = sp[1] + Vector3(0, s.y * 0.5, 0)
			var d := maxf(maxf(s.x, s.y), s.z) * 1.1 + 1.5
			cam.position = c + Vector3(d * 0.45, d * 0.3, d * 0.85)
			cam.look_at(c)
			for i in 12:
				await process_frame
			var safe := (sp[0] as String).replace("/", "__")
			root.get_viewport().get_texture().get_image().save_png("res://tools/previews/look%s_%d_%s.png" % [tag, k, safe])
	print("done: ", spots.size(), " models")
	quit()
