# Halos & Horns: menu, the test map, the HUD, practice mode, and the screens
# around online play (online rules themselves live in net_game.gd).
#   Practice: single player. Angel side hunts 3 test demons; demon side is a sandbox.
#   Online: one player hosts, friends join with a room code (through the relay
#   server) or by address. Mobification rules.
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Player = preload("res://scripts/player.gd")
const BotDemon = preload("res://scripts/bot_demon.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const NetGame = preload("res://scripts/net_game.gd")
const EffectIcons = preload("res://scripts/effect_icons.gd")
const Aura = preload("res://scripts/aura.gd")
const RelayProtocol = preload("res://relay/relay_protocol.gd")
# Drew's relay server. (relay_protocol.gd names it saucer.drewburr.com, after his
# game; it's the same server, and Drew asked games to use this name.)
const RELAY_HOST := "relay.drewburr.com"
const Effects = preload("res://scripts/effects.gd")
const Autobot = preload("res://scripts/autobot.gd")
const Skills = preload("res://scripts/skills.gd")
const Cherub = preload("res://scripts/cherub.gd")
const Fire = preload("res://scripts/fire.gd")
const Minion = preload("res://scripts/minion.gd")
const PowerUps = preload("res://scripts/powerups.gd")
const Keybinds = preload("res://scripts/keybinds.gd")
const PropAnims = preload("res://scripts/prop_anims.gd")
const PropAnimSounds = preload("res://scripts/prop_anim_sounds.gd")
const Bouncy = preload("res://scripts/bouncy.gd")
const Models = preload("res://scripts/models.gd")
const Shrine = preload("res://scripts/shrine.gd")
const MapData = preload("res://scripts/map_data.gd")
const Editor = preload("res://scripts/editor.gd")
const SenseCherub = preload("res://scripts/sense_cherub.gd")
const Bodies = preload("res://scripts/bodies.gd")
const Graphics = preload("res://scripts/graphics.gd")
const Lamp = preload("res://scripts/lamp.gd")
const Decor = preload("res://scripts/decor.gd")
const GroundBlock = preload("res://scripts/ground_block.gd")
const HollowBuildings = preload("res://scripts/hollow_buildings.gd")
const Backdrop = preload("res://scripts/backdrop.gd")
const SnowTracks = preload("res://scripts/snow_tracks.gd")
const SlimeTrail = preload("res://scripts/slime_trail.gd")
const Music = preload("res://scripts/music.gd")
const Knock = preload("res://scripts/knock.gd")
# The current map's layout (filled in by load_map from the map file).
var map_data := {}
var map_path := ""
var world_root: Node3D           # everything the map file built (rebuilt when the map changes)
var editor                       # Creative mode (made the first time it's opened)
var _editor_map := {}            # the last map built in Creative (reopened next time)
var building_online := false     # in Creative with everyone (net_game.gd's "building together")
var _back_to_editor: Button
var SHRINE_POS := Vector3(0, -1000, 0)   # the map's one shrine (far away if it has none)
var BOUNCIES := []               # permanent bouncy spots
var ONE_USE_BOUNCIES := []       # one-use bouncy spots (they come back each round)
var ONE_USE_LOOKS := []          # ...and their colours
var SUPER_BOUNCIES := []         # super-bouncy spots
var PLACED_PROPS := []           # [type, position, rotation] of props placed by hand
const Vortex = preload("res://scripts/vortex.gd")
const Projectile = preload("res://scripts/projectile.gd")
const BlessingSounds = preload("res://scripts/blessing_sounds.gd")
const Updater = preload("res://scripts/updater.gd")
const GameRules = preload("res://scripts/game_rules.gd")

const GAME_CODENAME := "Power-ups"
const HIDE_TIME := 30.0
const HUNT_TIME := 180.0
const HEAT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	float t = TIME;
	vec2 uv = SCREEN_UV;
	// Big slow swirls plus fast shimmer, like looking through a bonfire.
	uv.x += strength * (0.025 * sin(uv.y * 9.0 + t * 3.1) + 0.008 * sin(uv.y * 47.0 + t * 17.0));
	uv.y += strength * (0.02 * sin(uv.x * 7.0 - t * 2.3) + 0.008 * cos(uv.x * 39.0 + t * 13.0));
	// Edges pulled in and out, like the view is breathing.
	uv = mix(uv, vec2(0.5) + (uv - vec2(0.5)) * (1.0 + 0.06 * sin(t * 4.0)), strength);
	vec3 c = textureLod(screen_tex, uv, strength * 1.5).rgb;
	// Hot orange cast and a red glow creeping in from the edges.
	float edge = smoothstep(0.35, 0.75, distance(SCREEN_UV, vec2(0.5)));
	c = mix(c, c * vec3(1.35, 0.8, 0.45) + vec3(0.12, 0.03, 0.0), strength * 0.7);
	c = mix(c, vec3(0.9, 0.25, 0.02), edge * strength * 0.55);
	COLOR = vec4(c, 1.0);
}
"""
const HIDE_CHOICES := [15.0, 30.0, 45.0, 60.0, 90.0]
const IDLE_CHOICES := [0.0, 120.0, 300.0, 600.0]   # kick angels who haven't moved or looked around for this long (0 = never; demons are never kicked)
const HUNT_CHOICES := [120.0, 180.0, 300.0, 600.0, 900.0, 1800.0]
const BOT_COUNT := 3
var PROP_COUNT := 45            # random props each round (from the map)
var MAP_HALF := 28.0
var ANGEL_SPAWN := Vector3(0, 0.1, -24)
var DEMON_SPAWN := Vector3(0, 0.1, 0)
const SETTINGS_PATH := "user://settings.cfg"

enum State { LOBBY, HIDING, HUNTING, ENDED }

var mode := "menu"           # menu, practice, online
var state: State = State.LOBBY
var time_left := 0.0
var role := "angel"          # practice starts on the side that has a full round to play
var bots_left := 0           # demons left (test demons in practice, players online)
var my_health := 1.0         # online demons: fraction of health left (same fraction in every form)
var loadout := Skills.DEFAULTS.duplicate(true)   # your chosen skills (saved)
var props: Array = []        # this round's map props, by index (same on every computer)
var cherubs := {}           # cherub id -> Cherub node (visuals, everyone)
var _auth_cherubs := {}     # cherub id -> {pos, until, alarmed} (decider only)
var _cherub_counter := 0
var fires := {}              # fire id -> Fire node (everyone; angels check if they're standing in one)
var _fire_counter := 0
var powerups                 # power-up drops and pickups (powerups.gd)
var bouncies := {}            # one-use bouncy id -> node (this round)
var _auth_fires := {}        # decider: fire id -> {owner, pos, lit_at, until} (who earns Hatred from it)
var _naughty_tick := 0.0
var _cherub_check := 0.0
var _possessions := {}       # who possesses which prop: user key -> prop index (decider only)
var _loadout_buttons: Array = []   # [team, slot, OptionButton]
var skill_label: Label
var disguise_label: Label      # top left: the prop a demon looks like
var bonus_label: Label
var powerup_label: Label
var effect_icons                 # the top-right row of effect icons (effect_icons.gd)
var my_aura: Node3D              # our own power-up aura, as others see it (aura.gd)
var _sense_bubble: MeshInstance3D
var _sense_cherub: Node3D          # Cherub Sense: the little cherub dangling above our head
var _sense_sound_time := 0.0
var _bonus_time := 0.0
var shrine: Node3D
var shrine_panel: PanelContainer
var _shrine_buttons := []       # the two OptionButtons for the current side
var _shrine_pick := ["", ""]
var _shrine_elapsed := 0.0      # seconds since this swap started
var _shrine_done := false       # picked and confirmed; waiting out the rest of the 3 s
var _shrine_status: Label
var _shrine_look: OptionButton  # one of your saved wardrobe looks, put on with the swap (Ted, Nov 26)
var _was_at_shrine := false   # just walked up to the shrine: show how to use it
var chat_box: VBoxContainer     # recent chat lines, bottom left
var chat_edit: LineEdit
var chat_team_only := false
# Text size for everything (menus, HUD, Creative): the whole 2D layer is scaled. Settings, or Ctrl + / Ctrl - anywhere.
const UI_SCALES := [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.5]
var ui_scale := 1.0
var _ui_scale_pick: OptionButton
var _scroll_panels := []         # [ScrollContainer, its contents]: panels that scroll when too tall for the screen
var chat_font_size := 22         # Settings: how big chat text is (each player picks their own; was 17)
var _chat_size_pick: SpinBox
var _fps_pick: CheckButton
var fps_label: Label            # (Settings: "Show FPS", off by default; Ted, Nov 26)
var _fps_tick := 0.0
var lobby_chat: PanelContainer   # the lobby's own chat: a log and a box to type in
var _lobby_chat_log: VBoxContainer
var _lobby_chat_scroll: ScrollContainer
var _lobby_chat_edit: LineEdit
var _chat_lines := []           # [Label, seconds left on screen]
var lobby_times: VBoxContainer   # host's round-length pickers
var lobby_map_label: Label
var _map_pick: OptionButton      # host: which map
var _kick_pick: OptionButton     # host: who to kick
var _time_pick := {}            # picker label -> chosen index
var heat_rect: ColorRect         # Hellfire screen distortion
var hold_bar: ColorRect          # "returning to demon form" progress, under the crosshair
var hold_fill: ColorRect
var player: Player
var net: Node = null
# The version is the GitHub release tag, stamped into the build by release-builds.yml.
# Run from source, or built by hand, it's "dev".
var game_version: String = ProjectSettings.get_setting("application/config/version", "dev")
var game_build := 0          # the same version as one number (0.4.1 -> 401); only equal builds can play together
var updater: Updater          # checks GitHub for a newer version (see updater.gd)
var update_button: Button
var update_note: Label
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
# Angels' hiding-phase wait (Ted, Nov 25: "something fun or silly to do", and the mouse was stuck captured
# behind the black screen): Whack-an-Imp on top of the blindfold, with the mouse free.
const WaitingGame = preload("res://scripts/waiting_game.gd")
var waiting_game: Control
var _blind_was := false
var hurt_rect: ColorRect
var crosshair: Label
var _toast_time := 0.0
var _hitmarker_time := 0.0
var _hurt_time := 0.0
var _sounds := {}             # name -> AudioStreamPlayer
var _fly_sound: AudioStreamPlayer
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
var lobby_build: Button
var _public_ip := ""
var _room_code := ""          # the relay room code (the host's, or the one we joined with)
var _room_watermark: Label     # the code, big and faint, behind the lobby
var _settings_code_row: HBoxContainer
var _settings_code_label: Label
var _relay_override := ""     # --relay=HOST[:PORT]
var _settings := ConfigFile.new()
var ping_label: Label
var scoreboard_panel: PanelContainer
var _scoreboard_columns := {}     # "angel"/"demon" -> GridContainer
var _scoreboard_titles := {}
var _scoreboard_footer: Label
var _ping_timer := 0.0
var graphics: Graphics          # sky, lighting and the graphics quality setting
var music: Music               # the soundtrack (music.gd)
var _music_volume := 0.6
var _sound_volume := 1.0
var _quality_pick: OptionButton
# Game rules (game_rules.gd): Standard, or the player's own Custom set (saved). The host's count online.
var rules_custom := GameRules.standard()
var rules_use_custom := false
var rules_panel: Control
var _rules_inputs := {}           # rule -> SpinBox / CheckBox
var _rules_pick: OptionButton     # lobby: Standard / Custom
var _rules_summary: Label
var _switch_side: Button          # pause menu, practice / testing a map: play the other team
var _solo_pick: OptionButton      # lobby, host alone: which team you play
var _solo_row: HBoxContainer
var _solo_popup: Control          # host alone: someone joined mid-round
var _solo_label: Label
var _solo_until := 0.0
var _music_slider: HSlider
var _sound_slider: HSlider

# F1 tuning panel: [key, label, min, max, step]
const TUNING_SLIDERS := [
	["ground_accel", "Acceleration", 5.0, 120.0, 1.0],
	["ground_decel", "Stopping (lower = more slide)", 5.0, 120.0, 1.0],
	["air_accel", "Air control", 0.0, 40.0, 1.0],
	["gravity_scale", "Gravity", 0.5, 3.0, 0.05],
	["fall_multiplier", "Extra fall speed", 1.0, 3.0, 0.05],
	["jump_velocity", "Jump strength", 3.0, 9.0, 0.1],
	["head_bob", "Head bob (0 = off)", 0.0, 2.0, 0.05],
	["camera_kick", "Camera kick: run/dash zoom, lean, landing squash (0 = off)", 0.0, 2.0, 0.05],
	["coyote_time", "Jump: grace after leaving a ledge (s)", 0.0, 0.3, 0.01],
	["jump_buffer", "Jump: early press still counts (s)", 0.0, 0.3, 0.01],
	["dash_speed", "Dash: speed", 8.0, 35.0, 0.5],
	["dash_time", "Dash: length (seconds)", 0.1, 0.6, 0.01],
	["dash_carry", "Dash: momentum kept after", 0.0, 1.0, 0.05],
	["dash_ground_drag", "Dash: momentum fade on ground", 0.0, 40.0, 0.5],
	["dash_air_drag", "Dash: momentum fade in air", 0.0, 40.0, 0.5],
	["dash_turn_loss", "Dash: momentum lost in a slow 180", 0.0, 1.0, 0.05],
	["dash_sharp_turn", "Dash: turn speed that kills it (deg/s)", 60.0, 1080.0, 10.0],
]


func _ready() -> void:
	add_to_group("main_game")   # (projectiles report demon hits here)
	_build_fps_label()
	if DisplayServer.get_name() != "headless":
		Taunts.warm_up()   # (synthesized in the background, so the first taunt doesn't stall the game)
		PropAnimSounds.warm_up()
		FxWarmup.sounds()   # (stomp, Hellfire and Vacuum Orb sounds: Ted, Nov 26, near 1 s freezes)
	var numbers := Updater.version_numbers(game_version)
	while numbers.size() < 3:   # "dev" has no numbers and "0.4" has two: the rest count as 0
		numbers.append(0)
	game_build = numbers[0] * 10000 + numbers[1] * 100 + numbers[2]
	rng.randomize()
	_setup_input()
	graphics = Graphics.new()
	add_child(graphics)
	music = Music.new()
	add_child(music)
	Projectile.prop_hit = _on_blessing_hit_prop
	load_map(MapData.load_file(MapData.BUILT_IN[0]), MapData.BUILT_IN[0])
	_build_hud()
	_build_sounds()
	player = Player.new()
	player.role = role
	add_child(player)
	player.threw.connect(func(kind): _play("throw_" + kind))
	player.form_changed.connect(func(): _play("possess"))
	player.form_changed.connect(_animate_hint)
	player.animate_pressed.connect(_on_animate)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.taunted.connect(_on_taunted)
	player.bounced.connect(func(): _play("bounce"))
	player.scared.connect(func(): _toast("FEAR! You run for your life!", Skills.fear_time()))
	player.powerup_taken.connect(func(kind):
		_play("powerup")
		_toast(PowerUps.LABELS.get(kind, kind) + "!", 1.5))
	player.hatred_bonus.connect(func(amount, reason):
		bonus_label.text = "+%d Hatred: %s" % [int(round(amount)), reason]
		_bonus_time = 2.5)
	player.launched.connect(_on_player_launched)
	player.bumped.connect(_on_player_bumped)
	player.no_room.connect(func(): _toast("No room to change here!", 1.5))
	player.cant_possess.connect(func(): _toast("That one can't be possessed. You can still copy it!", 2.0))
	player.hit_taken.connect(_on_player_hit_taken)
	player.skill_used.connect(_on_player_skill)
	player.pick_minion_form = random_map_prop_type
	powerups = PowerUps.new()
	powerups.main = self
	add_child(powerups)
	player.melee_used.connect(_on_player_melee)
	player.released_possessed.connect(_on_player_released)
	_build_tuning_panel()
	_build_menu()
	_build_pause_menu()
	_build_controls()
	_build_lobby()
	_build_wardrobe()
	_build_shrine_panel()
	get_viewport().size_changed.connect(_fit_panels)
	_build_chat()
	_build_lobby_chat()
	_load_settings()
	_show_menu("")
	_handle_command_line()
	updater = Updater.new()
	add_child(updater)
	updater.changed.connect(_refresh_update_row)
	updater.check(game_version)


# ---------- input ----------

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	Keybinds.setup({})   # defaults now; saved choices are applied when settings load


func _unhandled_input(event: InputEvent) -> void:
	if mode == "editor":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and controls_panel.visible:
			_close_controls()
			get_viewport().set_input_as_handled()
		return   # Creative handles its own keys
	if mode == "menu":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and controls_panel.visible:
			_close_controls()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and wardrobe.visible:
			_close_wardrobe()
		return
	if chat_edit.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if mode == "online" and not _any_panel_open() and (event.is_action_pressed("chat_all") or event.is_action_pressed("chat_team")):
		_open_chat(event.is_action_pressed("chat_team"))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("shrine") and not _any_panel_open():
		_try_open_shrine()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and shrine_panel.visible:
		_close_shrine()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and controls_panel.visible:
		_close_controls()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and rules_panel != null and rules_panel.visible:
		_close_rules()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		pause_panel.visible = not pause_panel.visible
		# (a test round from Creative: a way back to building, offline or as the host online)
		_back_to_editor.visible = (mode == "practice" and editor != null and editor.testing) 				or (mode == "online" and net != null and net.is_host and net.test_round)
		_switch_side.visible = mode == "practice"
		_switch_side.text = "Switch to the %s" % ("demons" if role == "angel" else "angels")
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
func _any_panel_open() -> bool:
	return menu_panel.visible or pause_panel.visible or tuning_panel.visible or lobby_panel.visible \
			or (rules_panel != null and rules_panel.visible) or (_solo_popup != null and _solo_popup.visible) \
			or shrine_panel.visible or chat_edit.visible or (controls_panel != null and controls_panel.visible) \
			or (wardrobe != null and wardrobe.visible)


func _tick_waiting_game() -> void:
	if waiting_game == null:
		return
	var on: bool = blind_rect.visible and state == State.HIDING and not (editor != null and editor.testing)
	if on != _blind_was:
		_blind_was = on
		if on:
			waiting_game.start(time_left)
		else:
			var old_best: int = waiting_game.best
			waiting_game.stop()
			if waiting_game.best > old_best:
				_save_settings()   # (a new Whack-an-Imp best, kept between games)
			# how it went, against the record (Ted, Nov 26)
			var got: int = waiting_game.score
			if got > 0:
				if got > old_best and old_best > 0:
					_toast("Whack-an-Imp: %d bonks. NEW RECORD! (beat %d)" % [got, old_best], 4.0)
				elif old_best > 0:
					_toast("Whack-an-Imp: %d bonks (your record: %d)" % [got, old_best], 4.0)
				else:
					_toast("Whack-an-Imp: %d bonks. That's your record to beat!" % got, 4.0)
		_refresh_mouse()
	elif on:
		waiting_game.set_seconds_left(time_left)


func _refresh_mouse() -> void:
	if mode == "editor":
		player.input_enabled = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var ui_open := _any_panel_open()
	player.input_enabled = not ui_open
	if _blind_was:
		ui_open = true   # (Whack-an-Imp: the mouse is free while we wait to hunt)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui_open else Input.MOUSE_MODE_CAPTURED


# ---------- the shrine (swap skills mid-round) ----------
# Stand at the shrine and press G. Picking takes as long as you like, but the
# whole swap takes at least 3 seconds from pressing G: pick fast and you wait out
# the rest, take longer and it applies as soon as you confirm. You can't move
# while you're at it, demons have to leave their prop first, and the shrine
# flares up so everyone knows someone is there.

func _build_shrine_panel() -> void:
	var parts := _panel(420)
	shrine_panel = parts[0]
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Shrine: swap your skills and look"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	for slot in 2:
		var ob := OptionButton.new()
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(i): _on_shrine_pick(slot, ob.get_item_metadata(i)))
		row.add_child(ob)
		_shrine_buttons.append(ob)
	_shrine_look = OptionButton.new()
	_shrine_look.tooltip_text = "Put on one of the looks you saved in the Wardrobe (or a matching set)"
	box.add_child(_shrine_look)
	_shrine_status = Label.new()
	box.add_child(_shrine_status)
	_button(box, "Done", _confirm_shrine)
	_button(box, "Cancel (Esc)", _close_shrine)
	shrine_panel.visible = false


func near_shrine(pos: Vector3) -> bool:
	return Vector2(pos.x - SHRINE_POS.x, pos.z - SHRINE_POS.z).length() <= Shrine.RADIUS and absf(pos.y - SHRINE_POS.y) < 2.0


# Angels waiting out the hiding period can swap skills anywhere, instantly, with no cooldowns (Ted, Nov 18).
func waiting_angel() -> bool:
	return state == State.HIDING and role == "angel"


func _try_open_shrine() -> void:
	if not (state == State.HIDING or state == State.HUNTING) or (player.frozen and not waiting_angel()):
		return
	if not near_shrine(player.global_position) and not waiting_angel():
		_toast("The shrine is the only place to swap skills.", 1.5)
		return
	if player.possessed_type != "":
		_toast("Leave your prop first (hold left click).", 1.5)
		return
	_shrine_pick = player.loadout[role].duplicate()
	var keys: Array = [Keybinds.key_name("skill_1"), Keybinds.key_name("rmb")]
	for slot in 2:
		var ob: OptionButton = _shrine_buttons[slot]
		ob.clear()
		ob.add_item("%s: none" % keys[slot])
		ob.set_item_metadata(0, "")
		for id in Skills.for_team(role):
			ob.add_item("%s: %s" % [keys[slot], Skills.label(id)])
			ob.set_item_metadata(ob.item_count - 1, id)
			ob.set_item_tooltip(ob.item_count - 1, Skills.SKILLS[id]["desc"])
			if id == _shrine_pick[slot]:
				ob.select(ob.item_count - 1)
	_shrine_look.clear()
	_shrine_look.add_item("Look: keep what I'm wearing")
	_shrine_look.set_item_metadata(0, null)
	for p in wardrobe_presets:
		if p.get("team") == role:
			_shrine_look.add_item("Look: " + str(p.get("name", "?")))
			_shrine_look.set_item_metadata(_shrine_look.item_count - 1, p.get("outfit", {}))
	for m in Characters.matching_sets(role):
		_shrine_look.add_item("Look: matching " + m[0])
		var dressed: Dictionary = Characters.clean_outfit(m[1], role)
		dressed["trail"] = outfits[role].get("trail", "")   # (a matching set dresses you; your colour stays)
		_shrine_look.set_item_metadata(_shrine_look.item_count - 1, dressed)
	_shrine_look.select(0)
	_shrine_elapsed = 0.0
	_shrine_done = false
	shrine_panel.visible = true
	player.velocity = Vector3.ZERO
	_refresh_mouse()
	if waiting_angel():
		_shrine_elapsed = Shrine.SWAP_TIME   # no waiting at the shrine: you're waiting anyway
	elif mode == "practice":
		if shrine:
			shrine.flare()
	elif net:
		net.shrine_open()


func _on_shrine_pick(slot: int, id: String) -> void:
	if id != "" and id in _shrine_pick:
		_shrine_pick[_shrine_pick.find(id)] = ""
	_shrine_pick[slot] = id
	for s2 in 2:   # keep both buttons showing the real picks
		var ob: OptionButton = _shrine_buttons[s2]
		for i in ob.item_count:
			if ob.get_item_metadata(i) == _shrine_pick[s2]:
				ob.select(i)


func _confirm_shrine() -> void:
	_shrine_done = true


func _close_shrine() -> void:
	_shrine_done = false
	shrine_panel.visible = false
	_refresh_mouse()


func _update_shrine(delta: float) -> void:
	if not shrine_panel.visible:
		return
	_shrine_elapsed += delta
	var waiting := waiting_angel()
	if not (state == State.HIDING or state == State.HUNTING) or (player.frozen and not waiting) or player.possessed_type != "":
		_close_shrine()
		return
	var left := Shrine.SWAP_TIME - _shrine_elapsed
	if _shrine_done and left <= 0.0:
		loadout[role] = Skills.clean_loadout(role, _shrine_pick)
		player.loadout = loadout.duplicate(true)
		player.skill_cd.clear()   # a swap refreshes every cooldown, new skills and old (Ted, Nov 20)
		_sync_loadout_buttons()
		_save_settings()
		if net:
			net.shrine_swap(loadout[role])
		var look = _shrine_look.get_item_metadata(_shrine_look.selected) if _shrine_look.selected >= 0 else null
		var new_look := look is Dictionary
		if new_look:
			var o := outfits.duplicate(true)
			o[role] = look
			set_outfits(o)   # (and tells everyone, like the wardrobe does)
			_save_settings()
		_close_shrine()
		_toast("Skills and look swapped!" if new_look else "Skills swapped!", 1.2)
		return
	if _shrine_done:
		_shrine_status.text = "Swapping... %.1f s" % left
	elif left > 0.0:
		_shrine_status.text = "Pick your skills (the swap takes %.1f s more)" % left
	else:
		_shrine_status.text = "Pick your skills, then Done"


# ---------- chat ----------
# Enter: everyone. Backspace: your team only. Enter sends, Esc cancels.

func _build_chat() -> void:
	chat_box = VBoxContainer.new()
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_box.position += Vector2(16, -190)
	chat_box.custom_minimum_size.x = 520
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(chat_box)
	chat_edit = LineEdit.new()
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_edit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_edit.position += Vector2(16, -150)
	chat_edit.custom_minimum_size.x = 520
	chat_edit.max_length = 120
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_send_chat)
	hud_layer.add_child(chat_edit)


# The lobby's chat (Ted, Nov 18): everything said, and a box to type in, while you wait for a round.
func _build_lobby_chat() -> void:
	lobby_chat = PanelContainer.new()
	lobby_chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lobby_chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lobby_chat.position += Vector2(16, -16)
	hud_layer.add_child(lobby_chat)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	lobby_chat.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Chat"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_lobby_chat_scroll = ScrollContainer.new()
	_lobby_chat_scroll.custom_minimum_size = Vector2(440, 260)
	_lobby_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_lobby_chat_scroll)
	_lobby_chat_log = VBoxContainer.new()
	_lobby_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_chat_scroll.add_child(_lobby_chat_log)
	_lobby_chat_edit = LineEdit.new()
	_lobby_chat_edit.placeholder_text = "Say something to everyone (Enter sends)"
	_lobby_chat_edit.max_length = 120
	_lobby_chat_edit.text_submitted.connect(func(text: String):
		text = text.strip_edges()
		_lobby_chat_edit.text = ""
		if text != "" and net:
			net.send_chat(text, false))
	box.add_child(_lobby_chat_edit)
	lobby_chat.visible = false


func _lobby_chat_line(text: String, color: Color) -> void:
	if _lobby_chat_log == null:
		return
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	l.add_theme_font_size_override("font_size", chat_font_size)
	l.add_theme_color_override("font_color", color)
	_lobby_chat_log.add_child(l)
	while _lobby_chat_log.get_child_count() > 60:
		_lobby_chat_log.get_child(0).free()
	await get_tree().process_frame
	_lobby_chat_scroll.scroll_vertical = int(_lobby_chat_scroll.get_v_scroll_bar().max_value)


# Settings: chat text size. Changes the lines already showing too.
func _set_chat_size(size: int) -> void:
	chat_font_size = size
	for n in chat_box.get_children():
		(n as Label).add_theme_font_size_override("font_size", size)
	if _lobby_chat_log:
		for n in _lobby_chat_log.get_children():
			(n as Label).add_theme_font_size_override("font_size", size)
	chat_edit.add_theme_font_size_override("font_size", size)
	if _lobby_chat_edit:
		_lobby_chat_edit.add_theme_font_size_override("font_size", size)


func _open_chat(team_only: bool) -> void:
	chat_team_only = team_only
	chat_edit.placeholder_text = ("Team chat (%ss only)" % role) if team_only else "Chat to everyone"
	chat_edit.text = ""
	chat_edit.visible = true
	_refresh_mouse()
	chat_edit.call_deferred("grab_focus")
	for entry in _chat_lines:
		entry[1] = maxf(entry[1], 8.0)   # show recent lines while typing


func _close_chat() -> void:
	chat_edit.release_focus()
	chat_edit.visible = false
	_refresh_mouse()


func _send_chat(text: String) -> void:
	text = text.strip_edges()
	_close_chat()
	if text == "":
		return
	# Host only: "/kick Name" removes someone mid-round.
	if text.begins_with("/kick ") and net and net.is_host:
		net.kick_by_name(text.trim_prefix("/kick ").strip_edges(), "The host kicked you.")
		return
	if net:
		net.send_chat(text, chat_team_only)


# Big news for everyone (who redeemed whom): shown in gold in the chat area.
func announce(text: String) -> void:
	var lbl := _make_label(chat_font_size + 2)
	lbl.text = "*** %s ***" % text
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	chat_box.add_child(lbl)
	print("[news] " + text)
	_chat_lines.append([lbl, 8.0])
	while _chat_lines.size() > 8:
		_chat_lines[0][0].queue_free()
		_chat_lines.pop_front()


# Called by the network for every chat line we're allowed to see.
func show_chat(sender: String, sender_role: String, text: String, team_only: bool) -> void:
	var lbl := _make_label(chat_font_size)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 520
	lbl.text = "%s %s: %s" % ["(Team Only)" if team_only else "(All)", sender, text]
	var color := Color(1, 1, 1)
	if sender_role == "angel":
		color = Color(1.0, 0.92, 0.6)
	elif sender_role == "demon":
		color = Color(1.0, 0.55, 0.5)
	lbl.add_theme_color_override("font_color", color)
	chat_box.add_child(lbl)
	_lobby_chat_line(lbl.text, color)
	print("[chat] " + lbl.text)
	_chat_lines.append([lbl, 12.0])
	while _chat_lines.size() > 8:
		_chat_lines[0][0].queue_free()
		_chat_lines.pop_front()


func _update_chat(delta: float) -> void:
	if lobby_chat:
		lobby_chat.visible = lobby_panel.visible and mode == "online"
		chat_box.visible = not lobby_chat.visible   # (the lobby shows its own)
	for entry in _chat_lines:
		if not chat_edit.visible:
			entry[1] -= delta
		entry[0].modulate.a = clampf(entry[1], 0.0, 1.0)


# ---------- world ----------

func _add_block(center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO, keep_clear := true, cylinder := false, surface := "stone") -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if cylinder:
		# size.x = width, size.y = height (the z size is ignored: it's round)
		var cs := CylinderShape3D.new()
		cs.radius = size.x / 2.0
		cs.height = size.y
		shape_node.shape = cs
		var cm := CylinderMesh.new()
		cm.top_radius = size.x / 2.0
		cm.bottom_radius = size.x / 2.0
		cm.height = size.y
		mi.mesh = cm
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape_node.shape = box
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
	body.add_child(shape_node)
	mi.material_override = PropLib.mat(color, surface)
	body.add_child(mi)
	body.position = center
	body.rotation = rot
	world_root.add_child(body)
	if keep_clear:
		structures.append([Vector2(center.x, center.z), maxf(size.x, size.z) / 2.0 + 1.0])
	return body


# Host lobby: built-in maps and the player's own, with the current one selected.
func refresh_map_list() -> void:
	_map_pick.clear()
	for entry in MapData.list_maps():
		_map_pick.add_item(entry["name"] + ("" if entry["built_in"] else ("  (shared)" if entry.get("shared", false) else "  (yours)")))
		_map_pick.set_item_metadata(_map_pick.item_count - 1, entry["path"])
		if entry["path"] == map_path:
			_map_pick.select(_map_pick.item_count - 1)


# Use a map: remember its layout and build it.
func load_map(map: Dictionary, path := "") -> void:
	map_data = MapData.clean(map)
	map_path = path
	MAP_HALF = map_data["size"]
	CEILING = map_data["ceiling"]
	PROP_COUNT = map_data["random_props"]
	SHRINE_POS = Vector3(0, -1000, 0)
	BOUNCIES = []
	ONE_USE_BOUNCIES = []
	ONE_USE_LOOKS = []
	SUPER_BOUNCIES = []
	PLACED_PROPS = []
	for p in map_data["pieces"]:
		var pos := MapData.vec(p["pos"])
		match p["type"]:
			"angel_spawn": ANGEL_SPAWN = pos
			"demon_spawn": DEMON_SPAWN = pos
			"shrine": SHRINE_POS = pos
			"bouncy": BOUNCIES.append(pos)
			"bouncy_once":
				ONE_USE_BOUNCIES.append(pos)
				ONE_USE_LOOKS.append(int(p.get("look", 0)))
			"bouncy_super": SUPER_BOUNCIES.append(pos)
			"prop": PLACED_PROPS.append([PropLib.with_fixed(PropLib.with_state(PropLib.scaled(p["prop"], p.get("scale", 1.0)), int(p.get("state", 0))),
					bool(p.get("fixed", false))), pos, MapData.rot_rad(p), bool(p.get("no_possess", false))])
	Models.festive = map_data["weather"] == "snow"   # (before building: trees and buildings get lights)
	_build_map()
	graphics.set_time_of_day(map_data["time"])
	graphics.set_weather(map_data["weather"])
	graphics.set_day_cycle(map_data["cycle"])


# Rain leaves about ten puddles about the place (Wife's notes, Nov 21), in the same spots on every screen
# (from the map's name), not on top of anything placed on the map. Rings ripple on them.
const PUDDLE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = UV - 0.5;
	float ang = atan(p.y, p.x);
	float edge = 0.42 + 0.05 * sin(ang * 3.0 + 1.3) + 0.03 * sin(ang * 7.0);
	float inside = 1.0 - smoothstep(edge - 0.06, edge, length(p));
	// raindrop rings
	float ring = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float t = fract(TIME * 0.7 + h(vec2(fi, 3.0)));
		vec2 c = vec2(h(vec2(fi, floor(TIME * 0.7 + h(vec2(fi, 3.0))))), h(vec2(fi + 9.0, floor(TIME * 0.7 + h(vec2(fi, 3.0)))))) * 0.5 - 0.25;
		float d = length(p - c);
		ring += smoothstep(0.012, 0.0, abs(d - t * 0.2)) * (1.0 - t);
	}
	ALBEDO = vec3(0.07, 0.08, 0.1) + ring * 0.15;
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	METALLIC = 0.1;
	ALPHA = inside * 0.85;
}
"""


