# The angels' Alarm Cherub. Normally it just hovers there, tooting its little horn
# now and then. If a demon is inside the detection radius, a bubble swells out to
# the radius and back, over and over, and it blasts the horn and flaps like mad.
# Gone after 9 seconds.
# It has a real collision box: hit it with a blessing and it skids off in that
# direction (handy for checking down a hallway). The host (or the practice game)
# decides the kick and tells everyone, so every screen shows it in the same place.
# Whether a demon is near is decided by the host (or the practice game) and
# set through `alarmed`; the cherub itself never knows where demons are.
# While alarmed it creeps, very slowly, toward the demon: the host only hands it
# a direction to drift in (`creep`), which is no more than watching it shows anyway.
extends CharacterBody3D

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")
const CherubModel = preload("res://scripts/cherub_model.gd")

var cherub_id := 0
var alarmed := false
var creep := Vector3.ZERO    # the slow drift toward a noticed demon (flat, m/s); zero when calm
var on_kick: Callable        # set only where kicks are decided (host / practice)
var on_bounce: Callable      # the same, for landing on a bouncy pad
var _life := Skills.CHERUB_LIFETIME
var _phase := 0.0
var _bubble: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _body: Node3D
var _voice: AudioStreamPlayer3D
var _wings := []
var _legs := []
var _cheeks := []
var _halo: Node3D
var _puff := 0.0
var _alarm_timer := 0.0
var _toot_timer := 1.5

static var _alarm: AudioStreamWAV
static var _toot: AudioStreamWAV


func _ready() -> void:
	if _alarm == null:
		# A tiny brass horn: a soft "doo-doot" when calm, frantic fanfare blasts when alarmed.
		_alarm = Sfx.voice([[784, 784, 0.09, 1.0, 0.02], [988, 988, 0.09, 1.0, 0.02], [1175, 1175, 0.22, 1.0, 0.0]], 0.24, 0.0, 0.03, 0.03)
		_toot = Sfx.voice([[587, 587, 0.1, 0.7, 0.05], [784, 784, 0.16, 0.7, 0.0]], 0.13, 0.0, 0.02, 0.025)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.0, 0.6)
	shape.shape = box
	shape.position.y = 0.5
	add_child(shape)
	floor_snap_length = 0.2
	collision_mask = 1 | 2   # stays inside the map's invisible walls
	_body = Node3D.new()      # everything you see; it hovers and bobs above the collision box
	add_child(_body)
	var model := CherubModel.make()
	_body.add_child(model["root"])
	_wings = model["wings"]
	_legs = model["legs"]
	_cheeks = model["cheeks"]
	_halo = model["halo"]

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
	_bubble.position.y = 0.5
	add_child(_bubble)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 8.0
	_voice.max_distance = 80.0
	_voice.position.y = 0.4
	add_child(_voice)
	_voice.stream = _toot
	_voice.play()


# A blessing hit us. Only the decider acts on it; everyone else just saw a puff.
func kick(projectile_velocity: Vector3) -> void:
	if on_kick.is_valid():
		on_kick.call(cherub_id, projectile_velocity)


# It landed on a bouncy pad. Like a kick, only the decider acts on it (and tells
# everyone); on other screens it waits a moment for that.
func bounce_from(pad_position: Vector3, up_speed: float) -> bool:
	if not on_bounce.is_valid():
		return false
	on_bounce.call(cherub_id, pad_position, up_speed)
	return true


func launch(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	velocity = vel


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		var flat := Vector3(velocity.x, 0, velocity.z)
		flat = flat.move_toward(creep, Skills.CHERUB_FRICTION * delta)   # a kick wears off; the creep doesn't
		velocity.x = flat.x
		velocity.z = flat.z
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed > 0.15:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z) + PI, 0.3)
	move_and_slide()
	# Never sit on anyone's head: hop off sideways.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		var is_someone: bool = other != null and (other is CharacterBody3D or other.get("eid") != null or other.is_in_group("demon"))
		# A demon disguised as a prop is just a prop here (anything else would give it away).
		if is_someone and (str(other.get("form")) not in ["", "<null>"] or str(other.get("possessed_type")) not in ["", "<null>"] or other.is_in_group("demon")):
			is_someone = false
		if col.get_normal().y > 0.6 and is_someone:
			var away := Vector3(global_position.x - other.global_position.x, 0.0, global_position.z - other.global_position.z)
			if away.length() < 0.05:
				away = Vector3.RIGHT
			velocity = away.normalized() * 3.0 + Vector3.DOWN
			break


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Swell out to the radius and back: 1.6 s per cycle, twice as fast when alarmed.
	_phase += delta * (1.25 if alarmed else 0.625)
	var t := 1.0 - absf(fmod(_phase, 1.0) * 2.0 - 1.0)   # 0 -> 1 -> 0
	var r := maxf(Skills.CHERUB_RADIUS * t, 0.05)
	_bubble.scale = Vector3.ONE * r
	_bubble.visible = alarmed           # no bubble unless a demon is close
	_bubble_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.22)
	# Hover and flap: gentle when calm, frantic when a demon is close.
	var now := Time.get_ticks_msec() / 1000.0
	var flap := sin(now * (30.0 if alarmed else 9.0))
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation.z = (0.1 + flap * (0.5 if alarmed else 0.3)) * side      # up and down
		_wings[i].rotation.y = flap * 0.15 * side                                    # and a little back and forth
	# Legs paddle lazily when calm and pedal like mad when alarmed.
	for i in _legs.size():
		_legs[i].rotation.x = sin(now * (14.0 if alarmed else 2.6) + i * PI) * (0.45 if alarmed else 0.18)
	# Cheeks puff out while the horn is sounding.
	_puff = move_toward(_puff, 1.0 if _voice.playing else 0.0, delta * 8.0)
	for cheek in _cheeks:
		cheek.scale = Vector3.ONE * (1.0 + 0.3 * _puff)
	_halo.position.y = 1.07 + sin(now * 3.1) * 0.012
	_body.position.y = 0.15 + sin(now * 2.2) * 0.06
	if alarmed:
		_body.position.y += absf(sin(_phase * 12.0)) * 0.12
		_alarm_timer -= delta
		if _alarm_timer <= 0.0:
			_alarm_timer = 0.6
			_voice.stream = _alarm
			_voice.pitch_scale = randf_range(0.97, 1.05)
			_voice.play()
	else:
		_toot_timer -= delta
		if _toot_timer <= 0.0:
			_toot_timer = randf_range(2.0, 3.5)
			_voice.stream = _toot
			_voice.pitch_scale = randf_range(0.95, 1.05)
			_voice.play()
