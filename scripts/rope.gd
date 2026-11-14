# A grappling hook's rope: a thin golden line from the thrower to the hook point.
# Follows the thrower if a node is given (so it stays attached while zipping).
extends Node3D

var from_node: Node3D        # optional: rope starts here (hand height)
var from_pos := Vector3.ZERO
var to_pos := Vector3.ZERO
var duration := 0.6
var _mesh: MeshInstance3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	_mesh.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.35)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.3)
	m.emission_energy_multiplier = 0.6
	_mesh.material_override = m
	add_child(_mesh)
	var hook := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.08
	s.height = 0.16
	hook.mesh = s
	hook.material_override = m
	hook.name = "Hook"
	add_child(hook)
	_update()


func _process(delta: float) -> void:
	duration -= delta
	if duration <= 0.0:
		queue_free()
		return
	_update()


func _update() -> void:
	var a := from_pos
	if is_instance_valid(from_node):
		a = from_node.global_position + Vector3.UP * 1.2
	var b := to_pos
	var mid := (a + b) * 0.5
	var length := maxf(a.distance_to(b), 0.01)
	_mesh.global_position = mid
	_mesh.scale = Vector3(1.0, length, 1.0)
	var dir := (b - a) / length
	# Point the cylinder (which runs along Y) from a to b.
	var axis := Vector3.UP.cross(dir)
	if axis.length() < 0.001:
		_mesh.global_basis = Basis.IDENTITY.scaled(Vector3(1, length, 1))
	else:
		var angle := acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0))
		_mesh.global_basis = Basis(axis.normalized(), angle).scaled(Vector3(1, length, 1))
	get_node("Hook").global_position = b
