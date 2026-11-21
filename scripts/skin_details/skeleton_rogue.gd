# Skeleton Rogue details: a hellish (and slightly hopeless) assassin. Ember-stitched hood with a brand
# on the forehead and a pair of "eyes in the back of my head", bone spikes poking out of the hood's
# sides and horn roots through the top so the skull still reads as a skull; crossed knife bandoliers,
# a tattered scarf, spiked bracers and a branded cape; a belt with a padlocked chain, a leg dagger and
# spiked boot cuffs. Model units, each piece in its bone's space (+Z = the character's front).
extends RefCounted


# ---------------- shared bits ----------------

static func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# Embers that breathe slowly (a shader on TIME, no scripts)
static func _ember(c := Color(1.0, 0.24, 0.04), e := 2.2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 col = vec3(1.0, 0.36, 0.08);
uniform float energy = 3.0;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float p = 0.72 + 0.28 * sin(TIME * 2.6 + w.y * 9.0 + w.x * 5.0);
	ALBEDO = col;
	EMISSION = col * energy * p;
	ROUGHNESS = 0.5;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("energy", e)
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mesh.get_aabb().get_longest_axis_size() < 0.08 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(top: float, bottom: float, h: float, sides := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


static func _ball(r: float, segs := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


static func _ring(r: float, t: float, segs := 10) -> TorusMesh:
	var t2 := TorusMesh.new()
	t2.inner_radius = r - t
	t2.outer_radius = r + t
	t2.rings = segs
	t2.ring_segments = 5
	return t2


static func _prism(s: Vector3, left := 0.5) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = s
	p.left_to_right = left
	return p


# Points a node's +Y along dir
static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


static func _bone(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	sk.add_child(a)
	return a


# A small throwing knife pointing along +Y (blade up), lying flat in the XY plane
static func _knife(parent: Node3D, pos: Vector3, rot: Vector3, steel: Mesh, grip: Mesh, pommel: Mesh, m_steel: Material, m_grip: Material, m_ember: Material) -> void:
	var k := Node3D.new()
	k.position = pos
	k.rotation = rot
	parent.add_child(k)
	_add(k, steel, m_steel, Vector3(0, 0.07, 0))
	_add(k, grip, m_grip, Vector3(0, -0.035, 0))
	_add(k, pommel, m_ember, Vector3(0, -0.085, 0), Vector3(PI / 2, 0, 0))


# ---------------- head ----------------

# A glowing horned eye-sigil (the rogue's brand), facing +Z
static func _brand(parent: Node3D, pos: Vector3, tilt: float, size: float, ember: Material, hot: Material) -> void:
	var brand := Node3D.new()
	brand.position = pos
	brand.rotation.x = tilt
	brand.scale = Vector3.ONE * size
	parent.add_child(brand)
	_add(brand, _ring(0.075, 0.016), ember, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_add(brand, _ball(0.03), hot, Vector3(0, 0, 0.01), Vector3.ZERO, Vector3(1, 1, 0.5))
	for side in [-1.0, 1.0]:
		_add(brand, _prism(Vector3(0.04, 0.08, 0.02)), ember, Vector3(0.06 * side, 0.08, 0), Vector3(0, 0, -0.5 * side))

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var char_black := _mat(Color(0.1, 0.07, 0.07), 0.9)
	var bone := _mat(Color(0.92, 0.87, 0.74), 0.6)
	var horn := _mat(Color(0.16, 0.1, 0.1), 0.4)   # (matches the team horns)
	var ember := _ember()
	var hot := _ember(Color(1.0, 0.42, 0.1), 3.0)
	var stitch := _box(Vector3(0.025, 0.07, 0.025))
	var demon := role == "demon"

	if bare:
		# A bare skull: a glowing crack down the back of the head, and a throwing knife stuck in it
		# (a rival's, or his own: he won't say)
		var crack := [Vector3(0.05, 0.86, -0.36), Vector3(-0.08, 0.72, -0.44), Vector3(0.06, 0.58, -0.46), Vector3(-0.04, 0.44, -0.45)]
		for i in crack.size() - 1:
			var a: Vector3 = crack[i]
			var b: Vector3 = crack[i + 1]
			var seg := _add(att, _box(Vector3(0.032, (b - a).length() + 0.03, 0.05)), ember, (a + b) * 0.5)
			seg.basis = _basis_y(b - a)
			var st := _add(att, _box(Vector3(0.09, 0.02, 0.04)), char_black, (a + b) * 0.5 + Vector3(0, 0, -0.012))
			st.basis = _basis_y(b - a) * Basis(Vector3.BACK, PI / 2)
		_brand(att, Vector3(0, 0.74, 0.4), -0.45, 0.8, ember, hot)   # branded right on the forehead
		var stuck := Node3D.new()
		stuck.position = Vector3(0.18, 0.78, -0.38)
		stuck.basis = _basis_y(Vector3(0.5, 0.45, -1.0))
		att.add_child(stuck)
		_add(stuck, _box(Vector3(0.05, 0.12, 0.05)), _mat(Color(0.22, 0.12, 0.08), 0.85), Vector3(0, 0.08, 0))
		_add(stuck, _box(Vector3(0.14, 0.03, 0.06)), _mat(Color(0.45, 0.28, 0.18), 0.55, 0.6), Vector3(0, 0.0, 0))
		_add(stuck, _ring(0.03, 0.01, 8), ember, Vector3(0, 0.16, 0), Vector3(PI / 2, 0, 0))
		# horn roots growing out of the skull
		if demon:
			for side in [-1.0, 1.0]:
				var dir := Vector3(0.45 * side, 1.0, -0.15).normalized()
				var base := Vector3(0.28 * side, 1.0, 0.05)
				var root := _add(att, _cyl(0.09, 0.12, 0.22), horn, base - dir * 0.1)
				root.basis = _basis_y(dir)
				var collar := _add(att, _ring(0.12, 0.025), ember, base - dir * 0.19)
				collar.basis = _basis_y(dir)
		return

	# ---- hooded ----
	# Horns burst out through the hood: dark roots with ragged, ember-singed holes
	if demon:
		for side in [-1.0, 1.0]:
			var dir := Vector3(0.45 * side, 1.0, -0.15).normalized()
			var base := Vector3(0.28 * side, 1.1, 0.05)
			var root := _add(att, _cyl(0.09, 0.12, 0.3), horn, base - dir * 0.14)
			root.basis = _basis_y(dir)
			var collar := _add(att, _ring(0.13, 0.03), char_black, base - dir * 0.24)
			collar.basis = _basis_y(dir)
			var singe := _add(att, _ring(0.155, 0.015), ember, base - dir * 0.25)
			singe.basis = _basis_y(dir)

	# A brand on the hood's forehead: a glowing horned eye-sigil
	_brand(att, Vector3(0, 0.83, 0.43), -0.55, 1.0, ember, hot)

	# Eyes in the back of my head: a goofy painted skull face on the back of the hood
	var back := Node3D.new()
	back.position = Vector3(0, 0.5, -0.515)
	att.add_child(back)
	var socket := _ball(0.1)
	var pupil := _ball(0.045)
	for side in [-1.0, 1.0]:
		_add(back, socket, char_black, Vector3(0.17 * side, 0.0, 0.0), Vector3(0, 0, 0.35 * side), Vector3(1.0, 0.7, 0.35))
		_add(back, pupil, hot, Vector3(0.16 * side, -0.01, -0.03), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
	# a stitched grin under them
	_add(back, _box(Vector3(0.3, 0.025, 0.03)), ember, Vector3(0, -0.19, 0.01))
	for i in 5:
		_add(back, stitch, char_black, Vector3(-0.12 + i * 0.06, -0.19, -0.005))

	# Bone spikes poking out through the hood's sides (the skull is in there!)
	var spike := _cyl(0.0, 0.075, 0.28, 6)
	var tear := _ring(0.09, 0.022, 8)
	for side in [-1.0, 1.0]:
		var at := Vector3(0.55 * side, 0.42, -0.05)
		var d := Vector3(side, 0.55, -0.6).normalized()
		var sp := _add(att, spike, bone, at + d * 0.08)
		sp.basis = _basis_y(d)
		var t := _add(att, tear, char_black, at)
		t.basis = _basis_y(d)
		var g := _add(att, _ring(0.11, 0.012, 8), ember, at - d * 0.01)
		g.basis = _basis_y(d)

	# Ember stitches along the hood's face opening (an arch over the face)
	for i in 7:
		var a := lerpf(-0.95, 0.95, i / 6.0)
		var p := Vector3(sin(a) * 0.47, 0.32 + cos(a) * 0.38, 0.5 - absf(sin(a)) * 0.1)
		var st := _add(att, stitch, ember, p)
		st.basis = Basis(Vector3.BACK, -a)


# ---------------- upper ----------------

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var leather := _mat(Color(0.22, 0.12, 0.08), 0.85)
	var iron := _mat(Color(0.45, 0.28, 0.18), 0.55, 0.6)   # rusted
	var steel := _mat(Color(0.85, 0.85, 0.9), 0.25, 0.3)
	var char_black := _mat(Color(0.1, 0.07, 0.07), 0.9)
	var rag := _mat(Color(0.3, 0.05, 0.08), 0.9)
	rag.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ember := _ember()

	# Crossed bandoliers over the chest, front and back
	var strap := _box(Vector3(0.09, 0.74, 0.035))
	for side in [-1.0, 1.0]:
		_add(att, strap, leather, Vector3(0, -0.2, 0.33), Vector3(-0.12, 0, 0.72 * side))
		_add(att, strap, leather, Vector3(0, -0.2, -0.34), Vector3(0.12, 0, 0.72 * side))
	_add(att, _cyl(0.07, 0.07, 0.04, 8), iron, Vector3(0, -0.2, 0.355), Vector3(PI / 2, 0, 0))
	_add(att, _ball(0.035), ember, Vector3(0, -0.2, 0.38), Vector3.ZERO, Vector3(1, 1, 0.5))
	# throwing knives tucked into the strap that runs up to the left shoulder, blades up and out
	var blade := _prism(Vector3(0.08, 0.2, 0.02))
	var grip := _box(Vector3(0.035, 0.07, 0.035))
	var pommel := _ring(0.025, 0.009, 8)
	var up := Vector3(sin(0.72), cos(0.72), 0)
	for i in 3:
		var p := Vector3(0, -0.2, 0.38) + up * (0.0 + i * 0.11)
		_knife(att, p, Vector3(0, 0, 0.35), blade, grip, pommel, steel, leather, ember)

	# A tattered scarf: two ragged tails fluttering from under the hood
	var tail := _box(Vector3(0.1, 0.2, 0.025))
	var tip := _prism(Vector3(0.1, 0.1, 0.025), 0.2)
	for t in [[0.2, 0.0, 0.12], [0.3, 0.04, 0.4]]:
		var n := Node3D.new()
		n.position = Vector3(t[0], 0.12 + t[1], 0.345)
		n.rotation = Vector3(-0.15, 0, t[2])
		att.add_child(n)
		_add(n, tail, rag, Vector3(0, -0.1, 0))
		_add(n, tip, rag, Vector3(0, -0.25, 0), Vector3(0, 0, PI))

	# Spiked, rusty bracers on both forearms
	var cuff := _cyl(0.1, 0.095, 0.13, 8)
	var band := _ring(0.1, 0.012, 10)
	var spike := _cyl(0.0, 0.035, 0.11, 5)
	for s in ["l", "r"]:
		var a := _bone(sk, "lowerarm." + s)
		_add(a, cuff, iron, Vector3(0, 0.17, 0))
		_add(a, band, ember, Vector3(0, 0.17, 0))
		for k in 3:
			var ang := k * TAU / 3.0 + 0.5
			var d := Vector3(cos(ang), 0, sin(ang))
			var sp := _add(a, spike, char_black, Vector3(0, 0.17, 0) + d * 0.12)
			sp.basis = _basis_y(d)

	if bare:
		return
	# The cape: a glowing brand (a horned skull-ish sigil) and ember-singed tatters at the hem
	var sig := Node3D.new()
	sig.position = Vector3(0, -0.42, -0.4)
	sig.rotation.y = PI
	att.add_child(sig)
	_add(sig, _ring(0.11, 0.018), ember, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_add(sig, _prism(Vector3(0.13, 0.13, 0.02)), ember, Vector3(0, -0.005, 0), Vector3(0, 0, PI))
	for side in [-1.0, 1.0]:
		_add(sig, _prism(Vector3(0.05, 0.11, 0.02)), ember, Vector3(0.1 * side, 0.12, 0), Vector3(0, 0, -0.45 * side))
	# a rusty clasp and chain across the collar front
	for side in [-1.0, 1.0]:
		_add(att, _cyl(0.05, 0.05, 0.03, 6), iron, Vector3(0.3 * side, 0.18, 0.2), Vector3(PI / 2, 0, 0))


# ---------------- lower ----------------

static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var leather := _mat(Color(0.22, 0.12, 0.08), 0.85)
	var iron := _mat(Color(0.45, 0.28, 0.18), 0.55, 0.6)
	var steel := _mat(Color(0.62, 0.6, 0.62), 0.3, 0.8)
	var char_black := _mat(Color(0.1, 0.07, 0.07), 0.9)
	var bone := _mat(Color(0.92, 0.87, 0.74), 0.6)
	var rag := _mat(Color(0.3, 0.05, 0.08), 0.9)
	rag.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ember := _ember()

	# Belt with a little skull buckle
	_add(att, _cyl(0.36, 0.36, 0.07, 12), leather, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 1, 0.9))
	_add(att, _ball(0.07), bone, Vector3(0, 0.06, 0.33), Vector3.ZERO, Vector3(1, 0.9, 0.6))
	for side in [-1.0, 1.0]:
		_add(att, _ball(0.018), ember, Vector3(0.025 * side, 0.07, 0.37))
	# a tattered loincloth flap with an ember rune
	_add(att, _prism(Vector3(0.2, 0.24, 0.02), 0.55), rag, Vector3(0, -0.07, 0.34), Vector3(PI, 0, 0))
	for side in [-1.0, 1.0]:   # a little horned "V" rune
		_add(att, _box(Vector3(0.02, 0.09, 0.01)), ember, Vector3(0.022 * side, -0.05, 0.355), Vector3(0, 0, 0.4 * side))
	# a chain looping from the belt to a goofy padlock on the hip
	var link := _ring(0.035, 0.01, 8)
	for i in 5:
		var p := Vector3(0.36, 0.03 - i * 0.04, 0.1 - i * 0.05)
		_add(att, link, iron, p, Vector3(0, 0, PI / 2) if i % 2 == 0 else Vector3(0, PI / 2, PI / 2))
	_add(att, _box(Vector3(0.03, 0.1, 0.09)), iron, Vector3(0.37, -0.22, -0.16), Vector3.ZERO)
	_add(att, _ring(0.03, 0.01, 8), steel, Vector3(0.37, -0.16, -0.16), Vector3(0, 0, PI / 2))
	_add(att, _ball(0.015), ember, Vector3(0.39, -0.23, -0.16))

	# A dagger strapped to the right thigh
	var thigh := _bone(sk, "upperleg.r")
	_add(thigh, _cyl(0.135, 0.135, 0.04, 10), leather, Vector3(0, 0.12, 0))
	var dag := Node3D.new()
	dag.position = Vector3(-0.15, 0.12, 0.0)
	dag.rotation.z = -0.1
	thigh.add_child(dag)
	_add(dag, _box(Vector3(0.04, 0.2, 0.07)), char_black, Vector3(0, 0.04, 0))   # sheath (point down the leg)
	_add(dag, _box(Vector3(0.04, 0.06, 0.03)), leather, Vector3(0, -0.1, 0))     # grip (up)
	_add(dag, _box(Vector3(0.05, 0.02, 0.12)), iron, Vector3(0, -0.065, 0))      # guard
	_add(dag, _ball(0.025), ember, Vector3(0, -0.14, 0))

	# Spiked boot cuffs
	var cuffring := _ring(0.14, 0.03, 10)
	var spike := _cyl(0.0, 0.035, 0.1, 5)
	for s in ["l", "r"]:
		var shin := _bone(sk, "lowerleg." + s)
		_add(shin, cuffring, iron, Vector3(0, 0.06, 0))
		for k in 4:
			var ang := k * TAU / 4.0 + PI / 4
			var d := Vector3(cos(ang), 0.25, sin(ang)).normalized()
			var sp := _add(shin, spike, char_black, Vector3(0, 0.06, 0) + Vector3(cos(ang), 0, sin(ang)) * 0.16)
			sp.basis = _basis_y(d)
		_add(shin, _ring(0.145, 0.008, 10), ember, Vector3(0, 0.035, 0))