func _add_puddles(half: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(map_data.get("name", "")) + "puddles")
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PUDDLE_SHADER
	mat.shader = sh
	var placed := 0
	for attempt in 80:
		if placed >= 10:
			break
		var at := Vector3(rng.randf_range(-half * 0.85, half * 0.85), 0.0, rng.randf_range(-half * 0.85, half * 0.85))
		var r := rng.randf_range(0.8, 1.8)
		var clear := true
		for p in map_data["pieces"]:
			var pp := MapData.vec(p["pos"])
			var reach := 2.0
			if p.has("size"):
				var sz := MapData.vec(p["size"])
				reach = maxf(sz.x, sz.z) * (Models.size(p["model"]).length() * 0.5 if p["type"] == "model" else 0.6)
			if Vector2(pp.x - at.x, pp.z - at.z).length() < reach + r:
				clear = false
				break
		if not clear:
			continue
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(r * 2.0, r * 2.0 * rng.randf_range(0.6, 1.0))
		mi.mesh = pm
		mi.material_override = mat
		mi.position = at + Vector3(0, 0.012, 0)
		mi.rotation.y = rng.randf_range(0.0, TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(mi)
		placed += 1


func _build_map() -> void:
	if world_root:
		world_root.free()
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	structures.clear()
	shrine = null
	var half: float = MAP_HALF
	# Ground and boundary walls
	var ground := Color(map_data["ground_color"])
	if map_data["weather"] == "snow":
		ground = ground.lerp(Color(0.92, 0.94, 0.98), 0.75)   # snow on the ground
	_add_block(Vector3(0, -0.5, 0), Vector3(half * 2 + 2, 1, half * 2 + 2), ground, Vector3.ZERO, false, false, "ground")
	if map_data["weather"] == "rain":
		_add_puddles(half)
	if map_data["weather"] == "snow":
		var tracks := SnowTracks.new()   # footprints and melted patches in the snow
		world_root.add_child(tracks)
		tracks.setup(half)
	world_root.add_child(SlimeTrail.new())   # (pickles leave a fading slime trail)
	var wall_color := Color(map_data["wall_color"])
	var span := half * 2 + 2
	_add_block(Vector3(0, 2, half + 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(0, 2, -half - 1), Vector3(span, 4, 1), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(half + 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	_add_block(Vector3(-half - 1, 2, 0), Vector3(1, 4, span), wall_color, Vector3.ZERO, false)
	# Invisible walls above the visible ones, and a ceiling, so flying demons
	# (and dashing angels) can't leave the map.
	var wall_h: float = CEILING + 2.0
	_add_invisible(Vector3(0, wall_h / 2.0 + 4.0, half + 1), Vector3(span, wall_h, 1))
	_add_invisible(Vector3(0, wall_h / 2.0 + 4.0, -half - 1), Vector3(span, wall_h, 1))
	_add_invisible(Vector3(half + 1, wall_h / 2.0 + 4.0, 0), Vector3(1, wall_h, span))
	_add_invisible(Vector3(-half - 1, wall_h / 2.0 + 4.0, 0), Vector3(1, wall_h, span))
	_add_invisible(Vector3(0, CEILING + 0.5, 0), Vector3(span, 1, span))
	# Scenery past the walls (hills, the sea, mountains, a city)
	world_root.add_child(Backdrop.make(map_data["backdrop"], half, str(map_data.get("name", ""))))
	# The map's own pieces
	var permanent_bouncies := 0
	for p in map_data["pieces"]:
		var pos := MapData.vec(p["pos"])
		match p["type"]:
			"block", "cylinder":
				_add_block(pos, MapData.vec(p["size"]), Color(p["color"]), MapData.rot_rad(p), true, p["type"] == "cylinder")
			"shrine":
				# The shrine: the only place to swap skills mid-round
				shrine = Shrine.new()
				world_root.add_child(shrine)
				shrine.position = pos
				structures.append([Vector2(pos.x, pos.z), 3.0])
			"bouncy", "bouncy_super":
				var b := Bouncy.new()
				b.bouncy_id = 1000 + permanent_bouncies
				b.super_bouncy = p["type"] == "bouncy_super"
				b.skin = int(p.get("look", 0))
				permanent_bouncies += 1
				world_root.add_child(b)
				b.position = pos
				structures.append([Vector2(pos.x, pos.z), 1.6])
			"bouncy_once", "prop":
				structures.append([Vector2(pos.x, pos.z), 1.6])   # (made fresh each round)
			"ground":
				var gb := GroundBlock.make(GroundBlock.KINDS.keys()[int(p.get("look", 0))], MapData.vec(p["size"]), Color(p.get("color", "#ffffff")))
				gb.position = pos
				gb.rotation = MapData.rot_rad(p)
				world_root.add_child(gb)
			"building":
				var hb := HollowBuildings.make(p["kind"], int(p.get("look", 0)))
				hb.position = pos
				hb.rotation = MapData.rot_rad(p)
				var bscale: Vector3 = MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
				hb.scale = bscale
				world_root.add_child(hb)
				var hs := HollowBuildings.size(p["kind"]) * bscale
				structures.append([Vector2(pos.x, pos.z), maxf(hs.x, hs.z) * 0.5])
			"sidewalk":
				var walk := Decor.make_sidewalk(p)
				walk.position = pos
				walk.rotation = MapData.rot_rad(p)
				world_root.add_child(walk)
			"window":
				var pane := Decor.make_window(p)
				pane.position = pos
				pane.rotation = MapData.rot_rad(p)
				world_root.add_child(pane)
			"ice":
				var ice := make_ice(p)
				ice.position = pos
				ice.rotation = MapData.rot_rad(p)
				world_root.add_child(ice)
			"light":
				var lamp := make_lamp(p, pos, false)   # (the bulb only shows in Creative)
				lamp.rotation = MapData.rot_rad(p)
				world_root.add_child(lamp)
			"model":
				# A structure from the model catalog: solid in its real shape (doorways, stairs, arches)
				var sc: Vector3 = MapData.vec(p["size"]) if p.has("size") else Vector3.ONE
				var body := Models.make_row(p["model"], sc, int(p.get("repeat", 1)), int(p.get("repeat2", 1)), int(p.get("look", 0)),
						not p.has("color"), MapData.rot_rad(p).y)   # (long rows drawn as one batch: Models._batched_row)
				if p.has("color"):
					if Models.is_rug(p["model"]):
						Models.recolor(body, Color(p["color"]))   # a rug in its chosen colour
					else:
						Models.tint(body, Color(p["color"]), int(p.get("look", 0)))
				if p.get("lights", false):
					body.add_child(Models.car_lights(p["model"], sc))
				body.position = pos
				body.rotation = MapData.rot_rad(p)
				world_root.add_child(body)
				var sz := Models.size(p["model"]) * sc
				var rb := Basis.from_euler(MapData.rot_rad(p))
				var step := rb * Models.row_step(p["model"], sc)
				var step2 := rb * Models.row_step2(p["model"], sc)
				for k2 in int(p.get("repeat2", 1)):
					for k in int(p.get("repeat", 1)):
						var at := pos + step * k + step2 * k2
						structures.append([Vector2(at.x, at.z), maxf(sz.x, sz.z) / 2.0 + 1.0])


const CHERUB_PAD_SIDEWAYS := 3.0  # m/s a cherub at least drifts off a bouncy pad (first guess)
const DASH_TRAIL := 4.5          # length of the sparkle trail others see behind a dash
const WORLD_LAYER := 1         # everything real you can see and hit
const BOUNDS_LAYER := 2        # invisible map walls and ceiling
var CEILING := 24.0


# A sheet of ice: glassy pale blue, solid to stand on, and in the "ice" group, which makes it
# slippery (player.gd).
static func make_ice(p: Dictionary) -> StaticBody3D:
	var sz := MapData.vec(p.get("size", [4, 0.06, 4]))
	var body := StaticBody3D.new()
	body.add_to_group("ice")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.9, 1.0, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.roughness = 0.04
	m.clearcoat_enabled = true
	m.rim_enabled = true
	m.rim = 0.4
	mi.material_override = m
	body.add_child(mi)
	return body


# A placed light: the light itself (no shadows: lots of them stay cheap), plus, in Creative only, a
# little glowing bulb to grab it by (and a cone showing which way a spotlight points).
# (In a round, the lamp follows the daylight unless it's "always" on, and may flicker. In Creative,
# show_bulb, it's always on so you can see what you're doing, but it shows its flicker.)
static func make_lamp(p: Dictionary, pos: Vector3, show_bulb := true) -> Node3D:
	var n := Lamp.new()
	n.position = pos
	var c := Color(p.get("color", "#ffd9a0"))
	var light: Light3D
	if p.get("spot", false):
		var sl := SpotLight3D.new()
		sl.light_energy = float(p.get("energy", 1.5)) * 2.0
		sl.spot_range = float(p.get("range", 8.0))
		sl.spot_angle = float(p.get("angle", 35.0))
		light = sl
	else:
		var l := OmniLight3D.new()
		l.light_energy = float(p.get("energy", 1.5))
		l.omni_range = float(p.get("range", 8.0))
		light = l
	light.light_color = c
	n.setup(light, not show_bulb and not p.get("always", false), float(p.get("flicker", 0.0)))
	if not show_bulb:
		return n
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 12   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
	sm.rings = 6
	sm.radius = 0.12
	sm.height = 0.24
	bulb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.material_override = m
	n.add_child(bulb)
	if p.get("spot", false):
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.18
		cm.height = 0.4
		cone.mesh = cm
		cone.material_override = m
		cone.rotation.x = PI / 2   # pointing the way the light shines (-Z)
		cone.position.z = -0.25
		n.add_child(cone)
	return n


# Standing on (or right by) a bouncy pad? The host uses it to excuse the long airtime of a bounce.
func near_pad(pos: Vector3) -> bool:
	for list in [BOUNCIES, ONE_USE_BOUNCIES, SUPER_BOUNCIES]:
		for b in list:
			if Vector2(pos.x - b.x, pos.z - b.z).length() < 2.5 and absf(pos.y - b.y) < 2.5:
				return true
	return false


func _add_invisible(center: Vector3, size: Vector3) -> void:
	_add_invisible_to(world_root, center, size)


func _add_invisible_to(parent: Node, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = center
	# Its own layer: it stops bodies (players, cherubs) but aim rays and
	# throws go right through.
	body.collision_layer = BOUNDS_LAYER
	body.collision_mask = 0
	parent.add_child(body)


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
			return Vector3(p.x, ground_height(p), p.y)
	return Vector3.ZERO


# How high the floor is here: on top of any ground block or sidewalk placed on the map (Wife's notes, Nov 26:
# random props were buried in the gravel). Worked out from the map itself, so every screen agrees.
func ground_height(at: Vector2) -> float:
	var top := 0.0
	for p in map_data["pieces"]:
		if not p["type"] in ["ground", "sidewalk"]:
			continue
		var sz := MapData.vec(p["size"]) if p.has("size") else Vector3(2.0, 0.18, 6.0)
		var xf := Transform3D(Basis.from_euler(MapData.rot_rad(p)), MapData.vec(p["pos"]))
		var local := xf.affine_inverse() * Vector3(at.x, 0.0, at.y)
		var up := xf.basis * Vector3.UP
		if up.y < 0.9:
			continue   # (tipped over on its side: no flat top to stand on)
		if absf(local.x) > sz.x * 0.5 - 0.3 or absf(local.z) > sz.z * 0.5 - 0.3:
			continue
		var top_pt := xf * Vector3(local.x, sz.y, local.z)
		top = maxf(top, top_pt.y)
	return top


func _spawn_prop(type_name: String, pos: Vector3, rot = null) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("prop")
	body.set_meta("prop_type", type_name)
	body.add_child(PropLib.make_visual(type_name))
	var shape_node := CollisionShape3D.new()
	shape_node.shape = PropLib.make_shape(type_name)
	shape_node.position.y = PropLib.height(type_name) / 2.0
	body.add_child(shape_node)
	body.position = pos
	if rot == null:
		body.rotation.y = rng.randf_range(0, TAU)
	else:
		body.rotation = rot
	body.set_meta("prop_index", props.size())
	props.append(body)
	round_root.add_child(body)


# Fresh props for a round. The same seed gives the same layout on every computer,
# which is how everyone in an online match sees an identical map.
# The hunt's music: one of these each round, from the round's seed (so everyone online hears the same).
const ROUND_THEMES := ["hunt", "shuffle", "tango", "bones"]
const Characters = preload("res://scripts/characters.gd")
# What we look like (the wardrobe): an outfit for each team, saved in settings.
var outfits := {"angel": Characters.default_outfit("angel"), "demon": Characters.default_outfit("demon")}


const Wardrobe = preload("res://scripts/wardrobe.gd")
var wardrobe: PanelContainer
var wardrobe_presets := []       # saved outfits: [{"name", "team", "outfit"}]
var _wardrobe_hid: Control


func _build_wardrobe() -> void:
	wardrobe = Wardrobe.new()
	wardrobe.main = self
	wardrobe.visible = false
	wardrobe.on_done = _close_wardrobe
	hud_layer.add_child(wardrobe)


func _open_wardrobe() -> void:
	_wardrobe_hid = menu_panel if menu_panel.visible else (lobby_panel if lobby_panel.visible else (pause_panel if pause_panel.visible else null))
	if _wardrobe_hid:
		_wardrobe_hid.visible = false
	wardrobe.open(outfits, wardrobe_presets)
	_refresh_mouse()


func _close_wardrobe() -> void:
	wardrobe.visible = false
	if _wardrobe_hid and _still_wanted(_wardrobe_hid):
		_wardrobe_hid.visible = true
		_wardrobe_hid = null
	_save_settings()
	_refresh_mouse()


func set_outfits(o: Dictionary) -> void:
	outfits = {"angel": Characters.clean_outfit(o.get("angel"), "angel"), "demon": Characters.clean_outfit(o.get("demon"), "demon")}
	player.outfits = outfits
	if player.possessed_type == "" and player.visual_root.visible:
		player._apply_form()
	if net:
		net.send_outfits(outfits)
var round_theme := "hunt"


func _reset_round_props(seed_value: int) -> void:
	round_theme = ROUND_THEMES[absi(seed_value) % ROUND_THEMES.size()]
	if round_root:
		round_root.free()
	round_root = Node3D.new()
	add_child(round_root)
	used_spots.clear()
	props.clear()
	cherubs.clear()
	powerups.reset()
	_auth_cherubs.clear()
	_auth_fires.clear()
	fires.clear()
	_possessions.clear()
	rng.seed = seed_value
	bouncies.clear()
	for i in ONE_USE_BOUNCIES.size():
		var b := Bouncy.new()
		b.bouncy_id = i
		b.one_use = true
		b.on_used = _on_bouncy_used
		round_root.add_child(b)
		b.position = ONE_USE_BOUNCIES[i]
		b.skin = ONE_USE_LOOKS[i] if i < ONE_USE_LOOKS.size() else 0
		bouncies[i] = b
	# Props placed by hand on the map, then the random ones.
	for pp in PLACED_PROPS:
		_spawn_prop(pp[0], pp[1], pp[2])
		if pp.size() > 3 and pp[3]:
			props[props.size() - 1].set_meta("no_possess", true)   # (Creative: copy it, but can't possess it)
	var types := PropLib.scatter_names()
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
	# It scrolls if it's taller than the screen (big text sizes).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(margin)
	_scroll_panels.append([scroll, margin])
	margin.minimum_size_changed.connect(_fit_panels.call_deferred)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = min_width
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return [panel, box]


# Size each panel to its contents, but no taller than the screen (then it scrolls).
func _fit_panels() -> void:
	var room := get_viewport().get_visible_rect().size.y - 24.0
	for e in _scroll_panels:
		var need: Vector2 = e[1].get_combined_minimum_size()
		var bar := 14.0 if need.y > room else 0.0
		e[0].custom_minimum_size = Vector2(need.x + bar, minf(need.y, room))
		var panel: Control = e[0].get_parent()
		panel.reset_size()
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)


func set_ui_scale(v: float, announce := false) -> void:
	ui_scale = clampf(v, UI_SCALES[0], UI_SCALES[-1])
	get_window().content_scale_factor = ui_scale
	if _ui_scale_pick:
		var best := 0
		for i in UI_SCALES.size():
			if absf(UI_SCALES[i] - ui_scale) < absf(UI_SCALES[best] - ui_scale):
				best = i
		_ui_scale_pick.select(best)
	_fit_panels.call_deferred()
	if announce:
		_toast("Text size %d%%
Ctrl +  /  Ctrl -  to change" % roundi(ui_scale * 100.0), 3.0)
		if menu_status and mode == "menu":
			menu_status.text = "Text size %d%%  (Ctrl + / Ctrl - to change)" % roundi(ui_scale * 100.0)


func _step_ui_scale(dir: int) -> void:
	var i := 0
	for k in UI_SCALES.size():
		if absf(UI_SCALES[k] - ui_scale) < absf(UI_SCALES[i] - ui_scale):
			i = k
	set_ui_scale(UI_SCALES[clampi(i + dir, 0, UI_SCALES.size() - 1)], true)
	_save_settings()


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
	version.text = "version %s" % game_version   # (the old "(Power-ups)" nickname was stale)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)
	# Hidden unless a newer version is out (see _refresh_update_row).
	update_button = _button(box, "", func(): updater.install())
	update_button.visible = false
	update_note = Label.new()
	update_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_note.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	update_note.visible = false
	box.add_child(update_note)
	name_edit = _field(box, "Your name", "Name")
	name_edit.text_changed.connect(func(_t): if _settings_loaded: _save_settings())   # (kept between games and updates)
	_build_loadout(box)
	_button(box, "Practice (single player)", start_practice)
	_button(box, "Game rules (gravity, damage, power-ups...)", _open_rules)
	_button(box, "Creative (build maps)", open_editor)
	_button(box, "Wardrobe (your angel and demon)", _open_wardrobe)
	box.add_child(HSeparator.new())
	_button(box, "Host a game", _on_host_relay_pressed)
	address_edit = _field(box, "Room code (or the host's address)", "e.g. KX4PZ")
	_button(box, "Join a game", _on_join_pressed)
	var direct := Label.new()
	direct.text = "Without the relay server (LAN, or a forwarded port):"
	direct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(direct)
	port_edit = _field(box, "Port", str(NetGame.DEFAULT_PORT))
	_button(box, "Host directly", _on_host_pressed)
	box.add_child(HSeparator.new())
	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 8)
	box.add_child(text_row)
	var tlab := Label.new()
	tlab.text = "Text size"
	tlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_row.add_child(tlab)
	for d in [[-1, "A -"], [1, "A +"]]:
		var tb := Button.new()
		tb.text = d[1]
		tb.custom_minimum_size = Vector2(70, 40)
		tb.add_theme_font_size_override("font_size", 22 if d[0] > 0 else 15)
		var dir: int = d[0]
		tb.pressed.connect(func(): _step_ui_scale(dir))
		text_row.add_child(tb)
	_button(box, "Settings & controls", _open_controls)
	_button(box, "Quit", func():
		_save_settings()
		get_tree().quit())
	menu_status = Label.new()
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	box.add_child(menu_status)


func _refresh_update_row() -> void:
	update_button.text = updater.button_text
	update_button.visible = updater.state != "idle"
	update_note.text = updater.note
	update_note.visible = updater.note != ""


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
	_back_to_editor = _button(box, "Back to Creative", back_to_editor)
	_back_to_editor.visible = false
	# (testing a map: try it from either side; Ted, Nov 26)
	_switch_side = _button(box, "Switch side", func():
		pause_panel.visible = false
		role = "demon" if role == "angel" else "angel"
		if editor != null:
			editor.test_role = role
		start_round()
		_refresh_mouse())
	_switch_side.visible = false
	_button(box, "Settings & controls", _open_controls)
	_leave_button = _button(box, "Leave to main menu", _try_leave)
	pause_panel.visible = false


# Online, leaving takes a second click (Nov 21: Esc out of a test round, one click on the wrong button and
# you'd left the whole game).
var _leave_button: Button
var _leave_armed := 0.0


func _try_leave() -> void:
	if mode == "online" and Time.get_ticks_msec() / 1000.0 > _leave_armed:
		_leave_armed = Time.get_ticks_msec() / 1000.0 + 4.0
		_leave_button.text = "Click again to leave the game"
		get_tree().create_timer(4.0).timeout.connect(func(): _leave_button.text = "Leave to main menu")
		return
	_show_menu("")


# ---- Controls: rebind any action to any key or mouse button ----
var controls_panel: PanelContainer
var _bind_buttons := {}        # action -> its Button
var _rebinding := ""           # action waiting for a key press
var _controls_note: Label


func _build_controls() -> void:
	var parts := _panel(560)
	controls_panel = parts[0]
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	solid.set_corner_radius_all(6)
	controls_panel.add_theme_stylebox_override("panel", solid)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Settings & controls"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_build_options(box)
	box.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Click a key, then press the key or mouse button you want. Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for a in Keybinds.ACTIONS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = a[1]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 34)
		var action: String = a[0]
		b.pressed.connect(func(): _start_rebind(action))
		row.add_child(b)
		rows.add_child(row)
		_bind_buttons[action] = b
	scroll.custom_minimum_size.y = 300
	_controls_note = Label.new()
	_controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_note.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	box.add_child(_controls_note)
	_settings_code_row = HBoxContainer.new()
	_settings_code_row.add_theme_constant_override("separation", 12)
	_settings_code_label = Label.new()
	_settings_code_label.add_theme_font_size_override("font_size", 22)
	_settings_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_code_row.add_child(_settings_code_label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.custom_minimum_size = Vector2(100, 36)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_room_code)
		_controls_note.text = "Room code copied: paste it into Discord.")
	_settings_code_row.add_child(copy)
	_settings_code_row.visible = false
	box.add_child(_settings_code_row)
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var reset := Button.new()
	reset.text = "Reset all to defaults"
	reset.custom_minimum_size.y = 40
	reset.pressed.connect(func():
		Keybinds.setup({})
		_controls_note.text = "Back to the default keys."
		_refresh_controls()
		_save_settings())
	bottom.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 40)
	done.pressed.connect(_close_controls)
	bottom.add_child(done)
	controls_panel.visible = false


# Music and sound volume, and graphics quality (top of the Settings & controls panel).
func _build_options(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	var tl := Label.new()
	tl.text = "Text size (everything)"
	tl.tooltip_text = "Makes all the menus and writing bigger. Ctrl + and Ctrl - change it anywhere, Ctrl 0 puts it back."
	grid.add_child(tl)
	_ui_scale_pick = OptionButton.new()
	for v in UI_SCALES:
		_ui_scale_pick.add_item("%d%%" % roundi(v * 100.0))
	_ui_scale_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_scale_pick.tooltip_text = tl.tooltip_text
	_ui_scale_pick.item_selected.connect(func(i): set_ui_scale(UI_SCALES[i]))
	grid.add_child(_ui_scale_pick)
	_music_slider = _volume_row(grid, "Music", func(v):
		_music_volume = v
		_apply_volumes())
	_sound_slider = _volume_row(grid, "Sound effects", func(v):
		_sound_volume = v
		_apply_volumes())
	var lbl := Label.new()
	lbl.text = "Graphics"
	grid.add_child(lbl)
	_quality_pick = OptionButton.new()
	for q in Graphics.QUALITY_NAMES:
		_quality_pick.add_item(q)
	_quality_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_pick.item_selected.connect(func(i): graphics.apply(i))
	grid.add_child(_quality_pick)
	var cl := Label.new()
	cl.text = "Chat text size"
	grid.add_child(cl)
	_chat_size_pick = SpinBox.new()
	_chat_size_pick.min_value = 12
	_chat_size_pick.max_value = 40
	_chat_size_pick.step = 1
	_chat_size_pick.value_changed.connect(func(v): _set_chat_size(int(v)))
	grid.add_child(_chat_size_pick)
	var fl := Label.new()
	fl.text = "Show FPS"
	fl.tooltip_text = "Frames per second in the top left corner, with how many triangles and draw calls each frame takes
(handy for spotting what slows the game down)."
	grid.add_child(fl)
	_fps_pick = CheckButton.new()
	_fps_pick.tooltip_text = fl.tooltip_text
	_fps_pick.toggled.connect(func(on): fps_label.visible = on)
	grid.add_child(_fps_pick)
	# A shared maps folder (Ted, Nov 25): pick a folder your cloud drive syncs with friends'
	var shl := Label.new()
	shl.text = "Shared maps folder"
	shl.tooltip_text = "A folder that OneDrive, Dropbox, Google Drive or similar keeps in sync with your friends.
Its maps show up next to yours, and Creative's \"Shared\" box saves there."
	grid.add_child(shl)
	var shrow := HBoxContainer.new()
	shrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shared_label = Label.new()
	_shared_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shared_label.clip_text = true
	_shared_label.tooltip_text = shl.tooltip_text
	shrow.add_child(_shared_label)
	var pick := Button.new()
	pick.text = "Choose..."
	pick.pressed.connect(_choose_shared_dir)
	shrow.add_child(pick)
	var clear := Button.new()
	clear.text = "None"
	clear.pressed.connect(func():
		_set_shared_dir("")
		_save_settings())
	shrow.add_child(clear)
	grid.add_child(shrow)
	_set_shared_dir(MapData.shared_dir)


var _shared_label: Label


func _set_shared_dir(dir: String) -> void:
	MapData.shared_dir = dir.strip_edges()
	if _shared_label:
		_shared_label.text = MapData.shared_dir if MapData.shared_dir != "" else "(none)"
		if MapData.shared_dir != "" and not MapData.has_shared():
			_shared_label.text += "  (not found)"
	if _map_pick:
		refresh_map_list()


func _choose_shared_dir() -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.title = "Pick the shared maps folder (one your cloud drive syncs)"
	fd.use_native_dialog = true
	if MapData.shared_dir != "":
		fd.current_dir = MapData.shared_dir
	fd.dir_selected.connect(func(d):
		_set_shared_dir(d)
		_save_settings()
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _volume_row(grid: GridContainer, text: String, on_change: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = text
	grid.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01   # (fine steps: the quiet end matters most)
	slider.custom_minimum_size.x = 260
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(on_change)
	grid.add_child(slider)
	return slider


var _controls_hid: Control     # the menu we hid while Controls is open


func _open_controls() -> void:
	_settings_code_row.visible = net != null and _room_code != ""
	_settings_code_label.text = "Room code:  %s" % _room_code
	_controls_hid = menu_panel if menu_panel.visible else (pause_panel if pause_panel.visible else (lobby_panel if lobby_panel.visible else null))
	if _controls_hid:
		_controls_hid.visible = false
	_rebinding = ""
	_controls_note.text = ""
	_refresh_controls()
	controls_panel.visible = true
	_refresh_mouse()


# Closing the wardrobe or settings goes back to the menu it was opened from, unless that menu has gone
# since (playtest, Nov 26: settings opened in the lobby, the round started, and closing settings brought
# the lobby back over the hunt, with the controls locked).
func _still_wanted(panel: Control) -> bool:
	if panel == lobby_panel:
		return state == State.LOBBY and mode == "online" and not building_online
	return true


func _close_controls() -> void:
	_rebinding = ""
	controls_panel.visible = false
	if mode == "editor" and editor != null and editor.active():
		editor.ui.visible = true
		hud_layer.visible = false
	if _controls_hid and _still_wanted(_controls_hid):
		_controls_hid.visible = true
		_controls_hid = null
	_save_settings()
	_refresh_mouse()


func _refresh_controls() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = "..." if action == _rebinding else Keybinds.key_name(action)


func _start_rebind(action: String) -> void:
	_rebinding = action
	_controls_note.text = ""
	_refresh_controls()


# While waiting for a key: the next key or mouse button becomes the binding.
func _input(event: InputEvent) -> void:
	# Ctrl + / Ctrl - / Ctrl 0: text size, anywhere (menus, rounds, Creative)
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed):
		var k: Key = event.physical_keycode
		if k in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			_step_ui_scale(1)
			get_viewport().set_input_as_handled()
			return
		if k in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_step_ui_scale(-1)
			get_viewport().set_input_as_handled()
			return
		if k in [KEY_0, KEY_KP_0]:
			set_ui_scale(1.0, true)
			_save_settings()
			get_viewport().set_input_as_handled()
			return
	if _rebinding == "" or not controls_panel.visible:
		return
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_rebinding = ""
		_refresh_controls()
		return
	var code := Keybinds.code_of(event)
	if code == "":
		return
	# Whatever else used that key gives it up (except the practice-only skip, which
	# shares Enter with chat on purpose).
	var moved_from := []
	for a in Keybinds.ACTIONS:
		if a[0] != _rebinding and Keybinds.current(a[0]) == code and not (a[0] in ["skip_hiding", "chat_all"] and _rebinding in ["skip_hiding", "chat_all"]):
			Keybinds.bind(a[0], "")
			moved_from.append(a[1])
	Keybinds.bind(_rebinding, code)
	_controls_note.text = ("%s was also on that key; it's now unbound." % ", ".join(moved_from)) if not moved_from.is_empty() else ""
	_rebinding = ""
	_refresh_controls()
	_save_settings()


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
	# Host only: how long the hiding and hunting phases last.
	lobby_map_label = Label.new()
	box.add_child(lobby_map_label)
	lobby_times = VBoxContainer.new()
	box.add_child(lobby_times)
	# Host: which map to play.
	var map_row := HBoxContainer.new()
	var map_lbl := Label.new()
	map_lbl.text = "Map"
	map_lbl.custom_minimum_size.x = 140
	map_row.add_child(map_lbl)
	_map_pick = OptionButton.new()
	_map_pick.custom_minimum_size.x = 260
	_map_pick.item_selected.connect(func(i):
		var path: String = _map_pick.get_item_metadata(i)
		var m := MapData.load_file(path)
		if not m.is_empty():
			load_map(m, path)
			if net and net.is_host:
				net.send_map_to_all())
	map_row.add_child(_map_pick)
	lobby_times.add_child(map_row)
	_time_choice(lobby_times, "Hiding time", HIDE_CHOICES, 1)
	_time_choice(lobby_times, "Hunting time", HUNT_CHOICES, 2)
	_time_choice(lobby_times, "Kick idle angels", IDLE_CHOICES, 0, func(i): if net: net.idle_limit = IDLE_CHOICES[i])
	var kick_row := HBoxContainer.new()
	lobby_times.add_child(kick_row)
	_kick_pick = OptionButton.new()
	_kick_pick.custom_minimum_size.x = 200
	kick_row.add_child(_kick_pick)
	var kick_btn := Button.new()
	kick_btn.text = "Kick"
	kick_btn.pressed.connect(func():
		if net and _kick_pick.selected >= 0:
			net.kick_by_name(_kick_pick.get_item_text(_kick_pick.selected), "The host kicked you."))
	kick_row.add_child(kick_btn)
	var rules_row := HBoxContainer.new()
	var rules_lbl := Label.new()
	rules_lbl.text = "Game rules"
	rules_lbl.custom_minimum_size.x = 140
	rules_row.add_child(rules_lbl)
	_rules_pick = OptionButton.new()
	_rules_pick.add_item("Standard")
	_rules_pick.add_item("Custom")
	_rules_pick.item_selected.connect(func(i):
		rules_use_custom = i == 1
		_sync_rules_ui()
		_save_settings())
	rules_row.add_child(_rules_pick)
	var rules_edit := Button.new()
	rules_edit.text = "Edit custom..."
	rules_edit.pressed.connect(_open_rules)
	rules_row.add_child(rules_edit)
	lobby_times.add_child(rules_row)
	_rules_summary = Label.new()
	_rules_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_summary.custom_minimum_size.x = 400
	_rules_summary.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	lobby_times.add_child(_rules_summary)
	_solo_row = HBoxContainer.new()
	var solo_lbl := Label.new()
	solo_lbl.text = "Play alone as"
	solo_lbl.custom_minimum_size.x = 140
	_solo_row.add_child(solo_lbl)
	_solo_pick = OptionButton.new()
	_solo_pick.add_item("Demon")
	_solo_pick.add_item("Angel")
	_solo_pick.item_selected.connect(func(i):
		if net:
			net.solo_role = "angel" if i == 1 else "demon")
	_solo_row.add_child(_solo_pick)
	lobby_times.add_child(_solo_row)
	lobby_start = _button(box, "Start round", func():
		if net:
			net.hide_time = HIDE_CHOICES[_time_pick["Hiding time"]]
			net.hunt_time = HUNT_CHOICES[_time_pick["Hunting time"]]
			net.start_round())
	lobby_build = _button(box, "Build together (Creative)", func():
		if net:
			net.start_building())
	lobby_build.tooltip_text = "Everyone goes into Creative on this map and builds it together."
	_button(box, "Wardrobe", _open_wardrobe)
	_button(box, "Settings & controls", _open_controls)
	_button(box, "Leave", func(): _show_menu(""))
	lobby_panel.visible = false


# ---------------- playing alone online ----------------
# Host, alone in a round, and someone joined: the round restarts with them when the countdown runs out,
# unless the host keeps it going (Ted, Nov 26).
func solo_join_prompt(who: String, seconds: float) -> void:
	if _solo_popup == null:
		var parts := _panel(380)
		_solo_popup = parts[0]
		var box: VBoxContainer = parts[1]
		_solo_label = Label.new()
		_solo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_solo_label.custom_minimum_size.x = 360
		box.add_child(_solo_label)
		_button(box, "Keep my round going (they join it)", func():
			_solo_popup.visible = false
			if net:
				net.solo_keep()
			_refresh_mouse())
		_button(box, "Restart now", func():
			_solo_popup.visible = false
			if net:
				net.solo_restart()
			_refresh_mouse())
	_solo_until = _now() + seconds
	_solo_popup.set_meta("who", who)
	_solo_popup.visible = true
	_solo_tick()
	_refresh_mouse()


func _solo_tick() -> void:
	if _solo_popup == null or not _solo_popup.visible:
		return
	var left := _solo_until - _now()
	if left <= 0.0 or net == null or not net.solo_round:
		_solo_popup.visible = false
		_refresh_mouse()
		if net and net.solo_round:
			net.solo_restart()
		return
	_solo_label.text = "%s joined! Restarting the round with them in %d..." % [_solo_popup.get_meta("who"), ceili(left)]
	get_tree().create_timer(0.25).timeout.connect(_solo_tick)


# ---------------- game rules ----------------

func active_rules() -> Dictionary:
	return GameRules.clean(rules_custom) if rules_use_custom else GameRules.standard()


func _sync_rules_ui() -> void:
	if _rules_pick:
		_rules_pick.select(1 if rules_use_custom else 0)
	if _rules_summary:
		_rules_summary.text = GameRules.summary(active_rules())
	for k in _rules_inputs:
		var w: Control = _rules_inputs[k]
		if w is SpinBox:
			(w as SpinBox).set_value_no_signal(rules_custom[k])
		elif w is OptionButton:
			(w as OptionButton).select(int(rules_custom[k]))
		elif w is CheckBox:
			(w as CheckBox).set_pressed_no_signal(rules_custom["powerups"][k])


func _open_rules() -> void:
	if rules_panel == null:
		_build_rules_panel()
	_sync_rules_ui()
	rules_panel.visible = true
	_refresh_mouse()


func _close_rules() -> void:
	rules_panel.visible = false
	_sync_rules_ui()
	_save_settings()
	_refresh_mouse()


# The Custom rules (Ted, Nov 26). Changing anything here switches the game to Custom.
# Nov 27: tabs (General, Demons, Angels, Skills, Power-ups), built from GameRules.RULES, each rule under its
# section heading, and a solid background (the menu behind showed through and made it hard to read).
func _build_rules_panel() -> void:
	var parts := _panel(560)
	rules_panel = parts[0]
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.07, 0.075, 0.11, 0.985)
	solid.border_color = Color(0.55, 0.5, 0.75, 0.9)
	solid.set_border_width_all(2)
	solid.set_corner_radius_all(10)
	solid.shadow_color = Color(0, 0, 0, 0.55)
	solid.shadow_size = 14
	rules_panel.add_theme_stylebox_override("panel", solid)
	var box: VBoxContainer = parts[1]
	var title := Label.new()
	title.text = "Custom game rules"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var note := Label.new()
	note.text = "Used when the rules are set to Custom (in the lobby, or for practice). Online, the host's rules count. " 			+ "Hover over a rule to see what it does. x1 is the game as standard."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 540
	box.add_child(note)
	var tabs := TabContainer.new()
	box.add_child(tabs)
	var pages := {}
	for t in GameRules.TABS:
		var page := VBoxContainer.new()
		page.name = t[1]
		page.add_theme_constant_override("separation", 6)
		tabs.add_child(page)
		pages[t[0]] = page
	# Power-ups first on their tab: which ones can turn up at all
	var pl := Label.new()
	pl.text = "Power-ups that can turn up"
	pl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	pages["powerups"].add_child(pl)
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pages["powerups"].add_child(pgrid)
	for k in GameRules.POWERUP_KINDS:
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [PowerUps.LABELS[k], "angels" if k in PowerUps.ANGEL_KINDS else "demons"]
		cb.toggled.connect(func(on):
			rules_custom["powerups"][k] = on
			rules_use_custom = true
			_sync_rules_ui())
		pgrid.add_child(cb)
		_rules_inputs[k] = cb
	# Every rule, under its section's heading
	var grids := {}
	for k in GameRules.RULES:
		var r: Array = GameRules.RULES[k]
		var gkey: String = r[0] + "/" + r[1]
		if not grids.has(gkey):
			var head := Label.new()
			head.text = r[1]
			head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
			pages[r[0]].add_child(head)
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			pages[r[0]].add_child(grid)
			grids[gkey] = grid
		var lbl := Label.new()
		lbl.text = "    " + r[2]
		lbl.tooltip_text = r[8]
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl.custom_minimum_size.x = 300
		grids[gkey].add_child(lbl)
		if GameRules.is_choice(k):
			var ob := OptionButton.new()
			for c in GameRules.CHOICES[k]:
				ob.add_item(c[1])
			ob.tooltip_text = r[8]
			ob.custom_minimum_size.x = 190
			ob.item_selected.connect(func(i):
				rules_custom[k] = i
				rules_use_custom = true
				_sync_rules_ui())
			grids[gkey].add_child(ob)
			_rules_inputs[k] = ob
			continue
		var sb := SpinBox.new()
		sb.min_value = r[3]
		sb.max_value = r[4]
		sb.step = r[5]
		sb.tooltip_text = r[8]
		sb.custom_minimum_size.x = 190
		match r[7]:
			"x": sb.prefix = "x"
			"s": sb.suffix = "s"
			"m": sb.suffix = "m"
		sb.value_changed.connect(func(v):
			rules_custom[k] = int(v) if GameRules.is_count(k) else v
			rules_use_custom = true
			_sync_rules_ui())
		grids[gkey].add_child(sb)
		_rules_inputs[k] = sb
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_button(row, "Reset this tab", func():
		var tab: String = GameRules.TABS[tabs.current_tab][0]
		var std := GameRules.standard()
		for k in GameRules.RULES:
			if GameRules.RULES[k][0] == tab:
				rules_custom[k] = std[k]
		if tab == "powerups":
			rules_custom["powerups"] = std["powerups"]
		_sync_rules_ui())
	_button(row, "Reset everything", func():
		rules_custom = GameRules.standard()
		_sync_rules_ui())
	_button(box, "Done", _close_rules)
	rules_panel.visible = false


func _time_choice(parent: Control, label_text: String, choices: Array, default_index: int, on_pick := Callable()) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var ob := OptionButton.new()
	for secs in choices:
		ob.add_item("Off" if secs == 0 else "%d:%02d" % [int(secs) / 60, int(secs) % 60])
	ob.select(default_index)
	_time_pick[label_text] = default_index
	ob.item_selected.connect(func(i):
		_time_pick[label_text] = i
		if on_pick.is_valid():
			on_pick.call(i))
	row.add_child(ob)
	parent.add_child(row)


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
		var keys: Array = ["Skill 1", "Skill 2"]   # (the keys are on the Controls screen)
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
	if _settings_loaded:
		_save_settings()
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
	_settings_loaded = false   # (nothing saves until it's all read back in, or half-loaded settings would overwrite the file)
	_settings.load(SETTINGS_PATH)
	name_edit.text = _settings.get_value("player", "name", "")
	address_edit.text = _settings.get_value("net", "address", "")
	port_edit.text = str(_settings.get_value("net", "port", NetGame.DEFAULT_PORT))
	for team in ["angel", "demon"]:
		loadout[team] = Skills.clean_loadout(team, _settings.get_value("skills", team, Skills.DEFAULTS[team]))
	# Picks saved before Fly became a skill (v0.3.1) wouldn't include it: reset once.
	if _settings.get_value("skills", "version", 1) < 2:
		loadout["demon"] = Skills.DEFAULTS["demon"].duplicate()
	_apply_loadout()
	var saved_keys := {}
	if _settings.has_section("keys"):
		for action in _settings.get_section_keys("keys"):
			saved_keys[action] = str(_settings.get_value("keys", action))
	Keybinds.setup(saved_keys)
	_music_volume = clampf(float(_settings.get_value("options", "music", 0.6)), 0.0, 1.0)
	_sound_volume = clampf(float(_settings.get_value("options", "sound", 1.0)), 0.0, 1.0)
	_music_slider.set_value_no_signal(_music_volume)
	_sound_slider.set_value_no_signal(_sound_volume)
	_apply_volumes()
	var q := clampi(int(_settings.get_value("options", "graphics", 1)), 0, 2)
	_quality_pick.select(q)
	graphics.apply(q)
	rules_custom = GameRules.clean(JSON.parse_string(str(_settings.get_value("rules", "custom", "{}"))))
	if _settings.has_section_key("options", "hellfire_splashes") and not _settings.has_section_key("rules", "custom"):
		rules_custom["splashes"] = clampi(int(_settings.get_value("options", "hellfire_splashes", 3)), 0, 8)   # (it was a Settings option)
	rules_use_custom = bool(_settings.get_value("rules", "use_custom", false))
	_sync_rules_ui()
	set_ui_scale(float(_settings.get_value("options", "ui_scale", 1.0)))
	_set_shared_dir(str(_settings.get_value("options", "shared_maps", "")))
	if waiting_game != null:
		waiting_game.best = int(_settings.get_value("options", "imp_best", 0))
	var presets = _settings.get_value("wardrobe", "presets", [])
	wardrobe_presets = []
	if typeof(presets) == TYPE_ARRAY:
		for p in presets.slice(0, 60):
			if typeof(p) == TYPE_DICTIONARY and p.get("team") in ["angel", "demon"] and typeof(p.get("name")) == TYPE_STRING:
				wardrobe_presets.append({"name": str(p["name"]).substr(0, 30), "team": p["team"], "outfit": Characters.clean_outfit(p.get("outfit"), p["team"])})
	set_outfits(_settings.get_value("wardrobe", "outfits", {}) if typeof(_settings.get_value("wardrobe", "outfits", {})) == TYPE_DICTIONARY else {})
	_settings_loaded = true
	_chat_size_pick.set_value_no_signal(clampi(int(_settings.get_value("options", "chat_size", 22)), 12, 40))
	_fps_pick.button_pressed = bool(_settings.get_value("options", "show_fps", false))
	_set_chat_size(int(_chat_size_pick.value))


var _settings_loaded := false


# Whatever closes the game (Quit, the window's X, the updater restarting it), what you chose is kept.
func _exit_tree() -> void:
	if _settings_loaded:
		_save_settings()
	Characters.release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _settings_loaded:
		_save_settings()


func _save_settings() -> void:
	_settings.set_value("player", "name", name_edit.text)
	_settings.set_value("net", "address", address_edit.text)
	_settings.set_value("net", "port", int(port_edit.text) if port_edit.text.is_valid_int() else NetGame.DEFAULT_PORT)
	_settings.set_value("skills", "angel", loadout["angel"])
	_settings.set_value("skills", "demon", loadout["demon"])
	_settings.set_value("skills", "version", 2)
	for a in Keybinds.ACTIONS:
		_settings.set_value("keys", a[0], Keybinds.current(a[0]))
	_settings.set_value("options", "music", _music_volume)
	_settings.set_value("options", "sound", _sound_volume)
	_settings.set_value("options", "graphics", Graphics.quality)
	_settings.set_value("rules", "custom", JSON.stringify(rules_custom))
	_settings.set_value("rules", "use_custom", rules_use_custom)
	_settings.set_value("options", "chat_size", chat_font_size)
	_settings.set_value("options", "show_fps", _fps_pick.button_pressed)
	_settings.set_value("options", "ui_scale", ui_scale)
	_settings.set_value("options", "shared_maps", MapData.shared_dir)
	if waiting_game != null:
		_settings.set_value("options", "imp_best", waiting_game.best)
	_settings.set_value("wardrobe", "outfits", outfits)
	_settings.set_value("wardrobe", "presets", wardrobe_presets)
	_settings.save(SETTINGS_PATH)


func _show_menu(message: String) -> void:
	if net:
		net.leave()
		net.name = "NetOld"
		net.queue_free()
		net = null
	var was_building: bool = editor != null and (editor.active() or editor.testing)
	building_online = false
	if editor:
		editor.leave()
	if _back_to_editor:
		_back_to_editor.visible = false
	if was_building:
		hud_layer.visible = true
		player.camera.current = true
		load_map(MapData.load_file(MapData.BUILT_IN[0]), MapData.BUILT_IN[0])
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


# Hosting through the relay server: friends join with a room code, no port forwarding.
func _on_host_relay_pressed() -> void:
	_save_settings()
	_make_net()
	_room_code = ""
	var r := _relay_address()
	var err: Error = net.host_relay(r[0], r[1], name_edit.text)
	if err != OK:
		_show_menu("Couldn't reach the relay server (error %d)." % err)
		return
	mode = "online"
	player.net_mode = "server"
	net.send_loadout(loadout)
	_hide_menus()
	online_lobby(lobby_names, "lobby")


# The relay server's address: the public one, or --relay=HOST[:PORT] (say, one
# running on this PC for testing).
func _relay_address() -> Array:
	if _relay_override == "":
		return [RELAY_HOST, RelayProtocol.PORT]
	var parts := _relay_override.rsplit(":", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return [parts[0], int(parts[1])]
	return [_relay_override, RelayProtocol.PORT]


func online_room_code(code: String) -> void:
	_room_code = code
	print("[room] code %s" % code)
	DisplayServer.clipboard_set(code)
	if net and lobby_panel.visible:
		online_lobby(lobby_names, "lobby")


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		menu_status.text = "Type the room code (or the host's address) first."
		return
	_save_settings()
	_make_net()
	# Five letters/numbers is a room code; anything else is an address.
	var code := RelayProtocol.normalize_code(address)
	_room_code = code
	var err: Error
	if code != "":
		var r := _relay_address()
		err = net.join_relay(r[0], r[1], code, name_edit.text)
	else:
		err = net.join(address, _port(), name_edit.text)
	if err != OK:
		_show_menu("Couldn't start connecting (error %d)." % err)
		return
	mode = "online"
	player.net_mode = "client"
	player.on_claim = func(seq, eid, point): if net: net.claim_hit(seq, eid, point)
	_hide_menus()
	lobby_players.text = ("Joining room %s..." % code) if code != "" else ("Connecting to %s..." % address)
	lobby_info.text = ""
	lobby_start.visible = false
	lobby_build.visible = false
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

# ---------- Creative mode ----------

func _enter_editor_mode() -> void:
	_hide_menus()
	if round_root:
		round_root.free()
		round_root = null
	mode = "editor"
	state = State.LOBBY
	player.frozen = true
	player.visual_root.visible = false
	hud_layer.visible = false
	if editor == null:
		editor = Editor.new()
		editor.main = self
		add_child(editor)


func open_editor() -> void:
	_enter_editor_mode()
	var start: Dictionary = _editor_map if not _editor_map.is_empty() else MapData.empty_map()
	if _editor_map.is_empty():
		start["author"] = name_edit.text.strip_edges()
	editor.enter(start, _editor_map.get("_path", ""))
	_refresh_mouse()


# Creative: play a practice round on the map being built.
func test_map_from_editor(map: Dictionary) -> void:
	_editor_map = map.duplicate(true)
	hud_layer.visible = true
	player.camera.current = true
	player.visual_root.visible = true
	load_map(map, "")
	_back_to_editor.visible = true
	start_practice()
	_refresh_mouse()   # (the editor left the mouse free and the player's input off: you couldn't move until Esc, Resume)
	_toast("Testing your map. Esc, then \"Back to Creative\" to keep building.", 5.0)


func back_to_editor() -> void:
	pause_panel.visible = false
	_back_to_editor.visible = false
	if mode == "online":
		if net != null:
			net.build_test_stop()   # everyone back to building together
		_refresh_mouse()
		return
	if round_root:
		round_root.free()
		round_root = null
	blind_rect.visible = false
	center_label.text = ""
	mode = "editor"
	state = State.LOBBY
	player.frozen = true
	player.visual_root.visible = false
	hud_layer.visible = false
	editor.wake()
	_refresh_mouse()


# Building together online (net_game.gd): the host starts it from the lobby, on the lobby's map.
func begin_building_host() -> void:
	_enter_editor_mode()
	building_online = true
	editor.enter_online(map_data, map_path, true, true)
	_refresh_mouse()


func online_build_start(m: Dictionary, allowed: bool) -> void:
	_enter_editor_mode()
	building_online = true
	editor.enter_online(m, "", false, allowed)
	_refresh_mouse()


# Host: done building. The map becomes the lobby's map, ready to play.
func end_building_host() -> void:
	var m: Dictionary = editor.map.duplicate(true)
	var p: String = editor.path if editor.path != "" else map_path
	_back_from_building()
	load_map(m, p)
	online_lobby(lobby_names, "lobby")


func online_build_end() -> void:
	_back_from_building()
	online_lobby(lobby_names, "lobby")


func _back_from_building() -> void:
	if controls_panel.visible:
		_close_controls()
	editor.leave()
	building_online = false
	mode = "online"
	state = State.LOBBY
	hud_layer.visible = true
	player.camera.current = true
	player.frozen = true


# A joined builder leaving: that's leaving the game.
func leave_online_building() -> void:
	_show_menu("")


# Creative's Settings button: music, sound effects, graphics, keys, without leaving.
func open_settings_from_editor() -> void:
	editor.ui.visible = false
	hud_layer.visible = true   # (the settings panel lives there)
	_open_controls()


func leave_editor() -> void:
	_editor_map = editor.map.duplicate(true)
	_editor_map["_path"] = editor.path
	_show_menu("")


func start_practice() -> void:
	_hide_menus()
	GameRules.current = active_rules()
	mode = "practice"
	player.net_mode = ""
	start_round()


# The rules can force the weather, time of day or day/night cycle for every map (Custom rules, General tab).
# Only the sky, light and falling weather change: the map's ground (snow cover, puddles) stays as built.
func _apply_round_environment() -> void:
	if map_data.is_empty():
		return
	var w := GameRules.weather_for(str(map_data["weather"]))
	var t := GameRules.time_for(str(map_data["time"]))
	var c := GameRules.cycle_for(int(map_data["cycle"]))
	if w != graphics.weather:
		graphics.set_weather(w)
	if t != graphics.time_of_day:
		graphics.set_time_of_day(t)
	if float(c) != graphics.day_cycle:
		graphics.set_day_cycle(c)


func start_round() -> void:
	_reset_round_props(randi())
	_apply_round_environment()
	Sfx.heal_bus(true)
	var types := PropLib.scatter_names()
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
	if editor != null and editor.testing:
		time_left = 3.0   # testing a map from Creative: no waiting around (Nov 21)
	blind_rect.visible = role == "angel"
	controls_label.text = _controls_text()
	if role == "angel":
		_toast("The demons are hiding...\n(%s to skip the wait while testing)" % Keybinds.key_name("skip_hiding"), HIDE_TIME)
	else:
		_toast("Demon sandbox: practice possessing props.\nTry Host / Join for real hunting.", 5.0)


func _controls_text() -> String:
	var k := Keybinds.key_name
	var move := "%s%s%s%s" % [k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right")]
	var common := "%s move   %s run   %s sneak   %s jump   %s / %s taunt   %s first/third person" % [
		move, k.call("run"), k.call("sneak"), k.call("jump"), k.call("taunt_random"), k.call("taunt_signature"), k.call("toggle_view")]
	var skills := "%s / %s skills" % [k.call("skill_1"), k.call("rmb")]
	var side := "%s throw   %s   %s melee   %s look around   %s swap skills (at the shrine)" % [
		k.call("shoot"), skills, k.call("melee"), k.call("free_look"), k.call("shrine")] if role == "angel" \
		else "%s a prop: become a copy   Hold %s: demon form   %s (hold Fly to rise)   %s + mouse: turn your prop   %s swap skills (at the shrine)" % [
		k.call("shoot"), k.call("shoot"), skills, k.call("run"), k.call("shrine")]
	if mode == "practice":
		return common + "\n" + side + "   %s switch side   %s restart   %s movement tuning   Esc menu" % [k.call("switch_role"), k.call("restart"), k.call("toggle_tuning")]
	return common + "\n" + side + "   %s roster   %s / %s chat   Esc menu" % [k.call("scoreboard"), k.call("chat_all"), k.call("chat_team")]


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
	_hush_cherubs()
	_round_sting(message)
	_toast(message + "\nR to play again   Tab to switch sides", 9999.0)


func _on_bot_caught(bot) -> void:
	_play("caught")
	if is_instance_valid(bot):
		demon_explosion(bot.global_position)
		powerups.demon_caught(bot.global_position)
	bots_left -= 1
	if bots_left <= 0 and state == State.HUNTING:
		_end_round("All demons caught! Angels win!")
	else:
		_toast("Demon caught! %d left" % bots_left, 2.0)


# The FPS counter (Settings: Show FPS): on top of everything, menus included, so it also shows what the
# menus and Creative cost. Triangles and draw calls are what the graphics card was asked to draw.
func _build_fps_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fps_label = Label.new()
	fps_label.position = Vector2(8, 4)
	fps_label.add_theme_font_size_override("font_size", 15)
	fps_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = false
	layer.add_child(fps_label)


func _update_fps(delta: float) -> void:
	if not fps_label.visible:
		return
	_fps_tick -= delta
	if _fps_tick > 0.0:
		return
	_fps_tick = 0.5
	var tris := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	fps_label.text = "%d FPS   %dk triangles   %d draw calls" % [int(Engine.get_frames_per_second()), tris / 1000, draws]


var _sound_check := 2.0


func _process(delta: float) -> void:
	_update_fps(delta)
	_sound_check -= delta
	if _sound_check <= 0.0:
		_sound_check = 2.0
		if Sfx.heal_bus():
			print("[sound] the effects bus went bad: made fresh")
	_tick_waiting_game()
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
		_check_cherubs(delta)
		_check_naughty(delta)
		if state == State.HUNTING:
			powerups.decider_tick(delta)
			_check_sense(delta)
	_check_burning()
	_update_music()
	_update_shrine(delta)
	_update_chat(delta)
	_update_hud(delta)
	_update_room_watermark()


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
	if _kick_pick and net and net.is_host:
		_kick_pick.clear()
		for n in names.slice(1):   # everyone but the host (always first)
			_kick_pick.add_item(n)
	if state != State.LOBBY or building_online:
		return   # mid-round (or building): the list updates, the panel stays hidden
	lobby_players.text = "Players (%d):\n  %s" % [names.size(), "\n  ".join(_lobby_lines(names))]
	lobby_map_label.text = "Map: %s" % map_data.get("name", "?") + ((" by " + map_data["author"]) if map_data.get("author", "") != "" else "")
	var is_host: bool = net != null and net.is_host
	if is_host and _map_pick.item_count == 0:
		refresh_map_list()
	lobby_start.visible = is_host
	lobby_build.visible = is_host
	lobby_times.visible = is_host
	if is_host:
		lobby_start.disabled = false
		lobby_start.text = "Start round" if names.size() >= 2 else "Start round (just you, for now)"
		_solo_row.visible = names.size() < 2
		_solo_pick.select(1 if net.solo_role == "angel" else 0)
		_rules_summary.text = GameRules.summary(active_rules())
		if net.using_relay():
			if _room_code == "":
				lobby_info.text = "Opening a room on the relay server..."
			else:
				lobby_info.text = "Room code:  %s\nFriends type it under Join a game. (It's copied, so you can paste it into Discord.)" % _room_code
		else:
			var lines := ["Friends join with your address and port %d:" % _port()]
			if _public_ip != "":
				lines.append("  Over the internet: %s  (needs the port forwarded on your router)" % _public_ip)
			var lan := _local_ips()
			if not lan.is_empty():
				lines.append("  Same house / same Wi-Fi: %s" % ", ".join(lan))
			lobby_info.text = "\n".join(lines)
	elif host_phase == "lobby":
		lobby_info.text = "Waiting for the host to start the round..."
	elif host_phase == "building":
		lobby_info.text = "The host is building a map. Joining in..."
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
	_apply_round_environment()
	Sfx.heal_bus(true)
	role = new_role
	my_health = 1.0
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
		_toast("You're an ANGEL.\nThe demons are hiding...\n(%s: change your skills while you wait)" % Keybinds.key_name("shrine") if state == State.HIDING else "You're an ANGEL. Find the demons!", 4.0)
	else:
		_toast("You're a DEMON! Hide!\nClick a prop to become a copy of it.", 4.0)


func online_phase(phase: String, seconds: float) -> void:
	state = _phase_to_state(phase)
	time_left = seconds
	if state == State.HUNTING:
		player.frozen = false
		blind_rect.visible = false
		_toast("The hunt is on!" if role == "demon" else "Go find them!", 2.5)


func online_count(n: int) -> void:
	bots_left = n


func online_you_hit(health_fraction: float) -> void:
	if health_fraction < my_health - 0.001:   # (Unholy Mending also lands here: no "ouch" for a heal)
		# Hit! Make it impossible to miss (Ted, Nov 20): a big red flash, a jolt, and a yelp.
		_hurt_time = 0.45
		_play("hurt")
		_sounds["distress"].play()
		player.shake(0.45)
	my_health = health_fraction


# Holy Word knocked us out of the sky.
func online_struck() -> void:
	_hurt_time = 0.25
	if state != State.ENDED:
		_toast("STRUCK DOWN!", 1.2)


# The angels yanked us (vacuum orb, kick).
func online_affected(target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
	player.shoved(target - player.global_position)   # (a disguise may go over: Ted, Nov 27)
	if label == "":   # bumped into: a short shove, no fuss
		player.pull_to(target, 0.4)
		return
	player.pull_to(target, 1.0)
	player.hatred = maxf(player.hatred - hatred_drain, 0.0)
	player.skill_lock = maxf(player.skill_lock, lockout)
	_hurt_time = 0.2
	if state != State.ENDED:
		_toast(label, 1.2)


func online_you_were_caught(pos: Vector3, by_name := "") -> void:
	role = "angel"
	player.set_role("angel")
	powerups.forget_other_team("angel")
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.rotation.y = PI
	player.frozen = false
	controls_label.text = _controls_text()
	var who := ("%s got you!\n" % by_name) if by_name != "" else ""
	_toast("%sYou were caught and REDEEMED!\nNow you're an angel. Hunt your old friends!" % who, 4.0)


func online_caught_fx(pos: Vector3) -> void:
	_play("caught")
	demon_explosion(pos)
	if role == "angel" and bots_left > 0:
		_toast("A demon was redeemed! %d left" % bots_left, 2.0)


func online_round_end(message: String) -> void:
	state = State.ENDED
	_hush_cherubs()
	_round_sting(message)
	player.frozen = true
	if is_instance_valid(player.minion):
		player.minion.queue_free()
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
	player.clear_dash()


func online_disconnected(message: String) -> void:
	_show_menu(message)


func _on_player_launched(origin: Vector3, velocity: Vector3, kind: String, gravity: float, seq: int) -> void:
	if net:
		net.on_local_launched(origin, velocity, kind, gravity, seq)


func _on_player_hit_taken(damage: int, by: Node) -> void:
	if net and net.is_host:
		net.damage_player(1, damage, net.peer_of(by))


# ---------- skills: deciding what happens ----------
# In practice the game itself decides what a skill does; online, the host does
# (net_game.gd checks every request first). The same code runs either way, and
# broadcast_fx() shows the results on every screen.

func is_authority() -> bool:
	return mode == "practice" or (net != null and net.is_host)


# ---------- animated props (E; prop_anims.gd) ----------

func _animate_hint() -> void:
	if role == "demon" and PropAnims.can_animate(player.possessed_type):
		_toast("%s: %s" % [Keybinds.key_name("animate"), PropAnims.verb(player.possessed_type)], 2.0)


# We pressed E (our own visual already did its thing): online the host passes it on (and lights fuses);
# in practice an explosive goes off here.
func _on_animate(n: int) -> void:
	if mode == "online":
		if net:
			net.on_local_animate(n)
	elif PropAnims.is_explosive(player.possessed_type) and (state == State.HIDING or state == State.HUNTING):
		get_tree().create_timer(PropAnims.FUSE_TIME).timeout.connect(_practice_kaboom)


func _practice_kaboom() -> void:
	if mode != "practice" or not player.fuse_lit or not (state == State.HIDING or state == State.HUNTING):
		return
	var pos := player.global_position
	kaboom_fx(pos)
	demon_explosion(pos)
	player.fuse_lit = false
	player.unpossess()
	_end_round("KABOOM! You blew yourself up.")


# An explosive prop went off (with the demon inside): a fireball, a big bang, smoke, props flung about.
func kaboom_fx(pos: Vector3) -> void:
	var b := DemonBlast.new()
	_fx_parent().add_child(b)
	b.global_position = pos + Vector3.UP * 0.4
	Effects.puff(_fx_parent(), pos + Vector3.UP * 0.6, Color(1.0, 0.55, 0.1, 0.9), 3.2)
	Effects.smoke(_fx_parent(), pos + Vector3.UP * 0.8, Color(0.12, 0.1, 0.09), 3.0)
	_play_at(PropAnimSounds.get_sound("kaboom"), pos, 1.0, 4.0)
	_shake_near(pos, 0.9, 22.0)
	if round_root:
		_blast_props(pos, PropAnims.KABOOM_RADIUS * GameRules.f("blast") + 2.0, BLAST_SHOVE * 1.6)


func online_dazed(seconds: float) -> void:
	player.daze(seconds)
	_toast("DAZED!", 1.2)


func _on_player_skill(id: String, origin: Vector3, dir: Vector3, point: Vector3, index: int) -> void:
	if id == "minion":
		_spawn_my_minion(point, index)
	if mode == "practice":
		authority_skill(player, 0, id, origin, dir, point, index)
	elif net:
		if id == "vacuum" and not net.is_host:
			_spawn_orb(origin, dir, true)   # our own copy, just to see; the host's is real
		if id == "scripture" and not net.is_host:
			_spawn_scripture(origin, dir, true)
		net.on_local_skill(id, origin, dir, point, index)


# A random kind of prop that's standing somewhere on the map right now.
func random_map_prop_type() -> String:
	var kinds := []
	for prop in props:
		if is_instance_valid(prop) and prop.visible and prop.has_meta("prop_type") and not prop.get_meta("prop_type") in kinds:
			kinds.append(prop.get_meta("prop_type"))
	return kinds.pick_random() if not kinds.is_empty() else "crate"


func map_has_prop_type(type_name: String) -> bool:
	for prop in props:
		if is_instance_valid(prop) and prop.has_meta("prop_type") and prop.get_meta("prop_type") == type_name:
			return true
	return false


# Our own decoy: we run it (we steer it); the host shows it to everyone else.
func _spawn_my_minion(at: Vector3, form_index: int) -> void:
	if is_instance_valid(player.minion):
		player.minion.queue_free()
	var m := Minion.new()
	var types: Array = PropLib.type_names()
	m.form = types[form_index] if form_index >= 0 and form_index < types.size() else ""
	m.outfit = outfits["demon"]
	m.fall_gravity = player.gravity * player.tuning["gravity_scale"]
	m.jump_velocity = player.tuning["jump_velocity"]
	round_root.add_child(m)
	m.global_position = ground_below(at + Vector3.UP * 1.0)
	m.rotation.y = player.shown_yaw()
	player.minion = m
	if mode == "practice":
		# Practice: hits come straight here; it has the health of the form it copies.
		var hp := [PropLib.max_hp(m.form) * Skills.minion_health()]
		m.on_hit = func(_by, damage):
			hp[0] -= damage
			award_hatred(0, Skills.NAUGHTY_MINION_HIT, "your minion fooled an angel")
			if hp[0] <= 0 and is_instance_valid(m):
				m.pop()
			return true
	elif net and net.is_host:
		m.on_hit = func(by, damage): return net.minion_hit(1, by, damage)


func _on_player_melee(origin: Vector3, dir: Vector3) -> void:
	if mode == "practice":
		authority_melee(player, 0, origin, dir)
	elif net:
		net.on_local_melee(origin, dir)


func _on_player_released() -> void:
	if mode == "practice":
		authority_release(0, player.global_position, player.shown_yaw())
	elif net:
		net.on_local_release()


func _ray(from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	var rids := []
	for n in exclude:
		if is_instance_valid(n) and n is CollisionObject3D:
			rids.append(n.get_rid())
	q.exclude = rids
	return get_world_3d().direct_space_state.intersect_ray(q)


func ground_below(point: Vector3, exclude: Array = []) -> Vector3:
	var hit := _ray(point + Vector3.UP * 0.5, point + Vector3.DOWN * 40.0, exclude)
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
		"minion":
			if net and net.is_host:
				net.minion_spawned(user_key, point, index)
		"teleport":
			var from: Vector3 = user.global_position
			if Vector2(point.x - from.x, point.z - from.z).length() > Skills.teleport_range() + 3.0:
				return
			# (Too far: the point is set high up, so you land on top of whatever is there.)
			var dest := ground_below(point + Vector3.UP * 0.5)
			if absf(dest.x) > MAP_HALF - 1.0 or absf(dest.z) > MAP_HALF - 1.0 or point.y > CEILING:
				return
			broadcast_fx("teleport", [from, dest])
			if mode == "practice":
				player.teleport_to(dest)
			elif net:
				net.teleport_player(user_key, dest)
			print("[decider] teleport")
		"cherub":
			# Thrown from the angel's hands; where it ends up is up to physics.
			_cherub_counter += 1
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			var pos: Vector3 = user.global_position + Vector3.UP * 1.1 + flat * 1.2   # clear of the thrower
			var vel: Vector3 = dir * Skills.CHERUB_THROW_SPEED + Vector3.UP * Skills.CHERUB_THROW_UP
			_auth_cherubs[_cherub_counter] = {"pos": pos, "until": Time.get_ticks_msec() / 1000.0 + Skills.cherub_lifetime(),
					"alarmed": false, "rested": false}
			broadcast_fx("cherub", [_cherub_counter, pos, vel])
			print("[decider] cherub dropped")
		"fire":
			# Flung from the demon's hands; it lights wherever it comes down.
			_fire_counter += 1
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			var from: Vector3 = user.global_position + Vector3.UP * 1.3 + flat * 0.6
			var vel: Vector3 = dir * Skills.FIRE_THROW_SPEED + Vector3.UP * Skills.FIRE_THROW_UP
			var flight := _fly_until_hit(from, vel, Skills.FIRE_GRAVITY, [user])
			var spot := ground_below(flight[0] - vel.normalized() * 0.3)
			var fr := Skills.FIRE_RADIUS * GameRules.f("fire_radius")
			var fl := Skills.FIRE_LIFETIME * GameRules.f("fire_time")
			broadcast_fx("fire", [_fire_counter, from, vel, spot, flight[1], fr, fl])
			_auth_fires[_fire_counter] = {"owner": user_key, "pos": spot, "lit_at": _now() + flight[1],
				"until": _now() + flight[1] + fl, "r": fr}
			print("[decider] hellfire lit")
			if GameRules.splashes() > 0:
				get_tree().create_timer(flight[1]).timeout.connect(func(): _fire_splash(user_key, spot))
		"fear":
			# Every angel close by who can see the demon panics.
			var from: Vector3 = user.global_position
			broadcast_fx("fear", [from])
			var n := 0
			for e in team_entries():
				if e[2] != "angel" or e[1] == user:
					continue
				var a: Node3D = e[1]
				if a.global_position.distance_to(from) > Skills.fear_radius() or not _can_see(user, a):
					continue
				n += 1
				if a == player:
					player.scare(from, Skills.fear_time())
				elif net:
					net.scare_player(e[0], from, Skills.fear_time())
			print("[decider] fear: %d angel(s) scattered" % n)
		"word":
			# Holy Word: a shout down the crosshair. Fliers it catches high enough up are struck out of the sky.
			var aim := dir.normalized()
			var reach := Skills.WORD_RANGE * GameRules.f("word_range")
			var q := PhysicsRayQueryParameters3D.create(origin, origin + aim * reach)
			q.collision_mask = WORLD_LAYER
			if user is CollisionObject3D:
				q.exclude = [user.get_rid()]
			var n := 0
			for e in team_entries():
				if e[2] != "demon":
					continue
				var d: Node3D = e[1]
				if d == user:
					continue
				var mid: Vector3 = d.global_position + Vector3.UP * 0.6
				var along := (mid - origin).dot(aim)
				if along < 0.0 or along > reach or (origin + aim * along).distance_to(mid) > Skills.WORD_WIDTH:
					continue
				if not _can_see(user, d):
					continue
				var high: float = d.global_position.y - ground_below(d.global_position, [d]).y
				if not _is_flying(e[0], d) or high < Skills.WORD_MIN_HEIGHT:
					continue
				n += 1
				if d == player:
					player.strike_down(Skills.WORD_STUN * GameRules.f("word_stun"))
					online_struck()
				elif net:
					net.strike_down(e[0], Skills.WORD_STUN * GameRules.f("word_stun"))
				broadcast_fx("struck", [d.global_position])
			if n > 0 and user.has_method("confirm_hit"):
				user.confirm_hit()
			broadcast_fx("word", [origin, aim * reach])
			print("[decider] holy word struck down %d flier(s)" % n)
		"scripture":
			var book := _spawn_scripture(origin, dir, false)
			book.shooter = user
			book.on_impact = func(at: Vector3): _smite(user, at)
			book.homing = func(at: Vector3, vel: Vector3): return _book_target(user, at, vel)
			var key := _book_key(origin)
			book.on_steer = func(p: Vector3, v: Vector3): broadcast_fx("book_steer", [key, p, v])
			broadcast_fx("scripture", [origin, dir], user_key)
		"kick":
			var c = _close_demon(user, dir, Skills.KICK_RANGE)
			if c == null:
				_boot_prop(user, dir, Skills.KICK_RANGE, PROP_KICK)   # nothing to kick but the furniture
				return
			if c.take_hit(roundi(Skills.KICK_DAMAGE * GameRules.f("kick_damage")), user):
				user.confirm_hit()
				var away := Vector3(dir.x, 0.0, dir.z).normalized()
				var land := ground_below(c.global_position + away * Skills.KICK_PUSH * GameRules.f("kick_push") + Vector3.UP * 1.0, [c] + props + demon_targets())
				_affect_demon(c, land, 0.0, 0.0, "KICKED!")
				broadcast_fx("kick", [c.global_position + Vector3.UP * 0.6])
				print("[decider] holy kick sent a demon flying")
		"stomp":
			# Hurts every demon around where it landed: most in the middle, more from higher up.
			var drop := clampf(point.y - origin.y, 0.0, 40.0)
			if net and net.is_host and user_key > 1:
				drop = minf(drop, net.leap_drop(user_key, origin))   # no more than the host saw them climb
			var hurt := 0
			for d in demon_targets():
				var off: Vector3 = d.global_position - origin
				var dmg := Skills.stomp_damage(Vector2(off.x, off.z).length(), drop)
				if dmg > 0 and absf(off.y) < 3.0 and d.has_method("take_hit") and d.take_hit(dmg, user):
					hurt += 1
					# ...and the shockwave shoves them outward.
					var out := Vector3(off.x, 0.0, off.z)
					out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
					_affect_demon(d, ground_below(d.global_position + out * STOMP_PUSH + Vector3.UP * 1.0, [d] + props + demon_targets()), 0.0, STOMP_STUN, "STUNNED!")
			if hurt > 0 and user.has_method("confirm_hit"):
				user.confirm_hit()
			broadcast_fx("stomp", [origin, drop])
			print("[decider] cloud stomp hit %d demon(s) (from %.1f m up)" % [hurt, drop])
		"vacuum":
			var orb := _spawn_orb(origin, dir, false)   # (it bounces off bouncy pads: see _spawn_orb)
			orb.shooter = user
			orb.on_impact = _vacuum_at
			broadcast_fx("orb", [origin, dir], user_key)
		"dash":
			# The dash itself happens on the dasher's own screen; everyone gets the trail.
			var start := user.global_position + Vector3.UP * 0.5
			broadcast_fx("sparkle", [start, start + dir.normalized() * DASH_TRAIL])
			if net and user_key > 1:
				net.grant_dash(user_key)   # they may move fast for a moment
			print("[decider] flying dash")
		"possess":
			_authority_possess(user, user_key, index)


func authority_melee(user: Node3D, _user_key: int, origin: Vector3, dir: Vector3) -> void:
	var d = _close_demon(user, dir, Skills.MELEE_RANGE)
	if d and d.take_hit(roundi(Skills.MELEE_DAMAGE * GameRules.f("melee_damage")), user):
		user.confirm_hit()
		# (a swing shoves a disguised demon as far as it would the prop: lighter things go further; Ted, Nov 27)
		bump(d, Vector3(dir.x, 0.0, dir.z).normalized() * PROP_SWAT, null)
		print("[decider] melee hit a demon")
	elif d == null:
		_boot_prop(user, dir, Skills.MELEE_RANGE, PROP_SWAT)


# Up-close attacks (melee, kick) don't need pixel-perfect aim: the nearest demon
# within reach, roughly in front of you (within 45 degrees) and not behind a wall.
func _close_demon(user: Node3D, dir: Vector3, reach: float):
	var flat_dir := Vector2(dir.x, dir.z).normalized()
	var me := user.global_position + Vector3.UP * 0.9
	var best = null
	var best_d := INF
	for d in demon_targets():
		if d == user or not d.has_method("take_hit"):
			continue
		var off: Vector3 = d.global_position + Vector3.UP * 0.5 - me
		var flat := Vector2(off.x, off.z)
		var dist := flat.length()
		if dist > reach + 0.6 or absf(off.y) > 2.0 or dist >= best_d:
			continue
		if dist > 0.5 and rad_to_deg(absf(flat_dir.angle_to(flat))) > 45.0:
			continue
		var wall := _ray(me, d.global_position + Vector3.UP * 0.5, [user, d])
		if not wall.is_empty():
			continue
		best = d
		best_d = dist
	return best


# Follow a thrown thing's arc until it hits something: [where, after how many seconds].
func _fly_until_hit(from: Vector3, vel: Vector3, g: float, skip: Array) -> Array:
	var t := 0.0
	var prev := from
	while t < 4.0:
		t += 0.02
		var p := from + vel * t + Vector3.DOWN * 0.5 * g * t * t
		var hit := _ray(prev, p, skip)
		if not hit.is_empty():
			return [hit["position"], t]
		prev = p
	return [prev, t]


# Is this demon flying right now (as far as the host / practice game knows)?
func _is_flying(key: int, node: Node) -> bool:
	if node == player:
		return player.flying
	if net and net.peers.has(key):
		return net.peers[key].get("flying", false)
	return false


static var _word_voice: AudioStreamWAV


# Everyone: Holy Word's shout. A golden ripple races down the line, and a choir booms one chord.
func _word_fx(from: Vector3, span: Vector3) -> void:
	var parent := _fx_parent()
	var steps := 14
	for i in steps:
		var at := from + span * (float(i + 1) / steps)
		get_tree().create_timer(i * 0.018).timeout.connect(func():
			Effects.puff(parent, at, Color(1.0, 0.95, 0.65, 0.55), 0.9 + i * 0.05))
	if _word_voice == null:
		# A short, bright "HAH!" of a choir: a few voices on a major chord, a quick swell and decay.
		_word_voice = Sfx.voice([[392, 392, 0.32, 1.0, 0.0]], 0.3, 0.5, 0.01, 0.15)
	var v := AudioStreamPlayer3D.new()
	v.bus = Sfx.BUS
	v.stream = _word_voice
	v.unit_size = 10.0
	v.max_distance = 80.0
	parent.add_child(v)
	v.global_position = from
	v.play()
	v.finished.connect(v.queue_free)


# Host / practice: the Holy Scripture landed. Every demon close by is hurt (most in the middle), shoved
# outward, and can't use skills for a moment; everyone sees the pillar of light and hears the bell.
func _smite(user: Node3D, at: Vector3) -> void:
	if not is_inside_tree() or state != State.HUNTING:
		return
	var hurt := 0
	for d in demon_targets():
		if not is_instance_valid(d):
			continue
		var off: Vector3 = d.global_position - at
		var dist := Vector2(off.x, off.z).length()
		if dist > Skills.smite_radius() or absf(off.y) > 3.0:
			continue
		var dmg := roundi(lerpf(Skills.SMITE_DAMAGE, Skills.SMITE_MIN_DAMAGE, dist / Skills.smite_radius()) * GameRules.f("smite_damage"))
		if d.has_method("take_hit") and d.take_hit(dmg, user):
			hurt += 1
			var out := Vector3(off.x, 0.0, off.z)
			out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			_affect_demon(d, ground_below(d.global_position + out * Skills.SMITE_PUSH + Vector3.UP * 1.0), 0.0,
				Skills.SMITE_LOCKOUT, "SMITTEN!")
	if hurt > 0 and is_instance_valid(user) and user.has_method("confirm_hit"):
		user.confirm_hit()
	broadcast_fx("smite", [at])
	print("[decider] holy scripture smote %d demon(s)" % hurt)


static var _smite_bell: AudioStreamWAV


# Everyone: the smite's pillar of light, a golden shockwave, props flying, and a deep church-bell BONG.
func _smite_fx(at: Vector3) -> void:
	var parent := _fx_parent()
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 1.1
	cyl.height = 16.0
	pillar.mesh = cyl
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.92, 0.55, 0.75)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.4)
	m.emission_energy_multiplier = 2.0
	pillar.material_override = m
	parent.add_child(pillar)
	pillar.global_position = at + Vector3.UP * 8.0
	var tw := pillar.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pillar, "scale", Vector3(2.2, 1.0, 2.2), 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(pillar.queue_free)
	for i in 12:   # a golden ring out to the edge of where it hurts
		var a := TAU * i / 12.0
		Effects.puff(parent, at + Vector3(cos(a), 0.3, sin(a)) * Skills.smite_radius() * 0.8, Color(1.0, 0.9, 0.5, 0.7), 1.4)
	Effects.burst(parent, at + Vector3.UP * 0.5, Color(1.0, 0.95, 0.6), 40, 9.0, 0.8)
	_blast_props(at, Skills.smite_radius() * 1.2, 6.0)
	_shake_near(at, 0.4, 16.0)
	if _smite_bell == null:
		_smite_bell = Sfx.tone([[131.0, 1.0], [262.0, 0.7], [330.0, 0.35], [392.0, 0.45], [523.0, 0.3], [698.0, 0.15]],
				2.6, 0.5, 0.004, 4.0, 0.25, 0.985)
	var bell := AudioStreamPlayer3D.new()
	bell.bus = Sfx.BUS
	bell.stream = _smite_bell
	bell.unit_size = 12.0
	bell.max_distance = 90.0
	parent.add_child(bell)
	bell.global_position = at + Vector3.UP
	bell.play()
	bell.finished.connect(bell.queue_free)


# Host / practice: what a heat-seeking book flies at: the nearest demon or Minion ahead of it.
func _book_target(user: Node3D, at: Vector3, vel: Vector3):
	if state != State.HUNTING:
		return null
	var best = null
	var best_d := Skills.SEEK_RANGE
	for d in demon_targets():
		if not is_instance_valid(d) or d == user:
			continue
		var mid: Vector3 = d.global_position + Vector3.UP * 0.5
		var dist := at.distance_to(mid)
		if dist < best_d and vel.angle_to(mid - at) < Skills.SEEK_CONE:
			best_d = dist
			best = mid
	return best


# Every copy of a book (the thrower's, the host's, everyone else's) is known by where it was thrown from.
var _books := {}


func _book_key(origin: Vector3) -> String:
	return str(origin.snapped(Vector3.ONE * 0.01))


func _spawn_scripture(origin: Vector3, dir: Vector3, visual_only: bool) -> Projectile:
	var book := Projectile.new()
	book.kind = "book"
	book.book = true
	book.damage = roundi(Skills.SCRIPTURE_DAMAGE * GameRules.f("scripture_damage"))
	book.gravity = Skills.SCRIPTURE_GRAVITY
	book.visual_only = visual_only
	_fx_parent().add_child(book)
	book.global_position = origin + dir * 0.6
	book.velocity = dir * Skills.SCRIPTURE_SPEED + Vector3.UP * 3.0
	for k in _books.keys():
		if not is_instance_valid(_books[k]):
			_books.erase(k)
	_books[_book_key(origin)] = book
	return book


func _spawn_orb(origin: Vector3, dir: Vector3, visual_only: bool) -> Projectile:
	var orb := Projectile.new()
	orb.kind = "vacuum"
	orb.color = Color(0.65, 0.35, 1.0)
	orb.size = 0.22
	orb.gravity = 9.0
	orb.damage = 0
	orb.bounces_on_pads = true
	orb.visual_only = visual_only
	_fx_parent().add_child(orb)
	orb.global_position = origin + dir * 0.6
	orb.velocity = dir * 22.0 + Vector3.UP * 2.0
	return orb


# The vortex evaporates any Minion in reach, whatever it looks like (Ted, Nov 18).
func _vacuum_minions(center: Vector3, reach := -1.0) -> void:
	if reach < 0.0:
		reach = Skills.vacuum_radius()
	if mode == "practice":
		if is_instance_valid(player.minion) and player.minion.global_position.distance_to(center) <= reach:
			player.minion.pop()
		return
	if net and net.is_host:
		for owner in net.minions.keys():
			if (net.minions[owner]["pos"] as Vector3).distance_to(center) <= reach:
				net._minion_gone(owner, true)


# Host / practice: a Hellfire hit the ground and splashes: smaller blobs of fire hop out of the first pool
# and light their own pools nearby (Ted, Nov 18). How many is a setting.
func _fire_splash(owner: int, spot: Vector3) -> void:
	if not is_inside_tree() or state == State.ENDED:
		return
	var n := GameRules.splashes()
	var turn := randf() * TAU
	for i in n:
		var a := turn + TAU * i / n + randf_range(-0.3, 0.3)
		var reach := randf_range(Skills.FIRE_SPLASH_MIN, Skills.FIRE_SPLASH_MAX) * GameRules.f("blast")
		var to := ground_below(spot + Vector3(cos(a), 0.0, sin(a)) * reach + Vector3.UP * 3.0)
		if absf(to.y - spot.y) > 3.0:
			continue   # over a ledge or up a wall: skip that one
		var from := spot + Vector3.UP * 0.4
		var hop := Skills.FIRE_SPLASH_HOP
		var vel := (to - from) / hop + Vector3.UP * 0.5 * Skills.FIRE_GRAVITY * hop
		_fire_counter += 1
		var fr := Skills.FIRE_RADIUS * GameRules.f("fire_radius") * GameRules.f("splash_size")
		var fl := Skills.FIRE_LIFETIME * GameRules.f("fire_time") * GameRules.f("splash_time")
		broadcast_fx("fire", [_fire_counter, from, vel, to, hop, fr, fl])
		_auth_fires[_fire_counter] = {"owner": owner, "pos": to, "lit_at": _now() + hop,
			"until": _now() + hop + fl, "r": fr}


var _vortex_count := 0      # ids, so "vortex_caught" fx find the right vortex
var _vortices := {}         # vortex id -> the Vortex on this screen


func _vacuum_at(center: Vector3) -> void:
	_vortex_count += 1
	var caught := _vacuum_pulse(center, {}, 0, _vortex_count, false)
	broadcast_fx("vortex", [center, caught, _vortex_count])
	print("[decider] vacuum orb %s" % ("CAUGHT a demon" if caught else "found nothing"))


# Host / practice: every VACUUM_PULSE seconds until it dies, the vortex yanks every demon in its (shrinking) reach
# most of the way to its middle, harder as it goes, so running away doesn't work: far stronger than the props'
# pull, whatever the demon looks like. 'seen' keeps track of who it already caught (they get the smaller drain).
# When "is a demon caught right now" changes, everyone hears about it (just that, never who).
func _vacuum_pulse(center: Vector3, seen: Dictionary, n: int, id: int, was: bool) -> bool:
	if not is_inside_tree() or state == State.ENDED:
		return false
	var t := n * Skills.VACUUM_PULSE
	var reach := Vortex.radius_at(t)
	var pull := 0.55 + 0.4 * Vortex.power_at(t)   # share of the way to the middle, per yank
	var caught := false
	var i := 0
	for d in demon_targets():
		if d.global_position.distance_to(center) <= reach:
			caught = true
			var a := float(n * 3 + i) * 2.4   # (a little scatter so they don't stack exactly; no shared random)
			var flat_to: Vector3 = d.global_position.lerp(center, pull) + Vector3(cos(a), 0.0, sin(a)) * 0.3
			# (pulled across the ground and set down on whatever's there: never into a wall or block the
			# orb happened to hit)
			var to: Vector3 = ground_below(Vector3(flat_to.x, maxf(d.global_position.y, center.y) + 1.5, flat_to.z),
					[d] + props + demon_targets())   # (onto the ground or structures, not onto the props piling in)
			var first := not seen.has(d)
			seen[d] = true
			_affect_demon(d, to, (Skills.VACUUM_HATRED_DRAIN if first else Skills.VACUUM_PULSE_DRAIN) * GameRules.f("vacuum_drain"),
				Skills.VACUUM_TIME - t + Skills.VACUUM_LOCKOUT * GameRules.f("vacuum_lock"), "VACUUMED!")
		i += 1
	_vacuum_minions(center, reach)
	if n > 0 and caught != was:
		broadcast_fx("vortex_caught", [id, caught])
	if (n + 1) * Skills.VACUUM_PULSE < Skills.VACUUM_TIME - 0.05:
		get_tree().create_timer(Skills.VACUUM_PULSE).timeout.connect(func(): _vacuum_pulse(center, seen, n + 1, id, caught))
	return caught


# Every screen: the vortex itself, and the props it drags in.
func _vortex_fx(args: Array) -> void:
	var center: Vector3 = args[0]
	var v := Vortex.new()
	v.caught = bool(args[1])
	v.ground_y = ground_below(center + Vector3.UP * 0.6).y
	_fx_parent().add_child(v)
	v.global_position = center
	for k in _vortices.keys():
		if not is_instance_valid(_vortices[k]):
			_vortices.erase(k)
	if args.size() > 2:
		_vortices[int(args[2])] = v
	_pull_props(center, v)


# Yank a demon somewhere, drain Hatred, lock their skills.
# Nothing solid (walls, blocks) between two people's heads?
func _can_see(a: Node3D, b: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a.global_position + Vector3.UP * 1.2, b.global_position + Vector3.UP * 1.2)
	q.collision_mask = WORLD_LAYER
	var skip := []
	for n in [a, b]:
		if n is CollisionObject3D:
			skip.append(n.get_rid())
	for _i in 6:
		q.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return true
		var c = hit["collider"]
		if c is Node and world_root and world_root.is_ancestor_of(c):
			return false   # part of the map (a wall, a block): blocked
		skip.append(hit["rid"])   # props and people don't block the shriek
	return true


func _affect_demon(node: Node3D, target: Vector3, hatred_drain: float, lockout: float, label: String) -> void:
	if node is BotDemon:
		var tw := node.create_tween()
		tw.tween_property(node, "global_position", target, 0.3)   # (set down where it's sent: never slid into a block)
	elif net:
		net.affect_node(node, target, hatred_drain, lockout, label)


func _authority_possess(user: Node3D, user_key: int, index: int) -> void:
	if index < 0 or index >= props.size():
		return
	var prop = props[index]
	if not is_instance_valid(prop) or not prop.is_in_group("prop"):
		return   # already possessed by someone, or dissolving
	if prop.get_meta("no_possess", false):
		return   # placed as "can't be possessed" (copying its look is fine)
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


# Decider only: a blessing hit a cherub. Send it skidding the way the shot was going.
func kick_cherub(cid: int, shot_velocity: Vector3) -> void:
	if not _auth_cherubs.has(cid) or not cherubs.has(cid) or not is_instance_valid(cherubs[cid]):
		return
	var flat := Vector3(shot_velocity.x, 0, shot_velocity.z)
	if flat.length() < 0.1:
		return
	var vel := flat.normalized() * Skills.CHERUB_KICK_SPEED + Vector3.UP * Skills.CHERUB_KICK_UP
	var pos: Vector3 = cherubs[cid].global_position + Vector3.UP * 0.05
	_auth_cherubs[cid]["rested"] = false
	broadcast_fx("cherub_kick", [cid, pos, vel])
	print("[decider] cherub kicked")


# A cherub landed on a bouncy pad: it flies up and off, away from the pad's middle.
func bounce_cherub(cid: int, pad_position: Vector3, up_speed: float) -> void:
	if not _auth_cherubs.has(cid) or not cherubs.has(cid) or not is_instance_valid(cherubs[cid]):
		return
	var c: Node3D = cherubs[cid]
	var flat := Vector3(c.velocity.x, 0, c.velocity.z)
	if flat.length() < CHERUB_PAD_SIDEWAYS:
		var away := Vector3(c.global_position.x - pad_position.x, 0, c.global_position.z - pad_position.z)
		if away.length() < 0.05:
			away = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		flat = away.normalized() * CHERUB_PAD_SIDEWAYS
	var pos: Vector3 = c.global_position + Vector3.UP * 0.05
	_auth_cherubs[cid]["rested"] = false
	broadcast_fx("cherub_kick", [cid, pos, flat + Vector3.UP * up_speed])
	print("[decider] cherub bounced off a bouncy")


# What the top-right icons show: every effect on us right now -> seconds left.
func _my_effects() -> Dictionary:
	var out := {}
	for k in player.powerups:
		if k != "vanish" and k != "heal":
			out[k] = player.powerups[k]
	out["vanish"] = player.vanish_time
	out["burning"] = player.burning
	out["feared"] = player.feared
	out["skill_lock"] = player.skill_lock
	return out


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---- Hatred for naughtiness ----
# Demons earn a little Hatred for being naughty: angels roasting in their fire,
# their minion fooling an angel, taunting right under an angel's nose.
# The decider (host / practice game) hands it out.
# ---- One-use bouncies ----

# Our own player used one up: the decider tells everyone it's gone.
func _on_bouncy_used(id: int) -> void:
	if is_authority():
		bouncy_used(id, -1)
	elif net:
		net.c_bouncy_used.rpc_id(1, id)


# Decider: a one-use bouncy was used (by this player, or the decider's own).
func bouncy_used(id: int, _by_key: int) -> void:
	if not bouncies.has(id) or not is_instance_valid(bouncies[id]):
		return
	broadcast_fx("bouncy_gone", [id])


# ---- Power-ups (the drops are in powerups.gd) ----

# Everyone the decider can see: [key, body, team]. (Practice: you, and the test demons.)
func team_entries() -> Array:
	if mode == "practice":
		var out := [[0, player, role]]
		var i := 1
		for b in get_tree().get_nodes_in_group("demon"):
			out.append([-i, b, "demon"])
			i += 1
		return out
	return net.team_entries() if net else []


# Decider: someone picked up a power-up.
func give_powerup(user_key: int, kind: String, where: Vector3) -> void:
	if user_key < 0:
		return   # a practice test demon walked over it
	if kind == "fire_burst":
		broadcast_fx("fire_burst", [where])
		var burned := 0
		for e in team_entries():
			if e[2] == "angel" and e[1].global_position.distance_to(where) <= PowerUps.burst_radius():
				burned += 1
				if mode == "practice":
					e[1].burning = maxf(e[1].burning, Skills.fire_linger() * 2.0)
				elif net:
					net.burn_player(e[0], Skills.fire_linger() * 2.0)
		if burned > 0:
			award_hatred(user_key, Skills.NAUGHTY_FIRE_PER_SEC * burned, "your fire burst caught an angel")
		return
	if kind == "heal":
		if mode == "online" and net:
			net.heal_player(user_key)
		return
	if kind == "vanish" and net and net.is_host:
		net.set_vanished(user_key, Skills.VANISH_TIME * GameRules.f("vanish_time"))   # the angels stop hearing about them
	if mode == "practice":
		player.apply_powerup(kind)
	elif net:
		net.give_powerup(user_key, kind)
		if kind == "sense" and net.peers.has(user_key):
			# Everyone sees the little cherub flapping about over their head (Ted, Nov 18: "it's funny!").
			var who: int = net.my_eid if user_key == 1 else net.peers[user_key]["eid"]
			broadcast_fx("sense_cherub", [who, PowerUps.duration("sense")])


# Cherub Sense: a red bubble pulses around you and the horn blares while a demon is close.
func _update_sense_bubble(delta: float) -> void:
	if _sense_bubble == null:
		_sense_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 32   # (Godot's default is 64 x 32: ~4000 triangles each; Nov 26 audit)
		sm.rings = 16
		sm.radius = 1.0
		sm.height = 2.0
		_sense_bubble.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.15, 0.1, 0.12)
		_sense_bubble.material_override = mat
		player.add_child(_sense_bubble)
	# The cherub over our head, for as long as the power-up lasts.
	var sensing: bool = mode in ["practice", "online"] and player.role == "angel" and player.powerup_left("sense") > 0.0
	if sensing and not is_instance_valid(_sense_cherub):
		_sense_cherub = SenseCherub.new()
		player.add_child(_sense_cherub)
		# (a touch in front, so looking up shows it even in first person)
		_sense_cherub.position = Vector3(0, Bodies.height_for("angel") + SenseCherub.ABOVE_HEAD, -0.25)
	elif not sensing and is_instance_valid(_sense_cherub):
		_sense_cherub.queue_free()
		_sense_cherub = null
	if is_instance_valid(_sense_cherub):
		_sense_cherub.alarmed = player.sense_alarm
	_sense_bubble.visible = player.sense_alarm
	if player.sense_alarm:
		var tt := Time.get_ticks_msec() / 1000.0
		_sense_bubble.scale = Vector3.ONE * Skills.cherub_radius() * (0.6 + 0.4 * absf(sin(tt * 3.0)))
		_sense_bubble.position.y = 0.9
		_sense_sound_time -= delta
		if _sense_sound_time <= 0.0:
			_sense_sound_time = 0.8
			_play("sense")


# Cherub Sense: an angel with it acts like a walking alarm cherub.
var _sense_tick := 0.0


func _check_sense(delta: float) -> void:
	_sense_tick -= delta
	if _sense_tick > 0.0:
		return
	_sense_tick = 0.25
	if mode == "practice":
		if role == "angel" and player.powerup_left("sense") > 0.0:
			var near := false
			for d in demon_targets():
				if d.global_position.distance_to(player.global_position) <= Skills.cherub_radius():
					near = true
			player.sense_alarm = near
	elif net:
		net.check_sense()


func award_hatred(user_key: int, amount: float, reason: String) -> void:
	if mode == "practice" and user_key == 0:
		player.add_hatred(amount, reason)
	elif net and net.is_host:
		net.grant_hatred(user_key, amount, reason)


func angel_nodes() -> Array:
	if mode == "practice":
		return [player] if role == "angel" else []
	return net.angel_nodes() if net else []


func _check_naughty(delta: float) -> void:
	_naughty_tick -= delta
	if _naughty_tick > 0.0 or state != State.HUNTING:
		return
	_naughty_tick = 0.5
	var t := _now()
	for id in _auth_fires.keys():
		var f: Dictionary = _auth_fires[id]
		if t > f["until"]:
			_auth_fires.erase(id)
			continue
		if t < f["lit_at"]:
			continue
		for a in angel_nodes():
			var off: Vector3 = a.global_position - f["pos"]
			if Vector2(off.x, off.z).length() <= f.get("r", Skills.FIRE_RADIUS) and off.y > -0.5 and off.y < 1.5:
				award_hatred(f["owner"], Skills.NAUGHTY_FIRE_PER_SEC * 0.5, "an angel is roasting in your fire")


# Decider: is this spot inside a burning Hellfire pool?
func _in_lit_fire(pos: Vector3, t: float) -> bool:
	for id in _auth_fires:
		var f: Dictionary = _auth_fires[id]
		if t < f["lit_at"] or t > f["until"]:
			continue
		var off: Vector3 = pos - f["pos"]
		if Vector2(off.x, off.z).length() <= f.get("r", Skills.FIRE_RADIUS) and off.y > -0.5 and off.y < 1.5:
			return true
	return false


# Our own angel standing in demon fire? (Slowed, blessings burn away.)
func _check_burning() -> void:
	if role != "angel" or state != State.HUNTING:
		return   # angels are safe from fire until the hunt starts
	var me := player.global_position
	for id in fires.keys():
		var f = fires[id]
		if not is_instance_valid(f):
			fires.erase(id)
			continue
		var off: Vector3 = me - f.global_position
		if f.is_lit() and Vector2(off.x, off.z).length() <= f.radius and off.y > -0.5 and off.y < 1.5:
			player.burning = maxf(player.burning, Skills.fire_linger())


# The round is over: every cherub stops its alarm on this screen at once (the host's "cherub_alarm" may arrive
# after the round-end message, or not at all once the round's things are cleared).
func _hush_cherubs() -> void:
	for cid in cherubs:
		if is_instance_valid(cherubs[cid]):
			cherubs[cid].alarmed = false
			cherubs[cid].creep = Vector3.ZERO
	for cid in _auth_cherubs:
		_auth_cherubs[cid]["alarmed"] = false


func _check_cherubs(delta: float) -> void:
	_cherub_check -= delta
	if _cherub_check > 0.0 or _auth_cherubs.is_empty():
		return
	_cherub_check = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	# Only live demons during the hunt count. Once the last one is caught the round is over, so every cherub
	# goes quiet straight away (Ted, Nov 27: one kept screaming after the last demon was caught).
	var targets := []
	if state == State.HUNTING:
		for d in demon_targets():
			if is_instance_valid(d) and d.is_inside_tree() and not d.is_queued_for_deletion():
				targets.append(d)
	for cid in _auth_cherubs.keys():
		var c: Dictionary = _auth_cherubs[cid]
		if now > c["until"]:
			_auth_cherubs.erase(cid)
			continue
		var node = cherubs.get(cid)
		if node != null and is_instance_valid(node):
			c["pos"] = node.global_position   # it may have been knocked somewhere
		# Hellfire burns a cherub up if it stays in it (playtest, Nov 26: demons' answer to a cherub).
		if _in_lit_fire(c["pos"], now):
			c["burn"] = c.get("burn", 0.0) + 0.25
			if c["burn"] >= Skills.CHERUB_BURN_TIME:
				_auth_cherubs.erase(cid)
				broadcast_fx("cherub_burn", [cid])
				continue
		else:
			c["burn"] = 0.0
			# Once it comes to rest, tell everyone where it ended up (tiny drift fix).
			if node.is_on_floor() and node.velocity.length() < 0.2 and not c.get("rested", true):
				c["rested"] = true
				broadcast_fx("cherub_kick", [cid, node.global_position, Vector3.ZERO])
		var near := false
		var closest := Vector3.ZERO      # from the cherub to the nearest demon it can sense
		var closest_dist := INF
		for d in targets:
			var dist: float = d.global_position.distance_to(c["pos"])
			if dist <= Skills.cherub_radius():
				near = true
				if dist < closest_dist:
					closest_dist = dist
					closest = d.global_position - c["pos"]
		if near != c["alarmed"]:
			c["alarmed"] = near
			broadcast_fx("cherub_alarm", [cid, near])
			if near:
				print("[decider] cherub alarm: demon nearby")
		# An alarmed cherub creeps toward that demon. Only tell everyone when its
		# heading really changes, not four times a second.
		var creep := Vector3.ZERO
		closest.y = 0.0
		if near and closest.length() > Skills.CHERUB_CREEP_STOP:
			creep = closest.normalized() * Skills.CHERUB_CREEP_SPEED
		var old: Vector3 = c.get("creep", Vector3.ZERO)
		if creep.is_zero_approx() != old.is_zero_approx() or (not creep.is_zero_approx() and creep.angle_to(old) > 0.2):
			c["creep"] = creep
			if creep.is_zero_approx():
				c["rested"] = false      # when it has stopped, tell everyone exactly where
			broadcast_fx("cherub_creep", [cid, creep])


# ---------- effects everyone sees ----------

# Show an effect here and on everyone else's screen. `except_key` is the player
# who caused it: they already drew their own orb, so they don't get a copy.
func broadcast_fx(kind: String, args: Array, except_key := -1) -> void:
	var we_caused_it := except_key == 0 or except_key == 1   # practice player or the host
	# Orbs and books: the decider's own real projectile is already flying here.
	var real_one_here := kind == "orb" or kind == "scripture"
	if not real_one_here:
		fx(kind, args)
	if net and net.is_host:
		net.send_fx(kind, args, except_key)


func _fx_parent() -> Node:
	return round_root if round_root else self


func fx_parent() -> Node:
	return _fx_parent()


# An effect only one team may see (their power-ups).
func team_fx(team: String, kind: String, args: Array) -> void:
	if role == team:
		fx(kind, args)
	if net and net.is_host:
		net.send_fx_team(team, kind, args)


func puff_at(pos: Vector3, color: Color, size: float) -> void:
	Effects.puff(_fx_parent(), pos, color, size)


func fx(kind: String, args: Array) -> void:
	match kind:
		"kaboom":
			kaboom_fx(args[0])
		"hit_blast":
			var hb := DemonBlast.new()
			hb.small = true
			_fx_parent().add_child(hb)
			hb.global_position = args[0]
		"teleport":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.8, Color(0.15, 0.02, 0.05, 0.85), 1.8)
			Effects.puff(_fx_parent(), args[1] + Vector3.UP * 0.5, Color(0.15, 0.02, 0.05, 0.6), 0.9)
			Effects.smoke(_fx_parent(), args[0] + Vector3.UP * 0.5, Color(0.2, 0.05, 0.08), 1.4)
			Effects.smoke(_fx_parent(), args[1] + Vector3.UP * 0.3, Color(0.2, 0.05, 0.08), 0.8)
		"bouncy_gone":
			if bouncies.has(args[0]) and is_instance_valid(bouncies[args[0]]):
				Effects.puff(_fx_parent(), bouncies[args[0]].global_position + Vector3.UP * 0.4, Color(1.0, 0.85, 0.4, 0.8), 1.0)
				bouncies[args[0]].use_up()
			bouncies.erase(args[0])
		"powerup":
			powerups.show_item(args[0], args[1], args[2], args[3] if args.size() > 3 else args[2],
					float(args[4]) if args.size() > 4 else PowerUps.LIFETIME)
		"powerup_gone":
			powerups.hide_item(args[0], args[1])
		"fire_burst":
			for i in 10:
				var a := TAU * i / 10.0
				Effects.puff(_fx_parent(), args[0] + Vector3(cos(a), 0.3, sin(a)) * PowerUps.burst_radius() * 0.6, Color(1.0, 0.45, 0.05, 0.85), 2.2)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.5, Color(1.0, 0.3, 0.0, 0.9), 3.5)
			Effects.smoke(_fx_parent(), args[0] + Vector3.UP * 0.5, Color(0.25, 0.12, 0.08), 2.0)
			_blast_props(args[0], PowerUps.burst_radius(), 6.0)
			_shake_near(args[0], 0.4, 14.0)
		"cherub":
			var c := Cherub.new()
			c.cherub_id = args[0]
			_fx_parent().add_child(c)
			c.launch(args[1], args[2] if args.size() > 2 else Vector3.ZERO)
			cherubs[args[0]] = c
			if mode != "online" or (net and net.is_host):
				c.on_kick = kick_cherub
				c.on_bounce = bounce_cherub
		"cherub_kick":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].launch(args[1], args[2])
		"cherub_creep":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].creep = args[1]
		"cherub_alarm":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				cherubs[args[0]].alarmed = args[1]
		"cherub_burn":
			if cherubs.has(args[0]) and is_instance_valid(cherubs[args[0]]):
				var where: Vector3 = cherubs[args[0]].global_position
				Effects.puff(_fx_parent(), where + Vector3.UP * 0.4, Color(0.25, 0.22, 0.2, 0.85), 1.4)
				Effects.puff(_fx_parent(), where + Vector3.UP * 0.6, Color(1.0, 0.5, 0.1, 0.8), 0.9)
				cherubs[args[0]].queue_free()
			cherubs.erase(args[0])
		"shrine":
			if shrine:
				shrine.flare()
		"orb":
			_spawn_orb(args[0], args[1], true)
		"scripture":
			_spawn_scripture(args[0], args[1], true)
		"fire":
			var f := Fire.new()
			f.from = args[1]
			f.vel = args[2]
			f.to = args[3]
			f.flight_time = args[4]
			if args.size() >= 7:
				f.radius = clampf(float(args[5]), 0.2, 8.0)
				f.life_time = clampf(float(args[6]), 0.5, 30.0)
			f.add_to_group("hellfire")   # (snow_tracks.gd: it melts the snow)
			_fx_parent().add_child(f)
			fires[args[0]] = f
		"kick":
			Effects.puff(_fx_parent(), args[0], Color(1.0, 0.95, 0.6, 0.8), 1.2)
		"knock":
			_knock_here(int(args[0]), args[1])
		"prop_rest":
			_prop_rest_here(int(args[0]), args[1], float(args[2]))
		"sense_cherub":
			# An angel picked up Cherub Sense: hang a cherub over their head.
			if net and net.remotes.has(args[0]):
				var r: Node3D = net.remotes[args[0]]
				var old := r.get_node_or_null("SenseCherub")
				if old:
					old.free()
				var c := SenseCherub.new()
				c.name = "SenseCherub"
				c.life = clampf(float(args[1]), 0.0, 30.0)
				r.add_child(c)
				c.position.y = Bodies.height_for("angel") + SenseCherub.ABOVE_HEAD
				print("[fx] a cherub over an angel's head")
		"fear":
			for i in 12:
				var a := TAU * i / 12.0
				Effects.puff(_fx_parent(), args[0] + Vector3(cos(a), 0.4, sin(a)) * Skills.fear_radius() * 0.5, Color(0.25, 0.0, 0.3, 0.7), 2.0)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 1.0, Color(0.15, 0.0, 0.2, 0.85), 3.0)
			if player.global_position.distance_to(args[0]) < 35.0:
				_play("fear")
		"minion_pop":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(0.35, 0.05, 0.08, 0.8), 1.6)
			Effects.smoke(_fx_parent(), args[0] + Vector3.UP * 0.4, Color(0.3, 0.06, 0.1), 1.0)
		"stomp":
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.2, Color(1.0, 1.0, 1.0, 0.75), Skills.stomp_radius() * 1.2)
			for i in 10:   # a shockwave ring out to the edge of where it hurts
				var a := TAU * i / 10.0
				Effects.puff(_fx_parent(), args[0] + Vector3(cos(a), 0.3, sin(a)) * Skills.stomp_radius() * 0.8, Color(1.0, 0.97, 0.8, 0.6), 1.6)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(1.0, 0.95, 0.7, 0.6), 2.0)
			Effects.dust(_fx_parent(), args[0], Skills.stomp_radius() * 0.5, 24)
			_blast_props(args[0], Skills.stomp_radius() * 1.2, 7.0)
			_shake_near(args[0], 0.5, 18.0)
			# a superhero landing (Sara, Nov 25: the timpani wasn't it): bigger drops land deeper and longer
			var k := clampf((float(args[1]) if args.size() > 1 else 6.0) / 15.0, 0.0, 1.0)
			_play_at(StompSounds.landing(k), args[0], 1.0, 3.0 + 2.0 * k)
		"smite":
			_smite_fx(args[0])
		"word":
			_word_fx(args[0], args[1])
		"struck":
			Effects.burst(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(1.0, 0.95, 0.6), 30, 7.0, 0.6)
			Effects.puff(_fx_parent(), args[0] + Vector3.UP * 0.6, Color(1.0, 1.0, 0.85, 0.8), 1.6)
		"book_steer":
			# The host's book turned toward a demon: our copy follows the same curve.
			var b = _books.get(str(args[0]))
			if b != null and is_instance_valid(b) and b.visual_only:
				b.global_position = args[1]
				b.velocity = args[2]
		"vortex":
			_vortex_fx(args)
		"vortex_caught":
			var vc = _vortices.get(int(args[0]))
			if vc != null and is_instance_valid(vc):
				vc.set_caught(bool(args[1]))
		"sparkle":
			Effects.sparkle_trail(_fx_parent(), args[0], args[1])
		"prop_taken":
			_set_prop_taken(args[0])
		"prop_shell":
			_make_shell(args[0], args[1], args[2])


