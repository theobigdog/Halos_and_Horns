# The classic pumpkin and hay bale, dressed up (Ted's wife, Nov 25: "pumpkin and hay bale look very basic").
# Both are built from procedural meshes with vertex colours, made once and shared by every copy on the map.
# Real props and demons disguised as them must look exactly alike, so everything is fixed: hand-picked
# numbers and seeded RandomNumberGenerators only (never the global random functions).
#   pumpkin: fits the collision cylinder r 0.4, h 0.66, bottom at y = 0.
#   hay:     fits the box 1.2 x 0.8 x 0.8, bottom at y = 0, centred.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

static var _cache := {}


static func pumpkin(root: Node3D) -> void:
	if not _cache.has("pumpkin_body"):
		_cache["pumpkin_body"] = _pumpkin_body()
		_cache["pumpkin_bits"] = _pumpkin_bits()
	_add(root, _cache["pumpkin_body"], _mat("pumpkin"))
	_add(root, _cache["pumpkin_bits"], _mat("veg"))


static func hay(root: Node3D) -> void:
	if not _cache.has("hay_body"):
		_cache["hay_body"] = _hay_body()
		_cache["hay_bits"] = _hay_bits()
	_add(root, _cache["hay_body"], _mat("hay"))
	_add(root, _cache["hay_bits"], _mat("veg"))


