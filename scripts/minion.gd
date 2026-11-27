# A demon's Minion: a decoy that looks exactly like the demon did when it was
# made (its own body, or the prop it was disguised as) and moves by the same
# rules a player does: same speed for that form, same gravity and jump, it bumps
# into props and walls and can't fly or pass through anything.
#
# Only its owner runs this (the owner steers it); everyone else sees it the way
# they see any other player, through the host. Steering: while the owner holds
# the skill key, `target` follows the ground under their crosshair. Let go and
# it stops, then fidgets and wanders a little like a person waiting around.
extends CharacterBody3D

const PropLib = preload("res://scripts/prop_library.gd")
const Bodies = preload("res://scripts/bodies.gd")
const Effects = preload("res://scripts/effects.gd")
const Skills = preload("res://scripts/skills.gd")

var form := ""                 # prop type, or "" for a demon body
var outfit := {}                 # its owner's demon outfit
var speed := 6.5
var fall_gravity := 13.0
var jump_velocity := 5.6
var steering := false          # the owner is holding the key
var target := Vector3.ZERO     # where it's walking to
var life := Skills.minion_lifetime()
var on_hit: Callable           # practice / host-owned: an angel's hit landed on it

var _has_target := false
var _hop_timer := 3.0
var _fidget_timer := 1.5
var _stuck_time := 0.0


func _ready() -> void:
	add_to_group("snow_walker")
	collision_mask = 1 | 2      # the world, plus the invisible map walls
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var h: float
	if form != "":
		shape.shape = PropLib.make_shape(form)
		h = PropLib.height(form)
		add_child(PropLib.make_visual(form))
	else:
		shape.shape = Bodies.make_shape("demon")
		h = Bodies.height_for("demon")
		add_child(Bodies.make("demon", outfit))   # (dressed like its owner: it's a decoy)
	shape.position.y = h / 2.0
	add_child(shape)
	speed = PropLib.speed(form)


func bounce(up_speed: float) -> bool:
	velocity.y = up_speed
	return true


# The owner pressed the Minion jump key (Left Alt): hop now, if it's standing on something.
func jump() -> bool:
	if not is_on_floor():
		return false
	velocity.y = jump_velocity
	_hop_timer = randf_range(2.5, 6.0)
	return true


func walk_to(point: Vector3) -> void:
	target = point
	_has_target = true


func stop() -> void:
	steering = false
	_has_target = false
	_fidget_timer = randf_range(0.6, 2.0)


# A blessing (or anything else that hurts) hit it. Whoever decides hits treats it
# like a demon in that form (same health); when that runs out, it pops.
func take_hit(damage: int, by: Node = null) -> bool:
	if on_hit.is_valid():
		return on_hit.call(by, damage)
	return false


func pop() -> void:
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.6, Color(0.35, 0.05, 0.08, 0.8), 1.6)
	queue_free()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		pop()
		return
	var on_floor := is_on_floor()
	if not on_floor:
		var g := fall_gravity * (1.5 if velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta

	var want := Vector3.ZERO
	if _has_target:
		var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		if to.length() > 0.5:
			want = to.normalized() * speed
		elif not steering:
			_has_target = false     # arrived after a wander
	elif not steering:
		_idle(delta)

	# Accelerate and stop like a player does (not an instant glide).
	var flat := Vector2(velocity.x, velocity.z)
	var goal := Vector2(want.x, want.z)
	var rate := (45.0 if goal != Vector2.ZERO else 35.0) if on_floor else 12.0
	flat = flat.move_toward(goal, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.y

	if flat.length() > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.y), 10.0 * delta)
		# People hop now and then while running about, and when something's in the way.
		_hop_timer -= delta
		if on_floor and (_hop_timer <= 0.0 or (is_on_wall() and _stuck_time > 0.15)):
			velocity.y = jump_velocity
			_hop_timer = randf_range(2.5, 6.0)
		_stuck_time = _stuck_time + delta if is_on_wall() else 0.0
	move_and_slide()
	# Never stand on anyone's head: hop off sideways (same as players do).
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other == null or col.get_normal().y < 0.6:
			continue
		var someone: bool = other is CharacterBody3D or other.get("eid") != null or other.is_in_group("demon")
		if someone and (str(other.get("form")) not in ["", "<null>"] or str(other.get("possessed_type")) not in ["", "<null>"]):
			someone = false   # a demon disguised as a prop is just a prop: fine to stand on
		if someone:
			var away := Vector3(global_position.x - other.global_position.x, 0.0, global_position.z - other.global_position.z)
			if away.length() < 0.05:
				away = Vector3.RIGHT
			away = away.normalized()
			velocity.x = away.x * 4.0
			velocity.z = away.z * 4.0
			global_position += away * 0.06
			break


# Waiting around: little turns, and every so often a few steps somewhere.
func _idle(delta: float) -> void:
	_fidget_timer -= delta
	if _fidget_timer > 0.0:
		return
	_fidget_timer = randf_range(1.2, 3.5)
	if randf() < 0.35:
		var a := randf() * TAU
		walk_to(global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.5, 3.5))
	else:
		rotation.y += randf_range(-1.2, 1.2)