# Host: how the props differ from the fresh layout right now (taken by demons, or
# moved by vacuums), so someone joining mid-round sees the same thing as everyone.
func prop_state() -> Array:
	var gone := []
	var moved := []
	for i in props.size():
		var prop = props[i]
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			gone.append(i)
		elif prop.has_meta("moved_basis"):
			moved.append([i, prop.get_meta("moved_to"), prop.get_meta("moved_basis"), prop.get_meta("ground_offset", 0.0)])
		elif prop.has_meta("moved_to"):
			moved.append([i, prop.get_meta("moved_to")])
	return [gone, moved]


func apply_prop_state(gone: Array, moved: Array) -> void:
	for i in gone:
		_set_prop_taken(int(i))
	for m in moved:
		var i := int(m[0])
		if i >= 0 and i < props.size() and is_instance_valid(props[i]):
			if m.size() >= 4:
				_prop_rest_here(i, Transform3D(m[2], m[1]), float(m[3]))
			else:
				props[i].global_position = m[1]


func _set_prop_taken(index: int) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: Node3D = props[index]
	_stop_knock(prop)
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
	_stop_knock(prop)
	prop.global_position = pos
	prop.rotation = Vector3(0.0, yaw, 0.0)   # back upright, even if it had been knocked over
	prop.visible = true
	for c in prop.get_children():
		if c is CollisionShape3D:
			c.disabled = false
	# Whoever just left it is standing inside it: let them walk straight out
	# instead of being stuck until it fades. (Everyone else still bumps into it.)
	if player and prop is PhysicsBody3D and player.global_position.distance_to(pos) < 3.0:
		player.add_collision_exception_with(prop)
	Effects.dissolve(prop, 6.0)