static func _add(root: Node3D, mesh: Mesh, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	root.add_child(mi)


static func _mat(kind: String) -> StandardMaterial3D:
	if _cache.has("mat_" + kind):
		return _cache["mat_" + kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match kind:
		"pumpkin":
			Surfaces.apply(m, "plant")   # a faint skin texture under the colours
			m.roughness = 0.5
		"veg":
			m.roughness = 0.85
			m.cull_mode = BaseMaterial3D.CULL_DISABLED   # the leaf is a single sheet
		"hay":
			var tex := _straw_textures()
			m.albedo_texture = tex[0]
			m.normal_enabled = true
			m.normal_texture = tex[1]
			m.normal_scale = 0.9
			m.roughness = 1.0
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache["mat_" + kind] = m
	return m


# ---------------------------------------------------------------- shared bits

# A tube along pts (Vector3), radius per point, colour per point. ribs > 0 gives it ribs (darker in the
# grooves) that twist round by `twist` radians from end to end. cap: colour of a lid on the far end
# (alpha 0 = open).
static func _tube(st: SurfaceTool, pts: Array, radii: Array, cols: Array, sides: int, ribs := 0,
		rib_amp := 0.0, twist := 0.0, cap := Color(0, 0, 0, 0)) -> void:
	var n := pts.size()
	var first: Vector3 = pts[1] - pts[0]
	var side := first.cross(Vector3.UP if absf(first.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var rings := []
	var last_t := Vector3.UP
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		last_t = t
		side = (side - t * side.dot(t)).normalized()
		var up := t.cross(side)
		var ring := []
		for j in sides + 1:
			var a := TAU * j / sides
			var rib := 0.5 + 0.5 * cos(ribs * a + twist * float(i) / (n - 1)) if ribs > 0 else 1.0
			var r: float = radii[i] * (1.0 + rib_amp * (rib - 0.5))
			var c: Color = cols[i]
			if ribs > 0:
				c = c.darkened(0.3 * (1.0 - rib)).lightened(0.12 * rib * rib)
			ring.append([pts[i] + (side * cos(a) + up * sin(a)) * r, c])
		rings.append(ring)
	for i in n - 1:
		for j in sides:
			var q := [rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(q[k][1])
				st.add_vertex(q[k][0])
	if cap.a > 0.0:
		var tip: Vector3 = pts[n - 1] + last_t * radii[n - 1] * 0.15
		for j in sides:
			st.set_color(cap.darkened(0.15))
			st.add_vertex(rings[n - 1][j][0])
			st.set_color(cap.darkened(0.15))
			st.add_vertex(rings[n - 1][j + 1][0])
			st.set_color(cap)
			st.add_vertex(tip)


# ---------------------------------------------------------------- pumpkin

const PK_LOBES := 9
const PK_R := 0.385     # widest radius (collision 0.4)
const PK_H := 0.29      # half the body's height before the dimples
const PK_DEPTH := 0.13  # how deep the grooves cut in
const PK_LOBE_AMP := [1.0, 0.93, 1.04, 0.97, 1.03, 0.91, 1.02, 0.96, 0.99]   # slightly uneven lobes
const PK_LOBE_TINT := [0.0, 0.06, -0.04, 0.03, -0.02, 0.07, -0.05, 0.02, 0.04]


static func _pk_warp(phi: float) -> float:
	return phi + 0.07 * sin(phi * 2.0 + 1.3) + 0.045 * sin(phi * 3.0 + 0.4)


# x: radius factor, y: 0 in a groove .. 1 on the middle of a lobe, z: which lobe
static func _pk_lobe(phi: float) -> Vector3:
	var t := fposmod(_pk_warp(phi), TAU) / TAU * PK_LOBES
	var k := int(t) % PK_LOBES
	var s: float = t - floor(t)
	var prof := pow(sin(PI * s), 0.5)
	var amp: float = PK_LOBE_AMP[k]
	return Vector3(1.0 - PK_DEPTH + PK_DEPTH * prof * amp, prof, k)


# v: 0 at the bottom .. 1 at the top, phi: round the side.
static func _pk_point(v: float, phi: float) -> Vector3:
	var th := PI * v
	var sn := sin(th)
	var lobe := _pk_lobe(phi)
	var rr := PK_R * pow(sn, 0.7) * lobe.x
	var y := PK_H - PK_H * cos(th)
	y -= 0.13 * pow(1.0 - sn, 3.0) * smoothstep(0.5, 1.0, v)          # the deep dip the stem sits in
	y += 0.04 * pow(1.0 - sn, 2.0) * (1.0 - smoothstep(0.0, 0.5, v))   # and a little one underneath
	y += 0.025 * (lobe.y - 0.6) * sn * smoothstep(0.55, 0.85, v)         # lobes swell over the shoulders
	return Vector3(cos(phi) * rr, y - _pk_low(), sin(phi) * rr)


static func _pk_low() -> float:
	if not _cache.has("pk_low"):
		var low := 1.0
		for i in 60:
			var v := i / 120.0
			var th := PI * v
			var sn := sin(th)
			var y := PK_H - PK_H * cos(th) + 0.04 * pow(1.0 - sn, 2.0) * (1.0 - smoothstep(0.0, 0.5, v))
			low = minf(low, y)
		_cache["pk_low"] = low
	return _cache["pk_low"]


# The height of the pumpkin's top at (x, z) (for laying the leaf and tendril on it).
static func _pk_top_y(x: float, z: float) -> float:
	var phi := atan2(z, x)
	var rho := Vector2(x, z).length()
	var lo := 0.5
	var hi := 1.0
	for i in 18:
		var mid := (lo + hi) * 0.5
		var p := _pk_point(mid, phi)
		if Vector2(p.x, p.z).length() > rho:
			lo = mid
		else:
			hi = mid
	return _pk_point((lo + hi) * 0.5, phi).y


static func _pumpkin_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 18             # (Nov 26 performance audit: was 30 x 10 per lobe)
	var around := PK_LOBES * 6
	var groove := Color(0.55, 0.2, 0.03)
	var mid := Color(0.95, 0.46, 0.05)
	var ridge := Color(1.0, 0.64, 0.2)
	var grid := []
	for i in rings + 1:
		var v := float(i) / rings
		var row := []
		for j in around + 1:
			var phi := TAU * j / around
			var lobe := _pk_lobe(phi)
			var c := groove.lerp(mid, smoothstep(0.0, 0.6, lobe.y))
			var shoulder := sin(PI * v)
			c = c.lerp(ridge, smoothstep(0.65, 1.0, lobe.y) * (0.35 + 0.5 * shoulder))
			c = c.lightened(PK_LOBE_TINT[int(lobe.z)]) if PK_LOBE_TINT[int(lobe.z)] > 0.0 else c.darkened(-PK_LOBE_TINT[int(lobe.z)])
			c = c * (1.0 + 0.045 * sin(phi * PK_LOBES * 3.0 + 4.0 * sin(v * 5.0)))   # faint streaks
			c = c.lerp(Color(0.5, 0.32, 0.07), smoothstep(0.86, 1.0, v) * 0.55)         # darker round the stem
			c = c.lerp(Color(0.95, 0.72, 0.32), (1.0 - smoothstep(0.0, 0.25, v)) * 0.6)  # pale where it sat
			c.a = 1.0
			row.append([_pk_point(v, phi), c])
		grid.append(row)
	for i in rings:
		for j in around:
			var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_color(q[k][1])
				st.add_vertex(q[k][0])
	st.index()
	st.generate_normals()
	return st.commit()


static func _pumpkin_bits() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := _pk_point(1.0, 0.0).y
	# The stem: thick, ribbed and twisted, leaning and bending over at the tip, green going woody brown.
	var pts := []
	var radii := []
	var cols := []
	var n := 16
	for i in n:
		var t := float(i) / (n - 1)
		pts.append(Vector3(0.03 * t * t + 0.07 * pow(t, 4.0), top - 0.03 + 0.2 * t - 0.025 * pow(t, 4.0), -0.015 * t * t))
		radii.append(0.034 + 0.04 * pow(1.0 - minf(t / 0.3, 1.0), 2.0) + 0.006 * smoothstep(0.85, 1.0, t))
		cols.append(Color(0.3, 0.42, 0.12).lerp(Color(0.46, 0.35, 0.18), smoothstep(0.15, 0.85, t)))
	_tube(st, pts, radii, cols, 20, 5, 0.32, 2.2, Color(0.74, 0.64, 0.42))
	# A curly tendril springing from the stem's foot and corkscrewing out over the top.
	var dir := Vector3(cos(0.6), 0.0, sin(0.6))
	var perp := dir.cross(Vector3.UP)
	pts = []
	radii = []
	cols = []
	n = 90
	for i in n:
		var t := float(i) / (n - 1)
		var c := dir * (0.05 + 0.25 * t)
		c.y = _pk_top_y(c.x, c.z) + 0.03 + 0.04 * sin(PI * t)
		var ang := t * TAU * 3.2
		var rh := 0.03 * pow(sin(PI * minf(t * 1.15, 1.0)), 0.6) + 0.004
		pts.append(c + (Vector3.UP * cos(ang) + perp * sin(ang)) * rh * smoothstep(0.0, 0.15, t))
		radii.append(0.011 - 0.005 * t)
		cols.append(Color(0.32, 0.44, 0.13).lerp(Color(0.45, 0.5, 0.18), t))
	_tube(st, pts, radii, cols, 6)
	# A leaf laid over the top: five round lobes, pale veins, edges turning yellow-brown.
	var la := 2.5
	var ld := Vector3(cos(la), 0.0, sin(la))
	var lc := ld * 0.17
	var ring_n := 4
	var ang_n := 30
	var size := 0.13
	var lgrid := []
	for r in ring_n + 1:
		var f := float(r) / ring_n
		var row := []
		for j in ang_n + 1:
			var a := TAU * j / ang_n
			var rel := a - la   # 0 = pointing away from the stem
			var lobes := 0.62 + 0.38 * pow(absf(cos(rel * 2.5)), 0.6)
			var notch := 1.0 - 0.55 * pow(maxf(0.0, -cos(rel)), 8.0)   # the dip where the leaf stalk joins
			var rad := size * lobes * notch * f
			var x := lc.x + cos(a) * rad
			var z := lc.z + sin(a) * rad
			var y := _pk_top_y(x, z) + 0.012 + 0.03 * f * f + 0.006 * sin(a * 7.0) * f
			var vein := pow(absf(cos(rel * 2.5)), 30.0) * (1.0 - f * 0.6)
			var col := Color(0.2, 0.4, 0.12).lerp(Color(0.3, 0.52, 0.15), f)
			col = col.lerp(Color(0.62, 0.55, 0.18), smoothstep(0.7, 1.0, f) * (0.4 + 0.4 * sin(a * 3.0 + 1.0)))
			col = col.lerp(Color(0.55, 0.7, 0.35), vein * 0.8)
			row.append([Vector3(x, y, z), col])
		lgrid.append(row)
	for r in ring_n:
		for j in ang_n:
			var q := [lgrid[r][j], lgrid[r + 1][j], lgrid[r + 1][j + 1], lgrid[r][j + 1]]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_color(q[k][1])
				st.add_vertex(q[k][0])
	# its stalk, from the stem's foot to the leaf
	pts = []
	radii = []
	cols = []
	for i in 6:
		var t := i / 5.0
		var p := ld * (0.03 + 0.11 * t)
		p.y = _pk_top_y(p.x, p.z) + 0.015 + 0.02 * sin(PI * t)
		pts.append(p)
		radii.append(0.011)
		cols.append(Color(0.3, 0.45, 0.14))
	_tube(st, pts, radii, cols, 6)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- hay bale

const HAY_HALF := Vector3(0.525, 0.38, 0.37)   # before the bulges
const HAY_ROUND := 0.1
const HAY_TWINE_X := 0.3
const HAY_UV := 2.0   # strand texture repeats every half metre


# A point on (or just outside) the box -> on the rounded box, with the outward normal there.
static func _hay_round(p: Vector3) -> Array:
	var inner := HAY_HALF - Vector3.ONE * HAY_ROUND
	var q := p.clamp(-inner, inner)
	var d := p - q
	var nrm := d.normalized() if d.length() > 0.00001 else Vector3.UP
	return [q + nrm * HAY_ROUND, nrm]


# Squeezes in under the twine and at the seams between the pressed slabs ("flakes"), plumps out between.
static func _hay_squeeze(x: float) -> float:
	var ax := absf(x)
	var s := 1.0 + 0.03 * (1.0 - pow(x / HAY_HALF.x, 2.0))
	s -= 0.055 * exp(-pow((ax - HAY_TWINE_X) / 0.035, 2.0))
	for seam in [0.0, 0.18, 0.4]:
		s -= 0.012 * exp(-pow((ax - seam) / 0.014, 2.0))
	return s


static func _hay_deform(p: Vector3) -> Vector3:
	var s := _hay_squeeze(p.x)
	var q := Vector3(p.x, p.y * (s if p.y > 0.0 else minf(s, 1.0)), p.z * s)   # (the bottom stays on the floor)
	# the ends bulge out a little in the middle
	var bulge := (1.0 - pow(p.y / HAY_HALF.y, 2.0)) * (1.0 - pow(p.z / HAY_HALF.z, 2.0))
	q.x += signf(p.x) * 0.025 * maxf(bulge, 0.0) * smoothstep(HAY_HALF.x - 0.15, HAY_HALF.x, absf(p.x))
	q.y += HAY_HALF.y
	return q


static func _hay_flake(x: float) -> int:
	return clampi(int(floor((x + HAY_HALF.x) / (2.0 * HAY_HALF.x) * 6.0)), 0, 5)


static func _hay_color(p: Vector3, squeeze: float) -> Color:
	var tints: Array = _cache.get("hay_tints", [])
	if tints.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1107
		for i in 6:
			tints.append(Color(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.04, 0.05), rng.randf_range(-0.04, 0.03)))
		_cache["hay_tints"] = tints
	var t: Color = tints[_hay_flake(p.x)]
	var c := Color(1.0 + t.r, 0.8 + t.g, 0.32 + t.b)
	c = c.lerp(Color(1.0, 0.9, 0.6), smoothstep(0.55, 0.78, p.y) * 0.25)   # sun-bleached top
	c = c.lerp(Color(0.62, 0.46, 0.22), (1.0 - smoothstep(0.0, 0.18, p.y)) * 0.6)   # grubby bottom
	c = c.darkened(clampf((1.0 - squeeze) * 6.0, 0.0, 0.45))   # shadowed in the twine's groove
	c.a = 1.0
	return c


# Sample positions along one side of the box: dense round the rounded edges, even in between.
static func _hay_samples(h: float, step: float) -> Array:
	var out := []
	var r := HAY_ROUND
	var edge := []
	for k in 6:
		var ang := deg_to_rad(45.0 + 45.0 * k / 6.0)
		edge.append(r * (1.0 - 1.0 / tan(ang)))
	for e in edge:
		out.append(-h + e)
	var span := 2.0 * (h - r)
	var cnt := maxi(1, int(ceil(span / step)))
	for i in cnt + 1:
		out.append(-h + r + span * i / cnt)
	for k in range(edge.size() - 1, -1, -1):
		out.append(h - edge[k])
	return out


static func _hay_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# (Nov 26 performance audit: was 0.012 / 0.04 / 0.04, 23,700 triangles for one bale)
	var xs := _hay_samples(HAY_HALF.x, 0.03)
	var ys := _hay_samples(HAY_HALF.y, 0.07)
	var zs := _hay_samples(HAY_HALF.z, 0.07)
	# each face: [axis it faces along, sign, the two sample lists, how to build the box point]
	for face in 6:
		var axis := face / 2
		var sgn := 1.0 if face % 2 == 0 else -1.0
		var us: Array
		var vs: Array
		match axis:
			0: us = zs; vs = ys
			1: us = xs; vs = zs
			_: us = xs; vs = ys
		var grid := []
		for a in us.size():
			var row := []
			for b in vs.size():
				var u: float = us[a]
				var v: float = vs[b]
				var p: Vector3
				var uv: Vector2
				match axis:
					0:
						p = Vector3(sgn * HAY_HALF.x, v, u)
						uv = Vector2(v * 1.3 + 0.3 * sgn, u * 1.3) * HAY_UV   # ends: strands run up and down, crumpled
					1:
						p = Vector3(u, sgn * HAY_HALF.y, v)
						uv = Vector2(u, v) * HAY_UV
					_:
						p = Vector3(u, v, sgn * HAY_HALF.z)
						uv = Vector2(u, v + 0.37 * sgn) * HAY_UV
				var rp: Array = _hay_round(p)
				var fp := _hay_deform(rp[0])
				row.append([fp, _hay_color(fp, _hay_squeeze(u if axis != 0 else p.x)), uv])
			grid.append(row)
		for a in us.size() - 1:
			for b in vs.size() - 1:
				var q := [grid[a][b], grid[a + 1][b], grid[a + 1][b + 1], grid[a][b + 1]]
				# winding so the face points outwards, whichever way this face's grid runs
				# (Godot's front faces wind clockwise: (b - a) x (c - a) points into the bale.)
				var outward := Vector3.ZERO
				outward[axis] = sgn
				var a0: Vector3 = q[0][0]
				var c0: Vector3 = (q[2][0] - a0).cross(q[1][0] - a0)
				var order := [0, 2, 1, 0, 3, 2] if c0.dot(outward) < 0.0 else [0, 1, 2, 0, 2, 3]
				for k in order:
					st.set_color(q[k][1])
					st.set_uv(q[k][2])
					st.add_vertex(q[k][0])
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _hay_bits() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two bands of twine, sunk into their grooves, twisted.
	for sx in [-1.0, 1.0]:
		var x: float = sx * HAY_TWINE_X
		var pts := []
		var radii := []
		var cols := []
		var n := 40
		for i in n + 1:
			var a := TAU * i / n + 0.4
			var d := Vector2(cos(a), sin(a))
			var t := minf(HAY_HALF.y / maxf(absf(d.x), 0.0001), HAY_HALF.z / maxf(absf(d.y), 0.0001))
			var rp: Array = _hay_round(Vector3(x, d.x * t, d.y * t))
			var p := _hay_deform(rp[0]) + (rp[1] as Vector3) * 0.004
			p.y = maxf(p.y, 0.02)   # (flattened under the bale, never through the floor)
			pts.append(p)
			radii.append(0.016)
			cols.append(Color(0.6, 0.38, 0.17))
		_tube(st, pts, radii, cols, 8, 3, 0.45, 70.0)
		# a little knot on top
		var top: Vector3 = _hay_deform(_hay_round(Vector3(x, HAY_HALF.y, 0.12 * sx))[0])
		var kp := []
		var kr := []
		var kc := []
		for i in 14:
			var t := i / 13.0
			var ang := t * TAU * 1.1
			kp.append(top + Vector3(0.025 * sin(ang), 0.006 + 0.012 * sin(PI * t), 0.03 * cos(ang) - 0.015 + 0.05 * t * t))
			kr.append(0.014)
			kc.append(Color(0.7, 0.44, 0.2))
		_tube(st, kp, kr, kc, 6, 3, 0.4, 12.0, Color(0.6, 0.38, 0.17))
	# Loose straws poking out of the ends, the top edges and the sides.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2311
	var lim := Vector3(0.587, 0.787, 0.387)   # (minus the straw's thickness)
	for i in 46:
		var start: Vector3
		var dir: Vector3
		var length: float
		if i < 22:   # ends
			var sx := 1.0 if i % 2 == 0 else -1.0
			start = Vector3(sx * 0.47, rng.randf_range(0.12, 0.7), rng.randf_range(-0.3, 0.3))
			dir = Vector3(sx, rng.randf_range(-0.45, 0.45), rng.randf_range(-0.7, 0.7)).normalized()
			length = rng.randf_range(0.12, 0.22)
		elif i < 36:   # over the top, drooping over the long edges
			var sz := 1.0 if i % 2 == 0 else -1.0
			start = Vector3(rng.randf_range(-0.45, 0.45), 0.745, sz * rng.randf_range(0.15, 0.3))
			dir = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.0, 0.12), sz).normalized()
			length = rng.randf_range(0.12, 0.22)
		else:   # out of the long sides
			var sz := 1.0 if i % 2 == 0 else -1.0
			start = Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(0.15, 0.65), sz * 0.32)
			dir = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.4), sz * 0.8).normalized()
			length = rng.randf_range(0.1, 0.16)
		var col := Color(0.97, 0.84, 0.48).lerp(Color(0.85, 0.66, 0.3), rng.randf())
		var pts := []
		var radii := []
		var cols := []
		var droop := rng.randf_range(0.02, 0.06)
		for k in 4:
			var t := k / 3.0
			var p := start + dir * length * t - Vector3(0, droop * t * t, 0)
			pts.append(p.clamp(Vector3(-lim.x, 0.012, -lim.z), lim))
			radii.append(rng.randf_range(0.007, 0.01) * (1.0 - 0.4 * t))
			cols.append(col.lightened(0.15 * t))
		_tube(st, pts, radii, cols, 4)
	st.generate_normals()
	return st.commit()


