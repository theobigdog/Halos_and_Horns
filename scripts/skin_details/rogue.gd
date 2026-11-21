# Rogue details: a nimble ranger of light. Head: a tuft of white feathers tucked in the hair and a gold
# star hairpin. Upper: an ivory bandolier with pouches, a glowing vial and a feather charm, a sky-blue
# scarf, wrist wraps, and a glowing star on the cape. Lower: a gold-guarded dagger on the hip, laced boots
# with gold toe caps, and a sun medallion on the belt.
# Everything is placed in MODEL space (KayKit units, +Z front, +X the character's left) through _space(),
# which undoes the bone's rest pose, so numbers below can be read straight off the model.
extends RefCounted

const GOLD := Color(1.0, 0.8, 0.32)
const IVORY := Color(0.96, 0.93, 0.84)
const SKY := Color(0.55, 0.8, 1.0)
const LEATHER := Color(0.55, 0.36, 0.22)

static var _cache := {}   # shared meshes/materials (built once)


# ---------------- shared helpers (also used by rogue_hooded.gd) ----------------

static func mat(c: Color, rough := 0.6, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "m%s/%s/%s/%s" % [c.to_html(), rough, metal, emit]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_cache[key] = m
	return m


static func gold() -> StandardMaterial3D:
	return mat(GOLD, 0.35, 0.6, 0.35)


# A gently pulsing glow (shader TIME, no scripts).
static func pulse(c: Color, base := 2.0) -> ShaderMaterial:
	var key := "p%s/%s" % [c.to_html(), base]
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec4 col : source_color;
uniform float base = 2.0;
void fragment() {
	ALBEDO = col.rgb;
	ROUGHNESS = 0.3;
	EMISSION = col.rgb * (base + 0.9 * sin(TIME * 2.6));
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("base", base)
	_cache[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not _cache.has(key):
		var b := BoxMesh.new()
		b.size = size
		_cache[key] = b
	return _cache[key]


static func cyl(r_top: float, r_bot: float, h: float, segs := 8) -> CylinderMesh:
	var key := "c%s/%s/%s/%s" % [r_top, r_bot, h, segs]
	if not _cache.has(key):
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = segs
		c.rings = 1
		_cache[key] = c
	return _cache[key]


static func ball(r: float, segs := 10) -> SphereMesh:
	var key := "s%s/%s" % [r, segs]
	if not _cache.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = maxi(segs / 2, 4)
		_cache[key] = s
	return _cache[key]


static func ring(inner: float, outer: float, segs := 16) -> TorusMesh:
	var key := "t%s/%s/%s" % [inner, outer, segs]
	if not _cache.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = segs
		t.ring_segments = 6
		_cache[key] = t
	return _cache[key]


# A chunky 5-point star in the XY plane, facing +Z, `t` thick.
static func star(r: float, t: float, points := 5, inner := 0.45) -> ArrayMesh:
	var key := "st%s/%s/%s/%s" % [r, t, points, inner]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := points * 2
	var rim := []
	for i in n:
		var a := PI * 0.5 + TAU * i / n
		var rr := r if i % 2 == 0 else r * inner
		rim.append(Vector2(cos(a), sin(a)) * rr)
	var f := Vector3(0, 0, t * 0.5)
	var b := Vector3(0, 0, -t * 0.5)
	var cf := Vector3(0, 0, t * 0.9)    # slightly domed front
	for i in n:
		var p: Vector2 = rim[i]
		var q: Vector2 = rim[(i + 1) % n]
		var p3 := Vector3(p.x, p.y, 0)
		var q3 := Vector3(q.x, q.y, 0)
		# front
		st.add_vertex(cf); st.add_vertex(q3 + f); st.add_vertex(p3 + f)
		# back
		st.add_vertex(-cf); st.add_vertex(p3 + b); st.add_vertex(q3 + b)
		# side
		st.add_vertex(p3 + f); st.add_vertex(q3 + f); st.add_vertex(q3 + b)
		st.add_vertex(p3 + f); st.add_vertex(q3 + b); st.add_vertex(p3 + b)
	st.generate_normals()
	var m := st.commit()
	_cache[key] = m
	return m


# A feather: a flat leaf shape along +Y (base at 0, tip at `length`), facing +Z, with a little curl.
static func feather(length: float, width: float) -> ArrayMesh:
	var key := "f%s/%s" % [length, width]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var steps := 6
	var th := width * 0.18
	var l := []
	var rr := []
	for i in steps + 1:
		var u := float(i) / steps
		var w := width * 0.5 * sin(PI * pow(u, 0.8)) * (1.0 - 0.25 * u)
		var curl := 0.18 * length * u * u
		l.append(Vector3(-w, u * length, -curl))
		rr.append(Vector3(w * 0.8, u * length, -curl))
	for i in steps:
		var c0: Vector3 = (l[i] + rr[i]) * 0.5 + Vector3(0, 0, th)
		var c1: Vector3 = (l[i + 1] + rr[i + 1]) * 0.5 + Vector3(0, 0, th)
		var cb0: Vector3 = c0 - Vector3(0, 0, th * 2)
		var cb1: Vector3 = c1 - Vector3(0, 0, th * 2)
		for side in [[l, false], [rr, true]]:
			var e: Array = side[0]
			var flip: bool = side[1]
			var tris := [[c0, e[i], e[i + 1]], [c0, e[i + 1], c1], [cb0, e[i + 1], e[i]], [cb0, cb1, e[i + 1]]]
			for tri in tris:
				if flip:
					st.add_vertex(tri[0]); st.add_vertex(tri[1]); st.add_vertex(tri[2])
				else:
					st.add_vertex(tri[0]); st.add_vertex(tri[2]); st.add_vertex(tri[1])
	st.generate_normals()
	var m := st.commit()
	_cache[key] = m
	return m


# A node under `parent` (a BoneAttachment3D for `bone`) in which coordinates are model-space.
static func space(sk: Skeleton3D, parent: Node3D, bone: String) -> Node3D:
	var n := Node3D.new()
	var i := sk.find_bone(bone)
	if i >= 0:
		n.transform = sk.get_bone_global_rest(i).affine_inverse()
	parent.add_child(n)
	return n


# A new attachment on `bone`, returning its model-space node.
static func limb(sk: Skeleton3D, bone: String) -> Node3D:
	var att := BoneAttachment3D.new()
	att.name = "Details_" + bone.replace(".", "_")
	att.bone_name = bone
	sk.add_child(att)
	return space(sk, att, bone)


static func put(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.from_euler(rot_deg * PI / 180.0).scaled_local(scl), pos)
	parent.add_child(mi)
	return mi


# A mesh whose local +Y runs from a to b (meshes of height 1 along Y get stretched to fit).
static func span(parent: Node3D, mesh: Mesh, m: Material, a: Vector3, b: Vector3, thick := Vector3.ONE, roll := Vector3.FORWARD) -> MeshInstance3D:
	var y := (b - a)
	var len := y.length()
	y = y / len
	var x := roll.cross(y).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(x * thick.x, y * len * thick.y, z * thick.z), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


# A small tuft of feathers bound with gold (base at `pos`, pointing along `rot_deg`).
static func feather_tuft(parent: Node3D, pos: Vector3, rot_deg: Vector3, size := 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	n.scale = Vector3.ONE * size
	parent.add_child(n)
	var white := mat(Color(1, 1, 0.97), 0.7, 0.0, 0.15)
	var blue := mat(SKY, 0.6, 0.0, 0.25)
	put(n, feather(0.48, 0.2), white, Vector3(0, 0, 0), Vector3(0, 0, 8))
	put(n, feather(0.38, 0.17), white, Vector3(0.02, 0, -0.02), Vector3(-6, 20, -26))
	put(n, feather(0.3, 0.14), blue, Vector3(-0.02, 0, 0.02), Vector3(6, -15, 32))
	put(n, cyl(0.035, 0.03, 0.06, 8), gold(), Vector3(0, 0.01, 0))
	return n


# ---------------- the Rogue ----------------

static func head(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var s := space(sk, att, "head")
	# white feathers tucked into the hair on the right side (character's right = -X), above the ear
	feather_tuft(s, Vector3(-0.46, 1.86, -0.08), Vector3(-25, 0, 38), 1.0)
	# gold star hairpin on the other side of the parting
	put(s, star(0.075, 0.035), mat(GOLD, 0.3, 0.5, 1.4), Vector3(0.34, 1.98, 0.36), Vector3(-30, 25, 0))
	put(s, cyl(0.012, 0.012, 0.16, 6), gold(), Vector3(0.3, 2.0, 0.3), Vector3(-30, 25, 70))


static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var s := space(sk, att, "chest")
	var strap := mat(IVORY, 0.7)
	var leather := mat(LEATHER, 0.8)
	var g := gold()
	# bandolier from the right shoulder down to the left hip, in segments hugging the chest
	var pts := [Vector3(-0.30, 1.22, 0.16), Vector3(-0.18, 1.06, 0.33), Vector3(0.05, 0.84, 0.39),
		Vector3(0.26, 0.64, 0.36), Vector3(0.36, 0.52, 0.22)]
	for i in pts.size() - 1:
		span(s, box(Vector3(0.11, 1.0, 0.025)), strap, pts[i], pts[i + 1], Vector3.ONE, Vector3(0, 0, 1))
	# gold edging studs along it
	for p in [Vector3(-0.18, 1.06, 0.35), Vector3(0.26, 0.64, 0.38)]:
		put(s, ball(0.025, 8), g, p)
	# two pouches and a vial loop on the strap
	put(s, box(Vector3(0.11, 0.1, 0.07)), leather, Vector3(-0.07, 0.95, 0.40), Vector3(0, 0, 40))
	put(s, box(Vector3(0.12, 0.03, 0.08)), g, Vector3(-0.07, 0.95, 0.41) + Vector3(-0.03, 0.04, 0), Vector3(0, 0, 40))
	put(s, box(Vector3(0.11, 0.1, 0.07)), leather, Vector3(0.17, 0.72, 0.41), Vector3(0, 0, 40))
	put(s, box(Vector3(0.12, 0.03, 0.08)), g, Vector3(0.17, 0.72, 0.42) + Vector3(-0.03, 0.04, 0), Vector3(0, 0, 40))
	# the glowing vial of light
	var vial := Vector3(0.05, 0.84, 0.43)
	put(s, cyl(0.035, 0.045, 0.12, 8), pulse(Color(1.0, 0.92, 0.55), 2.2), vial, Vector3(0, 0, 40))
	put(s, cyl(0.022, 0.022, 0.04, 8), g, vial + Vector3(-0.045, 0.055, 0), Vector3(0, 0, 40))
	# feather charm dangling from the strap
	put(s, feather(0.16, 0.06), mat(Color(1, 1, 0.97), 0.7, 0.0, 0.2), Vector3(-0.22, 1.02, 0.36), Vector3(0, 0, 175))
	# sky-blue scarf peeking out under the chin, with a knot and two tails on the right
	var blue := mat(SKY, 0.8)
	put(s, ring(0.26, 0.36, 18), blue, Vector3(0, 1.22, 0.02), Vector3(0, 0, 0), Vector3(1, 0.9, 1))
	put(s, ball(0.07, 8), blue, Vector3(-0.2, 1.17, 0.3))
	span(s, box(Vector3(0.09, 1.0, 0.03)), blue, Vector3(-0.21, 1.15, 0.33), Vector3(-0.27, 0.93, 0.36), Vector3.ONE, Vector3(0, 0, 1))
	span(s, box(Vector3(0.08, 1.0, 0.03)), blue, Vector3(-0.19, 1.15, 0.33), Vector3(-0.15, 0.97, 0.38), Vector3.ONE, Vector3(0, 0, 1))
	# wrist wraps (ivory bands with a gold cuff) on both forearms
	for side in [1.0, -1.0]:
		var bone := "lowerarm.l" if side > 0 else "lowerarm.r"
		var arm := limb(sk, bone)
		for k in 3:
			var x: float = side * (0.56 + k * 0.05)
			put(arm, cyl(0.125, 0.125, 0.04, 10), strap, Vector3(x, 1.11, 0.0), Vector3(0, 0, 90 + side * (8 - k * 8)))
		put(arm, cyl(0.13, 0.13, 0.03, 10), g, Vector3(side * 0.69, 1.11, 0.0), Vector3(0, 0, 90))
	# glowing star on the back of the cape (below the wings)
	if not bare:
		put(s, star(0.1, 0.04), mat(GOLD, 0.3, 0.4, 1.6), Vector3(0, 0.42, -0.385), Vector3(0, 180, 0))
		put(s, ring(0.13, 0.155, 18), g, Vector3(0, 0.42, -0.375), Vector3(90, 0, 0))


static func lower(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var s := space(sk, att, "hips")
	var g := gold()
	var leather := mat(LEATHER, 0.8)
	var ivory := mat(IVORY, 0.7)
	# sun medallion on the belt, beside the buckle
	put(s, star(0.055, 0.03, 8, 0.6), mat(GOLD, 0.3, 0.5, 1.2), Vector3(0.2, 0.48, 0.38))
	# a short dagger in an ivory sheath on the left hip, hilt up with a gold cross-guard
	var d := Node3D.new()
	d.position = Vector3(0.42, 0.5, 0.06)
	d.rotation_degrees = Vector3(-15, 0, 18)
	s.add_child(d)
	put(d, box(Vector3(0.08, 0.26, 0.05)), ivory, Vector3(0, -0.13, 0))
	put(d, cyl(0.0, 0.045, 0.07, 4), g, Vector3(0, -0.29, 0), Vector3(180, 45, 0), Vector3(1, 1, 0.6))
	put(d, box(Vector3(0.09, 0.025, 0.06)), g, Vector3(0, -0.06, 0))
	put(d, box(Vector3(0.18, 0.035, 0.05)), g, Vector3(0, 0.01, 0))
	put(d, cyl(0.022, 0.022, 0.1, 6), leather, Vector3(0, 0.07, 0))
	put(d, ball(0.035, 8), mat(SKY, 0.3, 0.0, 1.5), Vector3(0, 0.14, 0))
	# boots: gold toe caps and crossed ivory laces
	for side in [1.0, -1.0]:
		var sfx := ".l" if side > 0 else ".r"
		var foot := limb(sk, "foot" + sfx)
		var x: float = side * 0.17
		put(foot, ball(0.1, 10), g, Vector3(x, 0.07, 0.2), Vector3(0, 0, 0), Vector3(1.05, 0.6, 0.9))
		var shin := limb(sk, "lowerleg" + sfx)
		for k in 2:
			var y := 0.2 + k * 0.08
			put(shin, box(Vector3(0.14, 0.022, 0.02)), ivory, Vector3(x, y, 0.15), Vector3(0, 0, 30))
			put(shin, box(Vector3(0.14, 0.022, 0.02)), ivory, Vector3(x, y, 0.15), Vector3(0, 0, -30))
		put(shin, ring(0.13, 0.155, 14), g, Vector3(x, 0.36, 0.02), Vector3(0, 0, 0))
