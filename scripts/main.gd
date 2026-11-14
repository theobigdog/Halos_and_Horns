# Halos & Horns: menu, the test map, the HUD, practice mode, and the screens
# around online play (online rules themselves live in net_game.gd).
#   Practice: single player. Angel side hunts 3 test demons; demon side is a sandbox.
#   Online: one player hosts, friends join by address. Mobification rules.
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Player = preload("res://scripts/player.gd")
const BotDemon = preload("res://scripts/bot_demon.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const NetGame = preload("res://scripts/net_game.gd")
const Effects = preload("res://scripts/effects.gd")
const Autobot = preload("res://scripts/autobot.gd")
const Skills = preload("res://scripts/skills.gd")
const Chicken = preload("res://scripts/chicken.gd")
const Vortex = preload("res://scripts/vortex.gd")
const Rope = preload("res://scripts/rope.gd")
const Projectile = preload("res://scripts/projectile.gd")

const GAME_VERSION := "0.3 (flying, skills, possess)"
const HIDE_TIME := 30.0
const HUNT_TIME := 180.0
const BOT_COUNT := 3
const PROP_COUNT := 45
const MAP_HALF := 28.0
const ANGEL_SPAWN := Vector3(0, 0.1, -24)
const DEMON_SPAWN := Vector3(0, 0.1, 0)
const SETTINGS_PATH := "user://settings.cfg"

enum State { LOBBY, HIDING, HUNTING, ENDED }

var mode := "menu"           # menu, practice, online
var state: State = State.LOBBY
var time_left := 0.0
var role := "angel"          # practice starts on the side that has a full round to play
var bots_left := 0           # demons left (test demons in practice, players online)
var my_health := 0           # online demons: health percent, shown in the HUD
var loadout := Skills.DEFAULTS.duplicate(true)   # your chosen skills (saved)
var props: Array = []        # this round's map props, by index (same on every computer)
var chickens := {}           # chicken id -> Chicken node (visuals, everyone)
var _auth_chickens := {}     # chicken id -> {pos, until, alarmed} (decider only)
var _chicken_counter := 0
var _chicken_check := 0.0
var _possessions := {}       # who possesses which prop: user key -> prop index (decider only)
var _loadout_buttons: Array = []   # [team, slot, OptionButton]
var skill_label: Label
var player: Player
var net: Node = null
var autobot: Node = null
var round_root: Node3D
var rng := RandomNumberGenerator.new()
var structures: Array = []   # each: [Vector2 center, float keep-clear radius]
var used_spots: Array = []
var lobby_names: Array = []
var scoreboard_rows: Array = []   # Tab roster, from the host

var status_label: Label
var hint_label: Label
var controls_label: Label
var center_label: Label
var blind_rect: ColorRect
var hurt_rect: ColorRect
var crosshair: Label
var _toast_time := 0.0
var _hitmarker_time := 0.0
var _hurt_time := 0.0
var _sounds := {}             # name -> AudioStreamPlayer
var bar_fills := {}           # HUD stamina bars: name -> [fill ColorRect, Label]
var taunt_label: Label
var hud_layer: CanvasLayer
var _taunt_label_time := 0.0
var tuning_panel: PanelContainer
var _tuning_rows := {}        # tuning key -> [HSlider, Label, title]
var _tuning_defaults := {}

var menu_panel: PanelContainer
var name_edit: LineEdit
var address_edit: LineEdit
var port_edit: LineEdit
var menu_status: Label
var pause_panel: PanelContainer
var lobby_panel: PanelContainer
var lobby_players: Label
var lobby_info: Label
var lobby_start: Button
var _public_ip := ""
var _settings := ConfigFile.new()
var ping_label: Label
var scoreboard_panel: PanelContainer
var _scoreboard_columns := {}     # "angel"/"demon" -> GridContainer
var _scoreboard_titles := {}
var _scoreboard_footer: Label
var _ping_timer := 0.0

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
	player.launched.connect(_on_player_launched)
	player.hit_taken.connect(_on_player_hit_taken)
	player.skill_used.connect(_on_player_skill)
	player.melee_used.connect(_on_player_melee)
	player.released_possessed.connect(_on_player_released)
	_build_tuning_panel()
	_build_menu()
	_build_pause_menu()
	_build_lobby()
	_load_settings()
	_show_menu("")
	_handle_command_line()


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
	_add_key("switch_role", KEY_F2)
	_add_key("scoreboard", KEY_TAB)
	_add_key("restart", KEY_R)
	_add_key("skip_hiding", KEY_ENTER)
	_add_key("taunt_random", KEY_1)
	_add_key("taunt_signature", KEY_2)
	_add_key("toggle_tuning", KEY_F1)
	_add_key("skill_1", KEY_Q)
	_add_key("melee", KEY_F)
	if not InputMap.has_action("rmb"):
		InputMap.add_action("rmb")
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("rmb", right)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", click)


func _unhandled_input(event: InputEvent) -> void:
	if mode == "menu":
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		pause_panel.visible = not pause_panel.visible
		_refresh_mouse()
	elif event.is_action_pressed("toggle_tuning"):
		tuning_panel.visible = not tuning_panel.visible
		_refresh_mouse()
	elif mode == "practice":
		if event.is_action_pressed("restart"):
			start_round()
		elif event.is_action_pressed("switch_role"):
			role = "demon" if role == "angel" else "angel"
			start_round()
		elif event.is_action_pressed("skip_hiding") and state == State.HIDING:
			time_left = 0.0


# The mouse is free whenever a menu or panel is open; otherwise it steers.
func _refresh_mouse() -> void:
	var ui_open := menu_panel.visible or pause_panel.visible or tuning_panel.visible \
			or lobby_panel.visible
	player.input_enabled = not ui_open
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED


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
	# Invisible walls above the visible ones, and a ceiling, so flying demons
	# (and grappling angels) can't leave the map.
	_add_invisible(Vector3(0, 17, MAP_HALF + 1), Vector3(span, 26, 1))
	_add_invisible(Vector3(0, 17, -MAP_HALF - 1), Vector3(span, 26, 1))
	_add_invisible(Vector3(MAP_HALF + 1, 17, 0), Vector3(1, 26, span))
	_add_invisible(Vector3(-MAP_HALF - 1, 17, 0), Vector3(1, 26, span))
	_add_invisible(Vector3(0, CEILING + 0.5, 0), Vector3(span, 1, span))
	# Buildings and cover
	_add_block(Vector3(8, 2, 8), Vector3(6, 4, 6), Color(0.7, 0.6, 0.5))
	_add_block(Vector3(-10, 2, -6), Vector3(7, 4, 5), Color(0.6, 0.55, 0.65))
	_add_block(Vector3(14, 4, -12), Vector3(3, 8, 3), Color(0.55, 0.5, 0.6))
	_add_block(Vector3(-16, 0.5, -16), Vector3(6, 1, 6), Color(0.65, 0.6, 0.5))
	_add_block(Vector3(18, 1.5, 14), Vector3(4, 3, 10), Color(0.6, 0.5, 0.45))
	# A raised platform with a ramp up to it
	_add_block(Vector3(-6, 1, 12), Vector3(8, 2, 4), Color(0.6, 0.6, 0.55))
	_add_block(Vector3(-6, 0.8, 7.3), Vector3(2.5, 0.4, 5.9), Color(0.5, 0.45, 0.4), Vector3(-0.35, 0, 0))   # top edge flush with the platform


const CEILING := 24.0


func _add_invisible(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = center
	add_child(body)


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
	body.set_meta("prop_index", props.size())
	props.append(body)
	round_root.add_child(body)


# Fresh props for a round. The same seed gives the same layout on every computer,
# which is how everyone in an online match sees an identical map.
func _reset_round_props(seed_value: int) -> void:
	if round_root:
		round_root.free()
	round_root = Node3D.new()
	add_child(round_root)
	used_spots.clear()
	props.clear()
	chickens.clear()
	_auth_chickens.clear()
	_possessions.clear()
	rng.seed = seed_value
	var types := PropLib.type_names()
	for i in PROP_COUNT:
		_spawn_prop(types[rng.randi() % types.size()], _random_spot())


# Spread players out around a spawn point so they don't stack.
func spawn_point(for_role: String, index: int) -> Vector3:
	var base := ANGEL_SPAWN if for_role == "angel" else DEMON_SPAWN
	var offsets := [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5),
			Vector3(0, 0, -1.5), Vector3(1.5, 0, 1.5), Vector3(-1.5, 0, 1.5), Vector3(1.5, 0, -1.5)]
	return base + offsets[index % offsets.size()]


func _spawn_bot(type_name: String, pos: Vector3) -> void:
	var bot := BotDemon.new()
	bot.setup(type_name)
	bot.position = pos
	bot.rotation.y = rng.randf_range(0, TAU)
	bot.caught.connect(_on_bot_caught)
	round_root.add_child(bot)


# ---------- menus ----------

func _panel(min_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = min_width
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return [panel, box]


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _field(parent: Control, label_text: String, placeholder: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	parent.add_child(e)
	return e


func _build_menu() -> void:
	var parts := _panel(420)
	menu_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "HALOS & HORNS"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var version := Label.new()
	version.text = "version " + GAME_VERSION
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)
	name_edit = _field(box, "Your name", "Name")
	_build_loadout(box)
	_button(box, "Practice (single player)", start_practice)
	box.add_child(HSeparator.new())
	port_edit = _field(box, "Port", str(NetGame.DEFAULT_PORT))
	_button(box, "Host a game", _on_host_pressed)
	address_edit = _field(box, "Host's address (to join)", "e.g. 203.0.113.5")
	_button(box, "Join a game", _on_join_pressed)
	box.add_child(HSeparator.new())
	_button(box, "Quit", func(): get_tree().quit())
	menu_status = Label.new()
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	box.add_child(menu_status)


func _build_pause_menu() -> void:
	var parts := _panel(300)
	pause_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Paused (the game keeps running)"
	box.add_child(title)
	_button(box, "Resume", func():
		pause_panel.visible = false
		_refresh_mouse())
	_button(box, "Leave to main menu", func(): _show_menu(""))
	pause_panel.visible = false


func _build_lobby() -> void:
	var parts := _panel(460)
	lobby_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Lobby"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	lobby_players = Label.new()
	box.add_child(lobby_players)
	lobby_info = Label.new()
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lobby_info)
	_build_loadout(box)
	lobby_start = _button(box, "Start round", func():
		if net:
			net.start_round())
	_button(box, "Leave", func(): _show_menu(""))
	lobby_panel.visible = false


# Pick 2 skills per side. Shown on the main menu and in the lobby (between rounds).
func _build_loadout(parent: Control) -> void:
	var title := Label.new()
	title.text = "Your skills (2 per side)"
	parent.add_child(title)
	for team in ["angel", "demon"]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "Angel:" if team == "angel" else "Demon:"
		lbl.custom_minimum_size.x = 64
		row.add_child(lbl)
		var keys := ["Q", "Right click"] if team == "angel" else ["Q", "F"]
		for slot in 2:
			var ob := OptionButton.new()
			ob.add_item("%s: none" % keys[slot])
			ob.set_item_metadata(0, "")
			for id in Skills.for_team(team):
				ob.add_item("%s: %s" % [keys[slot], Skills.label(id)])
				ob.set_item_metadata(ob.item_count - 1, id)
				ob.set_item_tooltip(ob.item_count - 1, Skills.SKILLS[id]["desc"])
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.item_selected.connect(func(i): _on_loadout_pick(team, slot, ob.get_item_metadata(i)))
			row.add_child(ob)
			_loadout_buttons.append([team, slot, ob])
		parent.add_child(row)
	_sync_loadout_buttons()


func _on_loadout_pick(team: String, slot: int, id: String) -> void:
	var picked: Array = loadout[team].duplicate()
	if id != "" and id in picked:
		picked[picked.find(id)] = ""   # picking it in the other slot moves it
	picked[slot] = id
	loadout[team] = Skills.clean_loadout(team, picked)
	_apply_loadout()
	_save_settings()


func _apply_loadout() -> void:
	player.loadout = loadout.duplicate(true)
	_sync_loadout_buttons()
	if net:
		net.send_loadout(loadout)


func _sync_loadout_buttons() -> void:
	for entry in _loadout_buttons:
		var ob: OptionButton = entry[2]
		var id: String = loadout[entry[0]][entry[1]]
		for i in ob.item_count:
			if ob.get_item_metadata(i) == id:
				ob.select(i)


func _load_settings() -> void:
	_settings.load(SETTINGS_PATH)
	name_edit.text = _settings.get_value("player", "name", "")
	address_edit.text = _settings.get_value("net", "address", "")
	port_edit.text = str(_settings.get_value("net", "port", NetGame.DEFAULT_PORT))
	for team in ["angel", "demon"]:
		loadout[team] = Skills.clean_loadout(team, _settings.get_value("skills", team, Skills.DEFAULTS[team]))
	_apply_loadout()


func _save_settings() -> void:
	_settings.set_value("player", "name", name_edit.text)
	_settings.set_value("net", "address", address_edit.text)
	_settings.set_value("net", "port", int(port_edit.text) if port_edit.text.is_valid_int() else NetGame.DEFAULT_PORT)
	_settings.set_value("skills", "angel", loadout["angel"])
	_settings.set_value("skills", "demon", loadout["demon"])
	_settings.save(SETTINGS_PATH)


func _show_menu(message: String) -> void:
	if net:
		net.leave()
		net.name = "NetOld"
		net.queue_free()
		net = null
	mode = "menu"
	state = State.LOBBY
	player.net_mode = ""
	player.frozen = true
	player.set_role("demon")
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 0.1, 22)   # a nice view of the map behind the menu
	player.rotation.y = 0.0
	player.visual_root.visible = false             # don't stand in front of the menu
	if round_root:
		round_root.free()
		round_root = null
	menu_status.text = message
	menu_panel.visible = true
	pause_panel.visible = false
	lobby_panel.visible = false
	tuning_panel.visible = false
	blind_rect.visible = false
	center_label.text = ""
	_refresh_mouse()


