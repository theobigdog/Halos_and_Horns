# A little yard built out of ground blocks, to look the paving, sidewalk and edging kinds over together at eye
# level (Nov 28): a sidewalk that turns a corner beside a road, the four pavings, and a lawn and beds lined with
# every edging. Run it hidden, like every tool that draws:
#   tools/render_hidden.ps1 -s res://tools/ground_demo.gd '--' --shot=0 --out=yard0
# writes tools/previews/_s_yard0.png.  --shot=0 the whole yard, 1 the sidewalk, 2 the pavings, 3 and 4 the edgings.
#   --low   Low graphics
extends SceneTree

const GroundBlock = preload("res://scripts/ground_block.gd")
const Graphics = preload("res://scripts/graphics.gd")

# [kind, size, where (bottom centre), turned (degrees), colour]
const YARD := [
	["grass", Vector3(30, 0.1, 24), Vector3(0, -0.1, 0), 0.0, "#ffffff"],
	["asphalt", Vector3(6, 0.1, 24), Vector3(-9, 0, 0), 0.0, "#ffffff"],
	# a sidewalk up the road, round the corner and along
	["sidewalk", Vector3(1.5, 0.15, 12), Vector3(-5.25, 0, 3), 0.0, "#ffffff"],
	["sidewalk", Vector3(9, 0.15, 1.5), Vector3(0, 0, -2.25), 0.0, "#ffffff"],
	["sidewalk", Vector3(3, 0.15, 3), Vector3(6, 0, -3), 0.0, "#ffffff"],
	# the four pavings, and two flagstone blocks side by side (one pattern across the join)
	["paving", Vector3(3, 0.1, 3), Vector3(-2.5, 0, 1), 0.0, "#ffffff"],
	["paving", Vector3(2, 0.1, 3), Vector3(0, 0, 1), 0.0, "#ffffff"],
	["crazy", Vector3(3, 0.1, 3), Vector3(3, 0, 1), 0.0, "#ffffff"],
	["cobbles", Vector3(3, 0.1, 3), Vector3(-2.5, 0, 4.5), 0.0, "#ffffff"],
	["pavers", Vector3(3, 0.1, 3), Vector3(1, 0, 4.5), 0.0, "#ffffff"],
	["pavers", Vector3(1.2, 0.1, 4), Vector3(4, 0, 5.6), 30.0, "#ffffff"],
	["paving", Vector3(3, 0.1, 3), Vector3(7.5, 0, 1.5), 0.0, "#8a7ab8"],
	# beds lined with each edging, turning a corner
	["flowerbed", Vector3(3, 0.12, 2), Vector3(-2.5, 0, 8.5), 0.0, "#ffffff"],
	["edge_rocks", Vector3(3.4, 0.14, 0.2), Vector3(-2.5, 0, 7.4), 0.0, "#ffffff"],
	["edge_rocks", Vector3(0.2, 0.14, 2.2), Vector3(-0.9, 0, 8.6), 0.0, "#ffffff"],
	["dirt", Vector3(3, 0.08, 2), Vector3(1.5, 0, 8.5), 0.0, "#ffffff"],
	["edge_fence", Vector3(3.2, 0.3, 0.1), Vector3(1.5, 0, 7.45), 0.0, "#ffffff"],
	["edge_fence", Vector3(0.1, 0.3, 2.1), Vector3(3.05, 0, 8.5), 0.0, "#ffffff"],
	["landscaping", Vector3(3, 0.1, 2), Vector3(5.5, 0, 8.5), 0.0, "#ffffff"],
	["edge_logs", Vector3(3.2, 0.22, 0.1), Vector3(5.5, 0, 7.45), 0.0, "#ffffff"],
	["edge_logs", Vector3(0.1, 0.22, 2.1), Vector3(7.05, 0, 8.5), 0.0, "#ffffff"],
	["edge_ceramic", Vector3(3, 0.2, 0.1), Vector3(-2.5, 0, 11), 0.0, "#ffffff"],
	["edge_ceramic", Vector3(3, 0.2, 0.1), Vector3(-2.5, 0, 11.6), 0.0, "#2f5fb0"],
	["edge_brick", Vector3(3, 0.12, 0.12), Vector3(1.5, 0, 11), 0.0, "#ffffff"],
	["edge_stone", Vector3(3, 0.14, 0.15), Vector3(1.5, 0, 11.6), 0.0, "#ffffff"],
	["edge_hedge", Vector3(3, 0.38, 0.32), Vector3(5.5, 0, 11), 0.0, "#ffffff"],
	["edge_rocks", Vector3(3, 0.14, 0.2), Vector3(5.5, 0, 11.8), 0.0, "#f2efe6"],
]

# [camera, looking at]
const SHOTS := [
	[Vector3(-2, 9, 20), Vector3(0, 0, 4)],
	[Vector3(-7.5, 1.7, 9), Vector3(-3.5, 0, -2)],
	[Vector3(0.5, 2.6, -1.5), Vector3(0.5, 0, 3.5)],
	[Vector3(1.5, 1.5, 5.6), Vector3(1.5, 0.1, 8.2)],
	[Vector3(1.5, 1.2, 9.3), Vector3(1.5, 0.1, 11.4)],
]


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.has("low"):
		Graphics.quality = 0
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 140, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	for y in YARD:
		var gb := GroundBlock.make(y[0], y[1], Color(str(y[4])))
		gb.position = y[2]
		gb.rotation_degrees.y = y[3]
		root.add_child(gb)
	var shot: Array = SHOTS[clampi(int(args.get("shot", "0")), 0, SHOTS.size() - 1)]
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	cam.current = true
	cam.position = shot[0]
	cam.look_at(shot[1])
	for f in 30:
		await process_frame
	var name := str(args.get("out", "yard"))
	vp.get_texture().get_image().save_png("res://tools/previews/_s_%s.png" % name)
	print("yard %s" % name)
	quit()
