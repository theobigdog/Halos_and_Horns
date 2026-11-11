# A practice demon for testing the angel side. It possesses a random prop,
# stands still, and occasionally fidgets (a tiny hop) - a hint, like a real
# player who can't sit still.
extends StaticBody3D

signal caught(bot)

const PropLib = preload("res://scripts/prop_library.gd")
const Effects = preload("res://scripts/effects.gd")

const MAX_HEALTH := 100

var prop_type := ""
var health := MAX_HEALTH
var visual: Node3D
var _fidget_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(type_name: String) -> void:
	prop_type = type_name
	add_to_group("demon")
	visual = PropLib.make_visual(type_name)
	add_child(visual)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = PropLib.make_shape(type_name)
	shape_node.position.y = PropLib.height(type_name) / 2.0
	add_child(shape_node)
	_rng.randomize()
	_reset_fidget()


func _reset_fidget() -> void:
	_fidget_timer = _rng.randf_range(8.0, 16.0)


func _process(delta: float) -> void:
	_fidget_timer -= delta
	if _fidget_timer <= 0.0:
		_reset_fidget()
		var tw := create_tween()
		tw.tween_property(visual, "position:y", 0.15, 0.1)
		tw.tween_property(visual, "position:y", 0.0, 0.12)


func take_hit(damage: int) -> void:
	if health <= 0:
		return
	health -= damage
	# Squash so the angel gets feedback that this one is a demon.
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.1)
	if health <= 0:
		Effects.puff(get_parent(), global_position + Vector3.UP * 0.5, Color(0.8, 0.1, 0.1, 0.9), 1.6)
		caught.emit(self)
		queue_free()
