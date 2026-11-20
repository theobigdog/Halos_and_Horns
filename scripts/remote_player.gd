# Another player in an online match, as seen on this computer.
# Smoothly follows the positions the network sends, shows an angel, demon or
# possessed prop, and has collision so throws (on the host) can hit it.
#
# Anti-cheat: it only knows a player's name if that player is on YOUR team.
# A disguised demon seen by an angel is just an id, a position and a prop type.
extends AnimatableBody3D

const Characters = preload("res://scripts/characters.gd")
const Effects = preload("res://scripts/effects.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Bodies = preload("res://scripts/bodies.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Taunts = preload("res://scripts/taunts.gd")
const Aura = preload("res://scripts/aura.gd")

var eid := 0                  # entity id for this round (not the player's network id)
var role := ""
var form := ""                # possessed prop type, "" = body form
var outfit := {}               # how their body looks (from the host; characters.gd)
var player_name := ""         # only set for teammates
var team := ""                # side, as the host's roster told us (arrives with the name)
var snap := false             # host: jump straight to reported positions (hits must be exact)
var net                       # the multiplayer controller (host only uses it for hits)

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _visual: Node3D
var _shape: CollisionShape3D
var _nameplate: Label3D
var _voice: AudioStreamPlayer3D
var _wings: AudioStreamPlayer3D   # flying: wing beats everyone around can hear
var _flames: CPUParticles3D        # ...and hellfire licking out from under it
static var _wing_loop: AudioStreamWAV
var _has_state := false
# Smooth movement: we show other players a tenth of a second in the past, sliding
# between the last two positions we got, instead of chasing the newest one (which
# arrives in uneven bursts and made props look skippy).
const INTERP_DELAY := 0.1
var _snaps := []          # [time received, position, yaw], oldest first
var _plate_h := 2.0       # nameplate height above the feet
var _aura: Node3D         # power-up particles (aura.gd); the host says which


func _ready() -> void:
	sync_to_physics = false
	_shape = CollisionShape3D.new()
	# No body until we know where it is: created at the map's center, a solid
	# body would sit on whoever is standing there (the demon spawn!) and then
	# fling them across the map when it snaps to its real position.
	_shape.disabled = true
	visible = false
	add_child(_shape)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 6.0
	_voice.max_distance = 70.0
	_voice.position.y = 0.8
	add_child(_voice)
	_nameplate = Label3D.new()
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = true    # teammates see each other through walls
	_nameplate.fixed_size = true
	_nameplate.pixel_size = 0.0012
	_nameplate.font_size = 28
	_nameplate.outline_size = 8
	add_child(_nameplate)
	_aura = Aura.new()
	add_child(_aura)
	_rebuild()


# Flying (the host says): loud wing beats from wherever it is, disguised or not.
func set_crouch(on: bool) -> void:
	if _visual and _visual.get("crouching") != null:
		_visual.crouching = on


# The host told us how this player (or minion) looks.
func set_outfit(o: Dictionary) -> void:
	if o == outfit:
		return
	outfit = o
	if form == "" and role != "":
		_rebuild()


func set_flying(on: bool) -> void:
	on = on and not _vanished
	if _visual and _visual.get("flying") != null:
		_visual.flying = on
	if on and _wings == null:
		if _wing_loop == null:
			_wing_loop = Sfx.fly_loop()
		_wings = AudioStreamPlayer3D.new()
		_wings.bus = Sfx.BUS
		_wings.stream = _wing_loop
		_wings.unit_size = 10.0       # (first guess) loud enough to hear across a room
		_wings.max_distance = 60.0
		_wings.volume_db = 3.0
		add_child(_wings)
		_flames = Effects.fly_flames()
		add_child(_flames)
		_flames.position.y = 0.1
		Effects.tint_flames(_flames, Characters.trail_color("demon", outfit))
	if _flames:
		_flames.emitting = on
	if _wings:
		if on and not _wings.playing:
			_wings.play()
		elif not on and _wings.playing:
			_wings.stop()


# Which power-up's aura to show ("" for none). Never anything while it's vanished.
func set_aura(kind: String) -> void:
	if _aura:
		var k := "" if _vanished else kind
		if k != _aura.kind and k != "":
			print("[aura] %s (%s) shows %s" % [role, form if form != "" else "own body", k])
		_aura.set_kind(k)


func set_name_for_teammate(n: String) -> void:
	player_name = n
	if _nameplate:
		_nameplate.text = n


# Invisible demon (Invisibility): gone from view until updates about it resume.
# (Only seen by angels: they also stop getting its position meanwhile.)
var _vanished := false
var _vanish_left := 0.0


func vanish(seconds := 7.0) -> void:
	_vanished = true
	_vanish_left = seconds
	if _aura:
		_aura.set_kind("")
	if _visual:
		_visual.visible = false
	_nameplate.visible = false
	if not snap:
		_shape.disabled = true   # nothing there to bump into on this screen


func apply_state(pos: Vector3, yaw: float, new_form: String, new_role: String) -> void:
	if _vanished and not snap:
		_unvanish()
		_snaps.clear()            # reappear where it is now, no slide from where it vanished
	_target_pos = pos
	_target_yaw = yaw
	var t := Time.get_ticks_msec() / 1000.0
	# Snap on big jumps (respawns, teleports): sliding across the map would drag
	# anyone in the way along with it.
	var jump := _snaps.is_empty() or (_snaps[-1][1] as Vector3).distance_to(pos) > 3.0
	if not _has_state or jump:
		_snaps.clear()
		global_position = pos
		rotation.y = yaw
		if _visual:
			_visual.top_level = false
		if not _has_state:
			_has_state = true
			_shape.disabled = false
			visible = true
	_snaps.append([t, pos, yaw])
	while _snaps.size() > 20:
		_snaps.pop_front()
	if snap:
		# The host's copy: the body sits exactly where the player last said (hits are
		# judged here), while what the host SEES slides smoothly like everyone else.
		global_position = pos
		rotation.y = yaw
	if new_form != form or new_role != role:
		form = new_form
		role = new_role
		_rebuild()


func _unvanish() -> void:
	_vanished = false
	if _visual:
		_visual.visible = true
	_nameplate.visible = true
	_shape.disabled = false


func _rebuild() -> void:
	if _visual:
		_visual.queue_free()
	if role == "":
		return
	var h: float
	if form != "":
		_visual = PropLib.make_visual(form)
		_shape.shape = PropLib.make_shape(form)
		h = PropLib.height(form)
	else:
		_visual = Bodies.make(role, outfit)
		_shape.shape = Bodies.make_shape(role)
		h = Bodies.height_for(role)
	_shape.position.y = h / 2.0
	add_child(_visual)
	_plate_h = h + 0.35
	_nameplate.position = Vector3(0, _plate_h, 0)
	_nameplate.text = player_name
	_nameplate.modulate = Color(1.0, 0.92, 0.6) if role == "angel" else Color(1.0, 0.5, 0.45)


# Where this player was INTERP_DELAY seconds ago, between the two updates around then.
func _smoothed() -> Array:
	var rt := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	if _snaps.size() == 1 or rt <= _snaps[0][0]:
		return [_snaps[0][1], _snaps[0][2]]
	for i in range(_snaps.size() - 1, 0, -1):
		var a: Array = _snaps[i - 1]
		var b: Array = _snaps[i]
		if rt >= a[0]:
			if rt >= b[0]:
				return [b[1], b[2]]   # nothing newer yet: hold the latest
			var f: float = (rt - a[0]) / maxf(b[0] - a[0], 0.001)
			return [(a[1] as Vector3).lerp(b[1], f), lerp_angle(a[2], b[2], f)]
	return [_snaps[-1][1], _snaps[-1][2]]


func _physics_process(delta: float) -> void:
	if _vanished:
		_vanish_left -= delta
		if _vanish_left <= 0.0:
			_unvanish()
		elif _visual:
			_visual.visible = false
	if not _has_state or _snaps.is_empty():
		return
	var sm := _smoothed()
	if snap:
		# Host: only the look is smoothed; the body stays exact for hit checks.
		if _visual:
			_visual.top_level = true
			_visual.global_position = sm[0]
			_visual.global_rotation = Vector3(0, sm[1], 0)
			_nameplate.global_position = sm[0] + Vector3.UP * _plate_h
		return
	global_position = sm[0]
	rotation.y = sm[1]


func play_taunt(taunt_name: String) -> void:
	_voice.stream = Taunts.stream(taunt_name)
	_voice.pitch_scale = randf_range(0.96, 1.04)
	_voice.play()


# Host only: a real projectile hit this player.
func take_hit(damage: int, by: Node = null) -> bool:
	if net == null or role != "demon":
		return false
	return net.on_remote_hit(self, damage, by)


# Host only: a projectile this player threw hit a demon.
func confirm_hit() -> void:
	if net:
		net.on_remote_confirm(self)
