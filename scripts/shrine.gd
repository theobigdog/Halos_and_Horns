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
var _halos := []               # the halos over the angel pillars
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
	# A big sparkly d20 (Wife's notes, Nov 21: the floating ball was dull): gold faces on top, ruby
	# underneath, glinting as it turns, numbered like a real one (opposite faces add up to 21).
	_crystal.add_child(_d20(0.34))

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

const D20_SHADER := """
shader_type spatial;
varying float face;
void vertex() { face = UV.x; }
void fragment() {
	vec3 c = COLOR.rgb;
	// each face glints now and then (a slow twinkle, different per face) on top of the real reflections
	float tw = pow(max(sin(TIME * 2.3 + face * 7.13) * 0.5 + 0.5, 0.0), 12.0);
	ALBEDO = c;
	METALLIC = 0.55;
	ROUGHNESS = 0.2;
	EMISSION = c * (0.08 + tw * 2.5);
}
"""


# An icosahedron with flat faces (gold above, ruby below) and the numbers 1-20 on them.
func _d20(r: float) -> Node3D:
	var n := Node3D.new()
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			v.append(Vector3(0, a, b * t))
			v.append(Vector3(a, b * t, 0))
			v.append(Vector3(b * t, 0, a))
	var faces := []
	for i in v.size():
		for j in range(i + 1, v.size()):
			for k in range(j + 1, v.size()):
				if absf(v[i].distance_to(v[j]) - 2.0) < 0.01 and absf(v[j].distance_to(v[k]) - 2.0) < 0.01 \
						and absf(v[i].distance_to(v[k]) - 2.0) < 0.01:
					faces.append([v[i], v[j], v[k]])
	# number them so opposite faces add up to 21
	var nums := {}
	var next := 1
	for fi in faces.size():
		if nums.has(fi):
			continue
		var c: Vector3 = (faces[fi][0] + faces[fi][1] + faces[fi][2]) / 3.0
		for fj in faces.size():
			var cj: Vector3 = (faces[fj][0] + faces[fj][1] + faces[fj][2]) / 3.0
			if (cj + c).length() < 0.01:
				nums[fi] = next
				nums[fj] = 21 - next
		next += 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := r / sqrt(1.0 + t * t)
	var gold_c := Color(0.8, 0.52, 0.08)
	var ruby_c := Color(0.5, 0.01, 0.03)
	for fi in faces.size():
		var f: Array = faces[fi]
		var c: Vector3 = (f[0] + f[1] + f[2]) / 3.0
		var nrm := c.normalized()
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var d: Vector3 = f[2]
		if (b - a).cross(d - a).dot(nrm) > 0.0:   # (Godot wants clockwise from the outside)
			var tmp := b
			b = d
			d = tmp
		var upper := c.y > 0.05 or (absf(c.y) <= 0.05 and fi % 2 == 0)
		var col := gold_c if upper else ruby_c
		for q in [a, b, d]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2(float(fi), 0.0))
			st.add_vertex(q * sc)
		# its number, flat on the face
		var lbl := Label3D.new()
		lbl.text = str(nums.get(fi, fi + 1))
		lbl.font_size = 64
		lbl.pixel_size = 0.0022
		lbl.outline_size = 0
		lbl.modulate = Color(0.3, 0.1, 0.02) if upper else Color(1.0, 0.9, 0.6)
		lbl.double_sided = false
		lbl.shaded = false
		lbl.basis = Basis.looking_at(-nrm, Vector3.UP if absf(nrm.y) < 0.95 else Vector3.FORWARD)
		lbl.position = c * sc * 1.03
		n.add_child(lbl)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = D20_SHADER
	mat.shader = sh
	mi.material_override = mat
	n.add_child(mi)
	return n

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
	# A fancy round rug on the top step (Wife's notes, Nov 21): ivory on the heavenly half, crimson on the
	# hellish half, gold and black rings, a gold sun on one side, black horns on the other, a gold fringe.
	var rug := Node3D.new()
	rug.position.y = 0.372
	add_child(rug)
	var ivory_cloth := PropLib.mat(Color(0.96, 0.92, 0.82), "fabric")
	var crimson := PropLib.mat(Color(0.55, 0.05, 0.08), "fabric")
	var black_cloth := PropLib.mat(Color(0.1, 0.06, 0.08), "fabric")
	var gold_thread := _gold_mat()
	_mesh(_half_disc(1.02, 0.012), ivory_cloth, Vector3.ZERO, rug)
	_mesh(_half_disc(1.02, 0.012), crimson, Vector3.ZERO, rug).rotation.y = PI
	for rr in [[0.98, 0.035, gold_thread], [0.74, 0.025, gold_thread], [0.5, 0.02, black_cloth], [0.3, 0.02, gold_thread]]:
		var ring_m := TorusMesh.new()
		ring_m.inner_radius = rr[0] - rr[1]
		ring_m.outer_radius = rr[0]
		ring_m.rings = 48
		_mesh(ring_m, rr[2], Vector3(0, 0.014, 0), rug).scale.y = 0.12
	for k3 in 8:
		var aa := PI * (k3 + 0.5) / 8.0
		var ray := _mesh(_box(Vector3(0.035, 0.008, 0.18)), gold_thread, Vector3(cos(aa) * 0.6, 0.016, -sin(aa) * 0.6), rug)
		ray.rotation.y = aa + PI / 2
	for k3 in 6:
		var aa2 := PI + PI * (k3 + 0.5) / 6.0
		var spike := _mesh(_cyl(0.0, 0.05, 0.14, 4), black_cloth, Vector3(cos(aa2) * 0.6, 0.016, -sin(aa2) * 0.6), rug)
		spike.basis = _up_to(Vector3(cos(aa2), 0, -sin(aa2))) * Basis.from_scale(Vector3(1, 1, 0.15))
	for k3 in 28:
		var aa3 := TAU * k3 / 28.0
		_mesh(_box(Vector3(0.03, 0.01, 0.07)), gold_thread, Vector3(cos(aa3) * 1.06, 0.006, sin(aa3) * 1.06), rug).rotation.y = -aa3 + PI / 2
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
		var mat := _gold_mat() if holy else _glow_mat(HELL, 1.3)
		if not holy:
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
	# Four pillars at the corners of the dais, angels and demons facing each other across it (Ted, Nov 20):
	# ivory angel pillars with a floating halo, dark demon pillars topped with horns and a trident.
	var ivory := PropLib.mat(Color(1.0, 0.96, 0.86), "marble")
	ivory.roughness = 0.25
	var iron := PropLib.mat(Color(0.2, 0.17, 0.17), "metal")
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var at := Vector3(cos(a), 0, sin(a)) * 1.45
		var holy := k % 2 == 0   # opposite corners match
		var pil := Node3D.new()
		pil.position = at + Vector3(0, 0.25, 0)
		add_child(pil)
		_mesh(_cyl(0.11, 0.15, 0.12, 12 if holy else 8), gold if holy else dark, Vector3(0, 0.06, 0), pil)
		_mesh(_cyl(0.08, 0.1, 1.1, 12 if holy else 8), ivory if holy else dark, Vector3(0, 0.67, 0), pil)
		_mesh(_cyl(0.13, 0.1, 0.1, 12 if holy else 8), gold if holy else dark, Vector3(0, 1.27, 0), pil)
		if holy:
			var halo := TorusMesh.new()
			halo.inner_radius = 0.1
			halo.outer_radius = 0.135
			var h := _mesh(halo, _gold_mat(), Vector3(0, 1.55, 0), pil)
			h.rotation.x = 0.25
			_halos.append(h)
		else:
			# big curved horns sweeping out and up from the top (Wife's notes, Nov 21: instead of a trident),
			# glowing red-hot at the tips
			for side in [-1.0, 1.0]:
				var segs := 7
				var prev := Vector3(0.07 * side, 1.34, 0)
				for k2 in segs:
					var u := float(k2 + 1) / segs
					# bull-ish: out sideways, up, and the tip curling back in and forward
					var pt := Vector3(side * (0.06 + 0.3 * sin(u * PI * 0.78)), 1.34 + 0.34 * u * u, 0.1 * sin(u * PI) * u)
					var rad_a := lerpf(0.085, 0.01, pow(float(k2) / segs, 0.8))
					var rad_b := lerpf(0.085, 0.01, pow(u, 0.8))
					var seg := _mesh(_cyl(rad_b, rad_a, prev.distance_to(pt) + 0.02, 8),
							_glow_mat(HELL, 2.0) if k2 >= segs - 2 else dark, (prev + pt) * 0.5, pil)
					seg.basis = _up_to(pt - prev)
					prev = pt
			# an iron collar round the base of the horns
			_mesh(_cyl(0.12, 0.13, 0.05, 8), iron, Vector3(0, 1.34, 0), pil)
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


# Polished metallic gold, like the base's band, with a faint glow (Wife's notes, Nov 21).
var _gold: StandardMaterial3D


func _gold_mat() -> StandardMaterial3D:
	if _gold == null:
		_gold = StandardMaterial3D.new()
		_gold.albedo_color = Color(1.0, 0.78, 0.3)
		_gold.metallic = 1.0
		_gold.roughness = 0.22
		_gold.emission_enabled = true
		_gold.emission = Color(1.0, 0.75, 0.3)
		_gold.emission_energy_multiplier = 0.25
	return _gold


# Half a thin disc (the rug is two halves of different cloth).
func _half_disc(r: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, h, 0))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a1) * r, h, -sin(a1) * r))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(cos(a0) * r, h, -sin(a0) * r))
	return st.commit()


func _up_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


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
	for h in _halos:
		h.position.y = 1.55 + sin(Time.get_ticks_msec() / 500.0) * 0.04
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
