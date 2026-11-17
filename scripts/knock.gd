# A loose prop getting shoved: it slides, hops, wobbles, tips over (tall things),
# or rolls (round things), bumps off walls, and settles.
#
# This isn't the physics engine. It's a small, simple simulation that every computer
# runs from the same push, so everyone sees the same thing. Only the host decides
# pushes (blessing hits, melee, kicks, chain bumps), and when a prop comes to rest
# the host sends where it ended up, which fixes any tiny difference between screens.
#
# Demons disguised as props are players, not props, so none of this touches them:
# what a real prop does is never a clue about a demon (beyond what a hit already says).
extends Node

const PropLib = preload("res://scripts/prop_library.gd")
const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")

# All first guesses, for the group to test.
const GRAVITY := 16.0
const FRICTION := 8.0           # m/s of sliding speed lost per second on the ground
const ROLL_FRICTION := 1.6      # round things roll on much further
const LYING_FRICTION := 5.0     # tipped-over things scrape along
const WALL_BOUNCE := 0.35       # share of speed kept bouncing off a wall
const TIP_BASE := 3.0           # push speed (m/s) that tips a prop as wide as it is tall
const WOBBLE_SPRING := 70.0
const WOBBLE_DAMP := 7.0
const WOBBLE_MAX := 0.3         # radians
const CHAIN_SPEED := 2.5        # sliding into another prop this fast shoves it too
const MAX_TIME := 8.0           # give up and settle after this long, whatever happens

static var _thud: AudioStreamWAV

var main: Node                  # main.gd (decides chain bumps and sends the resting spot)
var prop: StaticBody3D
var index := -1
var type_name := ""
var vel := Vector3.ZERO
var pos := Vector3.ZERO         # the prop's origin
var basis := Basis.IDENTITY
var ground_offset := 0.0        # how far the origin sits above the floor (more once tipped over)
var tipped := false
var _tip_dir := Vector3.ZERO    # which way it's falling over
var _tilt := 0.0
var _tilt_vel := 0.0
var _pivot := Vector3.ZERO
var _wobble := 0.0
var _wobble_vel := 0.0
var _wobble_dir := Vector3.ZERO
var _rolling := Basis.IDENTITY  # round things: how the visual has turned while rolling
var _visual: Node3D
var _still := 0.0
var _life := 0.0
var _voice: AudioStreamPlayer3D
var _chained := {}              # props we already bumped this time (no ping-pong)


# Get the knock state for a prop, starting it if needed.
static func on(the_main: Node, the_prop: StaticBody3D, the_index: int) -> Node:
	var k := the_prop.get_node_or_null("Knock")
	if k:
		return k
	k = load("res://scripts/knock.gd").new()
	k.name = "Knock"
	k.main = the_main
	k.prop = the_prop
	k.index = the_index
	the_prop.add_child(k)
	return k


func _ready() -> void:
	type_name = prop.get_meta("prop_type", "")
	pos = prop.global_position
	basis = prop.global_transform.basis.orthonormalized()
	# Already lying down (knocked over earlier, or we joined after it was)?
	tipped = PropLib.TYPES.get(type_name, {}).get("lying", false) or basis.y.dot(Vector3.UP) < 0.7
	ground_offset = prop.get_meta("ground_offset", 0.0)
	_visual = prop.get_child(0) as Node3D
	if _thud == null:
		_thud = Sfx.voice([[120, 70, 0.07, 1.0, 0.0]], 0.35, 0.6, 0.02, 0.0)
	_voice = AudioStreamPlayer3D.new()
	_voice.stream = _thud
	_voice.bus = Sfx.BUS
	_voice.unit_size = 5.0
	_voice.max_distance = 45.0
	add_child(_voice)


func _round() -> bool:
	return PropLib.TYPES.get(type_name, {}).get("round", false)


func _radius() -> float:
	return PropLib.half_width(type_name) if PropLib.TYPES.has(type_name) else 0.4


func _height() -> float:
	return PropLib.height(type_name) if PropLib.TYPES.has(type_name) else 1.0


