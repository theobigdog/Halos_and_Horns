# Creative mode: build your own maps.
#
# Fly around: hold the right mouse button to look, WASD to move, Space / E up,
# Ctrl / Q down, Shift to go faster, mouse wheel to zoom.
# Pick a piece on the left, then click in the world to put it there.
# Click a piece to select it, or press on it and drag to move it around (it slides
# over whatever's under the cursor: ground, roofs, other pieces). Or, once selected:
#   G move   R rotate   T resize (blocks, cylinders and structures)
#   Pull tabs (or V): a selected structure has glowing tabs at its ends; drag one and it repeats end
#   to end (walls, fences), posts and all. Floors have tabs on their sides too, to pull out a grid.
#     while doing it: X / Y / Z stick to one axis, L local or world axes,
#     hold Alt for no snapping, click or Enter to finish, Esc or right-click to undo it
#   Shift + mouse wheel: turn the piece you're about to place (or the selected one) around
#   Arrow keys nudge the selected piece one snap step (Alt: 1 cm), Page Up / Page Down raise and lower it
#   Ctrl+D copy   Delete remove   F fly to it   Ctrl+Z / Ctrl+Y undo / redo   Ctrl+S save
# The panel on the right takes exact numbers. 0, 0, 0 is the middle of the map, on the ground.
#
# A map is plain data (see map_data.gd). The editor only ever changes that data
# and rebuilds what it shows from it, so what you save is exactly what you saw.
#
# Building together online: see "building together" below. Every change is turned
# into small edits and sent through the host, who checks them and passes them on.
extends Node

const MapData = preload("res://scripts/map_data.gd")
const Decor = preload("res://scripts/decor.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const Backdrop = preload("res://scripts/backdrop.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Bouncy = preload("res://scripts/bouncy.gd")
const Models = preload("res://scripts/models.gd")
const Shrine = preload("res://scripts/shrine.gd")

const PIECES := [
	["block", "Block"], ["cylinder", "Cylinder"],
	["bouncy", "Bouncy (metal, reusable)"], ["bouncy_once", "Bouncy (wooden, 1-use)"],
	["bouncy_super", "Super Bouncy (magic, reusable)"],
	["light", "Light"], ["window", "Window picture (a room, or lit)"], ["sidewalk", "Sidewalk"], ["ice", "Ice (slippery)"], ["shrine", "Shrine"], ["angel_spawn", "Angel start"], ["demon_spawn", "Demon start"],
]
const ROTATES := ["block", "cylinder", "prop", "model", "light", "ice", "sidewalk", "window", "ground", "building"]       # the others always sit upright
const RESIZES := ["block", "cylinder", "model", "ice", "sidewalk", "window", "ground"]       # (a model's "size" is how much it's scaled on each axis)
const ONLY_ONE := ["shrine", "angel_spawn", "demon_spawn"]
const GRID_STEPS := [0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
const NUDGE_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN]
const WHEEL_TURN := 15.0       # Shift + wheel turns this many degrees a notch (Alt held: 1 degree)
const ANGLE_STEP := 15.0
const MAX_UNDO := 200
const FLY_SPEED := 12.0
const AXIS_COLORS := {"x": Color(1, 0.3, 0.3), "y": Color(0.4, 1, 0.4), "z": Color(0.4, 0.6, 1)}

var main
var map := {}                  # the map being built (MapData format)
var path := ""                 # where it was opened from / saved to
var dirty := false
var selected := -1
var _size_title: Label
var _palette_sections := []    # [header button, VBox of buttons] for each category
var _palette_groups := []      # [label, "Props" / "Structures"]
var _palette_scroll: ScrollContainer
var _palette_where: Label
var _palette_buttons := []     # [button, lowercase search text, its section]
var placing := ""              # armed palette piece: "block", "prop:barrel", ...
var drag := ""                 # "", "move", "rotate", "scale"
var axis := ""                 # "", "x", "y", "z"
var local_axes := false
var snapping := true
var grid := 0.5
var testing := false           # in a test round (the editor is asleep)

var root: Node3D               # what the pieces look like
var nodes := []                # piece index -> its node
var camera: Camera3D
var flying := false
var _yaw := 0.0
var _pitch := -0.6
var _undo := []
var _redo := []
var _change_tag := ""
var _change_time := 0.0
var _drag_before := ""         # the map as it was when a move/rotate/resize began
var _drag_piece := {}
# Grouping (Ted, Nov 25): the other pieces selected along with `selected` (Ctrl + click adds/removes; a
# piece with a "group" brings its whole group; Alt + click picks just the one). Moves, turns, deletes,
# copies and looks/colours apply to all of them.
var members: Array = []
var _group_label: Label
var _group_btn: Button
var _ungroup_btn: Button
var _member_start := {}       # index -> [position, basis] when a move/turn began
var _member_before := {}      # index -> piece copy (to undo a cancelled drag online)
const SHARE_KEYS := ["look", "color", "lights", "always", "flicker", "energy", "range", "spot", "angle"]
var _drag_mouse := Vector2.ZERO
var _drag_offset := Vector3.ZERO
var _drag_t0 := 0.0
var _surface := false          # moving by grabbing with the mouse: it follows whatever's under the cursor
var _grabbing := false         # ...and the button's still held (letting go drops it)
var _press_piece := -1         # the piece the left button went down on (dragging it grabs it)
var _press_at := Vector2.ZERO
var _confirm := ""             # a button waiting for a second click ("exit", "save")
var _lines: ImmediateMesh
var _boxes := {}               # piece index -> local AABB (for the selection outline)
var _undo_touched := []        # per undo step, online: the piece ids / "setting:key" we changed in it
var _redo_touched := []
var _undoing := false
var _id_count := 0
var _id_prefix := ""
var _preview: Node3D           # the see-through copy of the armed piece, under the mouse
var _preview_kind := ""
var _ext_axis := 0             # pulling a tab: 0 = along the row, 1 = across (floors)
var _ext_side := 1
var _tab_balls := []           # the pull tabs you see             # ...from the far end (1) or the near end (-1)
var place_yaw := 0.0           # degrees: how the next placed piece is turned (Shift + wheel)

# Building together online
const BUILDER_COLORS := [Color(0.3, 0.8, 1.0), Color(1.0, 0.45, 0.8), Color(0.5, 1.0, 0.4), Color(1.0, 0.6, 0.2),
		Color(0.75, 0.5, 1.0), Color(1.0, 1.0, 0.4), Color(0.3, 1.0, 0.85), Color(1.0, 0.35, 0.35)]
const CAM_RATE := 10.0         # times a second we tell the others where we're looking
var online := false
var hosting := false           # ...and this is the host's game
var can_edit := true           # false: the host made us view-only
var _synced := {}              # the shared map as we last knew it: {"pieces": {id: piece}, "settings": {...}}
var _my_claim := ""            # the piece we have selected (nobody else can touch it)
var claims := {}               # other builders: peer -> the piece id they have selected
var builders := {}             # other builders: peer -> {"name", "pos", "rot", "color", "can"}
var _ghosts := {}              # peer -> their floating marker
var _cam_accum := 0.0
var _builders_box: VBoxContainer
var _builders_sig := ""
var _left_panel: Control
var _new_button: Button
var _test_button: Button
var _extend_button: Button
var _top_panel: Control
var _light_range: SpinBox
var _light_energy: SpinBox
var _light_spot: CheckBox
var _light_tilt: SpinBox
var _light_always: CheckBox
var _light_flicker: SpinBox
var _look_pick: OptionButton
var _car_lights: CheckBox
var _weather_pick: OptionButton
var _backdrop_pick: OptionButton
var _cycle_pick: OptionButton
var _light_angle: SpinBox
var _time_pick: OptionButton
var _right_panel: Control

# UI
var ui: CanvasLayer
var status: Label
var _status_time := 0.0
var _name_edit: LineEdit
var _author_edit: LineEdit
var _setting_spins := {}       # "size" / "ceiling" / "random_props" -> SpinBox
var _ground_pick: ColorPickerButton
var _wall_pick: ColorPickerButton
var _open_pick: OptionButton
var _exit_button: Button
var _save_button: Button
var _inspector: VBoxContainer
var _insp_title: Label
var _spins := {}               # "pos0".."size2" -> SpinBox
var _rows := {}                # "pos" / "rot" / "size" -> row container
var _color_pick: ColorPickerButton
var _prop_pick: OptionButton
var _snap_check: CheckBox
var _local_check: CheckBox


# ---------------- entering and leaving ----------------

func enter(start_map: Dictionary, start_path := "") -> void:
	testing = false
	map = MapData.clean(start_map)
	path = start_path if MapData.is_saveable(start_path) else ""
	shared_save = MapData.is_shared(path)
	_remember_disk()
	dirty = false
	_undo.clear()
	_redo.clear()
	_undo_touched.clear()
	_redo_touched.clear()
	online = false
	hosting = false
	can_edit = true
	claims.clear()
	_my_claim = ""
	_id_prefix = "l%s-" % _rand_tag()
	if root == null:
		_build_scene()
		_build_ui()
	root.visible = true
	ui.visible = true
	camera.current = true
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_frame_whole_map()
	_online_ui()
	_say("Pick a piece on the left, then click in the world to place it.", 6.0)


# Going off to test the map: hide everything, keep the work.
func sleep() -> void:
	_end_drag(false)
	placing = ""
	_clear_preview()
	_set_flying(false)
	root.visible = false
	ui.visible = false


func wake() -> void:
	testing = false
	root.visible = true
	ui.visible = true
	camera.current = true
	_rebuild_ground()
	_say("Back in Creative.", 3.0)


func leave() -> void:
	sleep()
	testing = false
	online = false
	hosting = false
	can_edit = true
	claims.clear()
	builders.clear()
	for g in _ghosts.values():
		g.queue_free()
	_ghosts.clear()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()


func active() -> bool:
	return root != null and root.visible


# ---------------- the 3D side ----------------

func _build_scene() -> void:
	root = Node3D.new()
	root.name = "Creative"
	add_child(root)
	camera = Camera3D.new()
	camera.far = 600.0
	root.add_child(camera)
	var mi := MeshInstance3D.new()
	_lines = ImmediateMesh.new()
	mi.mesh = _lines
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 10
	mi.material_override = m
	root.add_child(mi)


# The ground and outer walls come from the game itself (same as in a real round).
func _rebuild_ground() -> void:
	var shell := map.duplicate(true)
	shell["pieces"] = []
	main.load_map(shell, "")


func _rebuild_all() -> void:
	members.clear()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	_boxes.clear()
	for i in map["pieces"].size():
		nodes.append(_make_node(map["pieces"][i], i))


func _refresh_piece(i: int) -> void:
	if i < 0 or i >= nodes.size():
		return
	if is_instance_valid(nodes[i]):
		nodes[i].free()
	nodes[i] = _make_node(map["pieces"][i], i)


func _make_node(p: Dictionary, i: int) -> Node3D:
	var n := Node3D.new()
	n.set_meta("piece_index", i)
	var t: String = p["type"]
	match t:
		"block", "cylinder":
			var size := MapData.vec(p["size"])
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var mi := MeshInstance3D.new()
			if t == "cylinder":
				var shape := CylinderShape3D.new()
				shape.radius = size.x / 2.0
				shape.height = size.y
				cs.shape = shape
				var mesh := CylinderMesh.new()
				mesh.top_radius = size.x / 2.0
				mesh.bottom_radius = size.x / 2.0
				mesh.height = size.y
				mi.mesh = mesh
			else:
				var shape := BoxShape3D.new()
				shape.size = size
				cs.shape = shape
				var mesh := BoxMesh.new()
				mesh.size = size
				mi.mesh = mesh
			mi.material_override = PropLib.mat(Color(p["color"]))
			body.add_child(cs)
			body.add_child(mi)
			n.add_child(body)
		"prop":
			var body := StaticBody3D.new()
			var pt := PropLib.scaled(p["prop"], p.get("scale", 1.0))
			body.add_child(PropLib.make_visual(pt))
			var cs := CollisionShape3D.new()
			cs.shape = PropLib.make_shape(pt)
			cs.position.y = PropLib.height(pt) / 2.0
			body.add_child(cs)
			n.add_child(body)
		"model":
			var msc := MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
			var row := Models.make_row(p["model"], msc, int(p.get("repeat", 1)), int(p.get("repeat2", 1)), int(p.get("look", 0)))
			if p.has("color"):
				Models.recolor(row, Color(p["color"]))
			n.add_child(row)
			if p.get("lights", false):
				n.add_child(Models.car_lights(p["model"], msc))
		"ice":
			n.add_child(main.make_ice(p))
		"ground":
			n.add_child(GroundBlock.make(GroundBlock.KINDS.keys()[int(p.get("look", 0))], MapData.vec(p["size"])))
		"building":
			n.add_child(HollowBuildings.make(p["kind"], int(p.get("look", 0))))
		"sidewalk":
			n.add_child(Decor.make_sidewalk(p))
		"window":
			n.add_child(Decor.make_window(p))
			var wsz := MapData.vec(p["size"])
			_add_pick_box(n, Vector3(wsz.x, wsz.y, 0.1), -wsz.y / 2.0)
		"light":
			n.add_child(main.make_lamp(p, Vector3.ZERO))
			_add_pick_box(n, Vector3(0.5, 0.5, 0.5), -0.25)
		"bouncy", "bouncy_once", "bouncy_super":
			var b := Bouncy.new()
			b.one_use = t == "bouncy_once"
			b.super_bouncy = t == "bouncy_super"
			b.skin = int(p.get("look", 0))
			n.add_child(b)
		"shrine":
			n.add_child(Shrine.new())
			_add_pick_box(n, Vector3(3.2, 2.0, 3.2))
		"angel_spawn", "demon_spawn":
			_add_marker(n, t == "angel_spawn")
	root.add_child(n)
	n.position = MapData.vec(p["pos"])
	if t in ROTATES:
		n.rotation = MapData.rot_rad(p)
	_boxes[i] = _local_box(n)
	return n


# Something to click on, for pieces that are mostly air.
# The Look list: a structure's wear (weathered, mossy...) or a window picture's room.
var _looks_for := ""


func _fill_looks(t: String) -> void:
	var kind := t if t in ["window", "bouncy", "bouncy_once", "bouncy_super", "ground", "building"] else "model"
	if kind == _looks_for:
		return
	_looks_for = kind
	_look_pick.clear()
	var names: Array = Models.LOOK_NAMES
	match kind:
		"window": names = Decor.WINDOW_LOOKS
		"bouncy": names = Bouncy.skin_names("metal")
		"bouncy_once": names = Bouncy.skin_names("wood")
		"bouncy_super": names = Bouncy.skin_names("super")
		"ground": names = GroundBlock.KINDS.values()
		"building": names = ["Colours 1", "Colours 2", "Colours 3", "Colours 4"]
	for ln in names:
		_look_pick.add_item(ln)


func _add_pick_box(n: Node3D, size: Vector3, y_from := 0.0) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = size.y / 2.0 + y_from
	body.add_child(cs)
	n.add_child(body)


# Where each team starts (Creative only): angels a golden circle under a soft beam of light with a
# halo floating in it, demons a scorched circle with a glowing red star and a pair of horns above.
func _add_marker(n: Node3D, angel: bool) -> void:
	var color := Color(1.0, 0.85, 0.35) if angel else Color(0.95, 0.18, 0.1)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 1.8
	# the circle on the ground
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.25
	dm.bottom_radius = 1.25
	dm.height = 0.03
	disc.mesh = dm
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(1.0, 0.95, 0.8, 0.35) if angel else Color(0.08, 0.02, 0.02, 0.75)
	floor_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = floor_m
	disc.position.y = 0.02
	n.add_child(disc)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
	rm.ring_segments = 12
	rm.inner_radius = 1.18
	rm.outer_radius = 1.3
	ring.mesh = rm
	ring.material_override = glow
	ring.scale.y = 0.3
	ring.position.y = 0.04
	n.add_child(ring)
	if angel:
		# a soft beam of light
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.75
		bm.bottom_radius = 1.15
		bm.height = 4.5
		beam.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 0.93, 0.7, 0.14)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = bmat
		beam.position.y = 2.25
		n.add_child(beam)
		var halo := MeshInstance3D.new()
		var hm := TorusMesh.new()
		hm.rings = 32   # (Godot's default 64 x 32 is ~4000 triangles; Nov 26 audit)
		hm.ring_segments = 12
		hm.inner_radius = 0.32
		hm.outer_radius = 0.42
		halo.mesh = hm
		halo.material_override = glow
		halo.position.y = 2.0
		halo.rotation.x = 0.25
		n.add_child(halo)
		for side in [-1.0, 1.0]:   # little wings either side of the halo
			var wing := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.5, 0.16, 0.03)
			wing.mesh = wm
			var white := StandardMaterial3D.new()
			white.albedo_color = Color(1, 1, 0.97)
			white.emission_enabled = true
			white.emission = Color(1, 0.97, 0.9)
			white.emission_energy_multiplier = 0.6
			wing.material_override = white
			wing.position = Vector3(0.62 * side, 2.05, 0)
			wing.rotation.z = 0.35 * side
			n.add_child(wing)
	else:
		# a five-pointed star in the circle, drawn in glowing red lines
		var pts := []
		for k in 5:
			var a := TAU * k / 5.0 - PI / 2.0
			pts.append(Vector3(cos(a), 0.05, sin(a)) * 1.1)
		for k in 5:
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[(k + 2) % 5]
			var line := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(p0.distance_to(p1), 0.02, 0.06)
			line.mesh = lm
			line.material_override = glow
			line.position = (p0 + p1) * 0.5
			line.rotation.y = -atan2(p1.z - p0.z, p1.x - p0.x)
			n.add_child(line)
		# a pair of horns floating above
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.15, 0.06, 0.06)
		dark.emission_enabled = true
		dark.emission = Color(0.5, 0.05, 0.02)
		for side in [-1.0, 1.0]:
			var horn := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.12
			cm.height = 0.6
			horn.mesh = cm
			horn.material_override = dark
			horn.position = Vector3(0.22 * side, 1.9, 0)
			horn.rotation.z = -0.5 * side
			n.add_child(horn)
		var eye_m := StandardMaterial3D.new()
		eye_m.albedo_color = Color(1.0, 0.3, 0.1)
		eye_m.emission_enabled = true
		eye_m.emission = Color(1.0, 0.3, 0.1)
		eye_m.emission_energy_multiplier = 3.0
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radial_segments = 12   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
			em.rings = 6
			em.radius = 0.06
			em.height = 0.12
			eye.mesh = em
			eye.material_override = eye_m
			eye.position = Vector3(0.12 * side, 1.62, 0)
			n.add_child(eye)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 3.5
	light.position.y = 1.0
	n.add_child(light)
	var tag := Label3D.new()
	tag.text = "ANGELS START HERE" if angel else "DEMONS START HERE"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.01
	tag.modulate = color.lightened(0.3)
	tag.position.y = 2.9
	n.add_child(tag)
	_add_pick_box(n, Vector3(1.2, 2.0, 1.2))