func _hide_menus() -> void:
	menu_panel.visible = false
	pause_panel.visible = false
	lobby_panel.visible = false
	_refresh_mouse()


func _port() -> int:
	return int(port_edit.text) if port_edit.text.is_valid_int() else NetGame.DEFAULT_PORT


func _make_net() -> void:
	net = NetGame.new()
	net.name = "Net"     # must be the same path on every computer
	net.main = self
	add_child(net)


func _on_host_pressed() -> void:
	_save_settings()
	_make_net()
	var err: Error = net.host(_port(), name_edit.text)
	if err != OK:
		_show_menu("Couldn't host on port %d (error %d). Is another copy already hosting?" % [_port(), err])
		return
	mode = "online"
	player.net_mode = "server"
	net.send_loadout(loadout)
	_hide_menus()
	_fetch_public_ip()
	online_lobby(lobby_names, "lobby")


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		menu_status.text = "Type the host's address first."
		return
	_save_settings()
	_make_net()
	var err: Error = net.join(address, _port(), name_edit.text)
	if err != OK:
		_show_menu("Couldn't start connecting (error %d)." % err)
		return
	mode = "online"
	player.net_mode = "client"
	_hide_menus()
	lobby_players.text = "Connecting to %s..." % address
	lobby_info.text = ""
	lobby_start.visible = false
	lobby_panel.visible = true
	_refresh_mouse()


