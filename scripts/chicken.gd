# The angels' Alarm Chicken. Normally just a chicken, clucking now and then.
# If a demon is inside the detection radius, a bubble swells out to the radius
# and back, over and over, and the chicken squawks and flaps. Gone after 9 seconds.
# It has a real collision box: hit it with a blessing and it skids off in that
# direction (handy for checking down a hallway). The host (or the practice game)
# decides the kick and tells everyone, so every screen shows it in the same place.
# Whether a demon is near is decided by the host (or the practice game) and
# set through `alarmed`; the chicken itself never knows where demons are.
extends CharacterBody3D

const Skills = preload("res://scripts/skills.gd")
const PropLib = preload("res://scripts/prop_library.gd")
const Sfx = preload("res://scripts/sfx.gd")

var chicken_id := 0
var alarmed := false
var on_kick: Callable        # set only where kicks are decided (host / practice)
var _life := Skills.CHICKEN_LIFETIME
var _phase := 0.0
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _body: Node3D
var _voice: AudioStreamPlayer3D
var _squawk_timer := 0.0
var _cluck_timer := 1.5

static var _squawk: AudioStreamWAV
static var _cluck: AudioStreamWAV


func _ready() -> void:
	if _squawk == null:
		_squawk = Sfx.voice([[900, 1300, 0.12, 1.0, 0.03], [1250, 800, 0.18, 0.9, 0.0]], 0.25, 0.3, 0.1)
		_cluck = Sfx.voice([[500, 420, 0.06, 0.6, 0.08], [520, 430, 0.06, 0.6, 0.0]], 0.18, 0.2, 0.05)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 0.75, 0.6)
	shape.shape = box
	shape.position.y = 0.375
	add_child(shape)
	floor_snap_length = 0.2
	_body = Node3D.new()
	add_child(_body)
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.4
	body.mesh = s
	body.material_override = PropLib.mat(Color(0.97, 0.95, 0.9))
	body.position.y = 0.3
	_body.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.11
	hs.height = 0.22
	head.mesh = hs
	head.material_override = PropLib.mat(Color(0.97, 0.95, 0.9))
	head.position = Vector3(0, 0.55, -0.12)
	_body.add_child(head)
	var comb := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.03, 0.08, 0.1)
	comb.mesh = cb
	comb.material_override = PropLib.mat(Color(0.9, 0.1, 0.1))
	comb.position = Vector3(0, 0.67, -0.12)
	_body.add_child(comb)
	var beak := MeshInstance3D.new()
	var bk := CylinderMesh.new()
	bk.top_radius = 0.0
	bk.bottom_radius = 0.035
	bk.height = 0.08
	beak.mesh = bk
	beak.material_override = PropLib.mat(Color(1.0, 0.75, 0.1))
	beak.rotation.x = -PI / 2
	beak.position = Vector3(0, 0.54, -0.25)
	_body.add_child(beak)

	_bubble = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 1.0
	bs.height = 2.0
	_bubble.mesh = bs
	_bubble_mat = StandardMaterial3D.new()
	_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble_mat.albedo_color = Color(1.0, 0.9, 0.2, 0.16)
	_bubble.material_override = _bubble_mat
	_bubble.position.y = 0.3
	add_child(_bubble)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 8.0
	_voice.max_distance = 80.0
	_voice.position.y = 0.4
	add_child(_voice)
	_voice.stream = _cluck
	_voice.play()


# A blessing hit us. Only the decider acts on it; everyone else just saw a puff.
func kick(projectile_velocity: Vector3) -> void:
	if on_kick.is_valid():
		on_kick.call(chicken_id, projectile_velocity)


func launch(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	velocity = vel


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		var flat := Vector3(velocity.x, 0, velocity.z)
		flat = flat.move_toward(Vector3.ZERO, Skills.CHICKEN_FRICTION * delta)
		velocity.x = flat.x
		velocity.z = flat.z
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, 0.3)
	move_and_slide()


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Swell out to the radius and back: 1.6 s per cycle, twice as fast when alarmed.
	_phase += delta * (1.25 if alarmed else 0.625)
	var t := 1.0 - absf(fmod(_phase, 1.0) * 2.0 - 1.0)   # 0 -> 1 -> 0
	var r := maxf(Skills.CHICKEN_RADIUS * t, 0.05)
	_bubble.scale = Vector3.ONE * r
	_bubble.visible = alarmed           # no bubble unless a demon is close
	_bubble_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.22)
	if alarmed:
		_body.position.y = absf(sin(_phase * 12.0)) * 0.12   # flapping panic hop
		_squawk_timer -= delta
		if _squawk_timer <= 0.0:
			_squawk_timer = 0.55
			_voice.stream = _squawk
			_voice.pitch_scale = randf_range(0.95, 1.08)
			_voice.play()
	else:
		_body.position.y = 0.0
		_cluck_timer -= delta
		if _cluck_timer <= 0.0:
			_cluck_timer = randf_range(1.5, 3.0)
			_voice.stream = _cluck
			_voice.pitch_scale = randf_range(0.9, 1.1)
			_voice.play()
