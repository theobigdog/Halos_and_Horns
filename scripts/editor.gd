# Creative mode: build your own maps.
#
# Fly around: hold the right mouse button to look, WASD to move, Space / E up,
# Ctrl / Q down, Shift to go faster, mouse wheel to zoom.
# Pick a piece on the left, then click in the world to put it there.
# Click a piece to select it, or press on it and drag to move it around (it slides
# over whatever's under the cursor: ground, roofs, other pieces). Or, once selected:
#   G move   R rotate   T resize (blocks, cylinders and structures)
#     while doing it: X / Y / Z stick to one axis, L local or world axes,
#     hold Alt for no snapping, click or Enter to finish, Esc or right-click to undo it
#   Ctrl+D copy   Delete remove   F fly to it   Ctrl+Z / Ctrl+Y undo / redo   Ctrl+S save
# The panel on the right takes exact numbers. 0, 0, 0 is the middle of the map, on the ground.
#
# A map is plain data (see map_data.gd). The editor only ever changes that data
# and rebuilds what it shows from it, so what you save is exactly what you saw.
extends Node

const MapData = preload("res://scripts/map_data.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Bouncy = preload("res://scripts/bouncy.gd")
const Models = preload("res://scripts/models.gd")
const Shrine = preload("res://scripts/shrine.gd")

const PIECES := [
	["block", "Block"], ["cylinder", "Cylinder"],
	["bouncy", "Bouncy (metal, stays)"], ["bouncy_once", "Bouncy (wooden, one use a round)"],
	["bouncy_super", "Super bouncy (magic, stays)"],
	["shrine", "Shrine"], ["angel_spawn", "Angel start"], ["demon_spawn", "Demon start"],
]
const ROTATES := ["block", "cylinder", "prop", "model"]       # the others always sit upright
const RESIZES := ["block", "cylinder", "model"]       # (a model's "size" is how much it's scaled on each axis)
const ONLY_ONE := ["shrine", "angel_spawn", "demon_spawn"]
const GRID_STEPS := [0.25, 0.5, 1.0, 2.0]
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
	path = start_path if start_path.begins_with(MapData.USER_DIR) else ""
	dirty = false
	_undo.clear()
	_redo.clear()
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
	_say("Pick a piece on the left, then click in the world to place it.", 6.0)


# Going off to test the map: hide everything, keep the work.
func sleep() -> void:
	_end_drag(false)
	placing = ""
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
			body.add_child(PropLib.make_visual(p["prop"]))
			var cs := CollisionShape3D.new()
			cs.shape = PropLib.make_shape(p["prop"])
			cs.position.y = PropLib.height(p["prop"]) / 2.0
			body.add_child(cs)
			n.add_child(body)
		"model":
			n.add_child(Models.make_structure(p["model"], MapData.vec(p["size"]) if p.has("size") else Vector3.ONE))
		"bouncy", "bouncy_once", "bouncy_super":
			var b := Bouncy.new()
			b.one_use = t == "bouncy_once"
			b.super_bouncy = t == "bouncy_super"
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
func _add_pick_box(n: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	n.add_child(body)


func _add_marker(n: Node3D, angel: bool) -> void:
	var color := Color(1.0, 0.85, 0.35) if angel else Color(0.9, 0.2, 0.15)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = 2.0
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	mi.material_override = m
	mi.position.y = 1.0
	n.add_child(mi)
	var tag := Label3D.new()
	tag.text = "ANGELS START HERE" if angel else "DEMONS START HERE"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 8
	tag.pixel_size = 0.01
	tag.modulate = color.lightened(0.3)
	tag.position.y = 2.6
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
		_undo.append(JSON.stringify(map))
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
		_redo.clear()
	_change_tag = tag
	_change_time = now
	dirty = true
	_confirm = ""


func place(kind: String, at: Vector3) -> int:
	_begin_change()
	var p := {"type": kind, "pos": [at.x, at.y, at.z]}
	if kind.begins_with("prop:"):
		p = {"type": "prop", "prop": kind.substr(5), "pos": [at.x, at.y, at.z]}
	elif kind.begins_with("model:"):
		p = {"type": "model", "model": kind.substr(6), "pos": [at.x, at.y, at.z]}
	elif kind == "block":
		p["size"] = [4.0, 2.0, 4.0]
		p["pos"][1] = at.y + 1.0
		p["color"] = "#a09080"
	elif kind == "cylinder":
		p["size"] = [2.0, 3.0, 2.0]
		p["pos"][1] = at.y + 1.5
		p["color"] = "#8c8c99"
	if kind in ONLY_ONE:
		for i in map["pieces"].size():
			if piece(i)["type"] == kind:
				piece(i)["pos"] = p["pos"]
				_refresh_piece(i)
				select(i)
				_say("A map has just one of those: moved it here.", 3.0)
				return i
	map["pieces"].append(_cleaned_piece(p))
	var i: int = map["pieces"].size() - 1
	nodes.append(_make_node(piece(i), i))
	select(i)
	return i


# Run one piece through the same checks a loaded map gets.
func _cleaned_piece(p: Dictionary) -> Dictionary:
	var m := MapData.clean({"pieces": [p]})
	for q in m["pieces"]:
		if q["type"] == p["type"]:
			return q
	return m["pieces"][0]


func set_value(i: int, key: String, value, tag := "") -> void:
	if i < 0 or i >= map["pieces"].size():
		return
	_begin_change(tag if tag != "" else "%d:%s" % [i, key])
	var p := piece(i)
	if value is Vector3:
		p[key] = [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
	else:
		p[key] = value
	map["pieces"][i] = _cleaned_piece(p)
	_refresh_piece(i)
	if i == selected:
		_sync_inspector()


func delete_selected() -> void:
	if selected < 0:
		return
	var t: String = piece(selected)["type"]
	if t in ["angel_spawn", "demon_spawn"]:
		_say("Every map needs an angel start and a demon start: move it instead.", 4.0)
		return
	_begin_change()
	map["pieces"].remove_at(selected)
	_rebuild_all()
	select(-1)


func duplicate_selected() -> int:
	if selected < 0:
		return -1
	var p: Dictionary = piece(selected).duplicate(true)
	if p["type"] in ONLY_ONE:
		_say("A map has just one of those.", 3.0)
		return -1
	_begin_change()
	p["pos"] = [p["pos"][0] + grid * 2.0, p["pos"][1], p["pos"][2] + grid * 2.0]
	map["pieces"].append(p)
	var i: int = map["pieces"].size() - 1
	nodes.append(_make_node(piece(i), i))
	select(i)
	return i


func undo() -> void:
	if _undo.is_empty():
		_say("Nothing to undo.", 2.0)
		return
	_redo.append(JSON.stringify(map))
	_restore(_undo.pop_back())
	_say("Undone.", 1.5)


func redo() -> void:
	if _redo.is_empty():
		_say("Nothing to redo.", 2.0)
		return
	_undo.append(JSON.stringify(map))
	_restore(_redo.pop_back())
	_say("Redone.", 1.5)


func _restore(text: String) -> void:
	var was_size: float = map["size"]
	var was_ground: String = map["ground_color"] + map["wall_color"]
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
	if map.get(key) == value:
		return
	_begin_change("setting:" + key)
	map[key] = value
	map = MapData.clean(map)
	if key in ["size", "ground_color", "wall_color"]:
		_rebuild_ground()


# ---------------- selecting ----------------

func select(i: int) -> void:
	selected = i if i >= 0 and i < map["pieces"].size() else -1
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
	if selected < 0:
		_say("Select a piece first (click it).", 2.0)
		return
	var t: String = piece(selected)["type"]
	if kind == "rotate" and not t in ROTATES:
		_say("That always sits upright.", 2.0)
		return
	if kind == "scale" and not t in RESIZES:
		_say("Only blocks, cylinders and structures can be resized.", 2.0)
		return
	_end_drag(true)
	drag = kind
	axis = ""
	_drag_before = JSON.stringify(map)
	_drag_piece = piece(selected).duplicate(true)
	_drag_mouse = _mouse()
	_drag_offset = Vector3.ZERO
	if kind == "move":
		_start_move_ray()
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
				var hit = Plane(Vector3.UP, start.y).intersects_ray(ray_from, ray_dir)
				if hit == null:
					return
				pos = hit + _drag_offset
				if snap:
					pos.x = snappedf(pos.x, grid)
					pos.z = snappedf(pos.z, grid)
			else:
				var d := _axis_dir(axis)
				var t := _along_axis(start, d, ray_from, ray_dir) - _drag_t0
				if snap:
					t = snappedf(t, grid)
				pos = start + d * t
			p["pos"] = [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)]
			nodes[selected].position = pos
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
		if before != JSON.stringify(map):
			_undo.append(before)
			_redo.clear()
			dirty = true
			_change_tag = ""
		var i := selected
		if i >= 0:
			map["pieces"][i] = _cleaned_piece(piece(i))
			_refresh_piece(i)
		_say("", 0.0)
	else:
		map = JSON.parse_string(before)
		map = MapData.clean(map)
		_rebuild_all()
		_say("Cancelled.", 1.5)
	_sync_inspector()


func _snap_on() -> bool:
	return snapping and not Input.is_physical_key_pressed(KEY_ALT)


# ---------------- input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
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
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := 2.0 * (3.0 if mb.shift_pressed else 1.0)
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
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _key(ev: InputEventKey) -> void:
	var k := ev.physical_keycode
	var ctrl := ev.ctrl_pressed or ev.meta_pressed
	var handled := true
	if ctrl:
		match k:
			KEY_Z: (redo() if ev.shift_pressed else undo())
			KEY_Y: redo()
			KEY_D: if duplicate_selected() >= 0: begin("move")
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
			KEY_L: _toggle_local()
			KEY_F: focus_selected()
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
	select(_piece_under(at))
	_press_piece = selected
	_press_at = at


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
	_lines.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(b)


# ---------------- saving, opening, testing ----------------

func save() -> bool:
	var target := MapData.user_path_for(map["name"])
	if target != path and FileAccess.file_exists(target) and _confirm != "save":
		_confirm = "save"
		_save_button.text = "Replace \"%s\"?" % map["name"]
		_say("There's already a map called \"%s\". Click Save again to replace it, or rename this one." % map["name"], 6.0)
		return false
	_confirm = ""
	_save_button.text = "Save"
	if not MapData.save_file(map, target):
		_say("Couldn't save to " + ProjectSettings.globalize_path(target), 6.0)
		return false
	path = target
	dirty = false
	_refresh_open_list()
	_say("Saved to " + ProjectSettings.globalize_path(target), 5.0)
	return true


func open(file_path: String) -> bool:
	var m := MapData.load_file(file_path)
	if m.is_empty():
		_say("Couldn't open that map.", 4.0)
		return false
	_end_drag(false)
	_begin_change()
	map = m
	path = file_path if file_path.begins_with(MapData.USER_DIR) else ""
	dirty = false
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_frame_whole_map()
	_say("Opened \"%s\"." % map["name"] + ("" if path != "" else " (A built-in map: saving makes your own copy.)"), 5.0)
	return true


func new_map() -> void:
	_end_drag(false)
	_begin_change()
	map = MapData.empty_map()
	map["author"] = main.name_edit.text.strip_edges() if main.name_edit else ""
	map = MapData.clean(map)
	path = ""
	dirty = false
	_rebuild_ground()
	_rebuild_all()
	select(-1)
	_sync_settings()
	_frame_whole_map()


func test_play() -> void:
	sleep()
	testing = true
	main.test_map_from_editor(map.duplicate(true))


func _try_exit() -> void:
	if dirty and _confirm != "exit":
		_confirm = "exit"
		_exit_button.text = "Leave without saving?"
		_say("You have unsaved changes. Click again to leave anyway.", 5.0)
		return
	_confirm = ""
	_exit_button.text = "Exit"
	main.leave_editor()


# ---------------- the panels ----------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)

	# Top: the map itself
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(top)
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var bar := HBoxContainer.new()
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

	var bar2 := HBoxContainer.new()
	bar2.add_theme_constant_override("separation", 8)
	rows.add_child(bar2)
	_small_button(bar2, "New", new_map)
	_open_pick = OptionButton.new()
	_open_pick.custom_minimum_size.x = 200
	_open_pick.item_selected.connect(func(idx):
		var p = _open_pick.get_item_metadata(idx)
		if p is String and p != "":
			open(p)
		_open_pick.select(0))
	bar2.add_child(_open_pick)
	_save_button = _small_button(bar2, "Save", func(): save())
	_small_button(bar2, "Open maps folder", func(): OS.shell_open(ProjectSettings.globalize_path(MapData.USER_DIR)))
	_small_button(bar2, "Test play", test_play)
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
	_exit_button = _small_button(bar2, "Exit", _try_exit)

	# Left: things to place
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 80
	left.offset_bottom = -40
	left.custom_minimum_size.x = 190
	ui.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var pal := VBoxContainer.new()
	pal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pal)
	var search := LineEdit.new()
	search.placeholder_text = "Search props & structures..."
	search.clear_button_enabled = true
	search.text_changed.connect(_filter_palette)
	pal.add_child(search)
	var special := _palette_section(pal, "Place", true)
	for p in PIECES:
		var kind: String = p[0]
		_palette_button(special, p[1], kind)
	# Props (demons can be these), then structures (solid scenery), each by category
	for group in [["Props", PropLib.type_names(), "prop:"], ["Structures", Models.ids("structure"), "model:"]]:
		_label(pal, "  " + group[0] + " (%d)" % group[1].size())
		var by_cat := {}
		for t in group[1]:
			var cat: String = PropLib.category(t) if group[2] == "prop:" else Models.category(t)
			if not by_cat.has(cat):
				by_cat[cat] = []
			by_cat[cat].append(t)
		for cat in by_cat:
			var sec := _palette_section(pal, "%s (%d)" % [cat, by_cat[cat].size()], false)
			for t in by_cat[cat]:
				var label_text: String = PropLib.label(t) if group[2] == "prop:" else Models.label(t)
				_palette_button(sec, label_text, group[2] + t, cat)

	# Right: the selected piece
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = 80
	right.offset_bottom = -40
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.custom_minimum_size.x = 250
	ui.add_child(right)
	_inspector = VBoxContainer.new()
	right.add_child(_inspector)
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
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 6)
	ui.add_child(status)
	_refresh_open_list()


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
	_palette_sections.append([header, box])
	return box