# The host's internet address, to share with friends (asks a free lookup service).
func _fetch_public_ip() -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_public_ip = body.get_string_from_utf8().strip_edges()
			if net and lobby_panel.visible:
				online_lobby(lobby_names, "lobby")
		req.queue_free())
	req.request("https://api.ipify.org")


# Real network addresses only, labeled with the adapter name ("Ethernet", "Wi-Fi").
# Virtual adapters from VirtualBox, VMware, Hyper-V, WSL and so on are left out:
# friends can't reach those, and they're confusing.
func _local_ips() -> Array:
	var ips := []
	var virtual_words := ["virtualbox", "vmware", "vethernet", "hyper-v", "wsl", "loopback",
			"bluetooth", "docker", "tap", "tun", "zerotier", "tailscale"]
	for iface in IP.get_local_interfaces():
		var label: String = str(iface.get("friendly", iface.get("name", "")))
		var lower := label.to_lower()
		var skip := false
		for w in virtual_words:
			if w in lower:
				skip = true
		for ip in iface.get("addresses", []):
			if skip or ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254.") \
					or ip.begins_with("192.168.56."):   # VirtualBox's usual fake network
				continue
			ips.append("%s (%s)" % [ip, label] if label != "" else ip)
	return ips


# ---------- practice rounds ----------

