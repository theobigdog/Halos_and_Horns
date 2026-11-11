# The local player. Plays as either an angel (first person, throws holy light)
# or a demon (third person, possesses props).
extends CharacterBody3D

const PropLib = preload("res://scripts/prop_library.gd")
const Projectile = preload("res://scripts/projectile.gd")
const Effects = preload("res://scripts/effects.gd")

const ANGEL_SPEED := 6.0
const DEMON_SPEED := 6.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.0025
const SHOOT_COOLDOWN := 0.35
const PROJECTILE_SPEED := 28.0
const POSSESS_REACH := 6.0   # how far past the camera a demon can possess
const DEMON_CAMERA_DISTANCE := 3.5

var role := "demon"           # "angel" or "demon"
var frozen := false           # true while angels wait out the hiding period
var possessed_type := ""      # prop type the demon is currently possessing
var look_target_type := ""    # prop type the demon is aiming at (for the HUD hint)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shoot_cooldown := 0.0

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
	pivot.rotation = Vector3.ZERO
	_apply_form()


func _apply_form() -> void:
	for child in visual_root.get_children():
		child.queue_free()
	var h: float
	if possessed_type != "":
		visual_root.add_child(PropLib.make_visual(possessed_type))
		shape_node.shape = PropLib.make_shape(possessed_type)
		h = PropLib.height(possessed_type)
	else:
		visual_root.add_child(_make_body_visual())
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.7
		shape_node.shape = capsule
		h = 1.7
	shape_node.position.y = h / 2.0
	if role == "angel":
		# First person: camera at eye height, own body hidden.
		pivot.position.y = 1.55
		spring.spring_length = 0.0
		visual_root.visible = false
	else:
		# Third person: camera follows from behind, height scales with the prop.
		pivot.position.y = maxf(h * 0.8, 0.6) + 0.3
		spring.spring_length = DEMON_CAMERA_DISTANCE
		visual_root.visible = true


func _make_body_visual() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	body.mesh = capsule
	body.position.y = 0.85
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
	if role == "demon" and not frozen:
		if event.is_action_pressed("possess"):
			try_possess()
		elif event.is_action_pressed("unpossess"):
			unpossess()


func _physics_process(delta: float) -> void:
	_shoot_cooldown = maxf(_shoot_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	var controls_active := not frozen and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input_dir := Vector2.ZERO
	if controls_active:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var direction := global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()
	var speed := ANGEL_SPEED if role == "angel" else DEMON_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	if role == "angel":
		if controls_active and Input.is_action_pressed("shoot") and _shoot_cooldown <= 0.0:
			_shoot()
	else:
		var target := _aim_ray(spring.spring_length + POSSESS_REACH)
		look_target_type = ""
		if not target.is_empty() and target["collider"].is_in_group("prop"):
			look_target_type = target["collider"].get_meta("prop_type")


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
	return true


func unpossess() -> void:
	if possessed_type == "":
		return
	possessed_type = ""
	_apply_form()
	Effects.puff(get_parent(), global_position + Vector3.UP * 0.8, Color(0.8, 0.1, 0.1, 0.8))


func _shoot() -> void:
	var p := Projectile.new()
	get_parent().add_child(p)
	var forward := -camera.global_transform.basis.z
	p.global_position = camera.global_position + forward * 0.6
	p.velocity = forward * PROJECTILE_SPEED + Vector3.UP * 1.0
	p.shooter = self
	_shoot_cooldown = SHOOT_COOLDOWN