# The piece's size in its own space, from what it looks like.
func _local_box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null or not mi.visible:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return box


# ---------------- changing the map (everything goes through these) ----------------

func piece(i: int) -> Dictionary:
	return map["pieces"][i]


# Remember how things were, for undo. Changes with the same tag close together
# (dragging a number, typing a name) count as one step.
func _begin_change(tag := "") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if tag == "" or tag != _change_tag or now - _change_time > 1.0:
		_push_undo(JSON.stringify(map))
		_redo.clear()
		_redo_touched.clear()
	_change_tag = tag
	_change_time = now
	dirty = true
	_confirm = ""


func _push_undo(text: String) -> void:
	_undo.append(text)
	_undo_touched.append({})
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
		_undo_touched.pop_front()


func _rand_tag() -> String:
	var chars := "abcdefghijkmnpqrstuvwxyz23456789"
	var t := ""
	for i in 4:
		t += chars[randi() % chars.length()]
	return t


func _new_id() -> String:
	_id_count += 1
	return "%s%d" % [_id_prefix, _id_count]


# A brand-new piece of this kind, standing at this spot (not added to the map).
func _new_piece(kind: String, at: Vector3) -> Dictionary:
	var p := {"type": kind, "pos": [at.x, at.y, at.z]}
	if kind.begins_with("prop:"):
		p = {"type": "prop", "prop": kind.substr(5), "pos": [at.x, at.y, at.z]}
	elif kind.begins_with("ground:"):
		p = {"type": "ground", "look": GroundBlock.KINDS.keys().find(kind.substr(7)), "size": [4.0, 0.3, 4.0], "pos": [at.x, at.y, at.z]}
	elif kind.begins_with("building:"):
		p = {"type": "building", "kind": kind.substr(9), "look": 0, "pos": [at.x, at.y, at.z]}
	elif kind.begins_with("model:"):
		p = {"type": "model", "model": kind.substr(6), "pos": [at.x, at.y, at.z]}
	elif kind == "block":
		p["size"] = [4.0, 2.0, 4.0]
		p["pos"][1] = at.y + 1.0
		p["color"] = "#a09080"
	elif kind == "ice":
		p["size"] = [4.0, 0.06, 4.0]
		p["pos"][1] = at.y + 0.03
	elif kind == "sidewalk":
		p["size"] = [2.0, 0.18, 6.0]
	elif kind == "window":
		p["size"] = [1.0, 1.4, 0.02]
		p["look"] = 0
		p["pos"][1] = at.y + 1.2
	elif kind == "light":
		p["pos"][1] = at.y + 0.4   # (right where you point: it was 2.5 m up, "way above the cursor")
		p["color"] = "#ffd9a0"
		p["range"] = 8.0
		p["energy"] = 1.5
	elif kind == "cylinder":
		p["size"] = [2.0, 3.0, 2.0]
		p["pos"][1] = at.y + 1.5
		p["color"] = "#8c8c99"
	if p["type"] in ROTATES and place_yaw != 0.0:
		p["rot"] = [0.0, place_yaw, 0.0]
	return p


func place(kind: String, at: Vector3) -> int:
	if not _may_edit():
		return -1
	var p := _new_piece(kind, at)
	p["id"] = _new_id()
	if kind in ONLY_ONE:
		for i in map["pieces"].size():
			if piece(i)["type"] == kind:
				if _claimed_by_other(piece_id(i)) != 0:
					_say("Someone else is working on that one right now.", 3.0)
					return -1
				_begin_change()
				piece(i)["pos"] = p["pos"]
				_refresh_piece(i)
				select(i)
				_say("A map has just one of those: moved it here.", 3.0)
				_after_change()
				return i
	_begin_change()
	map["pieces"].append(_cleaned_piece(p))
	var i: int = map["pieces"].size() - 1
	nodes.append(_make_node(piece(i), i))
	select(i)
	_after_change()
	return i


# Run one piece through the same checks a loaded map gets.
func _cleaned_piece(p: Dictionary) -> Dictionary:
	var m := MapData.clean({"pieces": [p]})
	for q in m["pieces"]:
		if q["type"] == p["type"]:
			return q
	return m["pieces"][0]


