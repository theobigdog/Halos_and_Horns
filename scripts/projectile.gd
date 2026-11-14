# An angel's thrown blessing. Arcs slightly with gravity.
# Uses a ray each physics frame so fast shots can't pass through thin props.
# Online, only the host's copy can hurt anyone (the server decides every hit);
# everyone else's copy is visual_only, so a hacked client can't fake hits.
extends Node3D

const Effects = preload("res://scripts/effects.gd")

const DAMAGE := 25
const LIFETIME := 3.0
var color := Color(1.0, 0.9, 0.4)   # set by the thrower from its blessing type
var velocity := Vector3.ZERO
var shooter: CollisionObject3D
var visual_only := false
var damage := DAMAGE
var gravity := 4.0
var size := 0.12
var on_impact: Callable          # called with the hit position (vacuum orb); host/practice only
var _life := LIFETIME


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 2.0
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
	velocity.y -= gravity * delta
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
	# take_hit returns true only if the hit counted (a demon, not a fellow angel).
	if not visual_only and on_impact.is_valid():
		on_impact.call(hit["position"])
	if not visual_only and damage > 0 and collider and collider.has_method("take_hit") and collider.take_hit(damage):
		hit_demon = true
		if is_instance_valid(shooter) and shooter.has_method("confirm_hit"):
			shooter.confirm_hit()
	# A demon hit gets a red puff; anything else gets a harmless golden one.
	var puff_color := Color(0.9, 0.15, 0.1, 0.8) if hit_demon else Color(1.0, 0.95, 0.6, 0.7)
	Effects.puff(get_parent(), hit["position"], puff_color, 1.0 if hit_demon else 0.6)
	queue_free()
