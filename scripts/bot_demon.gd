# A practice demon for testing the angel side. It possesses a random prop,
# stands still, and fidgets (a little hop) every few seconds so testers can
# find it fast. Real demons will be real players - this is test-only.
extends StaticBody3D

const HOP_EVERY_MIN := 2.0   # seconds between hops (testing: frequent on purpose)
const HOP_EVERY_MAX := 4.0
const TAUNT_EVERY_MIN := 5.0  # bots taunt too: listen for where it comes from
const TAUNT_EVERY_MAX := 9.0

signal caught(bot)

const PropLib = preload("res://scripts/prop_library.gd")
const Effects = preload("res://scripts/effects.gd")
const Taunts = preload("res://scripts/taunts.gd")
const Sfx = preload("res://scripts/sfx.gd")

const MAX_HEALTH := 100

var prop_type := ""
var health := MAX_HEALTH
var visual: Node3D
var _fidget_timer := 0.0
var _taunt_timer := 0.0
var _last_taunt := ""
var _voice: AudioStreamPlayer3D
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
	_taunt_timer = _rng.randf_range(TAUNT_EVERY_MIN, TAUNT_EVERY_MAX)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 6.0
	_voice.max_distance = 70.0
	_voice.position.y = 0.5
	add_child(_voice)


func _reset_fidget() -> void:
	_fidget_timer = _rng.randf_range(HOP_EVERY_MIN, HOP_EVERY_MAX)


func _process(delta: float) -> void:
	_taunt_timer -= delta
	if _taunt_timer <= 0.0:
		_taunt_timer = _rng.randf_range(TAUNT_EVERY_MIN, TAUNT_EVERY_MAX)
		_last_taunt = Taunts.pick_random("demon", _last_taunt)
		_voice.stream = Taunts.stream(_last_taunt)
		_voice.play()
	_fidget_timer -= delta
	if _fidget_timer <= 0.0:
		_reset_fidget()
		var tw := create_tween()
		tw.tween_property(visual, "position:y", 0.3, 0.12)
		tw.tween_property(visual, "position:y", 0.0, 0.15)


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
