# A bouncy: step on it and it flings you high into the air (angels, demons,
# minions, everyone). Alarm Cherubs and Vacuum Orbs that land on one go
# bouncing off too (cherub.gd's bounce_from, projectile.gd's bounces_on_pads). Permanent ones are part of the map; one-use ones vanish
# after their first bounce for the rest of the round.
#
# Each player's own game bounces them (movement is theirs to report); using up a
# one-use bouncy goes through the decider so everyone sees it go.
extends Node3D

const BOUNCE_VELOCITY := 15.0     # about 8.5 m up: onto most roofs
const RADIUS := 0.9

var bouncy_id := 0
var one_use := false
var on_used: Callable             # main: a one-use bouncy was used
var _used := false
var _top: MeshInstance3D
var _squish := 0.0


func _ready() -> void:
	# The base you can stand on
	var base := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 0.25
	shape.shape = cyl
	shape.position.y = 0.125
	base.add_child(shape)
	base.add_to_group("bouncy_pad")   # thrown things that hit it bounce (projectile.gd)
	add_child(base)
	var spring_color := Color(0.75, 0.75, 0.8)
	for i in 3:                    # the coil
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = RADIUS * 0.55
		t.outer_radius = RADIUS * 0.7
		ring.mesh = t
		ring.material_override = _mat(spring_color, false)
		ring.position.y = 0.06 + i * 0.07
		add_child(ring)
	# The cushion on top: soft and glowing (gold for one-use ones)
	_top = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = RADIUS
	c.bottom_radius = RADIUS * 0.9
	c.height = 0.12
	_top.mesh = c
	_top.material_override = _mat(Color(1.0, 0.82, 0.3) if one_use else Color(0.55, 0.85, 1.0), true)
	_top.position.y = 0.28
	add_child(_top)
	# The trigger: anyone landing on (or walking onto) the cushion
	var area := Area3D.new()
	var tshape := CollisionShape3D.new()
	var tcyl := CylinderShape3D.new()
	tcyl.radius = RADIUS + 0.2       # (walking up against its edge counts too)
	tcyl.height = 0.9
	tshape.shape = tcyl
	tshape.position.y = 0.45
	area.add_child(tshape)
	area.monitorable = false
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _mat(color: Color, glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6
	return m


func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if body.has_method("bounce_from"):   # an Alarm Cherub: it flies off, away from the middle
		if body.bounce_from(global_position, BOUNCE_VELOCITY):
			squish()
		return
	if not body.has_method("bounce"):
		return
	if not body.bounce(BOUNCE_VELOCITY):
		return
	_squish = 0.25
	if one_use and body.get("net_mode") != null:
		# Our own player used it up: tell the decider (it tells everyone).
		_used = true
		if on_used.is_valid():
			on_used.call(bouncy_id)


func squish() -> void:
	_squish = 0.25


func use_up() -> void:
	_used = true
	queue_free()


func _process(delta: float) -> void:
	if _squish > 0.0:
		_squish -= delta
		var s := 1.0 - 0.5 * sin(clampf(_squish / 0.25, 0.0, 1.0) * PI)
		_top.scale = Vector3(1.0 + (1.0 - s) * 0.3, s, 1.0 + (1.0 - s) * 0.3)