func set_value(i: int, key: String, value, tag := "") -> void:
	if i < 0 or i >= map["pieces"].size() or not _may_edit():
		return
	_begin_change(tag if tag != "" else "%d:%s" % [i, key])
	var p := piece(i)
	if value is Vector3:
		p[key] = [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
	else:
		p[key] = value
	map["pieces"][i] = _cleaned_piece(p)
	_refresh_piece(i)
	if i == selected and key in SHARE_KEYS:
		# the same look / colour / light setting on every selected piece of the same kind
		for m in members:
			var q := piece(m)
			if q.is_empty() or q["type"] != p["type"]:
				continue
			q[key] = value
			map["pieces"][m] = _cleaned_piece(q)
			_refresh_piece(m)
	if i == selected:
		_sync_inspector()
	_after_change()


# Move every other selected piece by `delta` (they keep their places relative to the main one).
func _shift_members(delta: Vector3) -> void:
	for m in members:
		var q := piece(m)
		if q.is_empty():
			continue
		var np := MapData.vec(q["pos"]) + delta
		q["pos"] = [snappedf(np.x, 0.001), snappedf(np.y, 0.001), snappedf(np.z, 0.001)]
		if m < nodes.size() and is_instance_valid(nodes[m]):
			nodes[m].position = np


func delete_selected() -> void:
	if selected < 0 or not _may_edit():
		return
	var t: String = piece(selected)["type"]
	if t in ["angel_spawn", "demon_spawn"] and members.is_empty():
		_say("Every map needs an angel start and a demon start: move it instead.", 4.0)
		return
	_begin_change()
	var gone: Array = [selected] + members
	gone = gone.filter(func(k): return not piece(k)["type"] in ["angel_spawn", "demon_spawn"])
	gone.sort()
	gone.reverse()
	for k in gone:
		map["pieces"].remove_at(k)
	_rebuild_all()
	select(-1)
	_after_change()
	if gone.size() > 1:
		_say("Removed %d pieces." % gone.size(), 2.5)


func duplicate_selected() -> int:
	if selected < 0 or not _may_edit():
		return -1
	var p: Dictionary = piece(selected).duplicate(true)
	if p["type"] in ONLY_ONE:
		_say("A map has just one of those.", 3.0)
		return -1
	_begin_change()
	var others: Array = []
	var new_groups := {}
	for src in [selected] + members:
		var q: Dictionary = piece(src).duplicate(true)
		if q["type"] in ONLY_ONE:
			continue
		q["pos"] = [q["pos"][0] + grid * 2.0, q["pos"][1], q["pos"][2] + grid * 2.0]
		q["id"] = _new_id()
		if q.has("group"):   # (a copied group is a new group of its own)
			if not new_groups.has(q["group"]):
				new_groups[q["group"]] = "g" + _rand_tag()
			q["group"] = new_groups[q["group"]]
		map["pieces"].append(q)
		var k: int = map["pieces"].size() - 1
		nodes.append(_make_node(piece(k), k))
		others.append(k)
	if others.is_empty():
		_say("A map has just one of those.", 3.0)
		return -1
	var i: int = others.pop_front()
	select(i, true)
	members = others
	_sync_inspector()
	_after_change()
	return i


# Ctrl + G: the selected pieces become a group (clicking one selects them all). Ctrl + Shift + G undoes it.
func group_selected() -> void:
	if selected < 0 or members.is_empty() or not _may_edit():
		_say("Select two or more pieces first (Ctrl + click adds pieces).", 3.0)
		return
	_begin_change()
	var gid := "g" + _rand_tag()
	for k in [selected] + members:
		var q := piece(k)
		q["group"] = gid
		map["pieces"][k] = _cleaned_piece(q)
	_after_change()
	_sync_inspector()
	_say("Grouped %d pieces: clicking any of them selects them all. (Alt + click picks just one; Ctrl + Shift + G ungroups.)" % (members.size() + 1), 5.0)


func ungroup_selected() -> void:
	if selected < 0 or not _may_edit():
		return
	_begin_change()
	var n := 0
	for k in [selected] + members:
		var q := piece(k)
		if q.has("group"):
			q.erase("group")
			map["pieces"][k] = _cleaned_piece(q)
			n += 1
	_after_change()
	_sync_inspector()
	_say("Ungrouped %d pieces (they stay selected for now)." % n if n > 0 else "Those aren't grouped.", 3.0)


# Ctrl + click: add a piece to the selection, or take it out.
func toggle_member(i: int) -> void:
	if i < 0:
		return
	if selected < 0:
		select(i)
		return
	if online and _claimed_by_other(piece_id(i)) != 0:
		_say("Someone else is working on that one.", 2.5)
		return
	var add := [i] + _group_mates(i)
	if i == selected or members.has(i):
		for k in add:
			members.erase(k)
		if i == selected:
			if members.is_empty():
				select(-1)
				return
			var nxt: int = members.pop_front()
			var rest := members.duplicate()
			select(nxt, true)
			members = rest
	else:
		for k in add:
			if k != selected and not members.has(k):
				members.append(k)
	_sync_inspector()
	_say("%d pieces selected. (Ctrl + G to group them for good.)" % (members.size() + 1), 3.0)


func _group_mates(i: int) -> Array:
	var out := []
	var g = piece(i).get("group")
	if g == null:
		return out
	for k in map["pieces"].size():
		if k != i and map["pieces"][k].get("group") == g and (not online or _claimed_by_other(piece_id(k)) == 0):
			out.append(k)
	return out


func undo() -> void:
	if not _may_edit():
		return
	if _undo.is_empty():
		_say("Nothing to undo.", 2.0)
		return
	_end_drag(true)
	if _undo.is_empty():
		return
	var touched: Dictionary = _undo_touched.pop_back()
	_redo.append(JSON.stringify(map))
	_redo_touched.append(touched)
	_restore(_undo.pop_back(), touched)
	_say("Undone.", 1.5)


func redo() -> void:
	if not _may_edit():
		return
	if _redo.is_empty():
		_say("Nothing to redo.", 2.0)
		return
	_end_drag(true)
	if _redo.is_empty():
		return
	var touched: Dictionary = _redo_touched.pop_back()
	_undo.append(JSON.stringify(map))
	_undo_touched.append(touched)
	_restore(_redo.pop_back(), touched)
	_say("Redone.", 1.5)


# Online, undo only puts back the things we changed in that step (touched), leaving everyone else's work alone.
func _restore(text: String, touched := {}) -> void:
	var was_size: float = map["size"]
	var was_ground: String = map["ground_color"] + map["wall_color"]
	if online:
		_restore_parts(MapData.clean(JSON.parse_string(text)), touched)
		return
	map = MapData.clean(JSON.parse_string(text))
	_change_tag = ""
	dirty = true
	var keep := selected if selected < map["pieces"].size() else -1
	_rebuild_all()
	if map["size"] != was_size or map["ground_color"] + map["wall_color"] != was_ground:
		_rebuild_ground()
	_sync_settings()
	select(keep)


func set_setting(key: String, value) -> void:
	if map.get(key) == value or not _may_edit():
		return
	_begin_change("setting:" + key)
	map[key] = value
	map = MapData.clean(map)
	if key in ["size", "ground_color", "wall_color", "time", "weather", "cycle", "backdrop"]:
		_rebuild_ground()
	_after_change()


# ---------------- selecting ----------------

func select(i: int, keep_members := false) -> void:
	if not keep_members:
		members.clear()
	if online and i >= 0 and i < map["pieces"].size():
		var who := _claimed_by_other(piece_id(i))
		if who != 0 or not can_edit:
			if who != 0:
				_say("%s is working on that one." % builders.get(who, {}).get("name", "Someone"), 3.0)
			i = -1
	selected = i if i >= 0 and i < map["pieces"].size() else -1
	if online:
		var want := piece_id(selected) if selected >= 0 else ""
		if want != _my_claim:
			_my_claim = want
			main.net.build_claim(want)
	if not keep_members and selected >= 0 and not Input.is_key_pressed(KEY_ALT):
		members = _group_mates(selected)
	_sync_inspector()


func _piece_under(screen_pos: Vector2) -> int:
	var hit := _ray_hit(screen_pos, true)
	if hit.is_empty():
		return -1
	var n = hit["collider"]
	while n != null and n != root:
		if n.has_meta("piece_index"):
			return n.get_meta("piece_index")
		n = n.get_parent()
	return -1


func _ray_hit(screen_pos: Vector2, pieces_only := false) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0)
	q.collide_with_areas = false
	q.collision_mask = 1
	var space := root.get_world_3d().direct_space_state
	for _i in 8:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		if not pieces_only or _is_piece(hit["collider"]):
			return hit
		q.exclude = q.exclude + [hit["rid"]]
	return {}


func _is_piece(n) -> bool:
	while n != null and n != root:
		if n is Node and n.has_meta("piece_index"):
			return true
		n = n.get_parent()
	return false


# Where a click lands: on top of whatever's under the mouse, or the ground plane.
func _place_point(screen_pos: Vector2) -> Vector3:
	var hit := _ray_hit(screen_pos)
	var p: Vector3
	if not hit.is_empty():
		p = hit["position"]
	else:
		var from := camera.project_ray_origin(screen_pos)
		var dir := camera.project_ray_normal(screen_pos)
		var g = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
		p = g if g != null else from + dir * 10.0
	if _snap_on():
		p.x = snappedf(p.x, grid)
		p.z = snappedf(p.z, grid)
	return p


# ---------------- move / rotate / resize ----------------

func begin(kind: String) -> void:
	if not _may_edit():
		return
	if kind == "extend" and drag == "":
		_ext_axis = 0
		_ext_side = 1
	if selected < 0:
		_say("Select a piece first (click it).", 2.0)
		return
	var t: String = piece(selected)["type"]
	if kind == "rotate" and not t in ROTATES:
		_say("That always sits upright.", 2.0)
		return
	if kind == "extend" and t != "model":
		_say("Only structures (walls, fences...) can be extended. Blocks can just be resized (T).", 3.0)
		return
	if kind == "scale" and not t in RESIZES:
		_say("Only blocks, cylinders and structures can be resized.", 2.0)
		return
	_end_drag(true)
	drag = kind
	axis = ""
	_drag_before = JSON.stringify(map)
	_drag_piece = piece(selected).duplicate(true)
	_member_start.clear()
	_member_before.clear()
	for m in members:
		var q := piece(m)
		_member_start[m] = [MapData.vec(q["pos"]), Basis.from_euler(MapData.rot_rad(q))]
		_member_before[m] = q.duplicate(true)
	_drag_mouse = _mouse()
	_drag_offset = Vector3.ZERO
	if kind == "move":
		_start_move_ray()
	if kind == "extend":
		_say("Extending: move the mouse along it to add copies end to end. Click to finish, Esc to cancel.", 999.0)
		return
	_say({"move": "Moving", "rotate": "Rotating", "scale": "Resizing"}[kind] + ": X / Y / Z for one axis, L local/world, Alt no snap. Click to finish, Esc to cancel.", 999.0)


func set_axis(a: String) -> void:
	axis = "" if axis == a else a
	_surface = false   # an axis means exact: stop following surfaces
	if drag == "move":
		_start_move_ray()


func _axis_dir(a: String) -> Vector3:
	var v := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[a] as Vector3
	if local_axes:
		v = Basis.from_euler(MapData.rot_rad(_drag_piece)) * v
	return v.normalized()


func _start_move_ray() -> void:
	# Restart from the original spot so changing axis mid-move doesn't jump.
	if selected < 0 or _drag_piece.is_empty():
		return
	piece(selected)["pos"] = _drag_piece["pos"].duplicate()
	var r := _mouse_ray(_mouse())
	var start := MapData.vec(_drag_piece["pos"])
	if axis == "":
		var hit = Plane(Vector3.UP, start.y).intersects_ray(r[0], r[1])
		_drag_offset = (start - hit) if hit != null else Vector3.ZERO
	else:
		_drag_t0 = _along_axis(start, _axis_dir(axis), r[0], r[1])


func _along_axis(start: Vector3, d: Vector3, ray_from: Vector3, ray_dir: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(start - d * 1000.0, start + d * 1000.0, ray_from, ray_from + ray_dir * 2000.0)
	return (pts[0] - start).dot(d)


func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _mouse_ray(screen_pos: Vector2) -> Array:
	return [camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos)]


# The mouse moved during a move/rotate/resize. Takes the mouse ray and screen
# position directly so tests can drive it too.
func drag_update(ray_from: Vector3, ray_dir: Vector3, mouse_pos: Vector2) -> void:
	if drag == "" or selected < 0:
		return
	var p := piece(selected)
	var snap := _snap_on()
	var start := MapData.vec(_drag_piece["pos"])
	match drag:
		"move":
			var pos := start
			if axis == "" and _surface:
				# Follow whatever's under the cursor (ground, roofs, other pieces), resting on top of it.
				var on := _surface_point(ray_from, ray_dir)
				pos = Vector3(on.x + _drag_offset.x, on.y + _rest_height(p), on.z + _drag_offset.z)
				if snap:
					pos.x = snappedf(pos.x, grid)
					pos.z = snappedf(pos.z, grid)
			elif axis == "":
				if absf(ray_dir.y) < 0.03:
					return   # looking level with the ground: the hit would be miles away
				var hit = Plane(Vector3.UP, start.y).intersects_ray(ray_from, ray_dir)
				if hit == null:
					return
				pos = hit + _drag_offset
				if snap:
					pos.x = snappedf(pos.x, grid)
					pos.z = snappedf(pos.z, grid)
			else:
				var d := _axis_dir(axis)
				if absf(d.dot(ray_dir)) > 0.985:
					return   # looking straight along the axis: no sensible answer
				var t := _along_axis(start, d, ray_from, ray_dir) - _drag_t0
				if snap:
					t = snappedf(t, grid)
				pos = start + d * t
			# (Ted, Nov 20: pieces sometimes shot to y = -500. A ray almost parallel to the plane or axis
			# lands absurdly far away; never jump a piece that far in one mouse move.)
			if not pos.is_finite() or pos.distance_to(start) > 250.0 or absf(pos.y) > 300.0:
				return
			p["pos"] = [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)]
			nodes[selected].position = pos
			for m in _member_start:   # the rest of the selection comes along
				var mp: Vector3 = _member_start[m][0] + (pos - start)
				piece(m)["pos"] = [snappedf(mp.x, 0.001), snappedf(mp.y, 0.001), snappedf(mp.z, 0.001)]
				if m < nodes.size() and is_instance_valid(nodes[m]):
					nodes[m].position = mp
		"extend":
			# The pulled end follows the mouse across the ground: whole copies get added (or taken away),
			# never stretched. The other end stays put.
			var ax := _ext_steps(_drag_piece)[_ext_axis] as Vector3
			# (measured across the ground: a staircase's step also goes up)
			var flat := Vector3(ax.x, 0.0, ax.z)
			var w := maxf(flat.length(), 0.05)
			var dir := flat / w
			var key := "repeat" if _ext_axis == 0 else "repeat2"
			var n0 := int(_drag_piece.get(key, 1))
			if absf(ray_dir.y) < 0.03:
				return
			var hit = Plane(Vector3.UP, start.y + 0.01).intersects_ray(ray_from, ray_dir)
			if hit == null or (hit - start).length() > 250.0:
				return
			var count := 1
			var first := start
			var flat_start := Vector3(start.x, hit.y, start.z)
			if _ext_side > 0:
				var from_edge: float = (hit - (flat_start - dir * w * 0.5)).dot(dir)
				count = clampi(roundi(from_edge / w), 1, MapData.MAX_REPEAT)
			else:
				var far_edge := flat_start + dir * w * (n0 - 0.5)
				var back: float = (far_edge - hit).dot(dir)
				count = clampi(roundi(back / w), 1, MapData.MAX_REPEAT)
				first = start - ax * (count - n0)   # (the top end stays put; stairs come down to meet the ground)
			var other := int(_drag_piece.get("repeat2" if _ext_axis == 0 else "repeat", 1))
			count = mini(count, MapData.MAX_GRID / maxi(other, 1))
			p["pos"] = [snappedf(first.x, 0.001), snappedf(first.y, 0.001), snappedf(first.z, 0.001)]
			if count > 1:
				p[key] = count
			else:
				p.erase(key)
			_refresh_piece(selected)
			var r1 := int(p.get("repeat", 1))
			var r2 := int(p.get("repeat2", 1))
			_say(("Extending: %d in a row" % r1 if r2 <= 1 else "Extending: %d x %d" % [r1, r2]) + ". Let go to finish, Esc to cancel.", 999.0)
		"rotate":
			var amount := (mouse_pos.x - _drag_mouse.x) * 0.5
			if snap:
				amount = snappedf(amount, ANGLE_STEP)
			var ax := "y" if axis == "" else axis
			var unit := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[ax] as Vector3
			var b0 := Basis.from_euler(MapData.rot_rad(_drag_piece))
			var b := (b0 * Basis(unit, deg_to_rad(amount))) if local_axes else (Basis(unit, deg_to_rad(amount)) * b0)
			var e := b.get_euler()
			p["rot"] = [snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)]
			nodes[selected].rotation = e
			var turn := b * b0.inverse()   # the rest of the selection swings round with it
			for m in _member_start:
				var mp: Vector3 = start + turn * (_member_start[m][0] - start)
				var me := (turn * (_member_start[m][1] as Basis)).get_euler()
				var mq := piece(m)
				mq["pos"] = [snappedf(mp.x, 0.001), snappedf(mp.y, 0.001), snappedf(mp.z, 0.001)]
				if mq["type"] in ROTATES:
					mq["rot"] = [snappedf(rad_to_deg(me.x), 0.01), snappedf(rad_to_deg(me.y), 0.01), snappedf(rad_to_deg(me.z), 0.01)]
				if m < nodes.size() and is_instance_valid(nodes[m]):
					nodes[m].position = mp
					if mq["type"] in ROTATES:
						nodes[m].rotation = me
		"scale":
			var factor := maxf(1.0 + (mouse_pos.x - _drag_mouse.x) * 0.006, 0.02)
			var is_model: bool = p["type"] == "model"
			var s0 := MapData.vec(_drag_piece["size"]) if _drag_piece.has("size") else Vector3.ONE
			var s := s0
			var which := ["x", "y", "z"] if axis == "" else [axis]
			if p["type"] == "cylinder" and ("x" in which or "z" in which):
				which = which + ["x", "z"]   # it's round: width and depth go together
			for a in which:
				var v: float = s0[a] * factor
				if snap:
					v = maxf(snappedf(v, 0.05), 0.05) if is_model else maxf(snappedf(v, grid), grid)
				s[a] = clampf(v, 0.1, 10.0) if is_model else clampf(v, 0.05, 400.0)
			p["size"] = [s.x, s.y, s.z]
			_refresh_piece(selected)
	_sync_inspector()