# The vortex drags nearby props toward its middle (vortex.gd moves them every frame). Every computer runs the
# same math on the same starting positions, so every screen ends up identical.
func _pull_props(center: Vector3, v: Node3D) -> void:
	var near := []
	for prop in props:
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			continue
		if not Vortex.in_reach(prop.global_position - center) or PropLib.is_fixed(prop.get_meta("prop_type", "")):
			continue
		var knock: Node = prop.get_node_or_null("Knock")
		if knock and knock.is_physics_processing():
			continue   # mid-slide: knock.gd has it
		near.append(prop)
		prop.set_meta("moved_to", Vortex.final_position(center, prop.global_position))   # (for anyone joining later)
	v.pull(near)


# ---------- loose props: shoving them about (see knock.gd) ----------

const PROP_SWAT := 3.0          # a melee swing that hits furniture instead of a demon (first guess)
const PROP_KICK := 7.0          # Holy Kick with no demon in reach (first guess)
const BLESSING_SHOVE := 0.05    # share of a blessing's speed that shoves a prop (first guess)
const STOMP_PUSH := 2.0         # m a Cloud Stomp shoves the demons it hurts (first guess)
const STOMP_STUN := 1.0         # s the demons it hurts can't use skills ("STUNNED!", Sara, Nov 25; first guess)
const StompSounds = preload("res://scripts/stomp_sounds.gd")
const FxWarmup = preload("res://scripts/fx_warmup.gd")


