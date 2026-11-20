# The one shrine on each map: the only place to swap skills mid-round.
# A carved two-step stone dais with a gold rim and a slowly turning ring of runes (holy gold on one
# half, demonic red on the other), two angel pillars with gold orbs and two horned demon pillars,
# gold sparkles and red embers drifting up, and a floating orb (gold on top, red underneath)
# inside two turning rings. Ted, Nov 19: "much more ornate". Only the look: its size and use are the same.
# When anyone uses it, a pillar of light shoots up and it chimes, so everyone
# on the map knows someone is standing there (and where to go pester them).
extends Node3D

const PropLib = preload("res://scripts/prop_library.gd")
const Sfx = preload("res://scripts/sfx.gd")

const RADIUS := 2.5           # how close you have to stand to use it
const SWAP_TIME := 3.0        # a swap takes this long in total

var _crystal: Node3D
var _pillar: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _voice: AudioStreamPlayer3D
var _glow := 0.0
var _runes: Node3D
var _rings := []               # the orb's two turning rings
var _rune_mats := []
var _motes := []               # [mesh, base, speed, phase, drift]

static var _chime: AudioStreamWAV


func _ready() -> void:
	if _chime == null:
		_chime = Sfx.voice([[1047, 1047, 0.25, 0.8, 0.0], [1319, 1319, 0.25, 0.7, 0.0], [1568, 1568, 0.6, 0.6, 0.0]], 0.18, 0.0, 0.01, 0.01)
	var dais := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 0.25
	shape.shape = cyl
	shape.position.y = 0.125
	dais.add_child(shape)
	var dm := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 1.6
	dmesh.bottom_radius = 1.75
	dmesh.height = 0.25
	dm.mesh = dmesh
	dm.material_override = PropLib.mat(Color(0.75, 0.72, 0.68), "stone")
	dm.position.y = 0.125
	dais.add_child(dm)
	add_child(dais)
	_build_ornaments()

	_crystal = Node3D.new()
	_crystal.position.y = 1.6
	add_child(_crystal)
	# The orb (Ted, Nov 19: the old floating diamond and halo were a confusing shape): a glowing ball,
	# heavenly gold on top and hellish red underneath, inside two rings turning different ways.
	for half in [[Color(1.0, 0.88, 0.45), false], [Color(0.9, 0.12, 0.06), true]]:
		var mi := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.26
		ball.height = 0.26
		ball.is_hemisphere = true
		mi.mesh = ball
		var m := StandardMaterial3D.new()
		m.albedo_color = half[0]
		m.emission_enabled = true
		m.emission = half[0]
		m.emission_energy_multiplier = 1.6
		mi.material_override = m
		if half[1]:
			mi.rotation.x = PI   # (the bottom half, upside down)
		_crystal.add_child(mi)
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.12
	cm.height = 0.24
	core.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1, 1, 1)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.95, 0.9)
	cmat.emission_energy_multiplier = 3.0
	core.material_override = cmat
	_crystal.add_child(core)
	for r in [[Color(1.0, 0.8, 0.3), 0.42, Vector3(PI / 2, 0, 0.35)], [Color(0.85, 0.12, 0.08), 0.36, Vector3(PI / 2, 0, -0.6)]]:
		var ring_holder := Node3D.new()
		_crystal.add_child(ring_holder)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r[1]
		tm.outer_radius = r[1] + 0.035
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = r[0]
		rm.metallic = 0.8
		rm.roughness = 0.25
		rm.emission_enabled = true
		rm.emission = r[0]
		rm.emission_energy_multiplier = 0.8
		ring.material_override = rm
		ring.rotation = r[2]
		ring_holder.add_child(ring)
		_rings.append(ring_holder)

	_pillar = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.9
	pm.bottom_radius = 0.9
	pm.height = 20.0
	_pillar.mesh = pm
	_pillar_mat = StandardMaterial3D.new()
	_pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pillar_mat.albedo_color = Color(1.0, 0.95, 0.75, 0.0)
	_pillar.material_override = _pillar_mat
	_pillar.position.y = 10.0
	_pillar.visible = false
	add_child(_pillar)

	# A label over it so people can find it and know what it's for.
	var sign := Label3D.new()
	sign.text = "SHRINE\n%s: swap skills" % preload("res://scripts/keybinds.gd").key_name("shrine")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.01
	sign.modulate = Color(1.0, 0.93, 0.7)
	sign.position.y = 2.7
	add_child(sign)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = Sfx.BUS
	_voice.unit_size = 12.0
	_voice.max_distance = 120.0
	_voice.position.y = 1.5
	add_child(_voice)


const HOLY := Color(1.0, 0.85, 0.35)
const HELL := Color(0.95, 0.15, 0.08)