# Grab the selected piece with the mouse: it follows the surface under the cursor.
func grab(ray_from: Vector3, ray_dir: Vector3) -> void:
	begin("move")
	if drag != "move":
		return
	_surface = true
	_grabbing = true
	var start := MapData.vec(_drag_piece["pos"])
	var on := _surface_point(ray_from, ray_dir)
	_drag_offset = Vector3(start.x - on.x, 0.0, start.z - on.z)
	_say("Dragging: let go to drop it. X / Y / Z lock to one axis, Alt no snap, Esc or right-click to cancel.", 999.0)


# Where the cursor ray lands, ignoring the piece being moved (or the ground if it misses everything).
func _surface_point(ray_from: Vector3, ray_dir: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * 500.0)
	q.collision_mask = 1
	var skip := []
	if selected >= 0 and selected < nodes.size() and is_instance_valid(nodes[selected]):
		for c in nodes[selected].find_children("*", "CollisionObject3D", true, false):
			skip.append(c.get_rid())
	q.exclude = skip
	var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	var g = Plane(Vector3.UP, 0.0).intersects_ray(ray_from, ray_dir)
	return g if g != null else ray_from + ray_dir * 10.0


# How high a piece's position sits above what it's standing on.
func _rest_height(p: Dictionary) -> float:
	if p["type"] in ["block", "cylinder"]:
		return float(p["size"][1]) / 2.0
	if p["type"] in ["angel_spawn", "demon_spawn"]:
		return 0.1
	if p["type"] == "ice":
		return 0.03
	if p["type"] == "window":
		return float(p["size"][1]) / 2.0
	return 0.0


func _end_drag(keep: bool) -> void:
	_surface = false
	_grabbing = false
	if drag == "":
		return
	var before := _drag_before
	drag = ""
	axis = ""
	if keep:
		var changed := before != JSON.stringify(map)
		if online:   # (others' edits change the map too: only our own piece counts)
			changed = selected >= 0 and piece(selected) != _drag_piece
		if changed:
			_push_undo(before)
			_redo.clear()
			_redo_touched.clear()
			dirty = true
			_change_tag = ""
		var i := selected
		if i >= 0:
			map["pieces"][i] = _cleaned_piece(piece(i))
			_refresh_piece(i)
		for m in _member_start:
			if m < map["pieces"].size():
				map["pieces"][m] = _cleaned_piece(piece(m))
				_refresh_piece(m)
		_say("", 0.0)
	elif online:
		if selected >= 0 and not _drag_piece.is_empty():
			map["pieces"][selected] = _drag_piece.duplicate(true)
			_refresh_piece(selected)
		for m in _member_before:
			if m < map["pieces"].size():
				map["pieces"][m] = (_member_before[m] as Dictionary).duplicate(true)
				_refresh_piece(m)
		_say("Cancelled.", 1.5)
	else:
		map = JSON.parse_string(before)
		map = MapData.clean(map)
		_rebuild_all()
		_say("Cancelled.", 1.5)
	_sync_inspector()
	_after_change()


func _snap_on() -> bool:
	return snapping and not Input.is_physical_key_pressed(KEY_ALT)


# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not active() or not ui.visible:
		return   # (Settings is open over us: its keys, Esc included, go to it)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed and drag != "":
				_end_drag(false)
			elif drag == "":
				_set_flying(mb.pressed)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			get_viewport().gui_release_focus()
			_click(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_press_piece = -1
			if _grabbing:
				_end_drag(true)   # let go: drop it there
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.ctrl_pressed and drag == "" and selected >= 0 and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			cycle_look(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.alt_pressed and not mb.shift_pressed and drag == "" and selected >= 0 and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			wheel_size(1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.shift_pressed and drag == "" and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var turn := (1.0 if mb.alt_pressed else WHEEL_TURN) * (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			wheel_turn(turn)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := 2.0
			camera.position += -camera.global_basis.z * (step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -step)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if flying:
			_yaw -= mm.relative.x * 0.004
			_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.55, 1.55)
			camera.rotation = Vector3(_pitch, _yaw, 0)
		elif drag != "":
			var r := _mouse_ray(mm.position)
			drag_update(r[0], r[1], mm.position)
		elif _press_piece >= 0 and _press_piece == selected and mm.position.distance_to(_press_at) > 6.0 \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# Pressed on a piece and moved: pick it up.
			_press_piece = -1
			var r0 := _mouse_ray(_press_at)
			grab(r0[0], r0[1])
			var r := _mouse_ray(mm.position)
			drag_update(r[0], r[1], mm.position)
	elif event is InputEventKey and event.pressed and (not event.echo or event.keycode in NUDGE_KEYS):
		_key(event)   # (arrows keep nudging while held: Wife's notes, Nov 21)


func _key(ev: InputEventKey) -> void:
	var k := ev.physical_keycode
	var ctrl := ev.ctrl_pressed or ev.meta_pressed
	var handled := true
	if ctrl:
		match k:
			KEY_Z: (redo() if ev.shift_pressed else undo())
			KEY_Y: redo()
			KEY_D: if duplicate_selected() >= 0: begin("move")
			KEY_G: (ungroup_selected() if ev.shift_pressed else group_selected())
			KEY_S: save()
			_: handled = false
	elif drag != "":
		match k:
			KEY_X: set_axis("x")
			KEY_Y: set_axis("y")
			KEY_Z: set_axis("z")
			KEY_L: _toggle_local()
			KEY_ENTER, KEY_KP_ENTER: _end_drag(true)
			KEY_ESCAPE: _end_drag(false)
			_: handled = false
	elif flying:
		handled = false   # (WASD is read every frame)
	else:
		match k:
			KEY_G: begin("move")
			KEY_R: begin("rotate")
			KEY_T: begin("scale")
			KEY_V: begin("extend")
			KEY_L: _toggle_local()
			KEY_F: focus_selected()
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN:
				if selected >= 0:
					if ev.shift_pressed and not ev.echo:
						slide_to_touch(k)
					else:
						nudge(k, ev.alt_pressed)
				else:
					handled = false
			KEY_DELETE, KEY_BACKSPACE: delete_selected()
			KEY_ESCAPE:
				if placing != "":
					placing = ""
					_say("", 0.0)
				else:
					select(-1)
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _click(at: Vector2) -> void:
	if drag != "":
		_end_drag(true)
		return
	if placing != "":
		var kind := placing
		place(kind, _place_point(at))
		if not Input.is_physical_key_pressed(KEY_SHIFT):
			placing = ""
			_say("Placed. (Hold Shift while clicking to place several.)", 3.0)
		return
	var tab := _tab_under(at)
	if not tab.is_empty():
		pull_tab(tab[0], tab[1])
		return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		toggle_member(_piece_under(at))
		return
	select(_piece_under(at))
	_press_piece = selected
	_press_at = at


# A selected structure's pull tabs: [axis, side, where] (axis 0 along the row, 1 across, floors only).
func _ext_steps(p: Dictionary) -> Array:
	var sc := MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
	var b := Basis.from_euler(MapData.rot_rad(p))
	return [b * Models.row_step(p["model"], sc), b * Models.row_step2(p["model"], sc)]


func _tabs() -> Array:
	if selected < 0 or drag != "" or not can_edit:
		return []
	var p := piece(selected)
	if p["type"] != "model":
		return []
	var steps := _ext_steps(p)
	var n1 := int(p.get("repeat", 1))
	var n2 := int(p.get("repeat2", 1))
	var base := MapData.vec(p["pos"])
	var sc := MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
	var lift := Vector3.UP * clampf(Models.size(p["model"]).y * sc.y * 0.5, 0.3, 1.5)
	var mid1: Vector3 = steps[0] * (n1 - 1) * 0.5
	var mid2: Vector3 = steps[1] * (n2 - 1) * 0.5
	var out := [
		[0, 1, base + steps[0] * (n1 - 0.5) + mid2 + lift],
		[0, -1, base - steps[0] * 0.5 + mid2 + lift],
	]
	if Models.is_flat(p["model"]):
		out.append([1, 1, base + steps[1] * (n2 - 0.5) + mid1 + lift])
		out.append([1, -1, base - steps[1] * 0.5 + mid1 + lift])
	return out


func _tab_under(at: Vector2) -> Array:
	for t in _tabs():
		if camera.is_position_behind(t[2]):
			continue
		if camera.unproject_position(t[2]).distance_to(at) < 22.0:
			return [t[0], t[1]]
	return []


# Grab a pull tab: dragging the mouse adds whole copies at that end (or across, for floors).
func pull_tab(axis_index: int, side: int) -> void:
	begin("extend")
	if drag != "extend":
		return
	_ext_axis = axis_index
	_ext_side = side
	_grabbing = true   # (letting go of the mouse finishes it)
	_say("Pull it out (or back in). Let go to finish, Esc to cancel.", 999.0)


func _toggle_local() -> void:
	local_axes = not local_axes
	if _local_check:
		_local_check.set_pressed_no_signal(local_axes)
	if drag == "move":
		_start_move_ray()
	_say("Axes: " + ("the piece's own" if local_axes else "the map's"), 2.0)


func _set_flying(on: bool) -> void:
	flying = on
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func focus_selected() -> void:
	if selected < 0:
		return
	var target := MapData.vec(piece(selected)["pos"])
	var back := camera.global_basis.z
	camera.position = target + back * 10.0 + Vector3.UP * 2.0
	camera.look_at(target)
	_pitch = camera.rotation.x
	_yaw = camera.rotation.y


func _frame_whole_map() -> void:
	var half: float = map["size"]
	camera.position = Vector3(0, half * 0.9 + 6.0, half + 10.0)
	camera.look_at(Vector3.ZERO)
	_pitch = camera.rotation.x
	_yaw = camera.rotation.y


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(delta: float) -> void:
	if active() or testing:
		_autosave_tick(delta)
	if not active():
		return
	_status_time -= delta
	if _status_time <= 0.0 and status and drag == "":
		status.text = _help_text()
	# Flying about
	if not _typing() and drag == "":
		var move := Vector3.ZERO
		if not Input.is_key_pressed(KEY_CTRL) or flying:
			if Input.is_physical_key_pressed(KEY_W): move.z -= 1
			if Input.is_physical_key_pressed(KEY_S): move.z += 1
			if Input.is_physical_key_pressed(KEY_A): move.x -= 1
			if Input.is_physical_key_pressed(KEY_D): move.x += 1
		var up := 0.0
		if flying or not Input.is_key_pressed(KEY_CTRL):
			if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E): up += 1
			if Input.is_physical_key_pressed(KEY_Q) or (flying and Input.is_physical_key_pressed(KEY_CTRL)): up -= 1
		if move != Vector3.ZERO or up != 0.0:
			var speed := FLY_SPEED * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
			var b := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
			camera.position += (b * move.normalized() + Vector3.UP * up) * speed * delta
	_update_preview()
	_update_palette_where()
	if online:
		_online_tick(delta)
	# The side panels start below the top bar, however tall it's grown (big text wraps it)
	var below := _top_panel.size.y + 4.0
	if absf(_left_panel.offset_top - below) > 0.5:
		_left_panel.offset_top = below
		_right_panel.offset_top = below
	_draw_lines()


func _draw_lines() -> void:
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	# The middle of the map: 0, 0, 0
	for a in ["x", "y", "z"]:
		var d := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[a] as Vector3
		_line(Vector3.ZERO, d * 2.0, AXIS_COLORS[a])
	if selected >= 0 and selected < nodes.size() and is_instance_valid(nodes[selected]):
		var n: Node3D = nodes[selected]
		var box: AABB = _boxes.get(selected, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)).grow(0.05)
		var x := n.global_transform
		var c := Color(1.0, 0.9, 0.2)
		for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			_line(x * box.get_endpoint(e[0]), x * box.get_endpoint(e[1]), c)
		if drag != "" and axis != "":
			var d := _axis_dir(axis) if drag == "move" else (x.basis * ({"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[axis] as Vector3)).normalized()
			_line(n.global_position - d * 60.0, n.global_position + d * 60.0, AXIS_COLORS[axis])
	# The rest of the selection, in a paler colour
	for m in members:
		if m >= nodes.size() or not is_instance_valid(nodes[m]):
			continue
		var mn: Node3D = nodes[m]
		var mb: AABB = _boxes.get(m, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)).grow(0.05)
		var mx := mn.global_transform
		for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			_line(mx * mb.get_endpoint(e[0]), mx * mb.get_endpoint(e[1]), Color(1.0, 0.75, 0.35))
	# Pull tabs on a selected structure: glowing balls (seen through walls) with an arrow pointing out
	var sel_p: Dictionary = piece(selected) if selected >= 0 else {}
	var tabs := _tabs()
	while _tab_balls.size() < tabs.size():
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 32   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
		sm.rings = 16
		sm.radius = 1.0
		sm.height = 2.0
		ball.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 11
		ball.material_override = m
		root.add_child(ball)
		_tab_balls.append(ball)
	for k in _tab_balls.size():
		_tab_balls[k].visible = k < tabs.size()
	for k in tabs.size():
		var t: Array = tabs[k]
		var steps := _ext_steps(sel_p)
		var outward: Vector3 = (steps[t[0]] as Vector3).normalized() * t[1]
		var c := Color(0.4, 1.0, 0.6) if t[0] == 0 else Color(0.5, 0.8, 1.0)
		var rr := 0.14 * maxf(1.0, camera.global_position.distance_to(t[2]) / 8.0)
		_tab_balls[k].position = t[2]
		_tab_balls[k].scale = Vector3.ONE * rr
		(_tab_balls[k].material_override as StandardMaterial3D).albedo_color = c
		_line(t[2], t[2] + outward * rr * 3.0, c)
	# What the other builders have selected, in their colour
	for peer in claims:
		var j := index_of(claims[peer])
		if j < 0 or j >= nodes.size() or not is_instance_valid(nodes[j]):
			continue
		var on: Node3D = nodes[j]
		var ob: AABB = _boxes.get(j, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)).grow(0.08)
		var ox := on.global_transform
		var oc: Color = builders.get(peer, {}).get("color", Color.WHITE)
		for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			_line(ox * ob.get_endpoint(e[0]), ox * ob.get_endpoint(e[1]), oc)
	_lines.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(b)


# ---------------- saving, opening, testing ----------------

# Autosave (Ted, Nov 21): every 10 minutes Creative is open, if anything changed. A map that was saved
# before is saved in place; a new one is saved under its name (or "<name> (autosave)" if that name is
# taken by another map, so nothing gets overwritten). Online, only the host has the real map.
const AUTOSAVE_EVERY := 600.0
var _autosave_left := AUTOSAVE_EVERY


func _autosave_tick(delta: float) -> void:
	_autosave_left -= delta
	if _autosave_left > 0.0:
		return
	_autosave_left = AUTOSAVE_EVERY
	autosave()


func autosave() -> bool:
	if not dirty or (online and not hosting):
		return false
	var target := path
	if target == "":
		target = MapData.user_path_for(map["name"], shared_save)
		if FileAccess.file_exists(target):
			target = MapData.user_path_for("%s (autosave)" % map["name"], shared_save)
	elif _changed_on_disk(target):
		target = _copy_path()   # (someone else saved the shared map meanwhile: don't wipe their work)
	if not MapData.save_file(map, target):
		_say("Autosave failed: couldn't write " + ProjectSettings.globalize_path(target), 6.0)
		return false
	path = target
	_remember_disk()
	dirty = false
	_refresh_open_list()
	_say("Autosaved \"%s\"." % target.get_file().get_basename(), 3.0)
	return true


# Shared maps (Ted, Nov 25): "Shared" next to Save saves into the shared maps folder. Two people can have
# the same shared map open on their own PCs: if the file changed on disk since we opened (or last saved)
# it, someone else saved it, so ours goes in a copy instead of wiping their work.
var shared_save := false
var _shared_check: CheckBox
var _disk_time := 0


func _remember_disk() -> void:
	_disk_time = FileAccess.get_modified_time(path) if path != "" and FileAccess.file_exists(path) else 0


func _changed_on_disk(target: String) -> bool:
	return target == path and _disk_time > 0 and FileAccess.file_exists(target) and FileAccess.get_modified_time(target) != _disk_time


func _copy_path() -> String:
	var who: String = main.name_edit.text.strip_edges() if main and main.name_edit else ""
	var base := "%s (%s's copy)" % [map["name"], who if who != "" else "my"]
	var target := MapData.user_path_for(base, shared_save)
	var n := 2
	while FileAccess.file_exists(target):
		target = MapData.user_path_for("%s %d" % [base, n], shared_save)
		n += 1
	return target


func save() -> bool:
	var target := MapData.user_path_for(map["name"], shared_save)
	if _changed_on_disk(target):
		var copy := _copy_path()
		if not MapData.save_file(map, copy):
			_say("Couldn't save to " + ProjectSettings.globalize_path(copy), 6.0)
			return false
		path = copy
		_remember_disk()
		dirty = false
		_refresh_open_list()
		_say("Someone else saved \"%s\" while you had it open, so yours is saved as a copy: %s" % [map["name"], copy.get_file()], 8.0)
		return true
	if target != path and FileAccess.file_exists(target) and _confirm != "save":
		_confirm = "save"
		_save_button.text = "Replace \"%s\"?" % map["name"]
		_say("There's already a map called \"%s\". Click Save again to replace it, or rename this one." % map["name"], 6.0)
		return false
	_confirm = ""
	_save_button.text = _save_label()
	if not MapData.save_file(map, target):
		_say("Couldn't save to " + ProjectSettings.globalize_path(target), 6.0)
		return false
	path = target
	_remember_disk()
	dirty = false
	_refresh_open_list()
	_say(("Saved to the shared folder: " if MapData.is_shared(target) else "Saved to ") + ProjectSettings.globalize_path(target), 5.0)
	return true


func open(file_path: String) -> bool:
	if online and not hosting:
		return false
	var m := MapData.load_file(file_path)
	if m.is_empty():
		_say("Couldn't open that map.", 4.0)
		return false
	_end_drag(false)
	_begin_change()
	map = m
	path = file_path if MapData.is_saveable(file_path) else ""
	shared_save = MapData.is_shared(path)
	_remember_disk()
	dirty = false
	_shared_reset()
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_frame_whole_map()
	_say("Opened \"%s\"." % map["name"] + ("" if path != "" else " (A built-in map: saving makes your own copy.)"), 5.0)
	return true


func new_map() -> void:
	if online and not hosting:
		return
	_end_drag(false)
	_begin_change()
	map = MapData.empty_map()
	map["author"] = main.name_edit.text.strip_edges() if main.name_edit else ""
	map = MapData.clean(map)
	path = ""
	dirty = false
	_shared_reset()
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_frame_whole_map()


func test_play() -> void:
	if online:
		if hosting:
			main.net.build_test_play()
		return
	sleep()
	testing = true
	main.test_map_from_editor(map.duplicate(true))


func _try_exit() -> void:
	if online and hosting:
		main.net.build_end()   # everyone back to the lobby, with the map ready to play
		return
	if online and _confirm != "exit":
		_confirm = "exit"
		_exit_button.text = "Leave the game?"
		_say("This leaves the game. (Save a copy first if you want one.) Click again to leave.", 5.0)
		return
	if not online and dirty and _confirm != "exit":
		_confirm = "exit"
		_exit_button.text = "Leave without saving?"
		_say("You have unsaved changes. Click again to leave anyway.", 5.0)
		return
	_confirm = ""
	_exit_button.text = _exit_label()
	if online:
		main.leave_online_building()
		return
	main.leave_editor()


# ---------------- building together (online) ----------------
# The host's copy of the map is the real one. Every change made here is turned into small edits
# ("put this piece", "remove that one", "change this setting") by comparing the map with the last
# shared copy (_synced), and sent to the host, who checks them and passes them on to everyone else.
# Pieces have ids so edits can name them. A piece someone has selected is theirs until they let go.
# Undo only takes back your own changes.

func enter_online(start_map: Dictionary, start_path: String, is_host: bool, allowed: bool) -> void:
	enter(start_map, start_path)
	online = true
	hosting = is_host
	_id_prefix = "p%d%s-" % [multiplayer.get_unique_id() % 1000000000, _rand_tag()]
	MapData.ensure_ids(map, "m")
	_synced = _shared_view(map)
	set_can_edit(allowed)
	_online_ui()
	_say("Building together! Everyone's changes show up for everyone. Whoever selects a piece has it to themselves.", 8.0)


func _may_edit() -> bool:
	if online and not can_edit:
		_say("You're watching: the host hasn't let you build right now.", 3.0)
		return false
	return true


func piece_id(i: int) -> String:
	if i < 0 or i >= map["pieces"].size():
		return ""
	return map["pieces"][i].get("id", "")


func index_of(id: String) -> int:
	if id == "":
		return -1
	for i in map["pieces"].size():
		if map["pieces"][i].get("id", "") == id:
			return i
	return -1


# Who else has this piece selected (0: nobody).
func _claimed_by_other(id: String) -> int:
	if id == "":
		return 0
	for peer in claims:
		if claims[peer] == id:
			return peer
	return 0


func _shared_view(m: Dictionary) -> Dictionary:
	var ps := {}
	for p in m["pieces"]:
		ps[p.get("id", "")] = p.duplicate(true)
	var st := {}
	for k in MapData.SETTING_KEYS:
		st[k] = m[k]
	return {"pieces": ps, "settings": st}


# What's changed here since the last shared copy, as edits.
func _diff_ops() -> Array:
	var now := _shared_view(map)
	var ops := []
	for k in MapData.SETTING_KEYS:
		if now["settings"][k] != _synced["settings"].get(k):
			ops.append({"o": "set", "k": k, "v": now["settings"][k]})
	for id in now["pieces"]:
		if not _synced["pieces"].has(id) or _synced["pieces"][id] != now["pieces"][id]:
			ops.append({"o": "put", "id": id, "p": now["pieces"][id]})
	for id in _synced["pieces"]:
		if not now["pieces"].has(id):
			ops.append({"o": "del", "id": id})
	return ops


func _apply_synced(op: Dictionary) -> void:
	match op["o"]:
		"set": _synced["settings"][op["k"]] = op["v"]
		"put": _synced["pieces"][op["id"]] = op["p"].duplicate(true)
		"del": _synced["pieces"].erase(op["id"])


static func _op_key(op: Dictionary) -> String:
	return "setting:" + op["k"] if op["o"] == "set" else op["id"]


# Something changed here: send it.
func _after_change() -> void:
	if not online or map.is_empty():
		return
	var ops := _diff_ops()
	if ops.is_empty():
		return
	for op in ops:
		_apply_synced(op)
	if not _undoing and not _undo_touched.is_empty():
		for op in ops:
			_undo_touched.back()[_op_key(op)] = true
	main.net.build_send_ops(ops)


# The host opened another map or started a new one: that's everyone's map now.
func _shared_reset() -> void:
	if not online:
		return
	MapData.ensure_ids(map, "m%s-" % _rand_tag())
	_synced = _shared_view(map)
	_undo.clear()
	_redo.clear()
	_undo_touched.clear()
	_redo_touched.clear()
	if hosting:
		main.net.build_reset()


# From the host: the whole map, replaced (the host opened or started one).
func load_shared(new_map: Dictionary) -> void:
	_end_drag(false)
	map = MapData.clean(new_map)
	MapData.ensure_ids(map, "m")
	_synced = _shared_view(map)
	_undo.clear()
	_redo.clear()
	_undo_touched.clear()
	_redo_touched.clear()
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_say("The host opened \"%s\"." % map["name"], 5.0)


# Edits from someone else (or the host putting ours right): apply them without touching our undo.
func apply_remote(ops: Array) -> void:
	if map.is_empty():
		return
	var sel_id := piece_id(selected)
	var rebuild := false
	var ground := false
	var settings := false
	for op in ops:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		var clean_op := {}
		match op.get("o"):
			"set":
				var v = MapData.clean_setting(op.get("k"), op.get("v"))
				if v == null:
					continue
				map[op["k"]] = v
				settings = true
				if op["k"] in ["size", "ground_color", "wall_color"]:
					ground = true
				clean_op = {"o": "set", "k": op["k"], "v": v}
			"put":
				var p := MapData.clean_piece(op.get("p"))
				if p.is_empty() or p.get("id", "") == "":
					continue
				var i := index_of(p["id"])
				if i >= 0:
					map["pieces"][i] = p
					if i == selected and drag != "":
						_drag_piece = p.duplicate(true)
					if not rebuild:
						_refresh_piece(i)
				else:
					map["pieces"].append(p)
					if not rebuild:
						nodes.append(_make_node(p, map["pieces"].size() - 1))
				clean_op = {"o": "put", "id": p["id"], "p": p}
			"del":
				var id := str(op.get("id", ""))
				var i := index_of(id)
				if i >= 0:
					map["pieces"].remove_at(i)
					rebuild = true
				clean_op = {"o": "del", "id": id}
			_:
				continue
		_apply_synced(clean_op)
	dirty = true
	if rebuild:
		_rebuild_all()
	if ground:
		_rebuild_ground()
	if settings:
		_sync_settings()
	var si := index_of(sel_id)
	if si != selected:
		if si < 0:
			drag = ""
			_say("Someone removed the piece you had selected.", 3.0)
		select(si)
	elif selected >= 0:
		_sync_inspector()


# Undo/redo online: put back just these pieces and settings, as they were in that snapshot.
func _restore_parts(old: Dictionary, touched: Dictionary) -> void:
	var sel_id := piece_id(selected)
	var olds := {}
	for p in old["pieces"]:
		olds[p.get("id", "")] = p
	var ground := false
	var skipped := 0
	for key in touched:
		if key.begins_with("setting:"):
			var k: String = key.substr(8)
			map[k] = old[k]
			if k in ["size", "ground_color", "wall_color"]:
				ground = true
			continue
		if _claimed_by_other(key) != 0:
			skipped += 1   # someone's working on it right now: leave it
			continue
		var i := index_of(key)
		if olds.has(key):
			if i >= 0:
				map["pieces"][i] = olds[key].duplicate(true)
			else:
				map["pieces"].append(olds[key].duplicate(true))
		elif i >= 0:
			map["pieces"].remove_at(i)
	map = MapData.clean(map)
	dirty = true
	_change_tag = ""
	_rebuild_all()
	if ground:
		_rebuild_ground()
	_sync_settings()
	select(index_of(sel_id))
	if skipped > 0:
		_say("Someone else is working on part of that, so it stayed as it is.", 3.0)
	_undoing = true
	_after_change()
	_undoing = false


func set_can_edit(allowed: bool) -> void:
	var was := can_edit
	can_edit = allowed
	if not allowed:
		_end_drag(false)
		placing = ""
		_clear_preview()
		select(-1)
	_online_ui()
	if online and was != allowed:
		_say("The host let you build." if allowed else "The host made you view-only: you can look around, but not change anything.", 6.0)


# The host said no: someone else got that piece first.
func claim_denied(id: String) -> void:
	_my_claim = ""
	if piece_id(selected) == id:
		_end_drag(false)
		selected = -1
		_sync_inspector()
		_say("Someone else grabbed that one first.", 3.0)


# From the host, ten times a second: where everyone else is and what they have selected.
# Each entry: [peer, name, camera position, Vector2(pitch, yaw), selected piece id, colour number, can build]
func apply_builders(list: Array) -> void:
	var seen := {}
	claims.clear()
	for e in list:
		if typeof(e) != TYPE_ARRAY or e.size() < 7:
			continue
		var peer := int(e[0])
		seen[peer] = true
		var color: Color = BUILDER_COLORS[int(e[5]) % BUILDER_COLORS.size()]
		builders[peer] = {"name": str(e[1]), "pos": e[2], "rot": e[3], "color": color, "can": bool(e[6])}
		if str(e[4]) != "":
			claims[peer] = str(e[4])
		if not _ghosts.has(peer):
			_ghosts[peer] = _make_ghost(str(e[1]), color)
			_ghosts[peer].position = e[2]
	for peer in builders.keys():
		if not seen.has(peer):
			builders.erase(peer)
			if _ghosts.has(peer):
				_ghosts[peer].queue_free()
				_ghosts.erase(peer)
	if hosting:
		_refresh_builders_panel()


# Another builder, as everyone sees them: a glowing ball with a pointy nose (where they're looking) and their name.
func _make_ghost(who: String, color: Color) -> Node3D:
	var g := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 20   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
	sm.rings = 10
	sm.radius = 0.35
	sm.height = 0.7
	head.mesh = sm
	head.material_override = m
	g.add_child(head)
	var nose := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.18
	cm.height = 0.45
	nose.mesh = cm
	nose.material_override = m
	nose.rotation.x = -PI / 2
	nose.position.z = -0.45
	g.add_child(nose)
	var tag := Label3D.new()
	tag.text = who
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 48
	tag.outline_size = 10
	tag.modulate = color
	tag.position.y = 0.75
	g.add_child(tag)
	root.add_child(g)
	return g


# Host: who can build (everyone can, unless the host unticks them).
func _refresh_builders_panel() -> void:
	var sig := ""
	for peer in builders:
		sig += "%d:%s:%s;" % [peer, builders[peer]["name"], builders[peer]["can"]]
	if sig == _builders_sig:
		return
	_builders_sig = sig
	for c in _builders_box.get_children():
		c.queue_free()
	_label(_builders_box, "Builders")
	if builders.is_empty():
		_label(_builders_box, "  (nobody else here yet)")
	for peer in builders:
		# A big green / red switch per builder (Wife's notes, Nov 21: the little checkbox was easy to miss)
		var who: String = builders[peer]["name"]
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = who
		name_lbl.add_theme_color_override("font_color", builders[peer]["color"])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var sw := Button.new()
		sw.toggle_mode = true
		sw.focus_mode = Control.FOCUS_NONE
		sw.custom_minimum_size = Vector2(120, 34)
		var paint := func(on: bool) -> void:
			sw.text = "✔ Can build" if on else "✖ View only"
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				var box := StyleBoxFlat.new()
				box.bg_color = Color(0.15, 0.55, 0.25) if on else Color(0.6, 0.15, 0.15)
				if st.begins_with("hover"):
					box.bg_color = box.bg_color.lightened(0.15)
				box.set_corner_radius_all(6)
				box.set_border_width_all(2)
				box.border_color = Color(1, 1, 1, 0.6)
				sw.add_theme_stylebox_override(st, box)
		sw.button_pressed = builders[peer]["can"]
		paint.call(sw.button_pressed)
		var pid: int = peer
		sw.toggled.connect(func(on):
			paint.call(on)
			main.net.build_set_can(pid, on))
		row.add_child(sw)
		_builders_box.add_child(row)


func _online_ui() -> void:
	if _new_button == null:
		return
	var full := not online or hosting
	_new_button.visible = full
	_open_pick.visible = full
	_test_button.visible = full
	_save_button.text = _save_label()
	_exit_button.text = _exit_label()
	_left_panel.visible = can_edit
	_builders_box.visible = online and hosting
	if not (online and hosting):
		_builders_sig = ""
		for c in _builders_box.get_children():
			c.queue_free()
	elif _builders_box.get_child_count() == 0:
		_builders_sig = "-"
		_refresh_builders_panel()


func _save_label() -> String:
	return "Save a copy" if online and not hosting else "Save"


func _exit_label() -> String:
	if online:
		return "Done building" if hosting else "Leave game"
	return "Exit"


func _online_tick(delta: float) -> void:
	_cam_accum += delta
	if _cam_accum >= 1.0 / CAM_RATE:
		_cam_accum = 0.0
		main.net.build_send_cam(camera.global_position, Vector2(_pitch, _yaw))
	for peer in _ghosts:
		var g: Node3D = _ghosts[peer]
		var info: Dictionary = builders.get(peer, {})
		if info.is_empty():
			continue
		g.position = g.position.lerp(info["pos"], minf(1.0, delta * 10.0))
		var r: Vector2 = info["rot"]
		g.rotation = Vector3(r.x, r.y, 0.0)


# ---------------- the placement preview ----------------
# With a piece picked on the left, a see-through copy follows the mouse to show where a click puts it.

# Shift + wheel: turn the piece about to be placed, or else the selected one, around the up axis
# (relative to the map, whatever way it already faces).
func wheel_turn(degrees: float) -> void:
	if placing != "":
		place_yaw = wrapf(place_yaw + degrees, -180.0, 180.0)
		_say("Turned to %d degrees (Shift + wheel; hold Alt for fine)" % roundi(place_yaw), 2.0)
		return
	if selected < 0 or not piece(selected)["type"] in ROTATES:
		return
	var b := Basis(Vector3.UP, deg_to_rad(degrees)) * Basis.from_euler(MapData.rot_rad(piece(selected)))
	var e := b.get_euler()
	set_value(selected, "rot", Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)), "wheel-turn")