# We ran into a loose prop or a disguised demon. Practice: shove it now. Online: ask the host.
func _on_player_bumped(thing: Node, push: Vector3) -> void:
	if mode == "practice":
		bump(thing, push, player)
	elif net and net.in_round_now():
		if thing.is_in_group("prop") and thing.has_meta("prop_index"):
			net.request_bump(int(thing.get_meta("prop_index")), -1, push)
		elif thing.get("eid") != null:
			net.request_bump(-1, int(thing.eid), push)


# Host / practice: someone ran into something. A prop slides (knock.gd); a demon disguised as that kind of
# prop gets pushed about as far as that prop would slide, so the two behave alike.
func bump(thing: Node, push: Vector3, by: Node) -> void:
	if not is_authority() or not is_instance_valid(thing):
		return
	push = push.limit_length(10.0)
	if thing.is_in_group("prop") and thing.has_meta("prop_index"):
		knock_prop(int(thing.get_meta("prop_index")), push)
		return
	var form := ""
	for field in ["form", "prop_type", "possessed_type"]:   # (someone else, a practice bot, or us)
		if thing.get(field) != null:
			form = str(thing.get(field))
			break
	if form in ["", "<null>"] or not PropLib.TYPES.has(form) or PropLib.is_fixed(form):
		return   # (a demon disguised as a fixed-in-place prop doesn't budge either)
	var dv := push / PropLib.mass(form)
	var slide := dv.length() * dv.length() / (2.0 * Knock.FRICTION)
	if slide < 0.05 or thing == by:
		return
	var to := ground_below(thing.global_position + dv.normalized() * slide + Vector3.UP * 1.0)
	_affect_demon(thing, to, 0.0, 0.0, "")