func start_practice() -> void:
	_hide_menus()
	mode = "practice"
	player.net_mode = ""
	start_round()


func start_round() -> void:
	_reset_round_props(randi())
	var types := PropLib.type_names()
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
	controls_label.text = _controls_text()
	if role == "angel":
		_toast("The demons are hiding...\n(Enter to skip the wait while testing)", HIDE_TIME)
	else:
		_toast("Demon sandbox: practice possessing props.\nTry Host / Join for real hunting.", 5.0)


func _controls_text() -> String:
	var common := "WASD move   Shift run   Ctrl sneak   Space jump   1 / 2 taunt   T first/third person"
	var side := "Left click throw   Q / Right click skills   F melee   B blessing (testing)" if role == "angel" \
			else "Click a prop: transform   Hold click: demon form   Hold right click: fly   Q / F skills"
	if mode == "practice":
		return common + "\n" + side + "   F2 switch side   R restart   F1 movement tuning   Esc menu"
	return common + "\n" + side + "   Tab roster   F1 movement tuning   Esc menu"


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
	if mode == "practice" and state != State.ENDED:
		time_left -= delta
		if time_left <= 0.0:
			if state == State.HIDING:
				_start_hunting()
			else:
				_end_round("Time's up! The demons win." if role == "angel" else "Time's up! You survived!")
	elif mode == "online":
		time_left = maxf(time_left - delta, 0.0)   # the host decides when phases change
	if is_authority():
		_check_chickens(delta)
	_update_hud(delta)


# ---------- online (called by net_game.gd) ----------

func in_online_round() -> bool:
	return mode == "online" and (state == State.HIDING or state == State.HUNTING)


func _phase_to_state(phase: String) -> State:
	match phase:
		"hiding":
			return State.HIDING
		"hunting":
			return State.HUNTING
		"ended":
			return State.ENDED
	return State.LOBBY


func online_lobby(names: Array, host_phase: String) -> void:
	lobby_names = names
	if state != State.LOBBY:
		return   # mid-round: the list updates, the panel stays hidden
	lobby_players.text = "Players (%d):\n  %s" % [names.size(), "\n  ".join(_lobby_lines(names))]
	var is_host: bool = net != null and net.is_host
	lobby_start.visible = is_host
	if is_host:
		lobby_start.disabled = names.size() < 2
		lobby_start.text = "Start round" if names.size() >= 2 else "Start round (need at least 2 players)"
		var lines := ["Friends join with your address and port %d:" % _port()]
		if _public_ip != "":
			lines.append("  Over the internet: %s  (needs the port forwarded on your router)" % _public_ip)
		var lan := _local_ips()
		if not lan.is_empty():
			lines.append("  Same house / same Wi-Fi: %s" % ", ".join(lan))
		lobby_info.text = "\n".join(lines)
	elif host_phase == "lobby":
		lobby_info.text = "Waiting for the host to start the round..."
	else:
		lobby_info.text = "A round is in progress. You'll join it as an angel in a moment..."
	lobby_panel.visible = true
	_refresh_mouse()


# Lobby list with pings when the host has sent them.
func _lobby_lines(names: Array) -> Array:
	var lines := []
	for n in names:
		var line: String = n
		for row in scoreboard_rows:
			if row[0] == n:
				if row[6]:
					line += "   (host)"
				elif row[2] >= 0:
					line += "   %d ms" % row[2]
				if row[5]:
					line += "   <- you"
		lines.append(line)
	return lines


func online_scoreboard(rows: Array) -> void:
	scoreboard_rows = rows
	if lobby_panel.visible and state == State.LOBBY:
		lobby_players.text = "Players (%d):\n  %s" % [lobby_names.size(), "\n  ".join(_lobby_lines(lobby_names))]
	if scoreboard_panel.visible:
		_fill_scoreboard()