# Ctrl + wheel: the selected structure's look (weathered, clean, mossy, charred...).
func cycle_look(dir: int) -> void:
	var t: String = piece(selected)["type"] if selected >= 0 else ""
	if not t in ["model", "window", "bouncy", "bouncy_once", "bouncy_super", "ground", "building"]:
		_say("Looks are for structures, window pictures and bouncy pads.", 2.5)
		return
	_fill_looks(t)
	var look := posmod(int(piece(selected).get("look", 0)) + dir, _look_pick.item_count)
	set_value(selected, "look", look, "look")
	_say("Look: %s  (Ctrl + wheel for the next)" % _look_pick.get_item_text(look), 2.5)


# Alt + wheel: the selected piece bigger or smaller, keeping its proportions.
func wheel_size(factor: float) -> void:
	if selected < 0:
		return
	var p := piece(selected)
	match p["type"]:
		"model":
			var s := MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
			s = (s * factor).clamp(Vector3.ONE * 0.1, Vector3.ONE * 10.0)
			set_value(selected, "size", s, "wheel-size")
		"block", "cylinder", "ice", "sidewalk", "window", "ground":
			set_value(selected, "size", MapData.vec(p["size"]) * factor, "wheel-size")
		"prop":   # evenly only (Sara, Nov 25), and a demon disguised as it matches its size
			var k := PropLib.snap_scale(float(p.get("scale", 1.0)) + (0.1 if factor > 1.0 else -0.1))
			set_value(selected, "scale", k, "wheel-size")
			_say("Prop size: %d%%" % roundi(k * 100.0), 1.5)


# Arrow keys: move the selected piece one snap step, along the map's axis nearest to where we're looking.
# Shift + arrow: slide the selected piece that way until it touches the next piece (never into it).
func slide_to_touch(key: Key) -> void:
	var move := _nudge_dir(key)
	var box := _world_box(selected)
	if box.size == Vector3.ZERO:
		return
	var best := 50.0
	for i in map["pieces"].size():
		if i == selected:
			continue
		var other := _world_box(i)
		if other.size == Vector3.ZERO:
			continue
		# only things in the way: overlapping across the other two axes
		var hit := true
		for a in 3:
			if absf(move[a]) > 0.5:
				continue
			if box.position[a] >= other.end[a] - 0.001 or box.end[a] <= other.position[a] + 0.001:
				hit = false
		if not hit:
			continue
		for a in 3:
			if move[a] > 0.5 and other.position[a] >= box.end[a] - 0.001:
				best = minf(best, other.position[a] - box.end[a])
			elif move[a] < -0.5 and other.end[a] <= box.position[a] + 0.001:
				best = minf(best, box.position[a] - other.end[a])
	if best >= 50.0:
		_say("Nothing that way to slide up against.", 3.0)
		return
	_shift_members(move * best)
	set_value(selected, "pos", MapData.vec(piece(selected)["pos"]) + move * best, "slide")
	_say("Slid %.2f m, up against the next piece." % best, 3.0)


func _world_box(i: int) -> AABB:
	if i < 0 or i >= nodes.size() or not is_instance_valid(nodes[i]) or not _boxes.has(i):
		return AABB()
	return (nodes[i] as Node3D).global_transform * (_boxes[i] as AABB)


func _nudge_dir(key: Key) -> Vector3:
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	var ax := Vector3.FORWARD
	if fwd.length() > 0.01:
		ax = Vector3(signf(fwd.x), 0, 0) if absf(fwd.x) > absf(fwd.z) else Vector3(0, 0, signf(fwd.z))
	var right := ax.cross(Vector3.UP)
	return {KEY_UP: ax, KEY_DOWN: -ax, KEY_RIGHT: right, KEY_LEFT: -right,
			KEY_PAGEUP: Vector3.UP, KEY_PAGEDOWN: Vector3.DOWN}[key]


func nudge(key: Key, fine: bool) -> void:
	var step := 0.01 if fine else grid
	var fwd := -camera.global_basis.z
	fwd.y = 0.0
	var ax := Vector3.FORWARD
	if fwd.length() > 0.01:
		ax = Vector3(signf(fwd.x), 0, 0) if absf(fwd.x) > absf(fwd.z) else Vector3(0, 0, signf(fwd.z))
	var right := ax.cross(Vector3.UP)
	var move: Vector3 = {KEY_UP: ax, KEY_DOWN: -ax, KEY_RIGHT: right, KEY_LEFT: -right,
			KEY_PAGEUP: Vector3.UP, KEY_PAGEDOWN: Vector3.DOWN}[key]
	_shift_members(move * step)
	set_value(selected, "pos", MapData.vec(piece(selected)["pos"]) + move * step, "nudge")


func _update_preview() -> void:
	if placing == "" or flying or drag != "" or not can_edit or _mouse_over_ui():
		_clear_preview()
		return
	if _preview_kind != placing:
		_clear_preview()
		_preview = _make_node(_new_piece(placing, Vector3.ZERO), -1)
		_boxes.erase(-1)
		_ghostify(_preview)
		_preview_kind = placing
	var at := _place_point(_mouse())
	var np := _new_piece(placing, at)
	_preview.position = MapData.vec(np["pos"])
	_preview.rotation = MapData.rot_rad(np)


func _ghostify(n: Node3D) -> void:
	n.remove_meta("piece_index")
	for c in n.find_children("*", "CollisionObject3D", true, false):
		var co: CollisionObject3D = c
		co.collision_layer = 0
		co.collision_mask = 0
		if co is Area3D:
			(co as Area3D).monitoring = false
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = c
		gi.transparency = 0.5
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _clear_preview() -> void:
	if is_instance_valid(_preview):
		_preview.free()
	_preview = null
	_preview_kind = ""


