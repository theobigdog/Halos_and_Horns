# A bouncy: step on it and it flings you high into the air (angels, demons,
# minions, everyone). Three kinds (Ted, Nov 19): one-use pads are wooden, permanent ones are
# solid metal, and super-bouncy ones are magical and shiny and throw you much higher. Alarm Cherubs and Vacuum Orbs that land on one go
# bouncing off too (cherub.gd's bounce_from, projectile.gd's bounces_on_pads). Permanent ones are part of the map; one-use ones vanish
# after their first bounce for the rest of the round.
#
# Each player's own game bounces them (movement is theirs to report); using up a
# one-use bouncy goes through the decider so everyone sees it go.
extends Node3D

const Surfaces = preload("res://scripts/surfaces.gd")

const BOUNCE_VELOCITY := 15.0     # about 8.5 m up: onto most roofs
const SUPER_BOUNCE_VELOCITY := 22.0   # about 18 m up (first guess)
const RADIUS := 0.9

var bouncy_id := 0
var one_use := false
var super_bouncy := false
var _magic: StandardMaterial3D    # the super pad's cushion: its colour drifts
var _magic_time := 0.0
var _runes: Node3D
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
	_build_look()
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


func velocity() -> float:
	return SUPER_BOUNCE_VELOCITY if super_bouncy else BOUNCE_VELOCITY