func online_round_start(seed_value: int, new_role: String, pos: Vector3, phase: String, seconds: float) -> void:
	_reset_round_props(seed_value)
	role = new_role
	my_health = NetGame.DEMON_HEALTH
	player.set_role(new_role)
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.rotation.y = PI if new_role == "angel" else 0.0
	state = _phase_to_state(phase)
	time_left = seconds
	player.frozen = new_role == "angel" and state == State.HIDING
	blind_rect.visible = player.frozen
	controls_label.text = _controls_text()
	lobby_panel.visible = false
	pause_panel.visible = false
	_refresh_mouse()
	if new_role == "angel":
		_toast("You're an ANGEL.\nThe demons are hiding..." if state == State.HIDING else "You're an ANGEL. Find the demons!", 4.0)
	else:
		_toast("You're a DEMON! Hide!\nClick a prop to possess it.", 4.0)


func online_phase(phase: String, seconds: float) -> void:
	state = _phase_to_state(phase)
	time_left = seconds
	if state == State.HUNTING:
		player.frozen = false
		blind_rect.visible = false
		_toast("The hunt is on!" if role == "demon" else "Go find them!", 2.5)


func online_count(n: int) -> void:
	bots_left = n


func online_you_hit(health: int) -> void:
	my_health = health
	_hurt_time = 0.25


# The angels yanked us (vacuum orb or grappling hook).
func online_affected(target: Vector3, hatred_drain: float, lockout: float) -> void:
	player.pull_to(target, 1.0)
	player.hatred = maxf(player.hatred - hatred_drain, 0.0)
	player.skill_lock = maxf(player.skill_lock, lockout)
	_hurt_time = 0.2
	_toast("VACUUMED!" if lockout > 0.0 else "HOOKED!", 1.2)


func online_you_were_caught(pos: Vector3) -> void:
	role = "angel"
	player.set_role("angel")
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.rotation.y = PI
	player.frozen = false
	controls_label.text = _controls_text()
	_toast("You were caught and REDEEMED!\nNow you're an angel. Hunt your old friends!", 4.0)


func online_caught_fx(pos: Vector3) -> void:
	_play("caught")
	Effects.puff(self, pos + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.9), 1.6)
	if role == "angel" and bots_left > 0:
		_toast("A demon was redeemed! %d left" % bots_left, 2.0)


func online_round_end(message: String) -> void:
	state = State.ENDED
	player.frozen = true
	_toast(message + "\nBack to the lobby in a few seconds...", 9999.0)


func online_back_to_lobby() -> void:
	state = State.LOBBY
	center_label.text = ""
	blind_rect.visible = false
	if round_root:
		round_root.free()
		round_root = null
	player.frozen = true
	online_lobby(lobby_names, "lobby")


