# Renders a small picture of every piece in Creative's palette into assets/thumbs/ (needs a window,
# not --headless):   godot --resolution 640x480 -s res://tools/make_thumbs.gd
# Run it again after adding models or props. Creative shows these next to each name.
# -- --missing only makes the ones that don't exist yet; -- --only=a,b remakes just those files (e.g. prop_lamp).
extends SceneTree

const PropLib = preload("res://scripts/prop_library.gd")
const Models = preload("res://scripts/models.gd")
const Editor = preload("res://scripts/editor.gd")
const Bouncy = preload("res://scripts/bouncy.gd")
const Shrine = preload("res://scripts/shrine.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const OUT := "res://assets/thumbs"
const SIZE := 128     # rendered at this, saved at THUMB
const THUMB := 64

var vp: SubViewport
var cam: Camera3D
var stage: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.9
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	vp.add_child(cam)
	stage = Node3D.new()
	vp.add_child(stage)
	_run.call_deferred()


func _run() -> void:
	var jobs := []   # [file name, Callable making the node]
	for k in Editor.PIECES:
		var kind: String = k[0]
		jobs.append(["piece_" + kind, func(): return _special(kind)])
	for t in PropLib.type_names():
		var tn: String = t
		jobs.append([file_key("prop:" + tn), func(): return PropLib.make_visual(tn)])
	for id in Models.ids("structure"):
		var mid: String = id
		jobs.append([file_key("model:" + mid), func(): return Models.instance(mid)])
	for gk in GroundBlock.KINDS:
		var g: String = gk
		jobs.append([file_key("ground:" + g), func(): return GroundBlock.make(g, Vector3(3, 0.6, 3))])
	for bk in HollowBuildings.KINDS:
		var hk: String = bk
		jobs.append([file_key("building:" + hk), func(): return HollowBuildings.make(hk, 0)])
	var n := 0
	var user := " ".join(OS.get_cmdline_user_args())
	var only: Array = Array(user.get_slice("--only=", 1).get_slice(" ", 0).split(",", false)) if "--only=" in user else []
	for job in jobs:
		if "--missing" in user and FileAccess.file_exists("%s/%s.png" % [OUT, job[0]]) and not job[0] in only:
			continue
		if not only.is_empty() and not "--missing" in user and not job[0] in only:
			continue
		var node: Node3D = job[1].call()
		stage.add_child(node)
		_frame(node)
		for f in 3:
			await process_frame
		var img := vp.get_texture().get_image()
		img.resize(THUMB, THUMB, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s.png" % [OUT, job[0]])
		node.free()
		n += 1
	print("made %d thumbnails" % n)
	quit()


# assets/thumbs/<this>.png for a palette entry ("block", "prop:barrel", "model:dungeon/wall").
static func file_key(kind: String) -> String:
	return kind.replace(":", "_").replace("/", "__")


func _special(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"block", "cylinder":
			var mi := MeshInstance3D.new()
			if kind == "block":
				var b := BoxMesh.new()
				b.size = Vector3(4, 2, 4)
				mi.mesh = b
			else:
				var c := CylinderMesh.new()
				c.top_radius = 1.0
				c.bottom_radius = 1.0
				c.height = 3.0
				mi.mesh = c
			mi.material_override = PropLib.mat(Color("#a09080") if kind == "block" else Color("#8c8c99"), "stone")
			mi.position.y = 1.0 if kind == "block" else 1.5
			root.add_child(mi)
		"bouncy", "bouncy_once", "bouncy_super":
			var b := Bouncy.new()
			b.one_use = kind == "bouncy_once"
			b.super_bouncy = kind == "bouncy_super"
			root.add_child(b)
		"shrine":
			root.add_child(Shrine.new())
		"ice":
			root.add_child(load("res://scripts/main.gd").make_ice({"size": [4, 0.06, 4]}))
		"sidewalk":
			root.add_child(load("res://scripts/decor.gd").make_sidewalk({"size": [2.0, 0.18, 3.0]}))
		"window":
			var w: Node3D = load("res://scripts/decor.gd").make_window({"size": [1.0, 1.4, 0.02], "look": 0})
			w.position.y = 0.7
			root.add_child(w)
		"light":
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.4
			sm.height = 0.8
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#ffd9a0")
			m.emission_enabled = true
			m.emission = Color("#ffd9a0")
			m.emission_energy_multiplier = 2.0
			mi.material_override = m
			root.add_child(mi)
		"angel_spawn", "demon_spawn":
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.6
			c.bottom_radius = 0.6
			c.height = 0.15
			mi.mesh = c
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.9, 0.4) if kind == "angel_spawn" else Color(0.85, 0.2, 0.2)
			m.emission_enabled = true
			m.emission = m.albedo_color
			mi.material_override = m
			root.add_child(mi)
			var arrow := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.6, 1.0, 0.2)
			arrow.mesh = pm
			arrow.material_override = m
			arrow.position.y = 1.0
			arrow.rotation.z = PI
			root.add_child(arrow)
	return root


# Point the camera at it from up and to the side, close enough to fill the picture.
func _frame(node: Node3D) -> void:
	var box := AABB()
	var first := true
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var center := box.get_center()
	var radius := maxf(box.size.length() / 2.0, 0.05)
	var dist := radius / sin(deg_to_rad(cam.fov / 2.0)) * 1.02
	var dir := Vector3(0.75, 0.6, 1.0).normalized()
	cam.position = center + dir * dist
	cam.look_at(center)
	cam.near = maxf(dist * 0.02, 0.01)
	cam.far = dist * 4.0
