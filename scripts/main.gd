# Phase 1 prototype: one small test map, single player.
#   Angel side: 30s hiding period, then find and catch 3 bot demons in 3 minutes.
#   Demon side: a sandbox to practice possessing props (no angel AI yet).
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Player = preload("res://scripts/player.gd")
const BotDemon = preload("res://scripts/bot_demon.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")

const HIDE_TIME := 30.0
const HUNT_TIME := 180.0
const BOT_COUNT := 3
const PROP_COUNT := 45
const MAP_HALF := 28.0
const ANGEL_SPAWN := Vector3(0, 0.1, -24)
const DEMON_SPAWN := Vector3(0, 0.1, 0)

enum State { HIDING, HUNTING, ENDED }

var state: State = State.HIDING
var time_left := 0.0
var role := "angel"          # start on the side that has a full round to play
var bots_left := 0
var player: Player
var round_root: Node3D
var rng := RandomNumberGenerator.new()
var structures: Array = []   # each: [Vector2 center, float keep-clear radius]
var used_spots: Array = []

var status_label: Label
var hint_label: Label
var controls_label: Label
var center_label: Label
var blind_rect: ColorRect
var crosshair: Label
var _toast_time := 0.0
var _hitmarker_time := 0.0
var _sounds := {}             # name -> AudioStreamPlayer
var bar_fills := {}           # HUD stamina bars: name -> [fill ColorRect, Label]
var taunt_label: Label
var hud_layer: CanvasLayer
var _taunt_label_time := 0.0
var tuning_panel: PanelContainer
var _tuning_rows := {}        # tuning key -> [HSlider, Label]

# F1 tuning panel: [key, label, min, max, step]
const TUNING_SLIDERS := [
	["ground_accel", "Acceleration", 5.0, 120.0, 1.0],
	["ground_decel", "Stopping (lower = more slide)", 5.0, 120.0, 1.0],
	["air_accel", "Air control", 0.0, 40.0, 1.0],
	["gravity_scale", "Gravity", 0.5, 3.0, 0.05],
	["fall_multiplier", "Extra fall speed", 1.0, 3.0, 0.05],
	["jump_velocity", "Jump strength", 3.0, 9.0, 0.1],
	["head_bob", "Head bob (0 = off)", 0.0, 2.0, 0.05],
]


func _ready() -> void:
	rng.randomize()
	_setup_input()
	_build_environment()
	_build_map()
	_build_hud()
	_build_sounds()
	player = Player.new()
	player.role = role
	add_child(player)
	player.threw.connect(func(kind): _play("throw_" + kind))
	player.form_changed.connect(func(): _play("possess"))
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.taunted.connect(_on_taunted)
	_build_tuning_panel()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	start_round()


# ---------- input ----------

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("run", KEY_SHIFT)
	_add_key("sneak", KEY_CTRL)
	_add_key("toggle_view", KEY_T)
	_add_key("cycle_blessing", KEY_B)
	_add_key("switch_role", KEY_TAB)
	_add_key("restart", KEY_R)
	_add_key("skip_hiding", KEY_ENTER)
	_add_key("taunt_random", KEY_1)
	_add_key("taunt_signature", KEY_2)
	_add_key("toggle_tuning", KEY_F1)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", click)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("restart"):
		start_round()
	elif event.is_action_pressed("switch_role"):
		role = "demon" if role == "angel" else "angel"
		start_round()
	elif event.is_action_pressed("skip_hiding") and state == State.HIDING:
		time_left = 0.0
	elif event.is_action_pressed("toggle_tuning"):
		tuning_panel.visible = not tuning_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if tuning_panel.visible else Input.MOUSE_MODE_CAPTURED


# ---------- world ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.4, 0.75)       # heavenly lavender up top
	sky_mat.sky_horizon_color = Color(0.95, 0.6, 0.45)   # hellish glow at the horizon
	sky_mat.ground_horizon_color = Color(0.95, 0.6, 0.45)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	add_child(sun)


func _add_block(center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, keep_clear := true) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = PropLib.mat(color)
	body.add_child(mi)
	body.position = center
	body.rotation = rot
	add_child(body)
	if keep_clear:
		structures.append([Vector2(center.x, center.z), maxf(size.x, size.z) / 2.0 + 1.0])