# The straw texture: hundreds of strands, mostly lying one way, each with a highlight down its middle and a
# dark edge so they read as separate straws. Greyscale (the vertex colours tint it); made once, seeded.
static func _straw_textures() -> Array:
	var size := 256
	var data := PackedByteArray()
	data.resize(size * size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in size * size:
		data[i] = 85 + rng.randi() % 35
	for k in 520:
		var x0 := rng.randf() * size
		var y0 := rng.randf() * size
		var ang := rng.randf_range(-0.2, 0.2) if rng.randf() < 0.85 else rng.randf_range(-1.1, 1.1)
		var length := rng.randf_range(30.0, 120.0)
		var w := rng.randf_range(1.6, 3.0)
		var bright := rng.randf_range(0.7, 1.0)
		var dx := cos(ang)
		var dy := sin(ang)
		var steps := int(length)
		for s in steps:
			var cx := x0 + dx * s
			var cy := y0 + dy * s
			var ww := w * (0.55 + 0.45 * pow(sin(PI * (s + 0.5) / steps), 0.4))
			var reach := int(ceil(ww)) + 1
			for o in range(-reach, reach + 1):
				var px := posmod(int(floor(cx - dy * o)), size)
				var py := posmod(int(floor(cy + dx * o)), size)
				var idx := py * size + px
				var dist := absf(o) / ww
				if dist <= 1.0:
					var v := bright * (0.72 + 0.28 * (1.0 - dist * dist)) * (0.93 + 0.07 * sin(s * 0.7 + k))
					data[idx] = int(clampf(v * 255.0, 0.0, 255.0))
				elif data[idx] > 70:
					data[idx] = int(data[idx] * 0.65)
	var img := Image.create_from_data(size, size, false, Image.FORMAT_L8, data)
	var nimg := img.duplicate() as Image
	nimg.convert(Image.FORMAT_RGBA8)
	nimg.bump_map_to_normal_map(3.0)
	img.generate_mipmaps()
	nimg.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(nimg)]
