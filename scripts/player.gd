# The local player. Plays as either an angel (throws blessings) or a demon
# (possesses props). T toggles first/third person; each side remembers its view.
extends CharacterBody3D

signal hit_confirmed   # one of our throws hit a demon
signal threw(kind)     # we threw a blessed projectile of this kind
signal form_changed    # we possessed a prop or returned to demon form
signal taunted(taunt_name)
signal launched(origin, velocity, kind)   # a throw left our hand (multiplayer forwards it)
signal hit_taken(damage)                  # a counted hit on us as a demon (host decides)

const PropLib = preload("res://scripts/prop_library.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Effects = preload("res://scripts/effects.gd")
const Blessings = preload("res://scripts/blessings.gd")
const Taunts = preload("res://scripts/taunts.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Bodies = preload("res://scripts/bodies.gd")

const ANGEL_SPEED := 6.0
const DEMON_SPEED := 6.5
const MOUSE_SENSITIVITY := 0.0025
const PROJECTILE_SPEED := 40.0
const POSSESS_REACH := 6.0        # how far past the camera a demon can possess
const THIRD_PERSON_DISTANCE := 3.5
const HOLD_TO_RETURN := 0.6       # seconds to hold left click to leave a prop
const BODY_HEIGHT := Bodies.BODY_HEIGHT
const SHOULDER_OFFSET := 0.7      # third-person camera sits over the right shoulder
const OUTLINE_COLOR := Color(1.0, 0.35, 0.1)
const RUN_MULTIPLIER := 1.6       # Shift
const SNEAK_MULTIPLIER := 0.45    # Ctrl

# Throwing: fast, limited by blessing stamina rather than a long cooldown.
const THROW_COOLDOWN := 0.1       # up to 10 throws per second
const THROW_STAMINA_MAX := 100.0
const THROW_COST := 7.0           # ~14 throws from full
const THROW_REGEN := 30.0         # per second (a future power-up multiplies this)
const THROW_REGEN_DELAY := 0.0    # pause after a throw before regen starts (0 = always regenerating)

# Sprinting: its own stamina pool, separate from throwing.
const SPRINT_MAX := 100.0
const SPRINT_DRAIN := 22.0        # per second while running (~4.5 s from full)
const SPRINT_REGEN := 18.0
const SPRINT_REGEN_DELAY := 0.8
const SPRINT_RESTART := 25.0      # once empty, need this much back before running again

# Demons' Hatred: their "mana". Fills slowly; demon skills will spend it later.
const HATRED_MAX := 100.0
const HATRED_REGEN := 4.0

const TAUNT_COOLDOWN := 0.8

# Movement feel. Live-editable from the F1 tuning panel to compare settings.
var tuning := {
	"ground_accel": 45.0,    # m/s² to reach full speed (higher = snappier starts)
	"ground_decel": 35.0,    # m/s² to stop (lower = more slide)
	"air_accel": 12.0,       # steering in the air
	"gravity_scale": 1.35,   # >1 = less floaty
	"fall_multiplier": 1.5,  # extra gravity on the way down
	"jump_velocity": 5.6,
	"head_bob": 1.0,         # 0 = off
}

var role := "demon"           # "angel" or "demon"
var frozen := false           # true while angels wait out the hiding period
var possessed_type := ""      # prop type the demon is currently possessing
var look_target_type := ""    # prop type the demon is aiming at (for the HUD hint)
var first_person := {"angel": true, "demon": false}
var hold_fraction := 0.0      # 0-1 progress of hold-to-return (for the HUD)
var blessing := "holy_light"  # which blessed projectile an angel throws
var running := false
var sneaking := false
var throw_stamina := THROW_STAMINA_MAX
var throw_regen_multiplier := 1.0   # the future "quick regen" power-up raises this
var sprint_stamina := SPRINT_MAX
var hatred := 0.0
var last_taunt := ""
var input_enabled := true      # false while a menu is open
var net_mode := ""            # "" offline/practice, "server" = host, "client" = joined someone
var test_input := {}          # automated tests only: {"dir": Vector2, "sneak", "run", "jump": bool}

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _throw_cooldown := 0.0
var _throw_regen_wait := 0.0
var _sprint_regen_wait := 0.0
var _sprint_exhausted := false
var _taunt_cooldown := 0.0
var _holding := false
var _hold_time := 0.0
var _form_height := BODY_HEIGHT
var _hover_prop: Node3D       # prop currently outlined under the crosshair
var _outline_mat: StandardMaterial3D
var _bob_phase := 0.0
var _bob_offset := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _fall_speed := 0.0

var shape_node: CollisionShape3D
var visual_root: Node3D
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var voice: AudioStreamPlayer3D


func _ready() -> void:
	shape_node = CollisionShape3D.new()
	add_child(shape_node)
	visual_root = Node3D.new()
	add_child(visual_root)
	pivot = Node3D.new()
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	spring.add_child(camera)
	camera.current = true
	voice = AudioStreamPlayer3D.new()
	voice.bus = Sfx.BUS
	voice.unit_size = 6.0
	voice.max_distance = 70.0
	voice.position.y = 1.0
	add_child(voice)
	set_role(role)


func set_role(new_role: String) -> void:
	role = new_role
	possessed_type = ""
	look_target_type = ""
	_holding = false
	hold_fraction = 0.0
	_set_hover(null)
	pivot.rotation = Vector3.ZERO
	throw_stamina = THROW_STAMINA_MAX
	sprint_stamina = SPRINT_MAX
	_sprint_exhausted = false
	hatred = 0.0
	last_taunt = ""
	_apply_form()


func _apply_form() -> void:
	for child in visual_root.get_children():
		child.queue_free()
	if possessed_type != "":
		visual_root.add_child(PropLib.make_visual(possessed_type))
		shape_node.shape = PropLib.make_shape(possessed_type)
		_form_height = PropLib.height(possessed_type)
	else:
		visual_root.add_child(Bodies.make(role))
		shape_node.shape = Bodies.make_shape(role)
		_form_height = Bodies.height_for(role)
	shape_node.position.y = _form_height / 2.0
	_apply_camera()


func _apply_camera() -> void:
	if first_person[role]:
		# Eyes at the top of the body, or just above the possessed prop.
		pivot.position.y = _form_height * 0.9 if possessed_type == "" else _form_height + 0.15
		spring.position.x = 0.0
		spring.spring_length = 0.0
		visual_root.visible = false
	else:
		# Over the shoulder and above the head, so our own body never covers the crosshair.
		pivot.position.y = maxf(_form_height, 0.6) + 0.35
		spring.position.x = SHOULDER_OFFSET
		spring.spring_length = THIRD_PERSON_DISTANCE
		visual_root.visible = true


func toggle_view() -> void:
	first_person[role] = not first_person[role]
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_throw_cooldown = 0.3   # don't fire on the click that grabs the mouse
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.2)
		return
	if event.is_action_pressed("toggle_view"):
		toggle_view()
		return
	if event.is_action_pressed("cycle_blessing") and role == "angel":
		cycle_blessing()
		return
	# Taunts work even during the hiding period - trash talk is half the game.
	if event.is_action_pressed("taunt_random"):
		taunt(false)
		return
	if event.is_action_pressed("taunt_signature"):
		taunt(true)
		return
	if frozen:
		return
	if event.is_action_pressed("shoot"):
		if role == "angel":
			try_throw()   # on the click itself, not the next physics tick
		elif possessed_type == "":
			try_possess()
		else:
			# Already a prop: a quick tap switches props, a hold returns to demon form.
			_holding = true
			_hold_time = 0.0
	elif event.is_action_released("shoot") and role == "demon" and _holding:
		_holding = false
		hold_fraction = 0.0
		if _hold_time < HOLD_TO_RETURN:
			try_possess()


func _physics_process(delta: float) -> void:
	_throw_cooldown = maxf(_throw_cooldown - delta, 0.0)
	_taunt_cooldown = maxf(_taunt_cooldown - delta, 0.0)
	var on_floor := is_on_floor()
	if not on_floor:
		var g: float = gravity * tuning["gravity_scale"]
		if velocity.y < 0.0:
			g *= tuning["fall_multiplier"]   # fall faster than you rise: less floaty
		velocity.y -= g * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)

	var controls_active := input_enabled and not frozen and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input_dir := Vector2.ZERO
	var want_run := false
	var want_jump := false
	sneaking = false
	if not test_input.is_empty():
		# Automated tests drive movement here (headless mode can't capture the mouse).
		input_dir = test_input.get("dir", Vector2.ZERO)
		sneaking = test_input.get("sneak", false)
		want_run = test_input.get("run", false)
		want_jump = test_input.get("jump", false)
	elif controls_active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sneaking = Input.is_action_pressed("sneak")
		want_run = Input.is_action_pressed("run")
		want_jump = Input.is_action_just_pressed("jump")
	if want_jump and on_floor:
		velocity.y = tuning["jump_velocity"]

	_update_sprint(delta, want_run and not sneaking and input_dir != Vector2.ZERO)

	var direction := global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var speed := ANGEL_SPEED if role == "angel" else DEMON_SPEED
	if running:
		speed *= RUN_MULTIPLIER
	elif sneaking:
		speed *= SNEAK_MULTIPLIER
	# Accelerate toward the wanted speed instead of snapping to it: gives weight.
	var target := Vector2(direction.x, direction.z) * speed
	var current := Vector2(velocity.x, velocity.z)
	var rate: float
	if not on_floor:
		rate = tuning["air_accel"]
	elif target.length() < current.length():
		rate = tuning["ground_decel"]
	else:
		rate = tuning["ground_accel"]
	current = current.move_toward(target, rate * delta)
	velocity.x = current.x
	velocity.z = current.y
	move_and_slide()

	_update_head_bob(delta, current.length())
	_update_throw_stamina(delta)
	if role == "demon":
		hatred = minf(hatred + HATRED_REGEN * delta, HATRED_MAX)

	if role == "angel":
		# Holding the button keeps throwing as fast as cooldown and stamina allow.
		if controls_active and Input.is_action_pressed("shoot"):
			try_throw()
		return

	if _holding:
		_hold_time += delta
		hold_fraction = minf(_hold_time / HOLD_TO_RETURN, 1.0)
		if _hold_time >= HOLD_TO_RETURN:
			_holding = false
			hold_fraction = 0.0
			unpossess()
	var aim := _aim_ray(spring.spring_length + POSSESS_REACH)
	var hovered: Node3D = null
	if not aim.is_empty() and aim["collider"].is_in_group("prop"):
		hovered = aim["collider"]
	_set_hover(hovered)
	look_target_type = hovered.get_meta("prop_type") if hovered else ""