func online_correct(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO


func online_disconnected(message: String) -> void:
	_show_menu(message)


func _on_player_launched(origin: Vector3, velocity: Vector3, kind: String) -> void:
	if net:
		net.on_local_launched(origin, velocity, kind)


func _on_player_hit_taken(damage: int) -> void:
	if net and net.is_host:
		net.damage_player(1, damage)


# ---------- skills: deciding what happens ----------
# In practice the game itself decides what a skill does; online, the host does
# (net_game.gd checks every request first). The same code runs either way, and
# broadcast_fx() shows the results on every screen.

func is_authority() -> bool:
	return mode == "practice" or (net != null and net.is_host)


func _on_player_skill(id: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if id == "grapple":
		var rope := Rope.new()          # instant, and it follows us while we zip
		rope.from_node = player
		rope.to_pos = point
		rope.duration = 0.25 if not player.is_grappling() else 1.2
		_fx_parent().add_child(rope)
	if mode == "practice":
		authority_skill(player, 0, id, origin, dir, point, index)
	elif net:
		if id == "vacuum" and not net.is_host:
			_spawn_orb(origin, dir, true)   # our own copy, just to see; the host's is real
		net.on_local_skill(id, origin, dir, point, index)


func _on_player_melee(origin: Vector3, dir: Vector3) -> void:
	if mode == "practice":
		authority_melee(player, 0, origin, dir)
	elif net:
		net.on_local_melee(origin, dir)


func _on_player_released() -> void:
	if mode == "practice":
		authority_release(0, player.global_position, player.rotation.y)
	elif net:
		net.on_local_release()


func _ray(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var rids := []
	for n in exclude:
		if is_instance_valid(n) and n is CollisionObject3D:
			rids.append(n.get_rid())
	q.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(q)


func ground_below(point: Vector3) -> Vector3:
	var hit := _ray(point + Vector3.UP * 0.5, point + Vector3.DOWN * 40.0, [])
	return hit["position"] if not hit.is_empty() else Vector3(point.x, 0.0, point.z)


# Every demon the decider can affect: practice test demons, or (host) players.
func demon_targets() -> Array:
	if mode == "practice":
		var out := []
		if round_root:
			for c in round_root.get_children():
				if c is BotDemon:
					out.append(c)
		return out
	return net.demon_nodes() if net else []


# `user` is whoever used the skill (our player, or another player's stand-in on the
# host); `user_key` is 0 in practice, otherwise their network id (1 = host).
func authority_skill(user: Node3D, user_key: int, id: String, origin: Vector3, dir: Vector3,
		point: Vector3, index: int) -> void:
	match id:
		"chicken":
			_chicken_counter += 1
			var pos := ground_below(point)
			_auth_chickens[_chicken_counter] = {"pos": pos, "until": Time.get_ticks_msec() / 1000.0 + Skills.CHICKEN_LIFETIME, "alarmed": false}
			broadcast_fx("chicken", [_chicken_counter, pos])
			print("[decider] chicken dropped")
		"vacuum":
			var orb := _spawn_orb(origin, dir, false)
			orb.shooter = user
			orb.on_impact = _vacuum_at
			broadcast_fx("orb", [origin, dir], user_key)
		"grapple":
			var hit := _ray(origin, origin + dir * Skills.GRAPPLE_RANGE, [user])
			if hit.is_empty():
				return
			var c = hit["collider"]
			broadcast_fx("rope", [user.global_position + Vector3.UP * 1.2, hit["position"], 0.5], user_key)
			if c.has_method("take_hit") and c.take_hit(Skills.GRAPPLE_DAMAGE):
				user.confirm_hit()
				var flat := Vector3(dir.x, 0.0, dir.z).normalized()
				_affect_demon(c, user.global_position + flat * 1.5, 0.0, 0.0)
				print("[decider] grappling hook snagged a demon")
			elif net and user_key > 1:
				net.grant_grapple(user_key)   # they may zip fast for a moment
		"possess":
			_authority_possess(user, user_key, index)


func authority_melee(user: Node3D, _user_key: int, origin: Vector3, dir: Vector3) -> void:
	var hit := _ray(origin, origin + dir * Skills.MELEE_RANGE, [user])
	if not hit.is_empty() and hit["collider"].has_method("take_hit") \
			and hit["collider"].take_hit(Skills.MELEE_DAMAGE):
		user.confirm_hit()
		print("[decider] melee hit a demon")


func _spawn_orb(origin: Vector3, dir: Vector3, visual_only: bool) -> Projectile:
	var orb := Projectile.new()
	orb.color = Color(0.65, 0.35, 1.0)
	orb.size = 0.22
	orb.gravity = 9.0
	orb.damage = 0
	orb.visual_only = visual_only
	_fx_parent().add_child(orb)
	orb.global_position = origin + dir * 0.6
	orb.velocity = dir * 22.0 + Vector3.UP * 2.0
	return orb


func _vacuum_at(center: Vector3) -> void:
	var caught := false
	for d in demon_targets():
		if d.global_position.distance_to(center) <= Skills.VACUUM_RADIUS:
			caught = true
			var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
			_affect_demon(d, center + offset, Skills.VACUUM_HATRED_DRAIN, Skills.VACUUM_LOCKOUT)
	broadcast_fx("vortex", [center, caught])
	print("[decider] vacuum orb %s" % ("CAUGHT a demon" if caught else "found nothing"))


# Yank a demon somewhere, drain Hatred, lock their skills.
func _affect_demon(node: Node3D, target: Vector3, hatred_drain: float, lockout: float) -> void:
	if node is BotDemon:
		var tw := node.create_tween()
		tw.tween_property(node, "global_position", Vector3(target.x, node.global_position.y, target.z), 0.5)
	elif net:
		net.affect_node(node, target, hatred_drain, lockout)


func _authority_possess(user: Node3D, user_key: int, index: int) -> void:
	if index < 0 or index >= props.size():
		return
	var prop = props[index]
	if not is_instance_valid(prop) or not prop.is_in_group("prop"):
		return   # already possessed by someone, or dissolving
	if user.global_position.distance_to(prop.global_position) > 12.0:
		return
	var from: Vector3 = user.global_position
	authority_release(user_key, from, user.rotation.y)
	_possessions[user_key] = index
	broadcast_fx("prop_taken", [index])
	broadcast_fx("sparkle", [from, prop.global_position])
	var type_name: String = prop.get_meta("prop_type")
	if user_key <= 1:
		player.become_possessed(type_name, prop.global_position, prop.rotation.y, index)
	else:
		net.tell_possessed(user_key, type_name, prop.global_position, prop.rotation.y, index)
	print("[decider] a demon possessed a %s" % type_name)


# Someone left a possessed prop (or was caught in it): the original stays where
# they left it and slowly dissolves.
func authority_release(user_key: int, pos: Vector3, yaw: float) -> void:
	if not _possessions.has(user_key):
		return
	var index: int = _possessions[user_key]
	_possessions.erase(user_key)
	broadcast_fx("prop_shell", [index, pos, yaw])


func _check_chickens(delta: float) -> void:
	_chicken_check -= delta
	if _chicken_check > 0.0 or _auth_chickens.is_empty():
		return
	_chicken_check = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	var targets := demon_targets()
	for cid in _auth_chickens.keys():
		var c: Dictionary = _auth_chickens[cid]
		if now > c["until"]:
			_auth_chickens.erase(cid)
			continue
		var near := false
		for d in targets:
			if d.global_position.distance_to(c["pos"]) <= Skills.CHICKEN_RADIUS:
				near = true
		if near != c["alarmed"]:
			c["alarmed"] = near
			broadcast_fx("chicken_alarm", [cid, near])
			if near:
				print("[decider] chicken alarm: demon nearby")


# ---------- effects everyone sees ----------

# Show an effect here and on everyone else's screen. `except_key` is the player
# who caused it: they already drew their own rope / orb, so they don't get a copy.
func broadcast_fx(kind: String, args: Array, except_key := -1) -> void:
	var we_caused_it := except_key == 0 or except_key == 1   # practice player or the host
	if not (we_caused_it and (kind == "rope" or kind == "orb")):
		fx(kind, args)
	if net and net.is_host:
		net.send_fx(kind, args, except_key)


func _fx_parent() -> Node:
	return round_root if round_root else self


func fx(kind: String, args: Array) -> void:
	match kind:
		"chicken":
			var c := Chicken.new()
			c.chicken_id = args[0]
			_fx_parent().add_child(c)
			c.global_position = args[1]
			chickens[args[0]] = c
		"chicken_alarm":
			if chickens.has(args[0]) and is_instance_valid(chickens[args[0]]):
				chickens[args[0]].alarmed = args[1]
		"orb":
			_spawn_orb(args[0], args[1], true)
		"vortex":
			var v := Vortex.new()
			v.caught = args[1]
			_fx_parent().add_child(v)
			v.global_position = args[0]
			_pull_props(args[0])
		"rope":
			var r := Rope.new()
			r.from_pos = args[0]
			r.to_pos = args[1]
			r.duration = args[2]
			_fx_parent().add_child(r)
		"sparkle":
			Effects.sparkle_trail(_fx_parent(), args[0], args[1])
		"prop_taken":
			_set_prop_taken(args[0])
		"prop_shell":
			_make_shell(args[0], args[1], args[2])


func _set_prop_taken(index: int) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: Node3D = props[index]
	prop.visible = false
	prop.remove_from_group("prop")
	for c in prop.get_children():
		if c is CollisionShape3D:
			c.disabled = true


# The abandoned original: back where the demon left it, solid (shots just hit it,
# no damage), can't be transformed into or possessed again, fading away.
func _make_shell(index: int, pos: Vector3, yaw: float) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: Node3D = props[index]
	prop.global_position = pos
	prop.rotation.y = yaw
	prop.visible = true
	for c in prop.get_children():
		if c is CollisionShape3D:
			c.disabled = false
	Effects.dissolve(prop, 6.0)


# The vortex drags nearby props toward its middle. Every computer runs the same
# math on the same starting positions, so every screen ends up identical.
func _pull_props(center: Vector3) -> void:
	for prop in props:
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			continue
		var flat := Vector3(prop.global_position.x - center.x, 0.0, prop.global_position.z - center.z)
		var d := flat.length()
		if d >= Skills.VACUUM_RADIUS or d < 0.01:
			continue
		var target := Vector3(center.x, prop.global_position.y, center.z) + flat / d * maxf(1.2, d * 0.45)
		var tw: Tween = prop.create_tween()
		tw.tween_property(prop, "global_position", target, 1.2).set_ease(Tween.EASE_IN)


# ---------- command line (automated testing) ----------
# e.g.  godot -- --host --name=Ted --autostart=3 --hide=5
#       godot -- --join=127.0.0.1 --name=Bot --autobot

func _handle_command_line() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if args.is_empty():
		return
	if args.has("name"):
		name_edit.text = args["name"]
	if args.has("port"):
		port_edit.text = args["port"]
	if args.has("autobot"):
		autobot = Autobot.new()
		autobot.main = self
		autobot.options = args
		add_child(autobot)
	if args.has("practice"):
		start_practice()
	elif args.has("host"):
		_on_host_pressed()
		if net and args.has("hide"):
			net.hide_time = float(args["hide"])
		if net and args.has("hunt"):
			net.hunt_time = float(args["hunt"])
		if net and args.has("roles"):   # e.g. --roles=Theo:demon,Wife:angel
			for pair in args["roles"].split(","):
				var kv: PackedStringArray = pair.split(":")
				net.forced_roles[kv[0]] = kv[1]
	elif args.has("join"):
		address_edit.text = args["join"]
		_on_join_pressed()


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

	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.9, 0.05, 0.05, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hurt_rect)

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

	# Skills, bottom right
	skill_label = _make_label(18)
	skill_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skill_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skill_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skill_label.position += Vector2(-16, -16)
	hud.add_child(skill_label)

	# Ping, top right
	ping_label = _make_label(20)
	ping_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ping_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.position += Vector2(-16, 14)
	hud.add_child(ping_label)

	_build_scoreboard(hud)

	taunt_label = _make_label(22)
	taunt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	taunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taunt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	taunt_label.position.y -= 150
	hud.add_child(taunt_label)


const BAR_WIDTH := 260.0


# Hold Tab: both teams, ping and chosen skills.
func _build_scoreboard(hud: CanvasLayer) -> void:
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scoreboard_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_panel.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.05, 0.11, 0.9)   # dark enough to read over any scene
	bg.set_corner_radius_all(10)
	scoreboard_panel.add_theme_stylebox_override("panel", bg)
	hud.add_child(scoreboard_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	scoreboard_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	outer.add_child(cols)
	_scoreboard_footer = Label.new()
	_scoreboard_footer.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	outer.add_child(_scoreboard_footer)
	for team in ["angel", "demon"]:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 380
		cols.add_child(box)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 26)
		title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5) if team == "angel" else Color(1.0, 0.45, 0.4))
		box.add_child(title)
		_scoreboard_titles[team] = title
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 24)
		box.add_child(grid)
		_scoreboard_columns[team] = grid


