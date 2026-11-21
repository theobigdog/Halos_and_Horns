# Mage details: a celestial star-mage. Twinkling stars and a crescent moon on the hat, a gold-embroidered
# hat band, glowing constellations on the robe, star buttons, a crystal pendant and a scroll on the belt,
# bangles, starry cape and curled gold slipper tips. (Called from characters.gd, see _add_details.)
# Model space: +Z is the character's front, +Y up, +X the character's left. All procedural.
extends RefCounted

const TWINKLE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float glow = 1.5;
uniform float speed = 2.5;
void fragment() {
	float ph = dot(NODE_POSITION_WORLD, vec3(17.0, 23.0, 31.0));
	float tw = 0.6 + 0.4 * sin(TIME * speed + ph);
	ALBEDO = col.rgb;
	EMISSION = col.rgb * glow * tw;
	ROUGHNESS = 0.35;
	METALLIC = 0.2;
}
"""

static var _cache := {}

# Hat-space heights (see head()): band rims and brim surface
const BAND_LO := 0.25
const BAND_HI := 0.39
const BRIM_Y := 0.075
const BRIM_DROP := -0.03


# ---------------------------------------------------------------- palette / materials

static func _pal(role: String) -> Dictionary:
	if role == "demon":
		return {"gold": Color(0.45, 0.4, 0.38), "star": Color(1.0, 0.45, 0.15), "rune": Color(1.0, 0.3, 0.08),
			"gem": Color(0.95, 0.2, 0.1), "rope": Color(0.25, 0.2, 0.18), "paper": Color(0.75, 0.68, 0.55),
			"moon": Color(1.0, 0.55, 0.2)}
	return {"gold": Color(0.95, 0.75, 0.3), "star": Color(1.0, 0.88, 0.45), "rune": Color(0.55, 0.85, 1.0),
		"gem": Color(0.55, 0.85, 1.0), "rope": Color(0.93, 0.86, 0.68), "paper": Color(0.98, 0.95, 0.85),
		"moon": Color(0.95, 0.95, 1.0)}


static func _plain(key: String, c: Color, metal := 0.0, rough := 0.6) -> Material:
	var k := "plain_%s_%s" % [key, c.to_html()]
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = rough
		_cache[k] = m
	return _cache[k]


static func _glow(c: Color, energy: float, twinkle := 0.0) -> Material:
	var k := "glow_%s_%.2f_%.2f" % [c.to_html(), energy, twinkle]
	if not _cache.has(k):
		if twinkle > 0.0:
			var sm := ShaderMaterial.new()
			if not _cache.has("_shader"):
				var sh := Shader.new()
				sh.code = TWINKLE_SHADER
				_cache["_shader"] = sh
			sm.shader = _cache["_shader"]
			sm.set_shader_parameter("col", c)
			sm.set_shader_parameter("glow", energy)
			sm.set_shader_parameter("speed", twinkle)
			_cache[k] = sm
		else:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = energy
			m.roughness = 0.3
			_cache[k] = m
	return _cache[k]


# ---------------------------------------------------------------- meshes

static func _flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot(out) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# Godot's front faces wind clockwise as seen from the front
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


# A chunky extruded star in the XY plane, facing +Z (depth along Z, centred).
static func _star_mesh(r_out: float, r_in: float, depth: float, points := 5) -> Mesh:
	var k := "star_%.3f_%.3f_%.3f_%d" % [r_out, r_in, depth, points]
	if _cache.has(k):
		return _cache[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for i in points * 2:
		var a := PI / 2.0 + TAU * i / (points * 2.0)
		var r := r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(a), sin(a)) * r)
	var h := depth / 2.0
	var cf := Vector3(0, 0, h * 1.6)   # a little raised centre: bevelled look
	var cb := Vector3(0, 0, -h * 1.6)
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var pf := Vector3(p.x, p.y, h)
		var qf := Vector3(q.x, q.y, h)
		var pb := Vector3(p.x, p.y, -h)
		var qb := Vector3(q.x, q.y, -h)
		_flat_tri(st, cf, pf, qf, Vector3(0, 0, 1))
		_flat_tri(st, cb, pb, qb, Vector3(0, 0, -1))
		var mid := Vector3((p.x + q.x) / 2.0, (p.y + q.y) / 2.0, 0)
		_flat_tri(st, pf, qf, qb, mid)
		_flat_tri(st, pf, qb, pb, mid)
	var m := st.commit()
	_cache[k] = m
	return m


# A crescent moon in the XY plane, facing +Z, horns pointing toward +X.
static func _moon_mesh(r: float, w: float, depth: float) -> Mesh:
	var k := "moon_%.3f_%.3f_%.3f" % [r, w, depth]
	if _cache.has(k):
		return _cache[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var a0 := deg_to_rad(35.0)
	var a1 := deg_to_rad(325.0)
	var outer: Array[Vector2] = []
	var inner: Array[Vector2] = []
	for i in segs + 1:
		var t := float(i) / segs
		var a := lerpf(a0, a1, t)
		var d := Vector2(cos(a), sin(a))
		var ww := w * (0.15 + 0.85 * sin(PI * t))
		outer.append(d * r)
		inner.append(d * (r - ww))
	var h := depth / 2.0
	for i in segs:
		var o0 := outer[i]
		var o1 := outer[i + 1]
		var i0 := inner[i]
		var i1 := inner[i + 1]
		for z in [h, -h]:
			var f := Vector3(0, 0, signf(z))
			_flat_tri(st, Vector3(o0.x, o0.y, z), Vector3(o1.x, o1.y, z), Vector3(i1.x, i1.y, z), f)
			_flat_tri(st, Vector3(o0.x, o0.y, z), Vector3(i1.x, i1.y, z), Vector3(i0.x, i0.y, z), f)
		var on := Vector3((o0.x + o1.x), (o0.y + o1.y), 0)
		_flat_tri(st, Vector3(o0.x, o0.y, h), Vector3(o1.x, o1.y, h), Vector3(o1.x, o1.y, -h), on)
		_flat_tri(st, Vector3(o0.x, o0.y, h), Vector3(o1.x, o1.y, -h), Vector3(o0.x, o0.y, -h), on)
		_flat_tri(st, Vector3(i0.x, i0.y, h), Vector3(i1.x, i1.y, h), Vector3(i1.x, i1.y, -h), -on)
		_flat_tri(st, Vector3(i0.x, i0.y, h), Vector3(i1.x, i1.y, -h), Vector3(i0.x, i0.y, -h), -on)
	# end caps
	for e in [[outer[0], inner[0], Vector2(cos(a0), sin(a0)).orthogonal()],
			[outer[segs], inner[segs], -Vector2(cos(a1), sin(a1)).orthogonal()]]:
		var o: Vector2 = e[0]
		var n: Vector2 = e[1]
		var dir: Vector2 = e[2]
		var dv := Vector3(-dir.x, -dir.y, 0)
		_flat_tri(st, Vector3(o.x, o.y, h), Vector3(n.x, n.y, h), Vector3(n.x, n.y, -h), dv)
		_flat_tri(st, Vector3(o.x, o.y, h), Vector3(n.x, n.y, -h), Vector3(o.x, o.y, -h), dv)
	var m := st.commit()
	_cache[k] = m
	return m


static func _torus(inner: float, outer: float, rings := 16, sides := 6) -> Mesh:
	var k := "torus_%.3f_%.3f_%d_%d" % [inner, outer, rings, sides]
	if not _cache.has(k):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = rings
		t.ring_segments = sides
		_cache[k] = t
	return _cache[k]


static func _sphere(r: float, segs := 8, rings := 5) -> Mesh:
	var k := "sphere_%.3f_%d" % [r, segs]
	if not _cache.has(k):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = rings
		_cache[k] = s
	return _cache[k]


static func _box(size: Vector3) -> Mesh:
	var k := "box_%s" % size
	if not _cache.has(k):
		var b := BoxMesh.new()
		b.size = size
		_cache[k] = b
	return _cache[k]


static func _cyl(top: float, bottom: float, height: float, segs := 8) -> Mesh:
	var k := "cyl_%.3f_%.3f_%.3f_%d" % [top, bottom, height, segs]
	if not _cache.has(k):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = height
		c.radial_segments = segs
		c.rings = 1
		_cache[k] = c
	return _cache[k]


# A crystal: a double-pointed hexagonal gem (two cones)
static func _gem(r: float, h: float) -> Mesh:
	var k := "gem_%.3f_%.3f" % [r, h]
	if _cache.has(k):
		return _cache[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, h * 0.4, 0)
	var bot := Vector3(0, -h * 0.6, 0)
	for i in 6:
		var a := TAU * i / 6.0
		var b := TAU * (i + 1) / 6.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var q := Vector3(cos(b) * r, 0, sin(b) * r)
		var mid := (p + q) / 2.0
		_flat_tri(st, top, p, q, mid + Vector3(0, 0.3, 0))
		_flat_tri(st, bot, p, q, mid - Vector3(0, 0.3, 0))
	var m := st.commit()
	_cache[k] = m
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _bone(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var b := BoneAttachment3D.new()
	b.bone_name = bone
	sk.add_child(b)
	return b


# A small star lying on a surface: `normal` is the way the star faces.
static func _star_on(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, normal: Vector3, spin := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var z := normal.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	mi.transform = Transform3D(Basis(x, y, z) * Basis(Vector3(0, 0, 1), spin), pos)


# ---------------------------------------------------------------- head

static func head(_sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pal(role)
	var gold := _gold(p["gold"])
	var star_mat := _glow(p["star"], 1.6, 2.2)
	var moon_mat := _glow(p["moon"], 1.3, 0.0)
	var gem_mat := _glow(p["gem"], 1.4, 1.5)
	if bare:
		# A gold circlet with a little crescent moon over the forehead
		var c := Node3D.new()
		c.position = Vector3(0, 0.66, 0.0)
		c.rotation.x = deg_to_rad(7.0)
		att.add_child(c)
		_add(c, _torus(0.475, 0.525, 20, 6), gold, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.03))
		_add(c, _moon_mesh(0.11, 0.06, 0.04), moon_mat, Vector3(0, 0.08, 0.53), Vector3(0, 0, PI / 2))
		_add(c, _gem(0.035, 0.08), gem_mat, Vector3(0, 0.02, 0.54))
		var s := _star_mesh(0.055, 0.024, 0.03)
		for side in [-1.0, 1.0]:
			_star_on(c, s, star_mat, Vector3(side * 0.37, 0.02, 0.36), Vector3(side * 0.67, 0, 0.74))
		return
	# The hat is tilted back a little: work in the hat's own (upright) space for the band and brim
	var hat := Node3D.new()
	hat.position = Vector3(0, 0.55, 0)
	hat.rotation.x = deg_to_rad(-18.0)
	att.add_child(hat)
	# Gold-embroidered band: two gold rims and little gold stars around it
	_add(hat, _torus(0.44, 0.5, 20, 6), gold, Vector3(0, BAND_LO, 0))
	_add(hat, _torus(0.4, 0.46, 20, 6), gold, Vector3(0, BAND_HI, 0))
	var small := _star_mesh(0.055, 0.024, 0.04)
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		_star_on(hat, small, gold, Vector3(sin(a) * 0.48, (BAND_LO + BAND_HI) / 2.0, cos(a) * 0.48), Vector3(sin(a), 0.1, cos(a)))
	# A big glowing star clasp over the buckle
	_star_on(hat, _star_mesh(0.12, 0.05, 0.05), star_mat, Vector3(0, (BAND_LO + BAND_HI) / 2.0, 0.5), Vector3(0, 0.15, 1))
	# Stars on the brim
	var mid := _star_mesh(0.07, 0.03, 0.04)
	for i in 7:
		var a := TAU * (i + 0.25) / 7.0
		if absf(wrapf(a, -PI, PI)) < 0.5:
			continue   # not right over the face
		var r := 0.72 + 0.1 * (i % 2)
		_star_on(hat, small if i % 2 else mid, star_mat, Vector3(sin(a) * r, BRIM_Y + BRIM_DROP * r, cos(a) * r), Vector3(0, 1, 0), a)
	# The cone (head space): its axis runs from the band up and back to the point, then curls back down
	var c0 := Vector3(0, 0.88, 0.0)
	var c1 := Vector3(0, 1.45, -0.34)
	# Crescent moon charm on the front of the cone
	var mp := c0.lerp(c1, 0.35) + Vector3(0, 0, lerpf(0.4, 0.06, 0.35) - 0.03)
	_add(att, _moon_mesh(0.13, 0.07, 0.05), moon_mat, mp, Vector3(deg_to_rad(-25.0), 0, deg_to_rad(110.0)))
	# Stars scattered over the cone
	for e in [[0.35, 1.9], [0.42, -1.6], [0.55, 2.6], [0.6, -0.9], [0.3, 3.3], [0.75, 0.2]]:
		var t: float = e[0]
		var a: float = e[1]
		var n := Vector3(sin(a), 0.35, cos(a))
		var pos := c0.lerp(c1, t) + Vector3(sin(a), 0, cos(a)) * (lerpf(0.36, 0.06, t) + 0.01)
		_star_on(att, mid, star_mat, pos, n, a)
	# A twinkling star dangling from the curled tip of the hat (two crossed, so it reads from every side)
	var tip := Vector3(0, 1.1, -0.66)
	_add(att, _cyl(0.01, 0.01, 0.12, 4), gold, tip + Vector3(0, 0.08, 0))
	var big := _star_mesh(0.1, 0.045, 0.05)
	_star_on(att, big, star_mat, tip, Vector3(0, 0, 1))
	_star_on(att, big, star_mat, tip, Vector3(1, 0, 0))


# ---------------------------------------------------------------- upper (chest space; chest bone at y 0.97)

static func upper(sk: Skeleton3D, att: BoneAttachment3D, role: String, bare: bool) -> void:
	var p := _pal(role)
	var gold := _gold(p["gold"])
	var star_mat := _glow(p["star"], 1.6, 2.2)
	var rune_mat := _glow(p["rune"], 1.8, 1.4)
	var rune_line := _glow(p["rune"], 0.9, 0.0)
	var gem_mat := _glow(p["gem"], 1.5, 1.2)
	var rope := _plain("rope", p["rope"], 0.0, 0.9)
	var paper := _plain("paper", p["paper"], 0.0, 0.9)
	# Star clasp at the collar
	_star_on(att, _star_mesh(0.09, 0.038, 0.045), _glow(p["gold"], 0.6), Vector3(0, 0.25, 0.32), Vector3(0, 0.2, 1))
	_add(att, _sphere(0.025), gem_mat, Vector3(0, 0.25, 0.35))
	# Gold star buttons over the plain ones
	var btn := _star_mesh(0.05, 0.022, 0.03)
	var btn_mat := _glow(p["gold"], 0.5)
	for y in [0.05, -0.03, -0.11, -0.19]:
		_star_on(att, btn, btn_mat, Vector3(0, y, 0.34), Vector3(0, 0, 1))
	# Glowing constellations on each side of the chest
	var dot := _sphere(0.018, 6, 3)
	var line := _box(Vector3(0.012, 1.0, 0.008))
	var cons := [
		[Vector2(0.11, 0.1), Vector2(0.19, 0.04), Vector2(0.16, -0.06), Vector2(0.25, -0.12)],
		[Vector2(-0.12, 0.08), Vector2(-0.2, 0.0), Vector2(-0.14, -0.1), Vector2(-0.24, -0.14)],
	]
	for c in cons:
		for i in c.size():
			var v: Vector2 = c[i]
			var pos := Vector3(v.x, v.y, _robe_z(v.y) + 0.01)
			_add(att, dot, rune_mat, pos, Vector3.ZERO, Vector3(1, 1, 0.6) * (1.4 if i == 0 else 1.0))
			if i + 1 < c.size():
				var w: Vector2 = c[i + 1]
				var mid2 := (v + w) / 2.0
				var d := w - v
				_add(att, line, rune_line, Vector3(mid2.x, mid2.y, _robe_z(mid2.y)),
					Vector3(0, 0, -atan2(d.x, d.y)), Vector3(1, d.length(), 1))
	# Glowing rune marks down the front of the skirt (below the belt)
	var rune := _star_mesh(0.045, 0.012, 0.02, 4)
	for e in [[0.13, -0.48], [-0.14, -0.5], [0.24, -0.53], [-0.25, -0.46]]:
		_star_on(att, rune, rune_mat, Vector3(e[0], e[1], 0.375), Vector3(e[0] * 0.8, 0, 1))
	# Crystal pendant hanging from the belt, and a little rolled scroll on the right hip
	_add(att, _cyl(0.008, 0.008, 0.1, 4), rope, Vector3(0.12, -0.42, 0.4))
	_add(att, _gem(0.04, 0.13), gem_mat, Vector3(0.12, -0.5, 0.41))
	var scroll := Node3D.new()
	scroll.position = Vector3(-0.33, -0.43, 0.2)
	scroll.rotation = Vector3(0, deg_to_rad(-40.0), deg_to_rad(10.0))
	att.add_child(scroll)
	_add(scroll, _cyl(0.04, 0.04, 0.2, 8), paper, Vector3.ZERO)
	_add(scroll, _cyl(0.048, 0.048, 0.03, 8), gold, Vector3(0, 0.1, 0))
	_add(scroll, _cyl(0.048, 0.048, 0.03, 8), gold, Vector3(0, -0.1, 0))
	_add(scroll, _torus(0.04, 0.052, 10, 4), _plain("ribbon", Color(0.45, 0.65, 0.95) if role == "angel" else Color(0.5, 0.1, 0.08)), Vector3.ZERO)
	# Gold bangles on both wrists (local +Y runs along the arm)
	var bangle := _torus(0.12, 0.15, 14, 5)
	var bangle2 := _torus(0.115, 0.14, 14, 5)
	for side in ["l", "r"]:
		var w := _bone(sk, "lowerarm." + side)
		_add(w, bangle, gold, Vector3(0, 0.17, 0))
		_add(w, bangle2, _plain("sky", Color(0.5, 0.75, 1.0) if role == "angel" else Color(0.35, 0.1, 0.08), 0.3, 0.4), Vector3(0, 0.2, 0))
	# The cape (if worn): a gold crescent and stars embroidered on its lower back, gold beads on the hem
	if not bare:
		var back := Vector3(0, 0, -1)
		_add(att, _moon_mesh(0.13, 0.07, 0.03), gold, Vector3(0, -0.55, -0.405), Vector3(0, PI, deg_to_rad(-60.0)))
		var cs := _star_mesh(0.06, 0.026, 0.025)
		for e in [[0.22, -0.42], [-0.2, -0.36], [-0.27, -0.68], [0.26, -0.72], [0.05, -0.8]]:
			_star_on(att, cs, star_mat, Vector3(e[0], e[1], -0.4), back)
		var bead := _sphere(0.03, 6, 3)
		for i in 5:
			var x := -0.3 + 0.15 * i
			_add(att, bead, gold, Vector3(x, -0.9, -0.385))


# Front surface of the robe (chest space): roughly where the cloth is, by height
static func _robe_z(y: float) -> float:
	if y > 0.12:
		return 0.31
	if y > -0.05:
		return 0.34
	return 0.37


# ---------------------------------------------------------------- lower (legs only)

static func lower(sk: Skeleton3D, _att: BoneAttachment3D, role: String, _bare: bool) -> void:
	var p := _pal(role)
	var gold := _gold(p["gold"])
	var star_mat := _glow(p["star"], 1.6, 2.2)
	var cuff := _torus(0.12, 0.155, 14, 5)
	var s := _star_mesh(0.05, 0.022, 0.03)
	for side in ["l", "r"]:
		var x := 0.17 if side == "l" else -0.17
		# Gold cuff around the boot top, with a little star on the front
		var leg := _bone(sk, "lowerleg." + side)
		var lr := _rest_inv(sk, "lowerleg." + side)
		_add(leg, cuff, gold, lr * Vector3(x, 0.24, 0.0), (lr.basis * Basis.IDENTITY).get_euler())
		_star_on(leg, s, star_mat, lr * Vector3(x, 0.24, 0.15), lr.basis * Vector3(0, 0, 1))
		# Curled gold slipper tip: a chain of tapering segments curling up and back from the toe
		var toes := _bone(sk, "foot." + side)
		var tr := _rest_inv(sk, "foot." + side)
		var pts := [Vector3(x, 0.08, 0.2), Vector3(x, 0.1, 0.3), Vector3(x, 0.16, 0.36), Vector3(x, 0.22, 0.34), Vector3(x, 0.235, 0.29)]
		var rads := [0.05, 0.04, 0.03, 0.022, 0.015]
		for i in pts.size() - 1:
			_seg(toes, tr * pts[i], tr * pts[i + 1], rads[i], rads[i + 1], gold)
		_add(toes, _sphere(0.035, 8, 4), star_mat, tr * pts[pts.size() - 1])


# The inverse rest transform of a bone: turns model-space points into that bone's space
static func _rest_inv(sk: Skeleton3D, bone: String) -> Transform3D:
	return sk.get_bone_global_rest(sk.find_bone(bone)).affine_inverse()


# A tapering round segment from a to b
static func _seg(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mat: Material) -> void:
	var d := b - a
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl(rb, ra, 1.0, 6)
	mi.material_override = mat
	parent.add_child(mi)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * d.length(), z), (a + b) / 2.0)
	# a ball at the joint hides the seam
	_add(parent, _sphere(ra, 6, 3), mat, a)


# Gold that stays golden in shade: a little metallic, a little self-lit
static func _gold(c: Color) -> Material:
	var k := "gold_%s" % c.to_html()
	if not _cache.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.45
		m.roughness = 0.35
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.18
		_cache[k] = m
	return _cache[k]
