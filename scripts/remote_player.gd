# Another player in an online match, as seen on this computer.
# Smoothly follows the positions the network sends, shows an angel, demon or
# possessed prop, and has collision so throws (on the host) can hit it.
#
# Anti-cheat: it only knows a player's name if that player is on YOUR team.
# A disguised demon seen by an angel is just an id, a position and a prop type.
extends AnimatableBody3D

const PropLib = preload("res://scripts/prop_library.gd")
const Bodies = preload("res://scripts/bodies.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Taunts = preload("res://scripts/taunts.gd")

var eid := 0                  # entity id for this round (not the player's network id)
var role := ""
var form := ""                # possessed prop type, "" = body form
var player_name := ""         # only set for teammates
var snap := false             # host: jump straight to reported positions (hits must be exact)
var net                       # the multiplayer controller (host only uses it for hits)

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _visual: Node3D
var _shape: CollisionShape3D
var _nameplate: Label3D
var _voice: AudioStreamPlayer3D
var _has_state := false


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
	_rebuild()


func set_name_for_teammate(n: String) -> void:
	player_name = n
	if _nameplate:
		_nameplate.text = n


func apply_state(pos: Vector3, yaw: float, new_form: String, new_role: String) -> void:
	_target_pos = pos
	_target_yaw = yaw
	# Snap on big jumps (respawns, teleports): sliding across the map would drag
	# anyone in the way along with it.
	if not _has_state or snap or global_position.distance_to(pos) > 3.0:
		global_position = pos
		rotation.y = yaw
		if not _has_state:
			_has_state = true
			_shape.disabled = false
			visible = true
	if new_form != form or new_role != role:
		form = new_form
		role = new_role
		_rebuild()


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
		_visual = Bodies.make(role)
		_shape.shape = Bodies.make_shape(role)
		h = Bodies.height_for(role)
	_shape.position.y = h / 2.0
	add_child(_visual)
	_nameplate.position.y = h + 0.35
	_nameplate.text = player_name
	_nameplate.modulate = Color(1.0, 0.92, 0.6) if role == "angel" else Color(1.0, 0.5, 0.45)


func _physics_process(delta: float) -> void:
	if not _has_state or snap:
		return
	var w := 1.0 - exp(-15.0 * delta)   # smooth out network jitter
	global_position = global_position.lerp(_target_pos, w)
	rotation.y = lerp_angle(rotation.y, _target_yaw, w)


func play_taunt(taunt_name: String) -> void:
	_voice.stream = Taunts.stream(taunt_name)
	_voice.pitch_scale = randf_range(0.96, 1.04)
	_voice.play()


# Host only: a real projectile hit this player.
func take_hit(damage: int) -> bool:
	if net == null or role != "demon":
		return false
	return net.on_remote_hit(self, damage)


# Host only: a projectile this player threw hit a demon.
func confirm_hit() -> void:
	if net:
		net.on_remote_confirm(self)