# A shove: `impulse` is a velocity change for a prop of mass 1 (heavier props move less).
func hit(impulse: Vector3) -> void:
	set_physics_process(true)
	var dv := impulse / PropLib.mass(type_name)
	vel += dv
	_still = 0.0
	_life = 0.0
	var flat := Vector3(dv.x, 0.0, dv.z)
	var speed := flat.length()
	if speed < 0.05 or tipped or _round() or _tilt > 0.0:
		return
	# Tall, narrow things go over easily; squat, wide ones mostly wobble.
	var tip_speed := clampf(TIP_BASE * (_radius() * 2.0) / _height(), 0.9, 6.0)
	if speed >= tip_speed:
		_tip_dir = flat / speed
		_tilt_vel = 2.0 + (speed - tip_speed) * 0.7
		_wobble = 0.0
		_wobble_vel = 0.0
	else:
		_wobble_dir = flat / speed
		_wobble_vel += speed / tip_speed * 5.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(prop) or not prop.is_in_group("prop"):
		queue_free()   # possessed or gone: a demon has it now
		return
	_life += delta
	var flat := Vector3(vel.x, 0.0, vel.z)
	var speed := flat.length()

	# Sideways: slide or roll, stopping at walls and other props.
	if speed > 0.001:
		var move := flat * delta
		var probe_y := pos.y - ground_offset + minf(_height(), 0.6) * 0.5
		var from := Vector3(pos.x, probe_y, pos.z)
		var hit := _cast(from, from + move + flat / speed * _radius())
		if hit.is_empty():
			pos += move
		else:
			var n: Vector3 = hit["normal"]
			n.y = 0.0
			n = n.normalized() if n.length() > 0.01 else -flat / speed
			var other: Object = hit["collider"]
			if other is StaticBody3D and other.is_in_group("prop") and speed > CHAIN_SPEED:
				_shove_other(other, flat)
			flat = (flat - 2.0 * flat.dot(n) * n) * WALL_BOUNCE   # bounce off
			vel.x = flat.x
			vel.z = flat.z
			if speed > 1.5:
				_thump(minf(speed / 6.0, 1.0))
		var rolled := flat.length()   # (after any bounce off a wall)
		if _round() and rolled > 0.001:
			var axis := (basis.inverse() * Vector3.UP.cross(flat / rolled)).normalized()
			_rolling = Basis(axis, rolled * delta / _radius()) * _rolling

	# Up and down: fall onto whatever is below.
	var floor_y := _floor_below()
	var bottom := pos.y - ground_offset
	vel.y -= GRAVITY * delta
	bottom += vel.y * delta
	var on_ground := false
	if bottom <= floor_y:
		bottom = floor_y
		if vel.y < -3.0:
			_thump(minf(-vel.y / 10.0, 1.0))
			vel.y = -vel.y * 0.25   # a little hop
		else:
			vel.y = 0.0
			on_ground = true
	pos.y = bottom + ground_offset

	# Friction while on the ground.
	if on_ground and speed > 0.0:
		var f := ROLL_FRICTION if _round() else (LYING_FRICTION if tipped else FRICTION)
		var slowed := maxf(speed - f * delta, 0.0)
		vel.x *= slowed / speed
		vel.z *= slowed / speed

	# Tipping over: it falls faster the further it leans.
	if _tilt_vel > 0.0:
		_tilt_vel += 9.0 * sin(_tilt + 0.2) * delta
		_tilt += _tilt_vel * delta
		vel.x *= 0.96
		vel.z *= 0.96
		if _tilt >= PI / 2.0:
			_finish_tipping()
	# Wobbling: a springy rock back and forth that dies away.
	if _wobble != 0.0 or _wobble_vel != 0.0:
		_wobble_vel += (-WOBBLE_SPRING * _wobble - WOBBLE_DAMP * _wobble_vel) * delta
		_wobble = clampf(_wobble + _wobble_vel * delta, -WOBBLE_MAX, WOBBLE_MAX)
		if absf(_wobble) < 0.002 and absf(_wobble_vel) < 0.02:
			_wobble = 0.0
			_wobble_vel = 0.0

	_apply()

	# At rest?
	var moving := Vector2(vel.x, vel.z).length() > 0.05 or not on_ground or _tilt_vel > 0.0 or _wobble_vel != 0.0
	_still = 0.0 if moving else _still + delta
	if _still > 0.25 or _life > MAX_TIME:
		_settle()