# Host / practice: shove a prop, and tell everyone.
func knock_prop(index: int, impulse: Vector3) -> void:
	if not is_authority() or index < 0 or index >= props.size():
		return
	if impulse.length() > 30.0:
		impulse = impulse.limit_length(30.0)
	broadcast_fx("knock", [index, impulse])


func _knock_here(index: int, impulse: Vector3) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]) or not props[index].is_in_group("prop"):
		return
	Knock.on(self, props[index], index).hit(impulse)


# Host: a knocked prop came to rest; make sure everyone has it in exactly the same spot.
func prop_rested(index: int, xf: Transform3D, offset: float) -> void:
	if net and net.is_host:
		net.send_fx("prop_rest", [index, xf, offset], -1)


func _prop_rest_here(index: int, xf: Transform3D, offset: float) -> void:
	if index < 0 or index >= props.size() or not is_instance_valid(props[index]):
		return
	var prop: StaticBody3D = props[index]
	var k := prop.get_node_or_null("Knock")
	if k and k.is_physics_processing():
		k.set_physics_process(false)
		k.queue_free()
	prop.set_meta("moved_to", xf.origin)
	prop.set_meta("moved_basis", xf.basis)
	prop.set_meta("ground_offset", offset)
	if prop.global_transform.origin.distance_to(xf.origin) < 0.01:
		prop.global_transform = xf
		return
	var tw := prop.create_tween()
	tw.tween_property(prop, "global_transform", xf, 0.25)