func _build_map() -> void:
	# Ground and boundary walls
	_add_block(Vector3(0, -0.5, 0), Vector3(MAP_HALF * 2 + 2, 1, MAP_HALF * 2 + 2), Color(0.35, 0.55, 0.3), Vector3.ZERO, false)
	var wall_color := Color(0.5, 0.48, 0.52)
	var span := MAP_HALF * 2 + 2
	_add_block(Vector3(0, 2, MAP_HALF + 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(0, 2, -MAP_HALF - 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(MAP_HALF + 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(-MAP_HALF - 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	# Buildings and cover
	_add_block(Vector3(8, 2, 8), Vector3(6, 4, 6), Color(0.7, 0.6, 0.5))
	_add_block(Vector3(-10, 2, -6), Vector3(7, 4, 5), Color(0.6, 0.55, 0.65))
	_add_block(Vector3(14, 4, -12), Vector3(3, 8, 3), Color(0.55, 0.5, 0.6))
	_add_block(Vector3(-16, 0.5, -16), Vector3(6, 1, 6), Color(0.65, 0.6, 0.5))
	_add_block(Vector3(18, 1.5, 14), Vector3(4, 3, 10), Color(0.6, 0.5, 0.45))
	# A raised platform with a ramp up to it
	_add_block(Vector3(-6, 1, 12), Vector3(8, 2, 4), Color(0.6, 0.6, 0.55))
	_add_block(Vector3(-6, 0.8, 7.3), Vector3(2.5, 0.4, 5.9), Color(0.5, 0.45, 0.4), Vector3(-0.35, 0, 0))   # top edge flush with the platform


func _random_spot() -> Vector3:
	for _attempt in 60:
		var p := Vector2(rng.randf_range(-MAP_HALF + 1.5, MAP_HALF - 1.5), rng.randf_range(-MAP_HALF + 1.5, MAP_HALF - 1.5))
		var ok := p.distance_to(Vector2(ANGEL_SPAWN.x, ANGEL_SPAWN.z)) > 5.0 \
				and p.distance_to(Vector2(DEMON_SPAWN.x, DEMON_SPAWN.z)) > 3.0
		for s in structures:
			if ok and p.distance_to(s[0]) < s[1]:
				ok = false
		for u in used_spots:
			if ok and p.distance_to(u) < 1.8:
				ok = false
		if ok:
			used_spots.append(p)
			return Vector3(p.x, 0, p.y)
	return Vector3.ZERO


func _spawn_prop(type_name: String, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("prop")
	body.set_meta("prop_type", type_name)
	body.add_child(PropLib.make_visual(type_name))
	var shape_node := CollisionShape3D.new()
	shape_node.shape = PropLib.make_shape(type_name)
	shape_node.position.y = PropLib.height(type_name) / 2.0
	body.add_child(shape_node)
	body.position = pos
	body.rotation.y = rng.randf_range(0, TAU)
	round_root.add_child(body)


func _spawn_bot(type_name: String, pos: Vector3) -> void:
	var bot := BotDemon.new()
	bot.setup(type_name)
	bot.position = pos
	bot.rotation.y = rng.randf_range(0, TAU)
	bot.caught.connect(_on_bot_caught)
	round_root.add_child(bot)


# ---------- rounds ----------

func start_round() -> void:
	if round_root:
		round_root.free()
	round_root = Node3D.new()
	add_child(round_root)
	used_spots.clear()
	var types := PropLib.type_names()
	for i in PROP_COUNT:
		_spawn_prop(types[rng.randi() % types.size()], _random_spot())
	bots_left = 0
	if role == "angel":
		for i in BOT_COUNT:
			_spawn_bot(types[rng.randi() % types.size()], _random_spot())
			bots_left += 1

	player.set_role(role)
	player.velocity = Vector3.ZERO
	player.global_position = ANGEL_SPAWN if role == "angel" else DEMON_SPAWN
	player.rotation.y = PI if role == "angel" else 0.0   # angel faces into the map
	player.frozen = role == "angel"
	state = State.HIDING
	time_left = HIDE_TIME
	blind_rect.visible = role == "angel"
	if role == "angel":
		controls_label.text = "WASD move   Shift run   Ctrl sneak   Space jump   1 / 2 taunt\nLeft click throw   B change blessing (testing)   T first/third person   Tab switch to demon   R restart   F1 movement tuning   Esc free mouse"
		_toast("The demons are hiding...\n(Enter to skip the wait while testing)", HIDE_TIME)
	else:
		controls_label.text = "WASD move   Shift run   Ctrl sneak   Space jump   1 / 2 taunt\nClick a prop to possess it   Hold click to return to demon form   T first/third person   Tab switch to angel   R restart   F1 movement tuning   Esc free mouse"
		_toast("Demon sandbox: practice possessing props.\nNo angel AI yet - that comes with multiplayer.", 5.0)


func _start_hunting() -> void:
	state = State.HUNTING
	time_left = HUNT_TIME
	player.frozen = false
	blind_rect.visible = false
	if role == "angel":
		_toast("Find the %d demons hiding as props!" % bots_left, 3.0)
	else:
		_toast("The hunt is on!", 2.0)


func _end_round(message: String) -> void:
	state = State.ENDED
	_toast(message + "\nR to play again   Tab to switch sides", 9999.0)


func _on_bot_caught(_bot) -> void:
	_play("caught")
	bots_left -= 1
	if bots_left <= 0 and state == State.HUNTING:
		_end_round("All demons caught! Angels win!")
	else:
		_toast("Demon caught! %d left" % bots_left, 2.0)


func _process(delta: float) -> void:
	if state != State.ENDED:
		time_left -= delta
		if time_left <= 0.0:
			if state == State.HIDING:
				_start_hunting()
			else:
				_end_round("Time's up! The demons win." if role == "angel" else "Time's up! You survived!")
	_update_hud(delta)


# ---------- HUD ----------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud_layer = hud
	add_child(hud)

	blind_rect = ColorRect.new()
	blind_rect.color = Color(0.06, 0.03, 0.1)
	blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(blind_rect)

	status_label = _make_label(30)
	status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_label.position.y = 12
	hud.add_child(status_label)

	center_label = _make_label(36)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_label.position.y -= 120
	hud.add_child(center_label)

	crosshair = _make_label(28)
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.add_child(crosshair)

	hint_label = _make_label(24)
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.position.y += 40
	hud.add_child(hint_label)

	controls_label = _make_label(18)
	controls_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls_label.position += Vector2(16, -16)
	hud.add_child(controls_label)

	# Stamina bars, bottom center
	var bars := VBoxContainer.new()
	bars.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bars.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bars.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bars.position.y -= 70
	bars.add_theme_constant_override("separation", 6)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bars)
	_make_bar(bars, "sprint", Color(0.4, 0.85, 0.45))
	_make_bar(bars, "power", Color(1.0, 0.85, 0.3))

	taunt_label = _make_label(22)
	taunt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	taunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taunt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	taunt_label.position.y -= 150
	hud.add_child(taunt_label)


const BAR_WIDTH := 260.0


func _make_bar(parent: Control, bar_name: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := _make_label(16)
	lbl.custom_minimum_size.x = 70
	row.add_child(lbl)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.45)
	back.custom_minimum_size = Vector2(BAR_WIDTH, 14)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # don't stretch to the label's height
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(BAR_WIDTH, 14)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	parent.add_child(row)
	bar_fills[bar_name] = [fill, lbl]


func _set_bar(bar_name: String, text: String, fraction: float, color := Color.TRANSPARENT) -> void:
	var fill: ColorRect = bar_fills[bar_name][0]
	fill.size.x = BAR_WIDTH * clampf(fraction, 0.0, 1.0)
	if color != Color.TRANSPARENT:
		fill.color = color
	bar_fills[bar_name][1].text = text


func _build_tuning_panel() -> void:
	tuning_panel = PanelContainer.new()
	tuning_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tuning_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tuning_panel.position += Vector2(-16, 60)
	tuning_panel.visible = false
	hud_layer.add_child(tuning_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	tuning_panel.add_child(box)
	var title := Label.new()
	title.text = "Movement tuning (F1 to close)\nApplies to both teams for now"
	box.add_child(title)
	for row in TUNING_SLIDERS:
		var key: String = row[0]
		var lbl := Label.new()
		box.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.value = player.tuning[key]
		slider.value_changed.connect(func(v): _on_tuning_changed(key, v))
		box.add_child(slider)
		_tuning_rows[key] = [slider, lbl, row[1]]
		_on_tuning_changed(key, slider.value)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(_reset_tuning)
	box.add_child(reset)


var _tuning_defaults := {}


func _on_tuning_changed(key: String, value: float) -> void:
	if not _tuning_defaults.has(key):
		_tuning_defaults[key] = player.tuning[key]
	player.tuning[key] = value
	var row: Array = _tuning_rows[key]
	row[1].text = "%s: %s" % [row[2], str(snappedf(value, 0.01))]


func _reset_tuning() -> void:
	for key in _tuning_defaults:
		_tuning_rows[key][0].value = _tuning_defaults[key]


func _build_sounds() -> void:
	Sfx.setup_bus()
	var streams := {
		"hit": Sfx.hit_sound(),
		"caught": Sfx.caught_sound(),
		"possess": Sfx.possess_sound(),
	}
	for kind in Blessings.names():
		streams["throw_" + kind] = Sfx.throw_sound(kind)
	for sound_name in streams:
		var asp := AudioStreamPlayer.new()
		asp.max_polyphony = 4   # overlapping plays layer instead of cutting off
		asp.stream = streams[sound_name]
		asp.bus = Sfx.BUS
		if sound_name.begins_with("throw_"):
			asp.volume_db = -4.0   # throws happen constantly: keep them in the background
		add_child(asp)
		_sounds[sound_name] = asp


func _play(sound_name: String) -> void:
	var asp: AudioStreamPlayer = _sounds[sound_name]
	# A little random pitch each time so repeated sounds don't feel robotic.
	asp.pitch_scale = randf_range(0.94, 1.06)
	asp.play()


# Our throw hit a demon: ding, and flash a red X on the crosshair.
func _on_hit_confirmed() -> void:
	_play("hit")
	_hitmarker_time = 0.3


func _on_taunted(taunt_name: String) -> void:
	taunt_label.text = "\"%s\"" % Taunts.label(taunt_name)
	_taunt_label_time = 1.5


func _toast(text: String, seconds: float) -> void:
	center_label.text = text
	_toast_time = seconds


func _update_hud(delta: float) -> void:
	_toast_time -= delta
	if _toast_time <= 0.0:
		center_label.text = ""
	var t := maxi(int(ceil(time_left)), 0)
	var clock := "%d:%02d" % [t / 60, t % 60]
	var phase := "Hiding" if state == State.HIDING else ("Hunting" if state == State.HUNTING else "Round over")
	var side := "ANGEL" if role == "angel" else "DEMON"
	var text := "%s   |   %s  %s" % [side, phase, clock if state != State.ENDED else ""]
	if role == "angel":
		text += "   |   Demons left: %d   |   %s" % [bots_left, Blessings.label(player.blessing)]
	status_label.text = text
	_hitmarker_time -= delta
	if _hitmarker_time > 0.0:
		crosshair.text = "X"
		crosshair.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15))
		crosshair.add_theme_font_size_override("font_size", 40)
	else:
		crosshair.text = "+"
		crosshair.remove_theme_color_override("font_color")
		crosshair.add_theme_font_size_override("font_size", 28)

	_taunt_label_time -= delta
	if _taunt_label_time <= 0.0:
		taunt_label.text = ""

	var sprint_color := Color(0.85, 0.35, 0.3) if player._sprint_exhausted else Color(0.4, 0.85, 0.45)
	_set_bar("sprint", "Sprint", player.sprint_stamina / player.SPRINT_MAX, sprint_color)
	if role == "angel":
		var low := player.throw_stamina < player.THROW_COST
		_set_bar("power", "Blessing", player.throw_stamina / player.THROW_STAMINA_MAX,
				Color(0.6, 0.5, 0.25) if low else Color(1.0, 0.85, 0.3))
	else:
		_set_bar("power", "Hatred", player.hatred / player.HATRED_MAX, Color(0.8, 0.12, 0.12))

	if player.hold_fraction > 0.0:
		var filled := int(round(player.hold_fraction * 10))
		hint_label.text = "Returning to demon form  " + "|".repeat(filled) + ".".repeat(10 - filled)
	elif role == "demon" and player.look_target_type != "":
		hint_label.text = "Click: possess %s" % PropLib.label(player.look_target_type)
	else:
		hint_label.text = ""
