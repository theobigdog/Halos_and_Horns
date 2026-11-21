extends RefCounted
# Knight details: a holy paladin of heaven. Gold trim, little helmet wings, a sun crest, an ivory tabard
# with a glowing sun, gold cuffs, knee guards and toe caps. Everything is placed in model space (KayKit
# units, front = +Z, +X = the character's left) through a pivot that undoes the bone's rest pose.

const GOLD := Color(1.0, 0.76, 0.26)
const IVORY := Color(0.96, 0.93, 0.84)
const SKY := Color(0.55, 0.76, 0.98)

static var _glow_shader: Shader


# ---------------- shared bits ----------------

static func _gold() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = GOLD
	m.metallic = 0.75
	m.roughness = 0.32
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 0.25
	return m


static func _cloth(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


# Gently pulsing holy glow (shader TIME, no scripts)
static func _glow(c: Color, base := 2.2) -> ShaderMaterial:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = """
shader_type spatial;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float energy = 2.2;
void fragment() {
	ALBEDO = col.rgb;
	ROUGHNESS = 0.4;
	EMISSION = col.rgb * energy * (0.8 + 0.2 * sin(TIME * 2.2));
}
"""
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("energy", base)
	return m


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _torus(inner: float, outer: float, rings := 20, sides := 6) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = sides
	return t


static func _disc(r: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.transform = Transform3D(Basis.from_euler(rot).scaled(scl), pos)
	parent.add_child(m)
	return m


# A gold tube bent along an arc in the YZ plane (angle 0 = straight up, positive toward +Z), radius r
static func _arc(r: float, tube: float, a0: float, a1: float, segs := 10, sides := 6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		for j in sides:
			var quad := []
			for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var a: float = lerpf(a0, a1, float(k[0]) / segs)
				var b: float = TAU * k[1] / sides
				var out := Vector3(0, cos(a), sin(a))
				var nrm := out * cos(b) + Vector3(1, 0, 0) * sin(b)
				quad.append([out * r + nrm * tube, nrm])
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[idx][1])
				st.add_vertex(quad[idx][0])
	return st.commit()


# A node under `att` whose children are placed in model (skeleton) space at the bone's rest pose.
static func _pivot(sk: Skeleton3D, att: Node3D) -> Node3D:
	var p := Node3D.new()
	var bone: String = (att as BoneAttachment3D).bone_name
	p.transform = sk.get_bone_global_rest(sk.find_bone(bone)).affine_inverse()
	att.add_child(p)
	return p


static func _bone(sk: Skeleton3D, bone: String) -> Node3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	sk.add_child(a)
	return _pivot(sk, a)


# A sun: glowing disc with chunky rays, facing +Z (rotate the returned node to aim it)
static func _sun(parent: Node3D, pos: Vector3, r: float, glow: Material, gold: Material, rays := 8) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	_mi(n, _disc(r, r * 0.35), glow, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(n, _torus(r * 0.95, r * 1.25, 16, 5), gold, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var ray := PrismMesh.new()
	ray.size = Vector3(r * 0.7, r * 0.8, r * 0.25)
	for i in rays:
		var a := TAU * i / rays
		var d := Vector3(sin(a), cos(a), 0) * r * 1.6
		_mi(n, ray, glow, d, Vector3(0, 0, -a), Vector3.ONE * (1.0 if i % 2 == 0 else 0.7))
	return n


# A little feathered wing (3 layered feathers sweeping up and back); side = +1 (left) or -1 (right)
static func _little_wing(parent: Node3D, pos: Vector3, side: float, scl: float, feather: Material, gold: Material) -> void:
	var w := Node3D.new()
	w.position = pos
	w.rotation = Vector3(0, PI / 2, 0)
	w.rotate(Vector3(0, 0, 1), -side * 0.45)   # feathers drawn in the YZ plane, splayed outward a little
	w.scale = Vector3.ONE * scl
	parent.add_child(w)
	var f := PrismMesh.new()
	f.size = Vector3(0.16, 0.42, 0.05)
	for i in 3:
		var t := float(i)
		var tilt := 0.35 + 0.42 * t               # leans back more each feather
		var len := 1.0 - 0.18 * t
		var fm := _mi(w, f, feather, Vector3(0, 0, side * (0.02 - 0.02 * t)), Vector3(0, 0, tilt), Vector3(1, len, 1))
		fm.position += fm.transform.basis.y * 0.19 * len
	_mi(w, _disc(0.07, 0.06, 10), gold, Vector3.ZERO, Vector3(PI / 2, 0, 0))


# ---------------- head ----------------

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pivot(sk, att)
	var gold := _gold()
	var glow := _glow(Color(1.0, 0.85, 0.4), 2.4)
	var hy := 1.2414   # head bone height (model space)
	if bare:
		# A slim gold circlet with a glowing star on the brow
		_mi(p, _torus(0.5, 0.55, 24, 5), gold, Vector3(0, hy + 0.62, 0.0), Vector3(0.12, 0, 0), Vector3(1.0, 1, 0.95))
		_sun(p, Vector3(0, hy + 0.66, 0.5), 0.05, glow, gold, 6).rotation = Vector3(-0.12, 0, 0)
		return
	var feather := _cloth(IVORY)
	# Gold rim around the bottom of the dome, just above the eyes
	_mi(p, _torus(0.55, 0.6, 28, 6), gold, Vector3(0, hy + 0.7, 0.07), Vector3(-0.05, 0, 0), Vector3(1.0, 1, 1.08))
	# Gold rim along the bottom of the chin guard / gorget
	_mi(p, _torus(0.42, 0.47, 24, 6), gold, Vector3(0, hy + 0.06, 0.08), Vector3(0.05, 0, 0), Vector3(1.05, 1, 1.0))
	# Gold ridge over the crown, front to back
	_mi(p, _arc(0.6, 0.03, -0.95, 0.55, 12), gold, Vector3(0, hy + 0.63, 0.02))
	# Glowing sun crest on the brow, tilted up
	_sun(p, Vector3(0, hy + 1.0, 0.55), 0.08, glow, gold).rotation = Vector3(-0.6, 0, 0)
	# Little angel wings on the sides of the helmet
	for side in [1.0, -1.0]:
		_little_wing(p, Vector3(side * 0.58, hy + 0.6, -0.05), side, 1.0, feather, gold)


# ---------------- upper ----------------

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pivot(sk, att)
	var gold := _gold()
	var glow := _glow(Color(1.0, 0.86, 0.42), 2.6)
	var ivory := _cloth(IVORY)
	var sky := _cloth(SKY)
	# Ivory tabard with a gold border and a sky-blue stripe down the middle
	var tab := Node3D.new()
	tab.position = Vector3(0, 0.75, 0.355)
	tab.rotation = Vector3(-0.17, 0, 0)
	p.add_child(tab)
	_mi(tab, _box(Vector3(0.40, 0.46, 0.03)), gold, Vector3.ZERO)
	_mi(tab, _box(Vector3(0.34, 0.42, 0.03)), ivory, Vector3(0, 0, 0.01))
	_sun(tab, Vector3(0, 0.03, 0.03), 0.065, glow, gold)
	# Gold belt buckle with a glowing gem
	_mi(p, _box(Vector3(0.2, 0.12, 0.03)), gold, Vector3(0, 0.5, 0.38))
	_mi(p, _box(Vector3(0.06, 0.06, 0.03)), glow, Vector3(0, 0.5, 0.395), Vector3(0, 0, PI / 4))
	# Tabard tail hanging below the belt (follows the hips)
	var hips := _bone(sk, "hips")
	var tail := PrismMesh.new()
	tail.size = Vector3(0.3, 0.2, 0.025)
	_mi(hips, tail, gold, Vector3(0, 0.36, 0.35), Vector3(-0.12, 0, PI))
	_mi(hips, tail, ivory, Vector3(0, 0.37, 0.362), Vector3(-0.12, 0, PI), Vector3(0.8, 0.8, 1))
	_mi(hips, _box(Vector3(0.04, 0.12, 0.02)), sky, Vector3(0, 0.39, 0.37), Vector3(-0.12, 0, 0))
	# Gold-rimmed pauldrons and gold gauntlet cuffs
	var ring := _arc(0.165, 0.03, -1.6, 1.6, 12)
	var cuff := _torus(0.13, 0.17, 18, 6)
	for s in ["l", "r"]:
		var sx := 1.0 if s == "l" else -1.0
		var ua := _bone(sk, "upperarm." + s)
		_mi(ua, ring, gold, Vector3(sx * 0.4, 1.1, 0), Vector3.ZERO)
		var la := _bone(sk, "lowerarm." + s)
		_mi(la, cuff, gold, Vector3(sx * 0.68, 1.11, 0), Vector3(0, 0, PI / 2))
	if bare:
		return
	# Cape: gold hem and a sun on the back below the wings
	_mi(p, _box(Vector3(0.78, 0.05, 0.03)), gold, Vector3(0, 0.12, -0.39))
	_sun(p, Vector3(0, 0.5, -0.42), 0.07, glow, gold).rotation = Vector3(0, PI, 0)


# ---------------- lower ----------------

static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var gold := _gold()
	var glow := _glow(Color(1.0, 0.86, 0.42), 2.2)
	var feather := _cloth(IVORY)
	var knee := _disc(0.07, 0.04, 10)
	var rim := _torus(0.125, 0.155, 16, 5)
	var toe := _box(Vector3(0.18, 0.05, 0.07))
	for s in ["l", "r"]:
		var sx := 1.0 if s == "l" else -1.0
		var x := sx * 0.17
		# Gold knee guard with a glowing stud
		var ll := _bone(sk, "lowerleg." + s)
		_mi(ll, knee, gold, Vector3(x, 0.3, 0.16), Vector3(PI / 2, 0, 0))
		_mi(ll, _disc(0.03, 0.03, 8), glow, Vector3(x, 0.3, 0.185), Vector3(PI / 2, 0, 0))
		# Gold rim at the top of the greave
		_mi(ll, rim, gold, Vector3(x, 0.24, 0.01))
		# Gold toe cap and tiny ankle wings
		var ft := _bone(sk, "foot." + s)
		_mi(ft, toe, gold, Vector3(x, 0.07, 0.26), Vector3(0.3, 0, 0))
		_little_wing(ft, Vector3(sx * 0.3, 0.13, -0.02), sx, 0.5, feather, gold)