func _stop_knock(prop: Node) -> void:
	var k := prop.get_node_or_null("Knock")
	if k:
		k.free()
	var visual := prop.get_child(0) as Node3D
	if visual:
		visual.transform = Transform3D.IDENTITY   # (a rolled apple straightens up)
	prop.remove_meta("moved_basis")
	prop.remove_meta("ground_offset")


# Host / practice: a blessing hit a loose prop.
func _on_blessing_hit_prop(prop: Node, velocity: Vector3, _point: Vector3) -> void:
	knock_prop(int(prop.get_meta("prop_index", -1)), velocity * BLESSING_SHOVE + Vector3.UP * 0.6)


# Host / practice: a melee swing or a kick with no demon in reach boots the nearest
# prop in front instead.
func _boot_prop(user: Node3D, dir: Vector3, reach: float, strength: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var me := user.global_position
	var best := -1
	var best_d := INF
	for i in props.size():
		var prop = props[i]
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			continue
		var off: Vector3 = prop.global_position - me
		var d := Vector2(off.x, off.z).length()
		if d > reach + 0.6 or d >= best_d or absf(off.y) > 2.0:
			continue
		if d > 0.4 and rad_to_deg(Vector2(flat.x, flat.z).angle_to(Vector2(off.x, off.z))) > 50.0:
			continue
		best = i
		best_d = d
	if best >= 0:
		knock_prop(best, flat * strength + Vector3.UP * strength * 0.3)


# Everyone runs this from the same blast, so every screen shoves the same props
# the same way (like the vortex). Nearer = harder.
func _blast_props(center: Vector3, radius: float, strength: float) -> void:
	for i in props.size():
		var prop = props[i]
		if not is_instance_valid(prop) or not prop.is_in_group("prop"):
			continue
		var off: Vector3 = prop.global_position - center
		var flat := Vector3(off.x, 0.0, off.z)
		var d := flat.length()
		if d > radius or absf(off.y) > 3.0:
			continue
		var dir := flat / d if d > 0.05 else Vector3.RIGHT
		var power := strength * (1.0 - d / radius * 0.7)
		Knock.on(self, prop, i).hit(dir * power + Vector3.UP * power * 0.4)


# A one-off sound from a spot in the world (heard louder up close), no shared random numbers.
func _play_at(stream: AudioStream, where: Vector3, pitch: float, db := 0.0) -> void:
	var asp := AudioStreamPlayer3D.new()
	asp.stream = stream
	asp.bus = Sfx.BUS
	asp.pitch_scale = pitch
	asp.volume_db = db
	asp.unit_size = 14.0
	asp.max_distance = 140.0
	_fx_parent().add_child(asp)
	asp.global_position = where
	asp.finished.connect(asp.queue_free)
	asp.play()


func _shake_near(where: Vector3, amount: float, reach: float) -> void:
	var d := player.global_position.distance_to(where)
	if d < reach and mode != "menu":
		player.shake(amount * (1.0 - d / reach))


# ---------- music ----------

# Which song fits right now: the waltz in menus and lobbies, tiptoeing while the
# demons hide, the chase during the hunt.
func _update_music() -> void:
	var song := "lobby"
	if editor != null and editor.active():
		song = "lobby"
	elif mode != "menu":
		match state:
			State.HIDING: song = "hiding"
			State.HUNTING: song = round_theme
			State.ENDED: song = ""
	music.play(song)


func _round_sting(message: String) -> void:
	var angels_won := message.contains("Angels win")
	music.sting("win" if angels_won == (role == "angel") else "lose")


# The sliders run on a squared curve (Ted, Nov 20: the lowest setting was still too loud): the bottom
# of the slider gets properly quiet, the middle sounds about as before.
func _apply_volumes() -> void:
	Music.set_volume(_music_volume * _music_volume)
	var idx := AudioServer.get_bus_index(Sfx.BUS)
	if idx != -1:
		var gain := _sound_volume * _sound_volume
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(gain, 0.00001)))
		AudioServer.set_bus_mute(idx, _sound_volume <= 0.001)