# The bottom edge it's falling over on (it moves along with the prop if it slides).
func _update_pivot() -> void:
	_pivot = Vector3(pos.x, pos.y - ground_offset, pos.z) + _tip_dir * _radius()


func _finish_tipping() -> void:
	# Bake the fall into the prop's resting pose: it now lies on its side.
	_update_pivot()
	var r := Basis(Vector3.UP.cross(_tip_dir).normalized(), PI / 2.0)
	pos = _pivot + r * (pos - _pivot)
	basis = r * basis
	ground_offset = pos.y - _pivot.y
	_tilt = 0.0
	_tilt_vel = 0.0
	tipped = true
	_thump(0.8)
	if main:
		Effects.dust(main.fx_parent(), Vector3(pos.x, _pivot.y, pos.z), _height() * 0.5, 10)


func _apply() -> void:
	var xf := Transform3D(basis, pos)
	if _tilt > 0.0:
		_update_pivot()
		var r := Basis(Vector3.UP.cross(_tip_dir).normalized(), _tilt)
		xf = Transform3D(r, _pivot - r * _pivot) * xf
	elif _wobble != 0.0:
		# rock on the bottom edge it's leaning toward
		var lean := _wobble_dir if _wobble > 0.0 else -_wobble_dir
		var edge := Vector3(pos.x, pos.y - ground_offset, pos.z) + lean * _radius()
		var r := Basis(Vector3.UP.cross(lean).normalized(), absf(_wobble))
		xf = Transform3D(r, edge - r * edge) * xf
	prop.global_transform = xf
	if _round() and _visual:
		# Spin the look around its middle; the collision shape stays put.
		var c := Vector3(0.0, _height() / 2.0, 0.0)
		_visual.transform = Transform3D(_rolling, c - _rolling * c)


func _settle() -> void:
	set_physics_process(false)
	_wobble = 0.0
	_tilt = 0.0
	_apply()
	prop.set_meta("moved_to", prop.global_position)
	prop.set_meta("moved_basis", prop.global_transform.basis)
	prop.set_meta("ground_offset", ground_offset)
	if main and main.is_authority():
		main.prop_rested(index, prop.global_transform, ground_offset)
	# Leave the node (and its sound) for a moment, then tidy up, unless it got
	# shoved again in the meantime.
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(self) and not is_physics_processing():
			queue_free())


func _thump(loudness: float) -> void:
	if _voice and not _voice.playing:
		_voice.volume_db = linear_to_db(clampf(loudness, 0.1, 1.0))
		_voice.pitch_scale = randf_range(0.85, 1.15) / sqrt(PropLib.mass(type_name))
		_voice.play()


func _shove_other(other: StaticBody3D, flat: Vector3) -> void:
	if not main or not main.is_authority() or _chained.has(other):
		return
	_chained[other] = true
	var i: int = other.get_meta("prop_index", -1)
	if i >= 0:
		main.knock_prop(i, flat * PropLib.mass(type_name) * 0.6)


# A ray against the world: map pieces and other props, never players (they see
# different positions on every screen) and never this prop itself.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space := prop.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var skip: Array[RID] = [prop.get_rid()]
	for attempt in 6:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty() or _solid(hit["collider"]):
			return hit
		skip.append(hit["rid"])
	return {}


# The map and props count; players, bots, minions and cherubs don't.
static func _solid(c: Object) -> bool:
	return c is StaticBody3D and not c is AnimatableBody3D and not c.has_method("take_hit")


func _floor_below() -> float:
	var top := Vector3(pos.x, pos.y - ground_offset + 0.4, pos.z)
	var hit := _cast(top, top + Vector3.DOWN * 30.0)
	return hit["position"].y if not hit.is_empty() else -50.0