func _build_look() -> void:
	var kind := "super" if super_bouncy else ("wood" if one_use else "metal")
	# The base plate it all sits on
	var base := _disc(RADIUS, RADIUS, 0.08, 0.04)
	match kind:
		"wood": base.material_override = _surface(Color(0.36, 0.22, 0.12), "wood")
		"metal": base.material_override = _surface(Color(0.32, 0.33, 0.36), "metal")
		"super": base.material_override = _surface(Color(0.2, 0.12, 0.35), "metal")
	# The coil
	var coil := {"wood": Color(0.45, 0.45, 0.48), "metal": Color(0.7, 0.72, 0.76), "super": Color(1.0, 0.8, 0.35)}[kind] as Color
	for i in 3:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = RADIUS * 0.55
		t.outer_radius = RADIUS * 0.7
		ring.mesh = t
		ring.material_override = _surface(coil, "metal")
		ring.position.y = 0.1 + i * 0.06
		add_child(ring)
	# The top you land on
	_top = _disc(RADIUS, RADIUS * 0.9, 0.12, 0.28)
	match kind:
		"wood":
			# A round wooden lid: grainy planks with dark gaps, held by an iron band
			var lid := _surface(Color(0.62, 0.42, 0.24), "wood")
			lid.uv1_scale = Vector3(2.0, 2.0, 2.0 / 7.0)   # grain running along the planks (the top face)
			_top.material_override = lid
			for i in range(-2, 3):
				var gap := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(0.025, 0.01, sqrt(maxf(RADIUS * RADIUS - pow(i * 0.33, 2.0), 0.01)) * 2.0 - 0.06)
				gap.mesh = b
				gap.material_override = _plain(Color(0.2, 0.12, 0.06))
				gap.position = Vector3(i * 0.33 + 0.165, 0.065, 0)
				_top.add_child(gap)
			var band := MeshInstance3D.new()
			var tb := TorusMesh.new()
			tb.inner_radius = RADIUS - 0.04
			tb.outer_radius = RADIUS + 0.03
			band.mesh = tb
			band.material_override = _surface(Color(0.25, 0.25, 0.27), "metal")
			band.scale.y = 0.6
			_top.add_child(band)
		"metal":
			# A riveted steel plate
			var plate := _surface(Color(0.78, 0.8, 0.84), "metal")
			plate.metallic = 0.5   # (fully metal looks black wherever there's little sky to reflect)
			_top.material_override = plate
			for i in 8:
				var rivet := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.045
				sm.height = 0.05
				rivet.mesh = sm
				rivet.material_override = _surface(Color(0.45, 0.47, 0.5), "metal")
				var a := TAU * i / 8.0
				rivet.position = Vector3(cos(a), 0, sin(a)) * (RADIUS - 0.12) + Vector3.UP * 0.06
				_top.add_child(rivet)
		"super":
			# Magic: glassy, glowing, colour slowly shifting, with sparkles rising off it
			_magic = StandardMaterial3D.new()
			_magic.albedo_color = Color(0.35, 0.2, 0.7)
			_magic.metallic = 0.6
			_magic.roughness = 0.1
			_magic.emission_enabled = true
			_magic.emission = Color(0.35, 0.2, 0.7)
			_magic.emission_energy_multiplier = 0.7
			_magic.clearcoat_enabled = true
			_top.material_override = _magic
			# A glowing gold rim, and a ring of runes (little glowing stars) slowly turning on top
			var rim := MeshInstance3D.new()
			var tr := TorusMesh.new()
			tr.inner_radius = RADIUS - 0.06
			tr.outer_radius = RADIUS + 0.04
			rim.mesh = tr
			rim.material_override = _mat(Color(1.0, 0.78, 0.3), true)
			rim.scale.y = 0.6
			rim.position.y = 0.05
			_top.add_child(rim)
			_runes = Node3D.new()
			_runes.position.y = 0.065
			_top.add_child(_runes)
			for i in 7:
				var star := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.16, 0.16, 0.01)
				star.mesh = pm
				star.material_override = _mat(Color(1.0, 0.92, 0.6), true)
				var a := TAU * i / 7.0
				star.position = Vector3(cos(a), 0, sin(a)) * RADIUS * 0.6
				star.rotation = Vector3(-PI / 2, -a, 0)
				_runes.add_child(star)
			var core := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = RADIUS * 0.28
			cc.bottom_radius = RADIUS * 0.28
			cc.height = 0.01
			core.mesh = cc
			core.material_override = _mat(Color(1.0, 0.9, 1.0), true)
			core.position.y = 0.065
			_top.add_child(core)
			var sparkles := CPUParticles3D.new()
			sparkles.amount = 18
			sparkles.lifetime = 1.4
			sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			sparkles.emission_sphere_radius = RADIUS * 0.8
			sparkles.direction = Vector3.UP
			sparkles.spread = 15.0
			sparkles.gravity = Vector3.ZERO
			sparkles.initial_velocity_min = 0.4
			sparkles.initial_velocity_max = 1.0
			sparkles.scale_amount_min = 0.5
			sparkles.scale_amount_max = 1.0
			var mote := SphereMesh.new()
			mote.radius = 0.035
			mote.height = 0.07
			mote.material = _mat(Color(1.0, 0.9, 1.0), true)
			sparkles.mesh = mote
			sparkles.position.y = 0.35
			add_child(sparkles)


func _disc(top_r: float, bottom_r: float, h: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	mi.mesh = c
	mi.position.y = y
	add_child(mi)
	return mi


func _surface(color: Color, kind: String) -> StandardMaterial3D:
	var m := _plain(color)
	Surfaces.apply(m, kind)
	return m


func _plain(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


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
		if body.bounce_from(global_position, velocity()):
			squish()
		return
	if not body.has_method("bounce"):
		return
	if not body.bounce(velocity()):
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
	if _magic:
		_magic_time += delta
		var c := Color.from_hsv(fmod(0.74 + 0.1 * sin(_magic_time * 0.9), 1.0), 0.75, 0.75)
		_magic.albedo_color = c
		_magic.emission = c
		_runes.rotation.y = _magic_time * 0.6
	if _squish > 0.0:
		_squish -= delta
		var s := 1.0 - 0.5 * sin(clampf(_squish / 0.25, 0.0, 1.0) * PI)
		_top.scale = Vector3(1.0 + (1.0 - s) * 0.3, s, 1.0 + (1.0 - s) * 0.3)