func _palette_button(sec: VBoxContainer, text: String, kind: String, cat := "") -> void:
	var b := _small_button(sec, "  " + text, func(): _arm(kind))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
		_open_pick.add_item(e["name"] + ("  (built in)" if e["built_in"] else ""))
		_open_pick.set_item_metadata(_open_pick.item_count - 1, e["path"])
	_open_pick.select(0)


func _sync_settings() -> void:
	if _name_edit == null:
		return
	if _name_edit.text != map["name"]:
		_name_edit.text = map["name"]
	if _author_edit.text != map["author"]:
		_author_edit.text = map["author"]
	for k in _setting_spins:
		_setting_spins[k].set_value_no_signal(map[k])
	_ground_pick.color = Color(map["ground_color"])
	_wall_pick.color = Color(map["wall_color"])


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
	var title := t
	for q in PIECES:
		if q[0] == t:
			title = q[1]
	if t == "prop":
		title = "Prop: " + PropLib.label(p["prop"])
	if t == "model":
		title = "%s (%s)" % [Models.label(p["model"]), Models.category(p["model"])]
	_insp_title.text = title
	var vals := {"pos": p["pos"], "rot": p.get("rot", [0, 0, 0]), "size": p.get("size", [1, 1, 1])}
	for k in vals:
		for a in 3:
			_spins[k + str(a)].set_value_no_signal(vals[k][a])
	_rows["rot"].visible = t in ROTATES
	_rows["size"].visible = t in RESIZES
	_size_title.text = "Scale (× normal)" if t == "model" else "Size (m)"
	_rows["color"].visible = t in ["block", "cylinder"]
	_rows["prop"].visible = t == "prop"
	if t in ["block", "cylinder"]:
		_color_pick.color = Color(p["color"])
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
	return "Hold right mouse: look   WASD: fly   Space/E up   Q down   Shift faster   Click: select   Drag: move it   G move   R rotate   T resize   Ctrl+D copy   Del remove   F fly to it   Ctrl+Z undo   Ctrl+S save"