func _glow_mat(c: Color, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, sides := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	return c


func _build_ornaments() -> void:
	var stone := PropLib.mat(Color(0.82, 0.8, 0.76), "stone")
	var dark := PropLib.mat(Color(0.22, 0.18, 0.2), "stone")
	var gold := PropLib.mat(Color(0.95, 0.75, 0.3), "metal")
	# A smaller second step on top, and a gold band around the edge
	_mesh(_cyl(1.15, 1.25, 0.12), stone, Vector3(0, 0.31, 0))
	var band := TorusMesh.new()
	band.inner_radius = 1.62
	band.outer_radius = 1.72
	_mesh(band, gold, Vector3(0, 0.24, 0)).scale.y = 0.5
	# The rune ring: glowing glyphs laid in the top, gold on the heavenly half, red on the hellish half
	_runes = Node3D.new()
	_runes.position.y = 0.255
	add_child(_runes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1777   # the same runes on every screen
	var count := 14
	for i in count:
		var a := TAU * (i + 0.5) / count
		var holy := i < count / 2
		var mat := _glow_mat(HOLY if holy else HELL, 1.3)
		_rune_mats.append(mat)
		var glyph := Node3D.new()
		glyph.position = Vector3(cos(a), 0, sin(a)) * 1.38
		glyph.rotation.y = -a + PI / 2
		_runes.add_child(glyph)
		# Each rune: a stem and two or three strokes, a different shape every time
		_mesh(_box(Vector3(0.035, 0.01, 0.26)), mat, Vector3.ZERO, glyph)
		for k in rng.randi_range(2, 3):
			var stroke := _mesh(_box(Vector3(0.03, 0.01, rng.randf_range(0.1, 0.18))), mat,
					Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.1, 0.1)), glyph)
			stroke.rotation.y = rng.randf_range(-1.2, 1.2)
		if holy and i % 2 == 0:   # some holy runes get a little ring
			var ring := TorusMesh.new()
			ring.inner_radius = 0.06
			ring.outer_radius = 0.085
			_mesh(ring, mat, Vector3(0, 0, -0.17), glyph).scale.y = 0.2
	# Four pillars at the corners of the dais: two angelic (white, gold orb), two demonic (black, horns)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var at := Vector3(cos(a), 0, sin(a)) * 1.45
		var holy := k < 2
		var pil := Node3D.new()
		pil.position = at + Vector3(0, 0.25, 0)
		add_child(pil)
		_mesh(_cyl(0.11, 0.15, 0.12, 8), gold if holy else dark, Vector3(0, 0.06, 0), pil)
		_mesh(_cyl(0.08, 0.1, 1.1, 8), stone if holy else dark, Vector3(0, 0.67, 0), pil)
		_mesh(_cyl(0.13, 0.1, 0.1, 8), gold if holy else dark, Vector3(0, 1.27, 0), pil)
		if holy:
			var orb := SphereMesh.new()
			orb.radius = 0.12
			orb.height = 0.24
			_mesh(orb, _glow_mat(HOLY, 2.0), Vector3(0, 1.45, 0), pil)
			for side in [-1.0, 1.0]:   # little wings
				var wing := _mesh(_box(Vector3(0.22, 0.12, 0.02)), _glow_mat(Color(1.0, 0.97, 0.88), 0.6), Vector3(0.16 * side, 1.4, 0), pil)
				wing.rotation.z = 0.5 * side
		else:
			for side in [-1.0, 1.0]:   # horns
				var horn := _mesh(_cyl(0.0, 0.05, 0.3, 8), _glow_mat(HELL, 1.0), Vector3(0.07 * side, 1.45, 0), pil)
				horn.rotation.z = -0.45 * side
			var ember := SphereMesh.new()
			ember.radius = 0.06
			ember.height = 0.12
			_mesh(ember, _glow_mat(HELL, 2.5), Vector3(0, 1.36, 0), pil)
	# Gold sparkles rising on the holy side, red embers on the hellish side
	_add_motes(HOLY, Vector3(0, 0.4, -0.7), 0.3)
	_add_motes(HELL, Vector3(0, 0.4, 0.7), -0.3)
	# A soft light, so it glows on whatever's around it
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.6)
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.position.y = 1.6
	add_child(light)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# Motes drifting up, animated by hand: Godot's particle systems draw from the game's shared random
# numbers, which would shift the seeded layouts the tests rely on.
func _add_motes(color: Color, at: Vector3, drift: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if drift > 0.0 else 666
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _glow_mat(color, 3.0)
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var base := at + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-0.6, 0.6))
		_motes.append([mi, base, rng.randf_range(0.3, 0.7), rng.randf(), drift])


func _move_motes() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for m in _motes:
		var k := fmod(t * m[2] / 1.8 + m[3], 1.0)   # 0 -> 1 as it rises, then starts over
		m[0].position = m[1] + Vector3(m[4] * k + sin(t * 2.0 + m[3] * 9.0) * 0.05, k * 1.8, 0.0)
		m[0].scale = Vector3.ONE * sin(k * PI)


# Someone started swapping here: light it up for everyone to see and hear.
func flare() -> void:
	_glow = SWAP_TIME + 0.5
	_voice.stream = _chime
	_voice.play()


func _process(delta: float) -> void:
	_crystal.rotation.y += delta * (4.0 if _glow > 0.0 else 0.6)
	for i in _rings.size():
		_rings[i].rotation.x += delta * (1.1 if i == 0 else -0.8) * (3.0 if _glow > 0.0 else 1.0)
	_runes.rotation.y -= delta * (1.5 if _glow > 0.0 else 0.15)
	var pulse := 1.1 + 0.4 * sin(Time.get_ticks_msec() / 400.0) + (2.0 if _glow > 0.0 else 0.0)
	for m in _rune_mats:
		m.emission_energy_multiplier = pulse
	_move_motes()
	_crystal.position.y = 1.6 + sin(Time.get_ticks_msec() / 600.0) * 0.1
	_glow = maxf(_glow - delta, 0.0)
	_pillar.visible = _glow > 0.0
	_pillar_mat.albedo_color.a = minf(_glow, 1.0) * 0.35