# ---------- command line (automated testing) ----------
# e.g.  godot -- --host --name=Ted --autostart=3 --hide=5
#       godot -- --join=127.0.0.1 --name=Bot --autobot
#       godot -- --host-relay --relay=127.0.0.1 ...   then   --join=KX4PZ --relay=127.0.0.1
# --host hosts directly and --host-relay through the relay server. --join takes an
# address or a room code. --relay=HOST[:PORT] picks another relay server.

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
	if args.has("relay"):
		_relay_override = args["relay"]
	if args.has("autobot"):
		autobot = Autobot.new()
		autobot.main = self
		autobot.options = args
		add_child(autobot)
	if args.has("sure-drops"):   # tests: every redeemed demon drops an angel power-up
		powerups.catch_drop = 1.0
	if args.has("buildbot"):   # tests/test_building.sh
		var bb: Node = load("res://tests/build_bot.gd").new()
		bb.set("main", self)
		bb.set("role", args["buildbot"])
		add_child(bb)
	if args.has("practice"):
		start_practice()
	elif args.has("host") or args.has("host-relay"):
		if args.has("host-relay"):
			_on_host_relay_pressed()
		else:
			_on_host_pressed()
		if net and args.has("hide"):
			net.hide_time = float(args["hide"])
		if net and args.has("hunt"):
			net.hunt_time = float(args["hunt"])
		if net and args.has("idle"):
			net.idle_limit = float(args["idle"])
		if args.has("map"):   # e.g. --map=res://tests/test_map.json
			var m := MapData.load_file(args["map"])
			if not m.is_empty():
				load_map(m, args["map"])
		if net and args.has("roles"):   # e.g. --roles=Abe:demon,Ava:angel
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


func _update_room_watermark() -> void:
	var show := mode == "online" and state == State.LOBBY and _room_code != "" and net != null
	_room_watermark.visible = show
	if show:
		_room_watermark.text = "ROOM  %s" % _room_code


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud_layer = hud
	add_child(hud)

	# The room code, big and faint behind everything while in the lobby (so it's there when friends ask).
	_room_watermark = Label.new()
	_room_watermark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_watermark.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_room_watermark.add_theme_font_size_override("font_size", 130)
	_room_watermark.modulate = Color(1, 1, 1, 0.13)
	_room_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_watermark.visible = false
	hud.add_child(_room_watermark)

	# Burning in Hellfire: the whole view wobbles and swims with heat (HUD stays readable).
	heat_rect = ColorRect.new()
	heat_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	heat_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heat := ShaderMaterial.new()
	heat.shader = Shader.new()
	heat.shader.code = HEAT_SHADER
	heat_rect.material = heat
	heat_rect.visible = false
	hud.add_child(heat_rect)

	blind_rect = ColorRect.new()
	blind_rect.color = Color(0.06, 0.03, 0.1)
	blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(blind_rect)
	waiting_game = WaitingGame.new()
	waiting_game.visible = false
	hud.add_child(waiting_game)

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

	disguise_label = _make_label(22)
	disguise_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	disguise_label.position = Vector2(16, 14)
	disguise_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	hud.add_child(disguise_label)

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
	_make_bar(bars, "health", Color(0.85, 0.2, 0.25))
	_make_bar(bars, "sprint", Color(0.4, 0.85, 0.45))
	_make_bar(bars, "power", Color(1.0, 0.85, 0.3))

	# Hold-to-return progress bar, just under the crosshair
	hold_bar = ColorRect.new()
	hold_bar.color = Color(0, 0, 0, 0.5)
	hold_bar.size = Vector2(80, 6)
	hold_bar.set_anchors_preset(Control.PRESET_CENTER)
	hold_bar.position += Vector2(-40, 24)
	hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_bar.visible = false
	hud.add_child(hold_bar)
	hold_fill = ColorRect.new()
	hold_fill.color = Color(0.9, 0.2, 0.15)
	hold_fill.size = Vector2(0, 6)
	hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_bar.add_child(hold_fill)

	# Skills, bottom right
	skill_label = _make_label(18)
	skill_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skill_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skill_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skill_label.position += Vector2(-16, -76)   # above the two controls lines
	hud.add_child(skill_label)

	# Ping, top right
	ping_label = _make_label(20)
	ping_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ping_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.position += Vector2(-16, 14)
	hud.add_child(ping_label)
	# Everything you're under right now (Hellfire, Fear, power-ups...), just below the ping.
	effect_icons = EffectIcons.new()
	effect_icons.position += Vector2(-16, 46)
	hud.add_child(effect_icons)

	_build_scoreboard(hud)

	# Active power-ups, with seconds left
	powerup_label = _make_label(18)
	powerup_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powerup_label.position.y -= 215
	powerup_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	hud.add_child(powerup_label)
	# "+4 Hatred: taunting right under an angel's nose"
	bonus_label = _make_label(18)
	bonus_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bonus_label.position.y -= 185
	bonus_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	hud.add_child(bonus_label)
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
	for team in ["demon", "angel"]:   # demons on the left, angels on the right
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
	if Skills.SKILLS[id].get("hold", false):
		return "[Hold %s] %s%s" % [key, Skills.label(id), "   (flying)" if player.flying else ""]
	var cd: float = player.skill_cd.get(id, 0.0)
	return "[%s] %s   %s" % [key, Skills.label(id), "ready" if cd <= 0.0 else "%ds" % ceili(cd)]


func _skill_text() -> String:
	var lo: Array = player.loadout[role]
	if role == "angel":
		var melee := "ready" if player.melee_cd <= 0.0 else "..."
		return "%s\n%s\n[%s] Melee   %s" % [_skill_line(Keybinds.key_name("skill_1"), lo[0]), _skill_line(Keybinds.key_name("rmb"), lo[1]), Keybinds.key_name("melee"), melee]
	var text := "%s\n%s" % [_skill_line(Keybinds.key_name("skill_1"), lo[0]), _skill_line(Keybinds.key_name("rmb"), lo[1])]
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
	var value := _make_label(16)      # optional number to the right of the bar
	value.custom_minimum_size.x = 80
	row.add_child(value)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(BAR_WIDTH, 14)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	parent.add_child(row)
	bar_fills[bar_name] = [fill, lbl, value]


func _set_bar(bar_name: String, text: String, fraction: float, color := Color.TRANSPARENT, value := "") -> void:
	bar_fills[bar_name][2].text = value
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
		"boom": Sfx.boom_sound(),
		"timpani": Sfx.timpani_sound(),
		"distress": Sfx.distress_sound(),
		"possess": Sfx.possess_sound(),
		# Cherub Sense alarm: the cherub's little horn fanfare.
		"sense": Sfx.voice([[784, 784, 0.09, 1.0, 0.02], [988, 988, 0.09, 1.0, 0.02], [1175, 1175, 0.22, 1.0, 0.0]], 0.24, 0.0, 0.03, 0.03),
		"bounce": Sfx.voice([[180, 520, 0.16, 0.9, 0.0], [520, 380, 0.12, 0.5, 0.0]], 0.18, 0.0, 0.02, 0.02),
		"powerup": Sfx.voice([[660, 990, 0.12, 0.8, 0.0], [990, 1320, 0.18, 0.7, 0.0]], 0.2, 0.0, 0.02, 0.02),
		# Fear: a hellish shriek.
		"fear": Sfx.voice([[260, 880, 0.12, 1.0, 0.0], [880, 640, 0.25, 1.0, 0.0], [640, 150, 0.45, 0.9, 0.0]], 0.28, 0.7, 0.08, 0.06),
		# We got hit (as a demon): a gravelly grunt.
		"hurt": Sfx.voice([[240, 150, 0.16, 1.0, 0.0], [150, 120, 0.08, 0.6, 0.0]], 0.3, 0.75, 0.06, 0.04),
	}
	for kind in Blessings.names():
		streams["throw_" + kind] = BlessingSounds.throw(kind)
	for sound_name in streams:
		var asp := AudioStreamPlayer.new()
		asp.max_polyphony = 4   # overlapping plays layer instead of cutting off
		asp.stream = streams[sound_name]
		asp.bus = Sfx.BUS
		if sound_name.begins_with("throw_"):
			asp.volume_db = -4.0   # throws happen constantly: keep them in the background
		add_child(asp)
		_sounds[sound_name] = asp
	# Flying: a wing-beat loop that plays while the Fly skill is on (in the air or not).
	_fly_sound = AudioStreamPlayer.new()
	_fly_sound.stream = Sfx.fly_loop()
	_fly_sound.bus = Sfx.BUS
	_fly_sound.volume_db = -80.0
	add_child(_fly_sound)


# Fade the flying loop in while we fly, and out when we stop.
func _update_fly_sound(delta: float) -> void:
	var on: bool = player.flying and mode != "menu"
	if on and not _fly_sound.playing:
		_fly_sound.play()
	var target := -6.0 if on else -60.0
	_fly_sound.volume_db = move_toward(_fly_sound.volume_db, target, delta * (90.0 if on else 60.0))
	if not on and _fly_sound.playing and _fly_sound.volume_db <= -59.0:
		_fly_sound.stop()


func _play(sound_name: String) -> void:
	var asp: AudioStreamPlayer = _sounds[sound_name]
	# A little random pitch each time so repeated sounds don't feel robotic.
	asp.pitch_scale = randf_range(0.94, 1.06)
	asp.play()


# A redeemed demon goes off like a bomb (demon_blast.gd): fire, a shockwave, flying chunks, a boom, the
# camera shaking if you're close, and loose props blown away. Every screen runs the same thing.
const DemonBlast = preload("res://scripts/demon_blast.gd")
const BLAST_RADIUS := 4.5        # props within this get blown back (first guess)
const BLAST_SHOVE := 7.0


# A blessing hit a demon: a small burst of fire and sparks there, on every screen.
# A blessing (or book) hit a disguised demon: it's shoved like the prop it looks like would be (Ted, Nov 27:
# "props and demons-as-props can be knocked over by... projectiles").
func shove_hit(thing: Node, shot_velocity: Vector3) -> void:
	if is_authority() and is_instance_valid(thing) and not thing is BotDemon:   # (players; practice bots stay put)
		var flat := Vector3(shot_velocity.x, 0.0, shot_velocity.z)
		bump(thing, flat.normalized() * minf(flat.length() * 0.02, 1.6), null)   # (a blessing is light: a nudge)


func demon_hit_fx(pos: Vector3) -> void:
	if is_authority():
		broadcast_fx("hit_blast", [pos])


func demon_explosion(pos: Vector3) -> void:
	var b := DemonBlast.new()
	add_child(b)
	b.global_position = pos
	var asp: AudioStreamPlayer = _sounds["boom"]
	asp.play()   # (no random pitch: _play's would use the shared random numbers)
	var d := player.global_position.distance_to(pos)
	if d < 16.0:
		player.shake(lerpf(0.6, 0.1, d / 16.0))
	if round_root:
		_blast_props(pos, BLAST_RADIUS, BLAST_SHOVE)


# Our throw hit a demon: ding, and flash a red X on the crosshair.
func _on_hit_confirmed() -> void:
	_play("hit")
	_hitmarker_time = 0.3
	if mode == "practice":
		powerups.angels_made_progress()


func _on_taunted(taunt_name: String) -> void:
	taunt_label.text = "\"%s\"" % Taunts.label(taunt_name)
	_taunt_label_time = 1.5
	if net:
		net.on_local_taunt(taunt_name)


# Demons who sit still too long during the hunt taunt anyway (the host decides when).
func still_warning(seconds: float) -> void:
	_toast("Holding very still... move within %d s or you'll taunt!" % int(seconds), seconds)


func forced_taunt(taunt_name: String) -> void:
	player.forced_taunt(taunt_name)
	_toast("You sat still too long, so you taunted!", 2.5)


func _toast(text: String, seconds: float) -> void:
	center_label.text = text
	_toast_time = seconds


func _update_hud(delta: float) -> void:
	# Standing at the shrine: say how to use it.
	var at_shrine := (state == State.HIDING or state == State.HUNTING) and near_shrine(player.global_position) \
			and not player.frozen
	if at_shrine and not _was_at_shrine and not shrine_panel.visible:
		_toast("Press %s to swap your skills" % Keybinds.key_name("shrine") + (" (leave your prop first)" if player.possessed_type != "" else ""), 2.5)
	_was_at_shrine = at_shrine
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
	status_label.text = text

	_hurt_time -= delta
	hurt_rect.color.a = clampf(_hurt_time, 0.0, 0.25) * 1.4
	heat_rect.visible = player.burning > 0.0
	if heat_rect.visible:
		(heat_rect.material as ShaderMaterial).set_shader_parameter("strength", clampf(player.burning / Skills.fire_linger(), 0.25, 1.0))
	if player.burning > 0.0:   # standing in demon fire: orange glow at the edges of sight
		hurt_rect.color = Color(1.0, 0.45, 0.05, maxf(hurt_rect.color.a, 0.18 + sin(Time.get_ticks_msec() * 0.02) * 0.05))
	else:
		hurt_rect.color = Color(0.9, 0.05, 0.05, hurt_rect.color.a)

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
	_bonus_time -= delta
	bonus_label.modulate.a = clampf(_bonus_time, 0.0, 1.0)
	# Power-ups we have going, and Cherub Sense's alarm around us.
	effect_icons.visible = in_game
	effect_icons.show_effects(_my_effects())
	_update_fly_sound(delta)
	# Our own aura, the same as everyone else sees on us (not in first person: it'd
	# be in our face; and never while disguised or invisible, like for everyone).
	if my_aura == null:
		my_aura = Aura.new()
		player.add_child(my_aura)
	var show_aura: bool = in_game and not player.first_person[player.role] and player.possessed_type == "" and player.vanish_time <= 0.0
	my_aura.set_kind(Aura.shown_kind(player.powerups) if show_aura else "")
	powerup_label.text = ""   # (power-ups show as icons in the top-right now)
	_update_sense_bubble(delta)
	skill_label.visible = in_game
	skill_label.text = _skill_text()

	# Health: the bar shows how much is left, the number shows real hit points for
	# the current form (a hay bale has more to lose than a stack of books).
	var health_row: Control = bar_fills["health"][0].get_parent().get_parent()
	health_row.visible = mode == "online" and role == "demon"
	if health_row.visible:
		var max_hp := PropLib.max_hp(player.possessed_type)
		# The bar's right end is 150% (the most a demon can heal up to); over 100% it glows green.
		var over := my_health > 1.001
		_set_bar("health", "Health", my_health / PowerUps.MAX_HEALTH, Color(0.3, 0.85, 0.35) if over else Color.TRANSPARENT,
				"%d / %d" % [int(ceil(my_health * max_hp)), max_hp])

	var sprint_color := Color(0.85, 0.35, 0.3) if player._sprint_exhausted else Color(0.4, 0.85, 0.45)
	_set_bar("sprint", "Sprint", player.sprint_stamina / player.SPRINT_MAX, sprint_color)
	if role == "angel":
		var low := player.throw_stamina < player.throw_cost()
		_set_bar("power", "Blessing", player.throw_stamina / player.THROW_STAMINA_MAX,
				Color(0.6, 0.5, 0.25) if low else Color(1.0, 0.85, 0.3))
	else:
		_set_bar("power", "Hatred", player.hatred / player.HATRED_MAX, Color(0.8, 0.12, 0.12))

	hold_bar.visible = player.hold_fraction > 0.0
	hold_fill.size.x = 80.0 * player.hold_fraction
	if player.hold_fraction > 0.0:
		hint_label.text = ""
	elif role == "demon" and player.look_target_type != "" and in_game:
		# (clicking makes you a copy; only the Possess skill takes over the real thing: Wife's notes, Nov 21)
		var what := PropLib.label(player.look_target_type)
		hint_label.text = "Click: become a copy of the %s" % what
		if loadout.get("demon", []).has("possess"):
			var slot: int = loadout["demon"].find("possess")
			hint_label.text += "
%s: possess it" % Keybinds.key_name("skill_1" if slot == 0 else "rmb")
	else:
		hint_label.text = ""
	# What you look like right now, top left
	disguise_label.text = "Disguised as: %s" % PropLib.label(player.possessed_type) 			if role == "demon" and in_game and player.possessed_type != "" else ""
