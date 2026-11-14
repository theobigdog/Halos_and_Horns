# The Vacuum Orb's vortex: purple swirling rings for a couple of seconds.
# If it caught a hidden demon (decided by the host / practice game) it flashes
# red and plays an alarm, so the angels know something is in the pile.
extends Node3D

const Skills = preload("res://scripts/skills.gd")
const Sfx = preload("res://scripts/sfx.gd")

var caught := false
var _life := Skills.VACUUM_TIME
var _rings: Array = []
var _mat: StandardMaterial3D

static var _whoosh: AudioStreamWAV
static var _alarm: AudioStreamWAV


func _ready() -> void:
	if _whoosh == null:
		_whoosh = Sfx.tone([[110.0, 0.3]], 1.6, 0.25, 0.3, 20.0, 0.9, 1.8)
		_alarm = Sfx.tone([[880.0, 0.5], [1320.0, 0.3]], 0.9, 0.16, 0.01, 6.0, 0.0, 0.8)
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.9, 0.2, 0.15, 0.55) if caught else Color(0.6, 0.3, 1.0, 0.45)
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		ring.mesh = torus
		ring.material_override = _mat
		ring.position.y = 0.3 + i * 0.5
		add_child(ring)
		_rings.append(ring)
	var voice := AudioStreamPlayer3D.new()
	voice.bus = Sfx.BUS
	voice.unit_size = 8.0
	voice.stream = _whoosh
	add_child(voice)
	voice.play()
	if caught:
		var alarm := AudioStreamPlayer3D.new()
		alarm.bus = Sfx.BUS
		alarm.unit_size = 10.0
		alarm.stream = _alarm
		add_child(alarm)
		alarm.play()


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var t := 1.0 - _life / Skills.VACUUM_TIME
	for i in _rings.size():
		var ring: MeshInstance3D = _rings[i]
		ring.rotation.y += delta * (6.0 + i * 3.0)
		# Rings shrink inward, like they're sucking everything to the middle.
		var r: float = Skills.VACUUM_RADIUS * (1.0 - fmod(t * 2.0 + i * 0.33, 1.0)) + 0.2
		ring.scale = Vector3(r, 1.0, r)
	_mat.albedo_color.a = 0.5 * minf(_life / 0.5, 1.0)