func _mouse_over_ui() -> bool:
	var vp := get_viewport()
	if vp.has_method("gui_get_hovered_control"):
		return vp.call("gui_get_hovered_control") != null
	return false


# ---------------- the panels ----------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)

	# Top: the map itself
	var top := PanelContainer.new()
	_top_panel = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(top)
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var bar := HFlowContainer.new()   # (wraps onto more lines with big text)
	bar.add_theme_constant_override("separation", 8)
	rows.add_child(bar)
	_label(bar, " Map:")
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size.x = 170
	_name_edit.max_length = 40
	_name_edit.text_changed.connect(func(t): set_setting("name", t if t.strip_edges() != "" else "Untitled map"))
	bar.add_child(_name_edit)
	_label(bar, "By:")
	_author_edit = LineEdit.new()
	_author_edit.custom_minimum_size.x = 120
	_author_edit.max_length = 40
	_author_edit.text_changed.connect(func(t): set_setting("author", t))
	bar.add_child(_author_edit)
	for s in [["size", "Size", 10, 200, 1], ["ceiling", "Ceiling", 6, 120, 1], ["random_props", "Random props", 0, 300, 1]]:
		_label(bar, s[1] + ":")
		var spin := SpinBox.new()
		spin.min_value = s[2]
		spin.max_value = s[3]
		spin.step = s[4]
		spin.tooltip_text = {"size": "Half the width of the play area, in meters (walls go around it)",
				"ceiling": "How high anyone can go", "random_props": "Props scattered at random each round, on top of the ones you place"}[s[0]]
		var key: String = s[0]
		spin.value_changed.connect(func(v): set_setting(key, int(v) if key == "random_props" else float(v)))
		bar.add_child(spin)
		_setting_spins[key] = spin
	_label(bar, "Ground:")
	_ground_pick = ColorPickerButton.new()
	_ground_pick.custom_minimum_size = Vector2(36, 28)
	_ground_pick.edit_alpha = false
	_ground_pick.color_changed.connect(func(c): set_setting("ground_color", "#" + c.to_html(false)))
	bar.add_child(_ground_pick)
	_label(bar, "Walls:")
	_wall_pick = ColorPickerButton.new()
	_wall_pick.custom_minimum_size = Vector2(36, 28)
	_wall_pick.edit_alpha = false
	_wall_pick.color_changed.connect(func(c): set_setting("wall_color", "#" + c.to_html(false)))
	bar.add_child(_wall_pick)
	_label(bar, "Time:")
	_time_pick = OptionButton.new()
	for tn in MapData.TIMES:
		_time_pick.add_item(tn.capitalize())
	_time_pick.item_selected.connect(func(i): set_setting("time", MapData.TIMES[i]))
	_time_pick.focus_mode = Control.FOCUS_NONE
	bar.add_child(_time_pick)
	_label(bar, "Weather:")
	_weather_pick = OptionButton.new()
	for wn in ["Sunny, clear", "Sunny, some clouds", "Cloudy", "Light fog", "Snow", "Rain"]:
		_weather_pick.add_item(wn)
	_weather_pick.item_selected.connect(func(i): set_setting("weather", MapData.WEATHERS[i]))
	_weather_pick.focus_mode = Control.FOCUS_NONE
	bar.add_child(_weather_pick)
	_label(bar, "Scenery:")
	_backdrop_pick = OptionButton.new()
	for bn in Backdrop.NAMES:
		_backdrop_pick.add_item(bn)
	_backdrop_pick.tooltip_text = "What you see past the map's walls"
	_backdrop_pick.item_selected.connect(func(i): set_setting("backdrop", MapData.BACKDROPS[i]))
	_backdrop_pick.focus_mode = Control.FOCUS_NONE
	bar.add_child(_backdrop_pick)
	_label(bar, "Day cycle:")
	_cycle_pick = OptionButton.new()
	for cm in MapData.CYCLES:
		_cycle_pick.add_item("Off" if cm == 0 else "%d min" % cm)
	_cycle_pick.item_selected.connect(func(i): set_setting("cycle", MapData.CYCLES[i]))
	_cycle_pick.focus_mode = Control.FOCUS_NONE
	_cycle_pick.tooltip_text = "Time passes: day, dusk, night, dawn and round again, starting from the Time above"
	bar.add_child(_cycle_pick)

	var bar2 := HFlowContainer.new()
	bar2.add_theme_constant_override("separation", 8)
	rows.add_child(bar2)
	_new_button = _small_button(bar2, "New", new_map)
	_open_pick = OptionButton.new()
	_open_pick.custom_minimum_size.x = 200
	_open_pick.item_selected.connect(func(idx):
		var p = _open_pick.get_item_metadata(idx)
		if p is String and p != "":
			open(p)
		_open_pick.select(0))
	bar2.add_child(_open_pick)
	_save_button = _small_button(bar2, "Save", func(): save())
	_shared_check = CheckBox.new()
	_shared_check.text = "Shared"
	_shared_check.focus_mode = Control.FOCUS_NONE
	_shared_check.tooltip_text = "Save into the shared maps folder (set it in Settings), so friends syncing that folder get it too"
	_shared_check.toggled.connect(func(on):
		shared_save = on and MapData.has_shared()
		if on and not MapData.has_shared():
			_shared_check.set_pressed_no_signal(false)
			_say("Pick a shared maps folder first: Settings > Shared maps folder.", 4.0))
	bar2.add_child(_shared_check)
	_small_button(bar2, "Open maps folder", func(): OS.shell_open(ProjectSettings.globalize_path(MapData.USER_DIR)))
	_test_button = _small_button(bar2, "Test play", test_play)
	_small_button(bar2, "Undo", undo)
	_small_button(bar2, "Redo", redo)
	_snap_check = CheckBox.new()
	_snap_check.text = "Snap"
	_snap_check.button_pressed = snapping
	_snap_check.toggled.connect(func(on): snapping = on)
	bar2.add_child(_snap_check)
	var grid_pick := OptionButton.new()
	for g in GRID_STEPS:
		grid_pick.add_item("%s m" % str(g))
	grid_pick.select(GRID_STEPS.find(grid))
	grid_pick.item_selected.connect(func(idx): grid = GRID_STEPS[idx])
	grid_pick.tooltip_text = "Snap step (rotation snaps to 15°)"
	bar2.add_child(grid_pick)
	_local_check = CheckBox.new()
	_local_check.text = "Piece's own axes"
	_local_check.toggled.connect(func(on):
		local_axes = on
		if drag == "move": _start_move_ray())
	bar2.add_child(_local_check)
	_small_button(bar2, "Settings", func(): main.open_settings_from_editor())
	_exit_button = _small_button(bar2, "Exit", _try_exit)

	# Left: things to place
	var left := PanelContainer.new()
	_left_panel = left
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 80
	left.offset_bottom = -40
	left.custom_minimum_size.x = 250
	ui.add_child(left)
	var lcol := VBoxContainer.new()
	left.add_child(lcol)
	# Where you are in the list, always showing at the top (e.g. "Props > Furniture") however far down you scroll
	_palette_where = Label.new()
	_palette_where.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_palette_where.text = "Special structures"
	lcol.add_child(_palette_where)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(scroll)
	_palette_scroll = scroll
	var pal := VBoxContainer.new()
	pal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pal)
	var search := LineEdit.new()
	search.placeholder_text = "Search props & structures..."
	search.clear_button_enabled = true
	search.text_changed.connect(_filter_palette)
	pal.add_child(search)
	var special := _palette_section(pal, "Special structures", true)
	for p in PIECES:
		var kind: String = p[0]
		if kind in ["ice", "sidewalk"]:
			continue   # (in Ground, with the floors and roads)
		_palette_button(special, p[1], kind)
	var walk_in := _palette_section(pal, "Walk-in buildings", true)
	for bk in HollowBuildings.KINDS:
		_palette_button(walk_in, HollowBuildings.KINDS[bk], "building:" + bk)
	# Props (demons can be these), then structures (solid scenery), each by category
	for group in [["Props", PropLib.type_names().filter(PropLib.in_palette), "prop:"], ["Structures", Models.ids("structure"), "model:"]]:
		var glabel := _label(pal, "  " + group[0] + " (%d)" % group[1].size())
		glabel.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		_palette_groups.append([glabel, group[0]])
		var by_cat := {}
		for t in group[1]:
			var cat: String = PropLib.category(t) if group[2] == "prop:" else Models.category(t)
			if not by_cat.has(cat):
				by_cat[cat] = []
			by_cat[cat].append(t)
		var cats: Array = by_cat.keys()
		if group[2] == "model:" and by_cat.has("Ground"):
			cats.erase("Ground")
			cats.push_front("Ground")   # (floors, roads, paths and ice: first, they go down first)
		for cat in cats:
			var count: int = by_cat[cat].size() + (2 + GroundBlock.KINDS.size() if cat == "Ground" and group[2] == "model:" else 0)
			var sec := _palette_section(pal, "%s (%d)" % [cat, count], false)
			if cat == "Ground" and group[2] == "model:":
				_palette_button(sec, "Ice (slippery)", "ice", "Ground")
				_palette_button(sec, "Sidewalk", "sidewalk", "Ground")
				for gk in GroundBlock.KINDS:
					_palette_button(sec, GroundBlock.KINDS[gk] + " block", "ground:" + gk, "Ground")
			for t in by_cat[cat]:
				var label_text: String = PropLib.label(t) if group[2] == "prop:" else Models.label(t)
				_palette_button(sec, label_text, group[2] + t, cat)

	# Right: the selected piece
	var right := PanelContainer.new()
	_right_panel = right
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = 80
	right.offset_bottom = -40
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.custom_minimum_size.x = 250
	ui.add_child(right)
	_inspector = VBoxContainer.new()
	var rscroll := ScrollContainer.new()   # (scrolls when big text makes it too tall)
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(rcol)
	rcol.add_child(_inspector)
	_builders_box = VBoxContainer.new()
	rcol.add_child(_builders_box)
	_insp_title = _label(_inspector, "")
	for row in [["pos", "Position (m)", -500, 500], ["rot", "Rotation (°)", -360, 360], ["size", "Size (m)", 0.05, 400]]:
		var box := VBoxContainer.new()
		var title_label := _label(box, row[1])
		if row[0] == "size":
			_size_title = title_label
		var line := HBoxContainer.new()
		box.add_child(line)
		for a in 3:
			_label(line, ["X", "Y", "Z"][a])
			var spin := SpinBox.new()
			spin.min_value = row[2]
			spin.max_value = row[3]
			spin.step = 0.01
			spin.custom_minimum_size.x = 64
			spin.get_line_edit().add_theme_color_override("font_color", AXIS_COLORS[["x", "y", "z"][a]].lightened(0.3))
			var key: String = row[0]
			spin.value_changed.connect(func(_v): _on_spin(key))
			line.add_child(spin)
			_spins[key + str(a)] = spin
		_inspector.add_child(box)
		_rows[row[0]] = box
	var crow := HBoxContainer.new()
	_label(crow, "Colour")
	_color_pick = ColorPickerButton.new()
	_color_pick.custom_minimum_size = Vector2(60, 28)
	_color_pick.edit_alpha = false
	_color_pick.color_changed.connect(func(c): set_value(selected, "color", "#" + c.to_html(false)))
	crow.add_child(_color_pick)
	_inspector.add_child(crow)
	_rows["color"] = crow
	var lrow := HBoxContainer.new()
	_label(lrow, "Reach (m)")
	_light_range = SpinBox.new()
	_light_range.min_value = 1
	_light_range.max_value = 40
	_light_range.step = 0.5
	_light_range.value_changed.connect(func(v): set_value(selected, "range", v, "light-range"))
	lrow.add_child(_light_range)
	_label(lrow, "Brightness")
	_light_energy = SpinBox.new()
	_light_energy.min_value = 0.1
	_light_energy.max_value = 8
	_light_energy.step = 0.1
	_light_energy.value_changed.connect(func(v): set_value(selected, "energy", v, "light-energy"))
	lrow.add_child(_light_energy)
	_inspector.add_child(lrow)
	_rows["light"] = lrow
	var look_row := HBoxContainer.new()
	_label(look_row, "Look")
	_look_pick = OptionButton.new()
	_fill_looks("model")
	_look_pick.focus_mode = Control.FOCUS_NONE
	_look_pick.tooltip_text = "Ctrl + mouse wheel cycles through them"
	_look_pick.item_selected.connect(func(i): set_value(selected, "look", i, "look"))
	look_row.add_child(_look_pick)
	_car_lights = CheckBox.new()
	_car_lights.text = "Lights on"
	_car_lights.focus_mode = Control.FOCUS_NONE
	_car_lights.toggled.connect(func(on): set_value(selected, "lights", on))
	look_row.add_child(_car_lights)
	_inspector.add_child(look_row)
	_rows["look"] = look_row
	var grow := HBoxContainer.new()
	_group_label = _label(grow, "")
	_group_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_btn = _small_button(grow, "Group", group_selected)
	_group_btn.tooltip_text = "Make the selected pieces a group: clicking any of them selects them all (Ctrl + G)"
	_ungroup_btn = _small_button(grow, "Ungroup", ungroup_selected)
	_ungroup_btn.tooltip_text = "Split the group up again (Ctrl + Shift + G)"
	_inspector.add_child(grow)
	_rows["group"] = grow
	var srow := HBoxContainer.new()
	_light_spot = CheckBox.new()
	_light_spot.text = "Spotlight"
	_light_spot.tooltip_text = "Shine one way, in a cone (turn it with R or Shift + wheel), instead of all around"
	_light_spot.focus_mode = Control.FOCUS_NONE
	_light_spot.toggled.connect(func(on):
		if selected < 0:
			return
		var p := piece(selected).duplicate(true)
		if on:
			p["spot"] = true
			p["angle"] = p.get("angle", 35.0)
			if not p.has("rot"):
				p["rot"] = [-90.0, 0.0, 0.0]   # pointing down to start with
		else:
			p.erase("spot")
		_begin_change()
		map["pieces"][selected] = _cleaned_piece(p)
		_refresh_piece(selected)
		_sync_inspector()
		_after_change())
	srow.add_child(_light_spot)
	_label(srow, "Cone (°)")
	_light_angle = SpinBox.new()
	_light_angle.min_value = 5
	_light_angle.max_value = 85
	_light_angle.step = 1
	_light_angle.tooltip_text = "How wide the beam is: small is a tight beam, big a wide one (makes it a spotlight)"
	_light_angle.value_changed.connect(func(v):
		if selected >= 0 and not piece(selected).get("spot", false):
			_light_spot.button_pressed = true   # (a cone only means something for a spotlight)
		set_value(selected, "angle", v, "light-angle"))
	srow.add_child(_light_angle)
	_label(srow, "Tilt (°)")
	_light_tilt = SpinBox.new()
	_light_tilt.min_value = -90
	_light_tilt.max_value = 90
	_light_tilt.step = 5
	_light_tilt.tooltip_text = "Aim a spotlight up or down: -90 straight down, 0 level, 90 straight up (R / Shift + wheel turns it round)"
	_light_tilt.value_changed.connect(func(v):
		if selected < 0:
			return
		var r: Array = piece(selected).get("rot", [0.0, 0.0, 0.0]).duplicate()
		r[0] = v
		set_value(selected, "rot", r, "light-tilt"))
	srow.add_child(_light_tilt)
	_inspector.add_child(srow)
	_rows["spot"] = srow
	var frow := HBoxContainer.new()
	_light_always = CheckBox.new()
	_light_always.text = "Always on"
	_light_always.tooltip_text = "Off: it has a daylight sensor (on at dusk, off at dawn). On: lit all the time"
	_light_always.focus_mode = Control.FOCUS_NONE
	_light_always.toggled.connect(func(on): set_value(selected, "always", on))
	frow.add_child(_light_always)
	_label(frow, "Flicker (per s)")
	_light_flicker = SpinBox.new()
	_light_flicker.min_value = 0
	_light_flicker.max_value = 20
	_light_flicker.step = 0.5
	_light_flicker.tooltip_text = "0: a steady light. Higher: flickers faster (a candle about 3, a dodgy bulb 8+)"
	_light_flicker.value_changed.connect(func(v): set_value(selected, "flicker", v, "light-flicker"))
	frow.add_child(_light_flicker)
	_inspector.add_child(frow)
	_rows["flicker"] = frow
	var prow := HBoxContainer.new()
	_label(prow, "Prop")
	_prop_pick = OptionButton.new()
	for t in PropLib.type_names():
		_prop_pick.add_item(PropLib.label(t))
		_prop_pick.set_item_metadata(_prop_pick.item_count - 1, t)
	_prop_pick.item_selected.connect(func(idx): set_value(selected, "prop", _prop_pick.get_item_metadata(idx)))
	prow.add_child(_prop_pick)
	_inspector.add_child(prow)
	_rows["prop"] = prow
	var brow := HBoxContainer.new()
	_small_button(brow, "Move (G)", func(): begin("move"))
	_small_button(brow, "Turn (R)", func(): begin("rotate"))
	_small_button(brow, "Size (T)", func(): begin("scale"))
	_extend_button = _small_button(brow, "Extend (V)", func(): begin("extend"))
	_inspector.add_child(brow)
	_rows["buttons"] = brow
	var brow2 := HBoxContainer.new()
	_small_button(brow2, "Copy (Ctrl+D)", func(): duplicate_selected())
	_small_button(brow2, "Delete", delete_selected)
	_inspector.add_child(brow2)
	_rows["buttons2"] = brow2

	# Bottom: what's going on / what the keys do
	status = Label.new()
	status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -38
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.grow_vertical = Control.GROW_DIRECTION_BEGIN   # (big text wraps upward instead of off the bottom)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 6)
	ui.add_child(status)
	_refresh_open_list()


