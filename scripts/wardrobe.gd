# The wardrobe (Ted, Nov 20): dress your angel and your demon a slot at a time (halo or horns, head,
# upper body, lower body, skin, blessing or flame colour), see it turning in a little preview, and save
# outfits as presets. The matching sets (every character, whole) are always there to start from.
# Open it from the main menu or the lobby, before any match.
extends PanelContainer

const Characters = preload("res://scripts/characters.gd")
const SLOTS := [["crown", "Halo / horns"], ["head", "Head"], ["upper", "Upper body and arms"],
		["lower", "Lower body and legs"], ["skin", "Skin colour"], ["trail", "Blessings / flames"]]

var main
var team := "angel"
var outfits := {}                # being edited: {"angel": {...}, "demon": {...}}
var presets := []                # [{"name", "team", "outfit"}], saved in settings
var on_done: Callable

var _picks := {}                 # slot -> OptionButton
var _slot_labels := {}
var _preset_pick: OptionButton
var _name_edit: LineEdit
var _team_buttons := {}
var _view: SubViewport
var _stage: Node3D
var _model: Node3D
var _note: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	solid.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", solid)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	margin.add_child(cols)
	# Left: the preview
	var left := VBoxContainer.new()
	cols.add_child(left)
	var title := Label.new()
	title.text = "Wardrobe"
	title.add_theme_font_size_override("font_size", 28)
	left.add_child(title)
	var tabs := HBoxContainer.new()
	left.add_child(tabs)
	for t in [["angel", "Angel"], ["demon", "Demon"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 38)
		var tt: String = t[0]
		b.pressed.connect(func(): _set_team(tt))
		tabs.add_child(b)
		_team_buttons[t[0]] = b
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(300, 380)
	svc.stretch = true
	left.add_child(svc)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_view)
	_stage = Node3D.new()
	_view.add_child(_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.8
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	_view.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, -3.6)
	cam.fov = 38.0
	_view.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	# Right: the slots and presets
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 380
	cols.add_child(right)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	right.add_child(grid)
	for s in SLOTS:
		var l := Label.new()
		l.text = s[1]
		grid.add_child(l)
		_slot_labels[s[0]] = l
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot: String = s[0]
		ob.item_selected.connect(func(i): _pick(slot, ob.get_item_metadata(i)))
		grid.add_child(ob)
		_picks[s[0]] = ob
	right.add_child(HSeparator.new())
	var pl := Label.new()
	pl.text = "Presets (matching sets, and your own)"
	right.add_child(pl)
	_preset_pick = OptionButton.new()
	_preset_pick.item_selected.connect(_load_preset)
	right.add_child(_preset_pick)
	var save_row := HBoxContainer.new()
	right.add_child(save_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name this outfit..."
	_name_edit.max_length = 30
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save_preset)
	save_row.add_child(save)
	var del := Button.new()
	del.text = "Delete"
	del.tooltip_text = "Delete the selected saved preset"
	del.pressed.connect(_delete_preset)
	save_row.add_child(del)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	right.add_child(_note)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 42)
	done.pressed.connect(func():
		visible = false
		if on_done.is_valid():
			on_done.call())
	right.add_child(done)


func open(current: Dictionary, saved: Array) -> void:
	outfits = current.duplicate(true)
	presets = saved.duplicate(true)
	visible = true
	_note.text = ""
	_set_team(team)
	_center.call_deferred()


func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)


func _set_team(t: String) -> void:
	team = t
	for k in _team_buttons:
		_team_buttons[k].set_pressed_no_signal(k == t)
	_slot_labels["crown"].text = "Halo" if t == "angel" else "Horns"
	_slot_labels["trail"].text = "Blessing colour" if t == "angel" else "Flame colour"
	for s in SLOTS:
		var ob: OptionButton = _picks[s[0]]
		ob.clear()
		var opts := Characters.options(s[0], t)
		for o in opts:
			ob.add_item(o[1])
			ob.set_item_metadata(ob.item_count - 1, o[0])
	_fill_presets()
	_sync()


func _sync() -> void:
	var o: Dictionary = outfits[team]
	for s in SLOTS:
		var ob: OptionButton = _picks[s[0]]
		for i in ob.item_count:
			if ob.get_item_metadata(i) == o.get(s[0]):
				ob.select(i)
	if is_instance_valid(_model):
		_model.queue_free()
	_model = Characters.build(team, o, 1.7)
	_stage.add_child(_model)


func _pick(slot: String, value) -> void:
	outfits[team][slot] = value
	_sync()
	_apply()


func _apply() -> void:
	if main:
		main.set_outfits(outfits)
		main.wardrobe_presets = presets
		main._save_settings()


func _fill_presets() -> void:
	_preset_pick.clear()
	_preset_pick.add_item("Pick a preset...")
	_preset_pick.set_item_metadata(0, null)
	for m in Characters.matching_sets(team):
		_preset_pick.add_item("Matching: " + m[0])
		_preset_pick.set_item_metadata(_preset_pick.item_count - 1, {"outfit": m[1], "mine": false})
	for p in presets:
		if p.get("team") == team:
			_preset_pick.add_item(p["name"])
			_preset_pick.set_item_metadata(_preset_pick.item_count - 1, {"outfit": p["outfit"], "mine": true, "name": p["name"]})
	_preset_pick.select(0)


func _load_preset(i: int) -> void:
	var m = _preset_pick.get_item_metadata(i)
	if m == null:
		return
	var keep_trail: String = outfits[team].get("trail", "")
	outfits[team] = Characters.clean_outfit(m["outfit"], team)
	if not m["mine"]:
		outfits[team]["trail"] = keep_trail   # (a matching set dresses you; your colour stays)
	if m.get("mine", false):
		_name_edit.text = m["name"]
	_sync()
	_apply()


func _save_preset() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		_note.text = "Give the outfit a name first."
		return
	for p in presets:
		if p["team"] == team and p["name"] == n:
			p["outfit"] = outfits[team].duplicate()
			_note.text = "Updated \"%s\"." % n
			_apply()
			_fill_presets()
			return
	if presets.size() >= 60:
		_note.text = "That's a lot of outfits! Delete one to save another."
		return
	presets.append({"name": n, "team": team, "outfit": outfits[team].duplicate()})
	_note.text = "Saved \"%s\"." % n
	_apply()
	_fill_presets()


func _delete_preset() -> void:
	var m = _preset_pick.get_item_metadata(_preset_pick.selected)
	if m == null or not m.get("mine", false):
		_note.text = "Pick one of your own saved outfits to delete it."
		return
	presets = presets.filter(func(p): return not (p["team"] == team and p["name"] == m["name"]))
	_note.text = "Deleted \"%s\"." % m["name"]
	_apply()
	_fill_presets()


func _process(delta: float) -> void:
	if visible and is_instance_valid(_model):
		_model.rotation.y += delta * 0.6
