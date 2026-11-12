# An angel's thrown ball of holy light. Arcs slightly with gravity.
# Uses a ray each physics frame so fast shots can't pass through thin props.
extends Node3D

const Effects = preload("res://scripts/effects.gd")

const DAMAGE := 25
const GRAVITY := 4.0
const LIFETIME := 3.0
var color := Color(1.0, 0.9, 0.4)   # set by the thrower from its blessing type
var velocity := Vector3.ZERO
var shooter: CollisionObject3D
var _life := LIFETIME


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	add_child(mi)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if shooter:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	var collider: Object = hit["collider"]
	var hit_demon := false
	if collider and collider.has_method("take_hit"):
		collider.take_hit(DAMAGE)
		hit_demon = true
		if is_instance_valid(shooter) and shooter.has_method("confirm_hit"):
			shooter.confirm_hit()
	# A demon hit gets a red puff; anything else gets a harmless golden one.
	var puff_color := Color(0.9, 0.15, 0.1, 0.8) if hit_demon else Color(1.0, 0.95, 0.6, 0.7)
	Effects.puff(get_parent(), hit["position"], puff_color, 1.0 if hit_demon else 0.6)
	queue_free()