# The palette's "you are here": the group and section of the topmost visible row.
func _update_palette_where() -> void:
	if _palette_scroll == null or not _palette_scroll.is_visible_in_tree():
		return
	var top := float(_palette_scroll.scroll_vertical) + 4.0
	var group := ""
	var section := ""
	var section_y := -1.0
	for g in _palette_groups:
		if g[0].visible and g[0].position.y <= top:
			group = g[1]
	for sec in _palette_sections:
		var hdr: Control = sec[0]
		if hdr.visible and hdr.position.y <= top and hdr.position.y > section_y:
			section_y = hdr.position.y
			section = sec[2]
	var group_y := -1.0
	for g in _palette_groups:
		if g[1] == group:
			group_y = g[0].position.y
	var text := section
	if group != "":
		text = group if section_y < group_y else "%s  >  %s" % [group, section]
	if text == "":
		text = "Special structures"
	if _palette_where.text != text:
		_palette_where.text = text


# A foldable list in the palette: click its header to open or close it.
func _palette_section(pal: Control, title: String, open: bool) -> VBoxContainer:
	var header := Button.new()
	header.text = ("▼ " if open else "▶ ") + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	pal.add_child(header)
	var box := VBoxContainer.new()
	box.visible = open
	pal.add_child(box)
	header.pressed.connect(func():
		box.visible = not box.visible
		header.text = ("▼ " if box.visible else "▶ ") + title)
	_palette_sections.append([header, box, title.get_slice(" (", 0)])
	return box


func _palette_button(sec: VBoxContainer, text: String, kind: String, cat := "") -> void:
	var b := _small_button(sec, " " + text, func(): _arm(kind))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# A little picture of it (made ahead of time by tools/make_thumbs.gd)
	var thumb := "res://assets/thumbs/%s.png" % kind.replace(":", "_").replace("/", "__")
	if not kind.contains(":"):
		thumb = "res://assets/thumbs/piece_%s.png" % kind
	if ResourceLoader.exists(thumb):
		b.icon = load(thumb)
		b.add_theme_constant_override("icon_max_width", 48)
		b.custom_minimum_size.y = 52
	b.tooltip_text = text
	_palette_buttons.append([b, (text + " " + cat + " " + kind).to_lower(), sec])


# Typing in the search box shows only what matches (every word has to match), with their lists opened.
func _filter_palette(text: String) -> void:
	var words := text.to_lower().split(" ", false)
	var shown := {}
	for e in _palette_buttons:
		var ok := true
		for w in words:
			if not w in e[1]:
				ok = false
				break
		e[0].visible = ok
		if ok:
			shown[e[2]] = true
	for sec in _palette_sections:
		if words.is_empty():
			sec[0].visible = true
			continue
		sec[0].visible = shown.has(sec[1])
		sec[1].visible = shown.has(sec[1])


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # so keys go to the editor, not the button
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _arm(kind: String) -> void:
	_end_drag(true)
	placing = kind
	var label := kind
	for p in PIECES:
		if p[0] == kind:
			label = p[1]
	if kind.begins_with("prop:"):
		label = PropLib.label(kind.substr(5))
	if kind.begins_with("model:"):
		label = Models.label(kind.substr(6))
	_say("Click in the world to place: %s   (Esc cancels, hold Shift to place several)" % label, 999.0)


func _refresh_open_list() -> void:
	if _open_pick == null:
		return
	_open_pick.clear()
	_open_pick.add_item("Open a map...")
	_open_pick.set_item_metadata(0, "")
	for e in MapData.list_maps():
		_open_pick.add_item(e["name"] + ("  (built in)" if e["built_in"] else ("  (shared)" if e.get("shared", false) else "")))
		_open_pick.set_item_metadata(_open_pick.item_count - 1, e["path"])
	_open_pick.select(0)


func _sync_settings() -> void:
	if _name_edit == null:
		return
	if _shared_check:
		_shared_check.set_pressed_no_signal(shared_save)
	if _name_edit.text != map["name"]:
		_name_edit.text = map["name"]
	if _author_edit.text != map["author"]:
		_author_edit.text = map["author"]
	for k in _setting_spins:
		_setting_spins[k].set_value_no_signal(map[k])
	_ground_pick.color = Color(map["ground_color"])
	_wall_pick.color = Color(map["wall_color"])
	_time_pick.select(MapData.TIMES.find(map["time"]))
	_weather_pick.select(MapData.WEATHERS.find(map["weather"]))
	_backdrop_pick.select(MapData.BACKDROPS.find(map["backdrop"]))
	_cycle_pick.select(MapData.CYCLES.find(map["cycle"]))
	main.graphics.set_time_of_day(map["time"])
	main.graphics.set_weather(map["weather"])
	main.graphics.set_day_cycle(map["cycle"])


func _sync_inspector() -> void:
	if _inspector == null:
		return
	var has := selected >= 0
	for k in _rows:
		_rows[k].visible = has
	if not has:
		_insp_title.text = "Nothing selected.\nClick a piece to select it."
		return
	var p := piece(selected)
	var t: String = p["type"]
	var grouped: bool = p.has("group")
	_rows["group"].visible = not members.is_empty() or grouped
	_group_label.text = ("%d selected%s" % [members.size() + 1, " (a group)" if grouped else ""]) if not members.is_empty() else "In a group"
	_group_btn.visible = not members.is_empty()
	_ungroup_btn.visible = grouped
	var title := t
	for q in PIECES:
		if q[0] == t:
			title = q[1]
	if t == "prop":
		title = "Prop: %s (%d%% size: Alt + mouse wheel)" % [PropLib.label(p["prop"]), roundi(float(p.get("scale", 1.0)) * 100.0)]
	if t == "model":
		title = "%s (%s)" % [Models.label(p["model"]), Models.category(p["model"])]
	_insp_title.text = title
	var vals := {"pos": p["pos"], "rot": p.get("rot", [0, 0, 0]), "size": p.get("size", [1, 1, 1])}
	for k in vals:
		for a in 3:
			_spins[k + str(a)].set_value_no_signal(vals[k][a])
	_rows["rot"].visible = t in ROTATES
	_rows["size"].visible = t in RESIZES
	_extend_button.visible = t == "model"
	_size_title.text = "Scale (× normal)" if t == "model" else "Size (m)"
	_rows["color"].visible = t in ["block", "cylinder", "light"] or (t == "model" and Models.is_rug(p["model"]))
	if t == "ice":
		_size_title.text = "Size (m; ice is always thin)"
	_rows["look"].visible = t in ["model", "window", "bouncy", "bouncy_once", "bouncy_super", "ground", "building"]
	_fill_looks(t)
	if t in ["model", "window", "bouncy", "bouncy_once", "bouncy_super", "ground", "building"]:
		_look_pick.select(int(p.get("look", 0)))
		_car_lights.visible = t == "model" and Models.is_car(p["model"])   # (windows and pads have no car lights)
		_car_lights.set_pressed_no_signal(p.get("lights", false))
	_rows["light"].visible = t == "light"
	_rows["spot"].visible = t == "light"
	_rows["flicker"].visible = t == "light"
	if t == "light":
		_light_tilt.set_value_no_signal(float(p.get("rot", [0.0, 0.0, 0.0])[0]))
		_light_always.set_pressed_no_signal(p.get("always", false))
		_light_flicker.set_value_no_signal(float(p.get("flicker", 0.0)))
		_light_range.set_value_no_signal(p["range"])
		_light_energy.set_value_no_signal(p["energy"])
		_light_spot.set_pressed_no_signal(p.get("spot", false))
		_light_angle.set_value_no_signal(p.get("angle", 35.0))
	_rows["prop"].visible = t == "prop"
	if t in ["block", "cylinder", "light"] or p.has("color"):
		_color_pick.color = Color(p["color"])
	elif t == "model":
		_color_pick.color = Color(0.75, 0.7, 0.65)   # (a rug still in its own colours)
	if t == "prop":
		for idx in _prop_pick.item_count:
			if _prop_pick.get_item_metadata(idx) == p["prop"]:
				_prop_pick.select(idx)


func _on_spin(key: String) -> void:
	if selected < 0:
		return
	var v := Vector3(_spins[key + "0"].value, _spins[key + "1"].value, _spins[key + "2"].value)
	set_value(selected, key, v)


func _say(text: String, seconds: float) -> void:
	if status == null:
		return
	status.text = text if text != "" else _help_text()
	_status_time = seconds


func _help_text() -> String:
	return "Hold right mouse: look   WASD: fly   Space/E up   Q down   Shift faster   Click: select   Ctrl+click: select several   Ctrl+G group (Alt+click one of a group)   Drag: move it   G move   R rotate   T resize   Drag the tabs to extend   Shift+wheel turn   Alt+wheel size   Ctrl+wheel look   Arrows nudge (hold to keep going; Shift: slide up against the next piece)   Ctrl+D copy   Del remove   F fly to it   Ctrl+Z undo   Ctrl+S save"