func _fill_scoreboard() -> void:
	var rows := scoreboard_rows
	if mode == "practice":
		rows = [[name_edit.text if name_edit.text != "" else "You", role, 0, [], false, true, false]]
	for team in ["angel", "demon"]:
		var grid: GridContainer = _scoreboard_columns[team]
		for c in grid.get_children():
			c.queue_free()
		var count := 0
		for header in ["Name", "Ping", "Skills"]:
			var h := Label.new()
			h.text = header
			h.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
			grid.add_child(h)
		for row in rows:
			if row[1] != team:
				continue
			count += 1
			var n := Label.new()
			n.text = row[0] + ("  (you)" if row[5] else "") + ("  (host)" if row[6] else "") \
					+ ("  redeemed" if row[4] else "")
			if row[5]:
				n.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
			grid.add_child(n)
			var p := Label.new()
			p.text = "-" if row[6] or mode == "practice" else ("%d ms" % row[2] if row[2] >= 0 else "?")
			p.add_theme_color_override("font_color", _ping_color(row[2]))
			grid.add_child(p)
			var sk := Label.new()
			sk.text = ", ".join(row[3]) if not row[3].is_empty() else "none yet"
			grid.add_child(sk)
		_scoreboard_titles[team].text = ("ANGELS" if team == "angel" else "DEMONS") + " (%d)" % count
	var waiting := 0
	for row in rows:
		if row[1] == "":
			waiting += 1
	_scoreboard_footer.text = "%d waiting in the lobby for the next round" % waiting if waiting > 0 else ""
	_scoreboard_footer.visible = waiting > 0


