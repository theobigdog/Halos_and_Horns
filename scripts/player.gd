# The local player. Plays as either an angel (throws holy light) or a demon
# (possesses props). T toggles first/third person; each side remembers its view.
extends CharacterBody3D

signal hit_confirmed   # one of our throws hit a demon
signal threw(kind)     # we threw a blessed projectile of this kind
signal form_changed    # we possessed a prop or returned to demon form

const PropLib = preload("res://scripts/prop_library.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Effects = preload("res://scripts/effects.gd")
const Blessings = preload("res://scripts/blessings.gd")

const ANGEL_SPEED := 6.0
const DEMON_SPEED := 6.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.0025
const SHOOT_COOLDOWN := 0.3
const PROJECTILE_SPEED := 40.0
const POSSESS_REACH := 6.0        # how far past the camera a demon can possess
const THIRD_PERSON_DISTANCE := 3.5
const HOLD_TO_RETURN := 0.6       # seconds to hold left click to leave a prop
const BODY_HEIGHT := 1.7         # angel height
const DEMON_SCALE := 0.6          # demons are little gremlins: 60% of angel size
const SHOULDER_OFFSET := 0.7      # third-person camera sits over the right shoulder
const OUTLINE_COLOR := Color(1.0, 0.35, 0.1)
const RUN_MULTIPLIER := 1.6       # Left Shift
const SNEAK_MULTIPLIER := 0.45    # Left Ctrl
const LEDGE_DROP := 0.5           # sneaking won't step down more than this

var role := "demon"           # "angel" or "demon"
var frozen := false           # true while angels wait out the hiding period
var possessed_type := ""      # prop type the demon is currently possessing
var look_target_type := ""    # prop type the demon is aiming at (for the HUD hint)
var first_person := {"angel": true, "demon": false}
var hold_fraction := 0.0      # 0-1 progress of hold-to-return (for the HUD)
var blessing := "holy_light"  # which blessed projectile an angel throws
var running := false
var sneaking := false
var test_input := {}          # automated tests only: {"dir": Vector2, "sneak": bool, "run": bool}

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shoot_cooldown := 0.0
var _holding := false
var _hold_time := 0.0
var _form_height := BODY_HEIGHT
var _hover_prop: Node3D       # prop currently outlined under the crosshair
var _outline_mat: StandardMaterial3D

var shape_node: CollisionShape3D
var visual_root: Node3D
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D


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
	set_role(role)


func set_role(new_role: String) -> void:
	role = new_role
	possessed_type = ""
	look_target_type = ""
	_holding = false
	hold_fraction = 0.0
	_set_hover(null)
	pivot.rotation = Vector3.ZERO
	_apply_form()


func _apply_form() -> void:
	for child in visual_root.get_children():
		child.queue_free()
	if possessed_type != "":
		visual_root.add_child(PropLib.make_visual(possessed_type))
		shape_node.shape = PropLib.make_shape(possessed_type)
		_form_height = PropLib.height(possessed_type)
	else:
		visual_root.add_child(_make_body_visual())
		var body_scale := _body_scale()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35 * body_scale
		capsule.height = BODY_HEIGHT * body_scale
		shape_node.shape = capsule
		_form_height = BODY_HEIGHT * body_scale
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


func _body_scale() -> float:
	return 1.0 if role == "angel" else DEMON_SCALE


func toggle_view() -> void:
	first_person[role] = not first_person[role]
	_apply_camera()


func _make_body_visual() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = BODY_HEIGHT
	body.mesh = capsule
	body.position.y = BODY_HEIGHT / 2.0
	root.add_child(body)
	if role == "angel":
		body.material_override = PropLib.mat(Color(0.95, 0.95, 1.0))
		var halo := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.18
		torus.outer_radius = 0.25
		halo.mesh = torus
		var gold := PropLib.mat(Color(1.0, 0.85, 0.3))
		gold.emission_enabled = true
		gold.emission = Color(1.0, 0.85, 0.3)
		halo.material_override = gold
		halo.position.y = 1.95
		root.add_child(halo)
	else:
		body.material_override = PropLib.mat(Color(0.75, 0.12, 0.12))
		for side in [-1.0, 1.0]:
			var horn := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.08
			cone.height = 0.3
			horn.mesh = cone
			horn.material_override = PropLib.mat(Color(0.15, 0.1, 0.1))
			horn.position = Vector3(0.17 * side, 1.75, 0.0)
			horn.rotation.z = -0.35 * side
			root.add_child(horn)
			var eye := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.06
			sphere.height = 0.12
			eye.mesh = sphere
			var yellow := PropLib.mat(Color(1.0, 0.9, 0.1))
			yellow.emission_enabled = true
			yellow.emission = Color(1.0, 0.9, 0.1)
			eye.material_override = yellow
			eye.position = Vector3(0.12 * side, 1.45, -0.31)   # -Z is forward
			root.add_child(eye)
		root.scale = Vector3.ONE * DEMON_SCALE
	return root


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_shoot_cooldown = 0.3   # don't fire on the click that grabs the mouse
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
	if frozen:
		return
	if event.is_action_pressed("shoot"):
		if role == "angel":
			# Fire right on the click rather than waiting for the next physics tick.
			if _shoot_cooldown <= 0.0:
				_shoot()
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
	_shoot_cooldown = maxf(_shoot_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	var controls_active := not frozen and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input_dir := Vector2.ZERO
	sneaking = false
	running = false
	if not test_input.is_empty():
		# Automated tests drive movement here (headless mode can't capture the mouse).
		input_dir = test_input.get("dir", Vector2.ZERO)
		sneaking = test_input.get("sneak", false)
		running = test_input.get("run", false) and not sneaking
	elif controls_active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sneaking = Input.is_action_pressed("sneak")
		running = Input.is_action_pressed("run") and not sneaking   # sneak wins if both held
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var direction := global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var speed := ANGEL_SPEED if role == "angel" else DEMON_SPEED
	if running:
		speed *= RUN_MULTIPLIER
	elif sneaking:
		speed *= SNEAK_MULTIPLIER
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if sneaking and is_on_floor():
		_guard_ledges(delta)
	move_and_slide()

	if role == "angel":
		# Holding the button keeps throwing at the cooldown rate.
		if controls_active and Input.is_action_pressed("shoot") and _shoot_cooldown <= 0.0:
			_shoot()
		return

	if _holding:
		_hold_time += delta
		hold_fraction = minf(_hold_time / HOLD_TO_RETURN, 1.0)
		if _hold_time >= HOLD_TO_RETURN:
			_holding = false
			hold_fraction = 0.0
			unpossess()
	var target := _aim_ray(spring.spring_length + POSSESS_REACH)
	var hovered: Node3D = null
	if not target.is_empty() and target["collider"].is_in_group("prop"):
		hovered = target["collider"]
	_set_hover(hovered)
	look_target_type = hovered.get_meta("prop_type") if hovered else ""


# Minecraft-style sneaking: cancel any sideways movement that would carry us off
# a ledge. X and Z are checked separately, so you can still slide along an edge.
func _guard_ledges(delta: float) -> void:
	var step := Vector3(velocity.x, 0.0, velocity.z) * delta
	if step.length_squared() == 0.0:
		return
	if not _has_ground_at(global_position + Vector3(step.x, 0.0, 0.0)):
		velocity.x = 0.0
	if not _has_ground_at(global_position + Vector3(0.0, 0.0, step.z)):
		velocity.z = 0.0
	# Moving diagonally straight at a corner: both single-axis checks can pass
	# while the combined move still steps off, so check that too.
	if velocity.x != 0.0 and velocity.z != 0.0 \
			and not _has_ground_at(global_position + Vector3(velocity.x, 0.0, velocity.z) * delta):
		velocity.x = 0.0
		velocity.z = 0.0


# Is there floor under this spot within a small step down? (Ramps count; drops don't.)
func _has_ground_at(spot: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
			spot + Vector3.UP * 0.3, spot + Vector3.DOWN * LEDGE_DROP)
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
	possessed_type = hit["collider"].get_meta("prop_type")
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()
	return true


func unpossess() -> void:
	if possessed_type == "":
		return
	possessed_type = ""
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.8, Color(0.8, 0.1, 0.1, 0.8))
	form_changed.emit()


func confirm_hit() -> void:
	hit_confirmed.emit()


func _shoot() -> void:
	var p := Projectile.new()
	p.color = Blessings.color(blessing)   # before add_child: its glow is built on entering the world
	get_parent().add_child(p)
	var forward := -camera.global_transform.basis.z
	# In third person, start the throw at the angel's hand height, not back at the camera.
	# Either way, aim at whatever is under the crosshair.
	var start := camera.global_position + forward * 0.6
	var direction := forward
	if not first_person[role]:
		start = global_position + Vector3.UP * 1.4 + forward * 0.6
		var hit := _aim_ray(100.0)
		var target: Vector3 = hit["position"] if not hit.is_empty() else camera.global_position + forward * 100.0
		direction = (target - start).normalized()
	p.global_position = start
	p.velocity = direction * PROJECTILE_SPEED + Vector3.UP * 0.6
	p.shooter = self
	_shoot_cooldown = SHOOT_COOLDOWN
	threw.emit(blessing)


func cycle_blessing() -> void:
	var kinds := Blessings.names()
	blessing = kinds[(kinds.find(blessing) + 1) % kinds.size()]