func _update_sprint(delta: float, wants_to_run: bool) -> void:
	if _sprint_exhausted and sprint_stamina >= SPRINT_RESTART:
		_sprint_exhausted = false
	running = wants_to_run and not _sprint_exhausted and sprint_stamina > 0.0
	if running:
		sprint_stamina = maxf(sprint_stamina - SPRINT_DRAIN * delta, 0.0)
		_sprint_regen_wait = SPRINT_REGEN_DELAY
		if sprint_stamina <= 0.0:
			_sprint_exhausted = true
	elif _sprint_regen_wait > 0.0:
		_sprint_regen_wait -= delta
	else:
		sprint_stamina = minf(sprint_stamina + SPRINT_REGEN * delta, SPRINT_MAX)


func _update_throw_stamina(delta: float) -> void:
	if _throw_regen_wait > 0.0:
		_throw_regen_wait -= delta
	else:
		throw_stamina = minf(throw_stamina + THROW_REGEN * throw_regen_multiplier * delta, THROW_STAMINA_MAX)


# Subtle first-person bob while moving, plus a small dip when landing.
func _update_head_bob(delta: float, ground_speed: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 2.0:
		_land_dip = -minf(_fall_speed * 0.02, 0.15)
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor
	_land_dip = lerpf(_land_dip, 0.0, minf(delta * 10.0, 1.0))

	var amount: float = tuning["head_bob"]
	var target := 0.0
	if on_floor and ground_speed > 0.5 and amount > 0.0:
		_bob_phase += delta * ground_speed * 1.7   # step rate follows speed
		target = sin(_bob_phase * 2.0) * 0.035 * amount * clampf(ground_speed / 6.0, 0.4, 1.6)
	_bob_offset = lerpf(_bob_offset, target, minf(delta * 12.0, 1.0))
	# Bob only in first person; in third person it just looks like a shaky camera.
	spring.position.y = (_bob_offset + _land_dip) if first_person[role] else 0.0


# Outline the prop under the crosshair so you know exactly what you'll become.
func _set_hover(prop: Node3D) -> void:
	if prop == _hover_prop and is_instance_valid(prop):
		return
	if is_instance_valid(_hover_prop):
		_apply_outline(_hover_prop, null)
	_hover_prop = prop
	if prop:
		if _outline_mat == null:
			_outline_mat = StandardMaterial3D.new()
			_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT   # only the "shell" shows
			_outline_mat.grow = true
			_outline_mat.grow_amount = 0.04
			_outline_mat.albedo_color = OUTLINE_COLOR
		_apply_outline(prop, _outline_mat)


func _apply_outline(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_overlay = material
		_apply_outline(child, material)


# Ray straight out of the camera (the crosshair), ignoring ourselves.
func _aim_ray(reach: float) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func try_possess() -> bool:
	var hit := _aim_ray(spring.spring_length + POSSESS_REACH)
	if hit.is_empty() or not hit["collider"].is_in_group("prop"):
		return false
	force_possess(hit["collider"].get_meta("prop_type"))
	return true


func force_possess(type_name: String) -> void:
	possessed_type = type_name
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()


func unpossess() -> void:
	if possessed_type == "":
		return
	possessed_type = ""
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.8, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()


func confirm_hit() -> void:
	hit_confirmed.emit()


# Called by a projectile that hit us. Only the host's projectiles are real, so this
# only ever runs on the host. Returns whether the hit counted (only demons get hurt).
func take_hit(damage: int) -> bool:
	if role != "demon" or net_mode == "":
		return false
	hit_taken.emit(damage)
	return true


# 1 = a random taunt (never the signature), 2 = your signature taunt.
func taunt(signature: bool) -> bool:
	if _taunt_cooldown > 0.0:
		return false
	var taunt_name: String = Taunts.signature(role) if signature else Taunts.pick_random(role, last_taunt)
	if not signature:
		last_taunt = taunt_name
	voice.stream = Taunts.stream(taunt_name)
	voice.pitch_scale = randf_range(0.96, 1.04)
	voice.play()
	_taunt_cooldown = TAUNT_COOLDOWN
	taunted.emit(taunt_name)
	return true


# Throw if the cooldown is done and there's enough blessing stamina.
func try_throw() -> bool:
	if _throw_cooldown > 0.0 or throw_stamina < THROW_COST:
		return false
	throw_stamina -= THROW_COST
	_throw_regen_wait = THROW_REGEN_DELAY
	_shoot()
	return true


func _shoot() -> void:
	var p := Projectile.new()
	p.color = Blessings.color(blessing)   # before add_child: its glow is built on entering the world
	p.visual_only = net_mode == "client"  # joined players only show throws; the host decides hits
	get_parent().add_child(p)
	var forward := -camera.global_transform.basis.z
	# In third person, start the throw at the angel's hand height, not back at the camera.
	# Either way, aim at whatever is under the crosshair.
	var start := camera.global_position + forward * 0.6
	var direction := forward
	if not first_person[role]:
		start = global_position + Vector3.UP * 1.4 + forward * 0.6
		var hit := _aim_ray(100.0)
		var aim_point: Vector3 = hit["position"] if not hit.is_empty() else camera.global_position + forward * 100.0
		direction = (aim_point - start).normalized()
	p.global_position = start
	p.velocity = direction * PROJECTILE_SPEED + Vector3.UP * 0.6
	p.shooter = self
	_throw_cooldown = THROW_COOLDOWN
	threw.emit(blessing)
	launched.emit(start, p.velocity, blessing)


func cycle_blessing() -> void:
	var kinds := Blessings.names()
	blessing = kinds[(kinds.find(blessing) + 1) % kinds.size()]