func _skill_line(key: String, id: String) -> String:
	if id == "":
		return "[%s] -" % key
	var cd: float = player.skill_cd.get(id, 0.0)
	return "[%s] %s   %s" % [key, Skills.label(id), "ready" if cd <= 0.0 else "%ds" % ceili(cd)]


func _skill_text() -> String:
	var lo: Array = player.loadout[role]
	if role == "angel":
		var melee := "ready" if player.melee_cd <= 0.0 else "..."
		return "%s\n%s\n[F] Melee   %s" % [_skill_line("Q", lo[0]), _skill_line("Right click", lo[1]), melee]
	var text := "%s\n%s\n[Hold right click] Fly%s" % [_skill_line("Q", lo[0]), _skill_line("F", lo[1]),
			"   (flying)" if player.flying else ""]
	if player.skill_lock > 0.0:
		text += "\nSKILLS LOCKED  %.1fs" % player.skill_lock
	return text


func _ping_color(ms: int) -> Color:
	if ms < 0:
		return Color(0.8, 0.8, 0.8)
	if ms < 90:
		return Color(0.55, 1.0, 0.55)
	if ms < 170:
		return Color(1.0, 0.9, 0.4)
	return Color(1.0, 0.5, 0.4)


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
	title.text = "Movement tuning (F1 to close)\nApplies to both teams, only on your computer"
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
	if net:
		net.on_local_taunt(taunt_name)


func _toast(text: String, seconds: float) -> void:
	center_label.text = text
	_toast_time = seconds


func _update_hud(delta: float) -> void:
	var want_board := mode != "menu" and Input.is_action_pressed("scoreboard") \
			and not pause_panel.visible and not menu_panel.visible
	if want_board and not scoreboard_panel.visible:
		_fill_scoreboard()
	scoreboard_panel.visible = want_board
	center_label.modulate.a = 0.0 if want_board else 1.0   # don't overlap the roster
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 0.5
		if mode == "online" and net:
			if net.is_host:
				ping_label.text = "You're hosting"
				ping_label.remove_theme_color_override("font_color")
			else:
				var ms: int = net.my_ping()
				ping_label.text = "Ping: %s" % ("%d ms" % ms if ms >= 0 else "...")
				ping_label.add_theme_color_override("font_color", _ping_color(ms))
		else:
			ping_label.text = ""
	_toast_time -= delta
	if _toast_time <= 0.0:
		center_label.text = ""
	var in_game := mode != "menu" and state != State.LOBBY
	status_label.visible = in_game
	crosshair.visible = in_game
	controls_label.visible = in_game
	bar_fills["sprint"][0].get_parent().get_parent().get_parent().visible = in_game
	var t := maxi(int(ceil(time_left)), 0)
	var clock := "%d:%02d" % [t / 60, t % 60]
	var phase := "Hiding" if state == State.HIDING else ("Hunting" if state == State.HUNTING else "Round over")
	var side := "ANGEL" if role == "angel" else "DEMON"
	var text := "%s   |   %s  %s" % [side, phase, clock if state != State.ENDED else ""]
	if role == "angel":
		text += "   |   Demons left: %d   |   %s" % [bots_left, Blessings.label(player.blessing)]
	elif mode == "online":
		text += "   |   Health: %d%%" % maxi(my_health, 0)
	status_label.text = text

	_hurt_time -= delta
	hurt_rect.color.a = clampf(_hurt_time, 0.0, 0.25) * 1.4

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
	skill_label.visible = in_game
	skill_label.text = _skill_text()

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
	elif role == "demon" and player.look_target_type != "" and in_game:
		hint_label.text = "Click: possess %s" % PropLib.label(player.look_target_type)
	else:
		hint_label.text = ""
