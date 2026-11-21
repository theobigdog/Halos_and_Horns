extends RefCounted
# Skeleton Minion: an impish little gremlin of hell.
# head: crooked iron nose-ring, a bone-and-iron earring, a glowing crack on the cranium, a snaggle fang,
#       a row of charred spikes down the back of the skull.
# upper: a glowing "horned grin" brand on the chest, bone spikes down the spine, spiked iron wristbands
#        (one with a broken shackle chain).
# lower: a swishing devil tail with a glowing spade tip, a scrappy loincloth with a burning hem,
#        black toe talons, an iron ankle cuff with a broken chain.
# (Bone spaces in KayKit units: +Z is the front, +Y up, +X the character's left.)

const CHAR := Color(0.16, 0.08, 0.07)      # charred black-red (matches the horns)
const DEVIL := Color(0.32, 0.05, 0.04)     # devil-tail red
const IRON := Color(0.36, 0.22, 0.14)      # rusted iron
const BONE := Color(0.88, 0.84, 0.72)      # old bone
const CLOTH := Color(0.22, 0.13, 0.1)      # scorched rag
const EMBER := Color(1.0, 0.22, 0.03)      # ember glow

static var _shader: Shader


# ---------------- shared bits ----------------

static func _plain(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# Vertex colour red = how much the spot glows (ember); sway = how much it swishes side to side
# (by distance behind the base, along -Z). The glow pulses gently.
static func _ember_mat(base: Color, sway: float, glow := 2.6) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col : source_color;
uniform vec3 glow_col : source_color;
uniform float glow = 2.6;
uniform float sway = 0.0;
varying float g;
void vertex() {
	g = COLOR.r;
	float t = max(0.0, -VERTEX.z - 0.15);
	VERTEX.x += sin(TIME * 2.6 + t * 4.0) * t * sway;
	VERTEX.y += sin(TIME * 1.7 + t * 3.0) * t * sway * 0.35;
}
void fragment() {
	ALBEDO = mix(base_col, glow_col, g);
	ROUGHNESS = 0.6;
	EMISSION = glow_col * g * glow * (0.8 + 0.2 * sin(TIME * 3.1));
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("glow_col", Vector3(EMBER.r, EMBER.g, EMBER.b))
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("sway", sway)
	return m


static func _glow_mat(e := 3.0) -> ShaderMaterial:
	var m := _ember_mat(EMBER, 0.0, e)
	return m


static func _add(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mesh is TorusMesh else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _cone(r: float, h: float, segs := 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _ring(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 6
	return t


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# A cone pointing along dir with its base at `at`.
static func _spike(parent: Node, mesh: CylinderMesh, mat: Material, at: Vector3, dir: Vector3) -> void:
	_add(parent, mesh, mat, at + dir.normalized() * mesh.height * 0.5, _align_y(dir))


static func _bone_att(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	sk.add_child(a)
	return a


# ---------------- head ----------------

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var iron := _plain(IRON, 0.45, 0.6)
	var bone := _plain(BONE, 0.8)
	var dark := _plain(CHAR, 0.45)
	var glow := _glow_mat(1.8)
	# Crooked nose-ring hanging from the nose hole, tilted for mischief
	var nose := _add(att, _ring(0.045, 0.075), iron, Vector3(0.015, 0.215, 0.44),
		Basis(Vector3.RIGHT, PI / 2 - 0.25) * Basis(Vector3.FORWARD, 0.3))
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Earring on the left side of the skull: an iron hoop with a little bone dangling off it
	_add(att, _ring(0.05, 0.08), iron, Vector3(0.44, 0.3, 0.04), Basis(Vector3.FORWARD, PI / 2))
	var dangle := CapsuleMesh.new()
	dangle.radius = 0.03
	dangle.height = 0.16
	dangle.radial_segments = 6
	dangle.rings = 1
	_add(att, dangle, bone, Vector3(0.46, 0.17, 0.05), Basis(Vector3.FORWARD, 0.5))
	var knob := SphereMesh.new()
	knob.radius = 0.035
	knob.height = 0.07
	knob.radial_segments = 6
	knob.rings = 3
	for s in [-1.0, 1.0]:
		_add(att, knob, bone, Vector3(0.46, 0.17, 0.05) + Basis(Vector3.FORWARD, 0.5) * Vector3(s * 0.025, s * 0.07, 0))
	# Snaggle fang poking up over the upper lip on the right
	_spike(att, _cone(0.04, 0.13, 5), bone, Vector3(-0.12, 0.08, 0.4), Vector3(-0.1, 1.0, 0.35))
	# Glowing crack over the cranium (front-left to the back)
	var pts := [Vector3(-0.21, 0.55, 0.43), Vector3(-0.13, 0.64, 0.42), Vector3(-0.19, 0.72, 0.39),
		Vector3(-0.13, 0.79, 0.34)]
	var crack := BoxMesh.new()
	crack.size = Vector3(0.04, 0.07, 1.0)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var mi := _add(att, crack, glow, (a + b) * 0.5, Basis.looking_at(b - a, Vector3.FORWARD) * Basis.from_scale(Vector3(1, 1, a.distance_to(b) + 0.03)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A row of charred spikes down the back of the skull (a punky little crest)
	var sp := _cone(0.055, 0.17, 5)
	for i in 4:
		var t := i / 3.0
		var a := lerpf(0.55, 1.75, t)   # angle around the X axis from straight up toward the back
		var at := Vector3(0, 0.5 + cos(a) * 0.42, -sin(a) * 0.44)
		_spike(att, sp, dark, at, Vector3(0, cos(a), -sin(a)))


# ---------------- upper ----------------

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var iron := _plain(IRON, 0.45, 0.6)
	var bone := _plain(BONE, 0.8)
	var glow := _glow_mat(1.8)
	# The brand: a "horned grin" rune burned into the chest (on the mantle, or the ribs when bare)
	var brand := Node3D.new()
	brand.position = Vector3(0, 0.02, 0.37) if not bare else Vector3(0, 0.04, 0.26)
	brand.rotation.x = -0.35 if not bare else -0.1
	att.add_child(brand)
	var bar := BoxMesh.new()
	bar.size = Vector3(0.035, 0.035, 0.035)
	var face := _ring(0.075, 0.105)
	_add(brand, face, glow, Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(1, 0.3, 1)))
	for s in [-1.0, 1.0]:
		# horns
		_add(brand, bar, glow, Vector3(s * 0.08, 0.13, 0), Basis(Vector3.FORWARD, s * 0.5).scaled(Vector3(1, 2.2, 0.5)))
		# eyes
		_add(brand, bar, glow, Vector3(s * 0.035, 0.025, 0), Basis.from_scale(Vector3(0.8, 0.8, 0.5)))
	# grin
	_add(brand, bar, glow, Vector3(0, -0.035, 0), Basis.from_scale(Vector3(2.0, 0.6, 0.5)))
	# Bone spikes down the spine (low on the back, under the wings)
	var sp := _cone(0.06, 0.2, 5)
	for i in 3:
		var y := -0.38 + i * 0.11
		_spike(att, sp, bone, Vector3(0, y, -0.2 - i * 0.015), Vector3(0, 0.6, -1.0))
	# Spiked iron wristbands, one dragging a broken shackle chain
	var band := CylinderMesh.new()
	band.top_radius = 0.085
	band.bottom_radius = 0.085
	band.height = 0.07
	band.radial_segments = 8
	band.rings = 1
	var stud := _cone(0.03, 0.07, 4)
	var link := _ring(0.03, 0.05)
	for side in ["l", "r"]:
		var arm := _bone_att(sk, "lowerarm." + side)
		var y := 0.17
		_add(arm, band, iron, Vector3(0, y, 0))
		for k in 3:
			var a := TAU * k / 3.0 + 0.5
			var d := Vector3(cos(a), 0, sin(a))
			_spike(arm, stud, iron, Vector3(0, y, 0) + d * 0.08, d)
		if side == "r":
			# two hanging links (local +Z is the model's up here, so hang toward -Z)
			_add(arm, link, iron, Vector3(0, y, -0.12), Basis(Vector3.FORWARD, PI / 2))
			_add(arm, link, iron, Vector3(0, y + 0.01, -0.2), Basis(Vector3.RIGHT, PI / 2))


# ---------------- lower ----------------

static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var iron := _plain(IRON, 0.45, 0.6)
	var dark := _plain(CHAR, 0.45)
	# Devil tail out of the back of the hips (kept low, clear of the wings)
	var tail := MeshInstance3D.new()
	tail.mesh = _tail_mesh()
	tail.material_override = _ember_mat(DEVIL, 0.22, 1.8)
	att.add_child(tail)
	# Scrappy loincloth (front and a short back flap) with a burning hem
	var cloth := _ember_mat(CLOTH, 0.0, 1.6)
	var front := MeshInstance3D.new()
	front.mesh = _rag_mesh(0.34, 0.36, 7, 11)
	front.material_override = cloth
	front.position = Vector3(0, 0.1, 0.27)
	front.rotation.x = 0.12
	att.add_child(front)
	var back := MeshInstance3D.new()
	back.mesh = _rag_mesh(0.3, 0.26, 5, 23)
	back.material_override = cloth
	back.position = Vector3(0, 0.1, -0.25)
	back.rotation = Vector3(-0.12, PI, 0)
	att.add_child(back)
	# Black talons on the toes (toes bone: local +Y = forward, +Z = up)
	var claw := _cone(0.035, 0.1, 5)
	for side in ["l", "r"]:
		var toes := _bone_att(sk, "toes." + side)
		for k in 3:
			var x := (k - 1) * 0.065
			_spike(toes, claw, dark, Vector3(x, 0.14 - absf(x) * 0.4, 0.03), Vector3(x * 2.0, 1.0, -0.35))
	# Iron cuff on the right ankle with a broken chain (lowerleg: local +Y runs down the leg)
	var leg := _bone_att(sk, "lowerleg.r")
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.135
	cuff.bottom_radius = 0.135
	cuff.height = 0.06
	cuff.radial_segments = 8
	cuff.rings = 1
	_add(leg, cuff, iron, Vector3(0, 0.07, 0))
	var link := _ring(0.03, 0.05)
	_add(leg, link, iron, Vector3(-0.12, 0.1, 0.06), Basis(Vector3.UP, 0.3))
	_add(leg, link, iron, Vector3(-0.17, 0.15, 0.1), Basis(Vector3.FORWARD, PI / 2))


# The tail: a tapering tube along a curve, then a flat spade; vertex colour red marks the glowing tip.
static func _tail_mesh() -> ArrayMesh:
	var path := Curve3D.new()
	path.add_point(Vector3(0, 0.08, -0.18), Vector3.ZERO, Vector3(0, -0.06, -0.12))
	path.add_point(Vector3(0.03, -0.02, -0.42), Vector3(0, 0, 0.1), Vector3(0, 0, -0.12))
	path.add_point(Vector3(0.1, 0.06, -0.66), Vector3(-0.03, -0.08, 0.06), Vector3(0.03, 0.08, -0.06))
	path.add_point(Vector3(0.16, 0.24, -0.74), Vector3(-0.02, -0.08, -0.02), Vector3.ZERO)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var sides := 6
	var rings := []
	var length := path.get_baked_length()
	for i in n + 1:
		var t := float(i) / n
		var p := path.sample_baked(t * length)
		var p2 := path.sample_baked(minf(t * length + 0.02, length))
		var p0 := path.sample_baked(maxf(t * length - 0.02, 0.0))
		var b := _align_y(p2 - p0)
		var rad := lerpf(0.06, 0.025, t)
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			ring.append(p + b * Vector3(cos(a) * rad, 0, sin(a) * rad))
		rings.append(ring)
	for i in n:
		var ga := clampf((float(i) / n - 0.75) * 4.0, 0.0, 1.0) * 0.6
		var gb := clampf((float(i + 1) / n - 0.75) * 4.0, 0.0, 1.0) * 0.6
		for k in sides:
			var k2 := (k + 1) % sides
			_tri(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], ga, gb, gb)
			_tri(st, rings[i][k], rings[i + 1][k2], rings[i][k2], ga, gb, ga)
	# Spade: a flat diamond-arrowhead at the end, facing sideways (flat in the tail's bending plane)
	var end := path.sample_baked(length)
	var dir := (end - path.sample_baked(length - 0.04)).normalized()
	var side := dir.cross(Vector3(1, 0, 0.3).normalized()).normalized()
	var flat := dir.cross(side).normalized()
	var tip := end + dir * 0.2
	var back := end - dir * 0.02
	var lft := end + dir * 0.04 + side * 0.1
	var rgt := end + dir * 0.04 - side * 0.1
	var notch_l := end - dir * 0.03 + side * 0.05
	var notch_r := end - dir * 0.03 - side * 0.05
	var th := flat * 0.022
	var outline := [tip, lft, notch_l, back, notch_r, rgt]
	for f in [1.0, -1.0]:
		var c: Vector3 = end + dir * 0.05 + th * f * 1.6
		for k in outline.size():
			var a: Vector3 = outline[k] + th * f * 0.3
			var bb: Vector3 = outline[(k + 1) % outline.size()] + th * f * 0.3
			if f > 0:
				_tri(st, c, a, bb, 0.7, 1.0, 1.0)
			else:
				_tri(st, c, bb, a, 0.7, 1.0, 1.0)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ga: float, gb: float, gc: float) -> void:
	st.set_color(Color(ga, 0, 0))
	st.add_vertex(a)
	st.set_color(Color(gb, 0, 0))
	st.add_vertex(b)
	st.set_color(Color(gc, 0, 0))
	st.add_vertex(c)


# A ragged cloth flap hanging down from its top edge (at y=0, in the XY plane, bulging a bit forward);
# the jagged hem glows like it's still smouldering.
static func _rag_mesh(width: float, drop: float, cols: int, sd: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := []
	var mid := []
	var hem := []
	var low := []
	for i in cols + 1:
		var u := float(i) / cols
		var x := (u - 0.5) * width
		var taper := 1.0 - 0.25 * absf(u - 0.5) * 2.0
		var y := -drop * taper - (rng.randf_range(0.0, 0.07) if i % 2 == 1 else 0.0)
		var bulge := 0.03 * sin(u * PI)
		top.append(Vector3(x * 1.05, 0, 0.0))
		mid.append(Vector3(x, y * 0.5, bulge + 0.02))
		low.append(Vector3(x * 0.97, y * 0.82, bulge + 0.03))
		hem.append(Vector3(x * 0.95 + rng.randf_range(-0.01, 0.01), y, bulge + 0.035))
	for i in cols:
		_tri(st, top[i], mid[i], mid[i + 1], 0, 0, 0)
		_tri(st, top[i], mid[i + 1], top[i + 1], 0, 0, 0)
		_tri(st, mid[i], low[i], low[i + 1], 0, 0, 0)
		_tri(st, mid[i], low[i + 1], mid[i + 1], 0, 0, 0)
		_tri(st, low[i], hem[i], hem[i + 1], 0, 1, 1)
		_tri(st, low[i], hem[i + 1], low[i + 1], 0, 1, 0)
	st.generate_normals()
	return st.commit()
