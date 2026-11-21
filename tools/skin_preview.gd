# Renders one character (a whole matching set) from several angles, at in-game size, into
# tools/previews/ (git-ignored), for working on its details (scripts/skin_details/<name>.gd).
#   godot --resolution 900x700 -s res://tools/skin_preview.gd -- --char=Knight [--bare] [--skin=hellred] [--tag=v2]
# Views: front, back, left, right, above (3/4 from above), head (close-up of the head, front),
# headback, crouch (sneaking pose, side), and mixed (its head/upper/lower on other characters' pieces).
extends SceneTree

const Characters = preload("res://scripts/characters.gd")
const Bodies = preload("res://scripts/bodies.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var c: String = args.get("char", "Knight")
	var role := "angel" if c in Characters.TEAM_CHARS["angel"] else "demon"
	var bare := args.has("bare")
	var tag: String = args.get("tag", "")
	var outfit := Characters.default_outfit(role)
	outfit["head"] = c + (":bare" if bare else "")
	outfit["upper"] = (("Rogue" if c == "Rogue_Hooded" else c)) + (":bare" if bare else "")
	outfit["lower"] = "Rogue" if c == "Rogue_Hooded" else c
	if args.has("skin"):
		outfit["skin"] = args["skin"]
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.5, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.7
	env.environment.glow_enabled = true
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.5, 0.32)
	ground.material_override = gm
	root.add_child(ground)
	var body := Bodies.make(role, outfit)
	root.add_child(body)
	var h := 1.7 if role == "angel" else 1.7 * Bodies.DEMON_SCALE
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true
	# (characters face -Z in the game)
	var views := {
		"front": [Vector3(0, h * 0.62, -h * 1.9), Vector3(0, h * 0.5, 0)],
		"back": [Vector3(0, h * 0.62, h * 1.9), Vector3(0, h * 0.5, 0)],
		"left": [Vector3(h * 1.9, h * 0.6, 0), Vector3(0, h * 0.5, 0)],
		"right": [Vector3(-h * 1.9, h * 0.6, 0), Vector3(0, h * 0.5, 0)],
		"above": [Vector3(h * 1.2, h * 1.9, -h * 1.3), Vector3(0, h * 0.45, 0)],
		"head": [Vector3(0, h * 0.82, -h * 0.85), Vector3(0, h * 0.78, 0)],
		"headback": [Vector3(h * 0.4, h * 0.85, h * 0.85), Vector3(0, h * 0.78, 0)],
	}
	for f in 12:
		await process_frame
	for v in views:
		cam.position = views[v][0]
		cam.look_at(views[v][1])
		for f in 4:
			await process_frame
		get_root().get_texture().get_image().save_png("res://tools/previews/%s%s_%s%s.png" % [c, "_bare" if bare else "", v, tag])
	# crouching, from the side
	if body.get("crouching") != null:
		body.crouching = true
		for f in 40:
			await process_frame
		cam.position = views["left"][0]
		cam.look_at(views["left"][1])
		await process_frame
		get_root().get_texture().get_image().save_png("res://tools/previews/%s%s_crouch%s.png" % [c, "_bare" if bare else "", tag])
	# its pieces mixed with others: head on the first other character, its upper on another's legs
	body.queue_free()
	var others: Array = Characters.TEAM_CHARS[role].filter(func(o): return o != c and o != "Rogue_Hooded")
	var m1 := outfit.duplicate()
	m1["upper"] = others[0]
	m1["lower"] = others[0]
	var m2 := outfit.duplicate()
	m2["head"] = others[1]
	var a1 := Bodies.make(role, m1)
	var a2 := Bodies.make(role, m2)
	a1.position.x = -h * 0.45
	a2.position.x = h * 0.45
	root.add_child(a1)
	root.add_child(a2)
	cam.position = Vector3(0, h * 0.7, -h * 2.4)
	cam.look_at(Vector3(0, h * 0.5, 0))
	for f in 8:
		await process_frame
	get_root().get_texture().get_image().save_png("res://tools/previews/%s%s_mixed%s.png" % [c, "_bare" if bare else "", tag])
	print("previews saved for ", c)
	quit()
