# The classic props, made properly (Ted, Nov 26: "the stack of books prop is still just a bunch of rectangles...
# go through ALL props, and anything that is still low-res like the books, upgrade them"; his wife: "apple, stack
# of books, and pot need to be refined to look more realistic", "the big floppy pickle still needs work", "make the
# crate more crate-like, with stickers or arrows or words on it"), and the new garden and street props she asked
# for (garbage cans, bushes that aren't in pots, flowers and plants).
#
# Everything is built in code from turned (lathe) and boxed shapes with vertex colours, over the shared surface
# textures (surfaces.gd), made once per type and shared. Real props and demons disguised as them must look exactly
# alike, so there's no randomness but seeded RandomNumberGenerators. Each fits its collision shape in
# prop_library.gd / extra_props.gd, standing on y = 0.
extends RefCounted

const Surfaces = preload("res://scripts/surfaces.gd")

static var _cache := {}


# ---------------------------------------------------------------- building blocks

static func _vmat(kind: String, rough := -1.0, metal := -1.0, two_sided := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [kind, rough, metal, two_sided]
	if _cache.has("m:" + key):
		return _cache["m:" + key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	Surfaces.apply(m, kind)
	if rough >= 0.0:
		m.roughness = rough
	if metal >= 0.0:
		m.metallic = metal
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["m:" + key] = m
	return m


static func _add(root: Node3D, mesh: Mesh, m: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	root.add_child(mi)
	return mi


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _end(st: SurfaceTool, smooth: bool) -> ArrayMesh:
	if smooth:
		st.index()
	st.generate_normals()
	return st.commit()


# A triangle facing `out` (Godot's front faces wind clockwise seen from the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	_tri(st, a, b, c, col, out)
	_tri(st, a, c, d, col, out)


# A box (centre, full size), turned by bas; `skip_bottom` leaves out the face nobody sees.
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, bas := Basis(), skip_bottom := false) -> void:
	var h := s * 0.5
	var ax := [bas.x.normalized(), bas.y.normalized(), bas.z.normalized()]
	for i in 3:
		for sg in [-1.0, 1.0]:
			if skip_bottom and i == 1 and sg < 0.0:
				continue
			var n: Vector3 = ax[i] * sg
			var a1: Vector3 = ax[(i + 1) % 3] * h[(i + 1) % 3]
			var a2: Vector3 = ax[(i + 2) % 3] * h[(i + 2) % 3]
			var fc: Vector3 = c + n * h[i]
			_quad(st, fc - a1 - a2, fc + a1 - a2, fc + a1 + a2, fc - a1 + a2, col, n)


# Turned on a lathe round the y axis at `at`: prof = [[radius, y], ...], traced up the outside and (for
# hollow things) back down the inside; each segment faces away from the side it was traced on. col(i, a)
# gives a ring's colour at angle a; rad(i, a) can bend the radius (ribs, staves, lumps).
static func _lathe(st: SurfaceTool, prof: Array, sides: int, col: Callable, at := Vector3.ZERO, rad := Callable()) -> void:
	for i in prof.size() - 1:
		var p0: Array = prof[i]
		var p1: Array = prof[i + 1]
		var dr: float = p1[0] - p0[0]
		var dy: float = p1[1] - p0[1]
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			var am := (a0 + a1) * 0.5
			var r00: float = p0[0] * (rad.call(i, a0) if rad.is_valid() else 1.0)
			var r01: float = p0[0] * (rad.call(i, a1) if rad.is_valid() else 1.0)
			var r10: float = p1[0] * (rad.call(i + 1, a0) if rad.is_valid() else 1.0)
			var r11: float = p1[0] * (rad.call(i + 1, a1) if rad.is_valid() else 1.0)
			var v00 := at + Vector3(cos(a0) * r00, p0[1], sin(a0) * r00)
			var v01 := at + Vector3(cos(a1) * r01, p0[1], sin(a1) * r01)
			var v10 := at + Vector3(cos(a0) * r10, p1[1], sin(a0) * r10)
			var v11 := at + Vector3(cos(a1) * r11, p1[1], sin(a1) * r11)
			var out := Vector3(cos(am), 0.0, sin(am)) * dy + Vector3.UP * -dr
			if out.length() < 0.0001:
				out = Vector3(cos(am), 0.0, sin(am))
			var c0: Color = col.call(i, a0)
			var c1: Color = col.call(i + 1, a0)
			var c2: Color = col.call(i + 1, a1)
			var c3: Color = col.call(i, a1)
			# (per-vertex colours, wound like _quad)
			var tris := [[v00, c0, v10, c1, v11, c2], [v00, c0, v11, c2, v01, c3]]
			for t in tris:
				var a: Vector3 = t[0]
				var b: Vector3 = t[2]
				var c: Vector3 = t[4]
				var ca: Color = t[1]
				var cb: Color = t[3]
				var cc: Color = t[5]
				if (b - a).cross(c - a).dot(out) > 0.0:
					var tv := b
					b = c
					c = tv
					var tc := cb
					cb = cc
					cc = tc
				st.set_color(ca)
				st.add_vertex(a)
				st.set_color(cb)
				st.add_vertex(b)
				st.set_color(cc)
				st.add_vertex(c)


static func _flat(c: Color) -> Callable:
	return func(_i: int, _a: float) -> Color: return c


# A ring (torus) round the y axis: radius R, tube radius r, at height y.
static func _ring(st: SurfaceTool, at: Vector3, big: float, small: float, col: Color, sides := 24, tube := 6) -> void:
	var prof := []
	for k in tube + 1:
		var t := TAU * k / tube - PI * 0.5
		prof.append([big + cos(t) * small, sin(t) * small])
	_lathe(st, prof, sides, _flat(col), at)


# A tube along pts with radius per point (stems, handles, branches).
static func _tube(st: SurfaceTool, pts: Array, radii: Array, col: Color, sides := 6) -> void:
	var n := pts.size()
	var rings := []
	var side := Vector3.RIGHT
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		side = (side - t * side.dot(t))
		if side.length() < 0.01:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := t.cross(side)
		var ring := []
		for j in sides:
			var a := TAU * j / sides
			ring.append(pts[i] + (side * cos(a) + up * sin(a)) * float(radii[i]))
		rings.append(ring)
	for i in n - 1:
		var mid: Vector3 = (pts[i] + pts[i + 1]) * 0.5
		for j in sides:
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i + 1][j]
			var c: Vector3 = rings[i + 1][(j + 1) % sides]
			var d: Vector3 = rings[i][(j + 1) % sides]
			_quad(st, a, b, c, d, col, (a + c) * 0.5 - mid)


static func _h(x: float) -> float:
	return fposmod(sin(x * 127.1 + 311.7) * 43758.5453, 1.0)


# ---------------------------------------------------------------- the classic props

static func make(type_name: String, root: Node3D) -> bool:
	match type_name:
		"barrel": _barrel(root)
		"crate": _crate(root)
		"lamp": _lamp(root)
		"pot": _pot(root)
		"bench": _bench(root)
		"books": _books(root)
		"apple": _apple(root)
		"pickle": _pickle(root)
		"trash_can": _trash_can(root)
		"wheelie_bin": _wheelie_bin(root)
		"bush": _bush(root, false)
		"bush_flowering": _bush(root, true)
		"flowers_daisies": _daisies(root)
		"flowers_tulips": _tulips(root)
		"fern": _fern(root)
		"snowball": _snowball(root, 0.35)
		"snowball_big": _snowball(root, 0.58)
		"snowman": _snowman(root)
		"coconut": _coconut(root)
		"beehive": _beehive(root)
		_: return false
	return true


# ---------------------------------------------------------------- Nov 27: snow, a coconut, a beehive

# A packed, rolled snowball: lumpy, with the crust of a roll's spiral and a few bits of grass and leaf rolled up
# in it, a little flattened where it sits. Lit by the snow shader's soft sparkle (vertex colours, matte).
static func _snow_ball(st: SurfaceTool, at: Vector3, r: float, seed: int) -> void:
	var rings := 14
	var around := 24
	var lump := func(u: float, a: float) -> float:
		return 1.0 + 0.045 * sin(a * 5.0 + u * 9.0 + seed) + 0.03 * sin(a * 11.0 - u * 17.0 + seed * 2.0) \
				+ 0.02 * sin(u * 40.0 + a * 3.0)
	var pt := func(u: float, a: float) -> Vector3:
		var th := PI * u
		var rr: float = r * lump.call(u, a)
		var p := Vector3(sin(th) * cos(a), -cos(th), sin(th) * sin(a)) * rr
		if p.y < -r * 0.82:
			p.y = -r * 0.82 + (p.y + r * 0.82) * 0.25   # sat down: a flattened bottom
		return at + p + Vector3.UP * r * 0.82
	var col := func(u: float, a: float) -> Color:
		var c := Color(0.93, 0.95, 0.99).lerp(Color(0.8, 0.86, 0.95), 0.5 + 0.5 * sin(a * 7.0 + u * 23.0 + seed))
		if _h(floor(u * 31.0) * 7.0 + floor(a * 9.0) + seed) > 0.993:
			c = c.lerp(Color(0.45, 0.5, 0.32), 0.6)   # a bit of grass rolled up in it
		return c
	for i in rings:
		for j in around:
			var u0 := float(i) / rings
			var u1 := float(i + 1) / rings
			var a0 := TAU * j / around
			var a1 := TAU * (j + 1) / around
			var p00: Vector3 = pt.call(u0, a0)
			var p01: Vector3 = pt.call(u0, a1)
			var p10: Vector3 = pt.call(u1, a0)
			var p11: Vector3 = pt.call(u1, a1)
			# (a colour per corner, so the smoothing can blend them: no squares)
			for v in [[p00, u0, a0], [p11, u1, a1], [p10, u1, a0], [p00, u0, a0], [p01, u0, a1], [p11, u1, a1]]:
				st.set_color(col.call(v[1], fmod(v[2], TAU)))
				st.add_vertex(v[0])


# (collision: a cylinder as wide as the ball)
static func _snowball(root: Node3D, r: float) -> void:
	var key := "snowball_%s" % r
	var parts := _cached(key, func() -> Array:
		var st := _begin()
		_snow_ball(st, Vector3.ZERO, r, 3 if r < 0.5 else 8)
		return [_end(st, true)])
	_add(root, parts[0], _vmat("plaster", 0.85))


# A cute snowman: three snowballs, coal eyes and a coal smile, a carrot nose, a knitted scarf with fringed
# ends, stick arms with twiggy fingers, three coal buttons and a little top hat. (collision: 0.45 x 1.62)
static func _snowman(root: Node3D) -> void:
	var parts := _cached("snowman", func() -> Array:
		var snow := _begin()
		_snow_ball(snow, Vector3.ZERO, 0.4, 11)
		_snow_ball(snow, Vector3(0, 0.6, 0), 0.29, 12)
		_snow_ball(snow, Vector3(0, 1.02, 0), 0.21, 13)
		var coal := _begin()
		var coal_c := Color(0.07, 0.07, 0.08)
		var head := Vector3(0, 1.02 + 0.21 * 0.82, 0)
		var face := func(yaw: float, pitch: float, rad: float) -> Vector3:
			return head + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * rad
		for s in [-1.0, 1.0]:   # eyes: shiny round coals
			_lathe(coal, [[0.0, -0.028], [0.026, -0.012], [0.028, 0.0], [0.022, 0.016], [0.0, 0.024]], 10,
					func(_i, _a): return coal_c, face.call(s * 0.32, 0.22, 0.2))
		for k in 7:   # the smile
			var a := lerpf(-0.55, 0.55, k / 6.0)
			_lathe(coal, [[0.0, -0.014], [0.016, -0.006], [0.016, 0.006], [0.0, 0.014]], 8,
					func(_i, _a): return coal_c, face.call(a, -0.28 - 0.12 * cos(a * 2.6), 0.205))
		var mid_c := Vector3(0, 0.6 + 0.29 * 0.82, 0)   # (the middle snowball's centre)
		for k in 3:   # buttons, down the front of the middle snowball
			var y: float = mid_c.y - 0.13 + 0.11 * k
			var bp := Vector3(0, y, sqrt(maxf(0.0, 0.29 * 0.29 - pow(y - mid_c.y, 2.0))) + 0.005)
			_lathe(coal, [[0.0, -0.03], [0.03, -0.012], [0.032, 0.0], [0.024, 0.02], [0.0, 0.028]], 10,
					func(_i, _a): return coal_c, bp + Vector3(0, 0, 0.0))
		# the hat: brim and a short crown, a red band
		var hat := _begin()
		var hat_c := Color(0.08, 0.08, 0.1)
		_lathe(hat, [[0.0, 0.0], [0.19, 0.0], [0.19, 0.018], [0.12, 0.022], [0.119, 0.06], [0.115, 0.17], [0.0, 0.175]], 20,
				func(i, _a): return Color(0.62, 0.1, 0.1) if i == 3 else hat_c, head + Vector3(0, 0.15, 0))
		# the carrot nose (pointing out of the face), with grooves
		var nose := _begin()
		var tip: Vector3 = face.call(0.0, 0.03, 0.42)
		var base: Vector3 = face.call(0.0, 0.03, 0.17)
		_tube(nose, [base, base.lerp(tip, 0.4), base.lerp(tip, 0.75), tip], [0.035, 0.026, 0.014, 0.002], Color(0.95, 0.45, 0.08), 8)
		# the scarf: a band round the neck and two ends hanging down the front, with fringes
		var scarf := _begin()
		var neck := Vector3(0, 0.6 + 0.29 * 0.82 + 0.25, 0)
		var red := Color(0.75, 0.12, 0.12)
		var stripe := Color(0.95, 0.9, 0.8)
		var n := 18
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var r0 := 0.2
			var cc := red if k % 3 != 0 else stripe
			for band in [[-0.05, 0.05]]:
				var q0 := neck + Vector3(cos(a0) * r0, band[0], sin(a0) * r0)
				var q1 := neck + Vector3(cos(a1) * r0, band[0], sin(a1) * r0)
				var q2 := neck + Vector3(cos(a1) * r0, band[1], sin(a1) * r0)
				var q3 := neck + Vector3(cos(a0) * r0, band[1], sin(a0) * r0)
				_quad(scarf, q0, q1, q2, q3, cc, Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)))
		for s in [0.07, -0.05]:   # the two hanging ends
			var top := neck + Vector3(s, -0.02, 0.21)
			var len := 0.32 if s > 0.0 else 0.24
			# (hanging forward over the middle snowball's bulge)
			_box(scarf, top + Vector3(0, -len * 0.5, 0.11), Vector3(0.09, len, 0.025), red,
					Basis(Vector3.RIGHT, 0.12) * Basis(Vector3.BACK, s * 1.2))
			for f in 4:
				var fp := top + Vector3(-0.03 + f * 0.02, -len - 0.03, 0.13)
				_box(scarf, fp, Vector3(0.008, 0.05, 0.008), stripe, Basis(Vector3.BACK, s * 1.2))
		# stick arms with twiggy hands
		var sticks := _begin()
		var wood := Color(0.32, 0.21, 0.12)
		for side in [-1.0, 1.0]:
			var sh := Vector3(side * 0.24, 0.72, 0.0)
			var el := Vector3(side * 0.48, 0.86, 0.04)
			var hand := Vector3(side * 0.66, 1.05, 0.02)
			_tube(sticks, [sh, el, hand], [0.02, 0.016, 0.011], wood, 6)
			for f in 3:
				var fdir := Vector3(side * (0.06 + 0.02 * f), 0.05 + 0.04 * (f - 1), 0.02 * (f - 1))
				_tube(sticks, [hand, hand + fdir], [0.008, 0.004], wood, 5)
			_tube(sticks, [el, el + Vector3(side * 0.05, -0.08, 0.02)], [0.009, 0.004], wood, 5)
		return [_end(snow, true), _end(coal, true), _end(hat, false), _end(nose, true), _end(scarf, false), _end(sticks, true)])
	_add(root, parts[0], _vmat("plaster", 0.85))
	_add(root, parts[1], _vmat("stone", 0.35))
	_add(root, parts[2], _vmat("cloth", 0.7))
	_add(root, parts[3], _vmat("plant", 0.6))
	_add(root, parts[4], _vmat("cloth", 0.95))
	_add(root, parts[5], _vmat("wood", 0.9))


# A coconut: a slightly egg-shaped brown nut with coarse fibres streaking it lengthwise, three dark "eyes" at
# one end and ridges down its sides. (collision: 0.12 x 0.22)
static func _coconut(root: Node3D) -> void:
	var parts := _cached("coconut", func() -> Array:
		var st := _begin()
		var prof := [[0.0, 0.0], [0.05, 0.006], [0.085, 0.03], [0.108, 0.07], [0.115, 0.11], [0.108, 0.15],
				[0.085, 0.185], [0.05, 0.208], [0.02, 0.216], [0.0, 0.218]]
		var col := func(i: int, a: float) -> Color:
			var fib := 0.5 + 0.5 * sin(a * 41.0 + sin(a * 7.0 + i) * 2.0)
			var c := Color(0.36, 0.22, 0.12).lerp(Color(0.52, 0.35, 0.19), fib * 0.7)
			if _h(float(i) * 5.0 + floor(a * 30.0)) > 0.8:
				c = c.darkened(0.25)
			if i >= prof.size() - 3:   # the eyes end: three dark dimples
				for k in 3:
					var ea := TAU * k / 3.0
					if absf(wrapf(a - ea, -PI, PI)) < 0.32 and i == prof.size() - 3:
						c = Color(0.12, 0.07, 0.04)
			return c
		var ridge := func(i: int, a: float) -> float:
			return 1.0 + 0.04 * absf(sin(a * 1.5)) + 0.012 * sin(a * 41.0 + i)
		_lathe(st, prof, 30, col, Vector3.ZERO, ridge)
		return [_end(st, true)])
	_add(root, parts[0], _vmat("wood", 0.92))


# A beehive: an old straw skep (a dome of coiled straw rope, stitched), on a little wooden stand, with an
# entrance hole at the bottom and a landing board. E sets the bees swarming round it (prop_animator "swarm").
# (collision: 0.33 x 0.95)
static func _beehive(root: Node3D) -> void:
	var parts := _cached("beehive", func() -> Array:
		var straw := _begin()
		var coils := 13
		var base_y := 0.36
		var h := 0.56
		for k in coils:
			var t0 := float(k) / coils
			var t1 := float(k + 1) / coils
			var r0: float = 0.32 * sqrt(maxf(0.0, 1.0 - pow(t0, 1.6))) + 0.01
			var r1: float = 0.32 * sqrt(maxf(0.0, 1.0 - pow(t1, 1.6))) + 0.01
			var y0 := base_y + h * t0
			var y1 := base_y + h * t1
			var light := Color(0.86, 0.7, 0.38) if k % 2 == 0 else Color(0.78, 0.62, 0.3)
			# each coil is a rounded roll: three rings bulging out
			var prof := [[r0, y0], [lerpf(r0, r1, 0.5) * 1.05 + 0.012, (y0 + y1) * 0.5], [r1, y1]]
			var coil := k
			var straw_col := func(_i: int, a: float) -> Color:
				var c := light.lerp(Color(0.6, 0.45, 0.2), 0.35 * (0.5 + 0.5 * sin(a * 60.0 + coil)))
				if absf(sin(a * 6.0 + coil * 0.9)) > 0.985:
					c = Color(0.45, 0.33, 0.16)   # the stitching binding the coils
				return c
			var hole := func(_i: int, a: float) -> float:   # the entrance hole, at the front of the bottom coil
				return 1.0 if absf(wrapf(a - PI * 0.5, -PI, PI)) > 0.28 or coil > 0 else 0.55
			_lathe(straw, prof, 28, straw_col, Vector3.ZERO, hole)
		# the hole's dark inside
		var dark := _begin()
		_box(dark, Vector3(0, base_y + 0.035, 0.2), Vector3(0.15, 0.06, 0.04), Color(0.05, 0.035, 0.02))
		# the stand: a round board on four legs, a landing board out the front
		var stand := _begin()
		var wood := Color(0.45, 0.3, 0.17)
		_lathe(stand, [[0.0, base_y - 0.05], [0.36, base_y - 0.05], [0.36, base_y], [0.0, base_y]], 20, func(_i, _a): return wood)
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4.0
			_box(stand, Vector3(cos(a) * 0.25, (base_y - 0.05) * 0.5, sin(a) * 0.25), Vector3(0.05, base_y - 0.05, 0.05), wood.darkened(0.1))
		_box(stand, Vector3(0, base_y - 0.02, 0.38), Vector3(0.2, 0.02, 0.1), wood.lightened(0.06))
		return [_end(straw, true), _end(dark, false), _end(stand, false)])
	_add(root, parts[0], _vmat("cloth", 0.95))
	_add(root, parts[1], _vmat("wood", 1.0))
	_add(root, parts[2], _vmat("wood", 0.85))
	root.set_meta("hive_centre", Vector3(0, 0.62, 0))


static func _cached(key: String, build: Callable) -> Array:
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


# A coopered barrel: bulging staves of slightly different woods, four iron hoops, a planked head set into the
# chime, and a bung in its side. (collision: cylinder r 0.45, h 1.0)
static func _barrel(root: Node3D) -> void:
	var parts := _cached("barrel", func() -> Array:
		var staves := 20
		var bulge := func(y: float) -> float: return 0.375 + 0.06 * sin(PI * clampf(y, 0.0, 1.0))
		var wood := _begin()
		for s in staves:
			var a0 := TAU * s / staves
			var a1 := TAU * (s + 1) / staves
			var am := (a0 + a1) * 0.5
			var tone := Color(0.56, 0.35, 0.18).lerp(Color(0.68, 0.45, 0.24), _h(float(s)))
			tone = tone.darkened(0.12 * _h(float(s) + 9.0))
			var rings := 12
			for k in rings:
				var y0 := float(k) / rings
				var y1 := float(k + 1) / rings
				var r0: float = bulge.call(y0)
				var r1: float = bulge.call(y1)
				# each stave a little narrower than its share: dark seams between them
				var g := 0.006 / r0
				var p00 := Vector3(cos(a0 + g) * r0, y0, sin(a0 + g) * r0)
				var p01 := Vector3(cos(a1 - g) * r0, y0, sin(a1 - g) * r0)
				var p10 := Vector3(cos(a0 + g) * r1, y1, sin(a0 + g) * r1)
				var p11 := Vector3(cos(a1 - g) * r1, y1, sin(a1 - g) * r1)
				_quad(wood, p00, p10, p11, p01, tone, Vector3(cos(am), 0.0, sin(am)))
		# the seams: a dark core just inside the staves
		_lathe(wood, [[0.0, 0.03], [0.37, 0.03], [0.37 + 0.055, 0.5], [0.37, 0.97], [0.0, 0.97]], 40,
				_flat(Color(0.12, 0.07, 0.04)), Vector3.ZERO, func(i: int, _a: float) -> float: return 0.985)
		# the chime (the staves' ends standing above the head) and the head, planked
		for top in [true, false]:
			var y := 0.955 if top else 0.045
			var planks := 5
			for p in planks:
				var x0 := -0.36 + 0.72 * p / planks
				var x1 := -0.36 + 0.72 * (p + 1) / planks - 0.004
				var tone := Color(0.6, 0.4, 0.22).lerp(Color(0.5, 0.31, 0.16), _h(float(p) + 3.0))
				for k in 4:
					var xa := lerpf(x0, x1, k / 4.0)
					var xb := lerpf(x0, x1, (k + 1) / 4.0)
					var za := sqrt(maxf(0.0, 0.37 * 0.37 - xa * xa))
					var zb := sqrt(maxf(0.0, 0.37 * 0.37 - xb * xb))
					_quad(wood, Vector3(xa, y, -za), Vector3(xb, y, -zb), Vector3(xb, y, zb), Vector3(xa, y, za), tone, Vector3.UP if top else Vector3.DOWN)
		var iron := _begin()
		for y in [0.07, 0.25, 0.75, 0.93]:
			var r: float = bulge.call(y) + 0.004
			_lathe(iron, [[r - 0.002, y - 0.028], [r + 0.008, y - 0.024], [r + 0.009, y + 0.024], [r - 0.002, y + 0.028]], 40, _flat(Color(0.2, 0.19, 0.18)))
		# rivets on each hoop
		for y in [0.25, 0.75]:
			for k in 6:
				var a := TAU * k / 6.0 + 0.3
				var r: float = bulge.call(y) + 0.014
				_box(iron, Vector3(cos(a) * r, y, sin(a) * r), Vector3(0.012, 0.012, 0.012), Color(0.28, 0.27, 0.25), Basis(Vector3.UP, -a))
		# the bung
		var bung := _begin()
		_lathe(bung, [[0.0, 0.0], [0.03, 0.0], [0.028, 0.025], [0.0, 0.027]], 10, _flat(Color(0.38, 0.24, 0.12)))
		var bm := _end(bung, true)
		return [_end(wood, false), _end(iron, false), bm])
	_add(root, parts[0], _vmat("wood"))
	_add(root, parts[1], _vmat("metal", 0.55, 0.6))
	var bung := _add(root, parts[2], _vmat("wood"))
	bung.position = Vector3(0.0, 0.5, 0.428)
	bung.rotation.x = PI * 0.5


# A slatted shipping crate: a frame of boards round every face, slats with gaps between them (the dark inside
# shows through), a diagonal brace, stencilled "FRAGILE" and "THIS WAY UP" arrows, and a shipping label.
# (collision: box 0.9)
static func _crate(root: Node3D) -> void:
	var parts := _cached("crate", func() -> Array:
		var st := _begin()
		var hs := 0.45
		_box(st, Vector3(0, hs, 0), Vector3(0.84, 0.84, 0.84), Color(0.16, 0.1, 0.06), Basis(), true)   # the dark inside
		var pine := func(k: float) -> Color: return Color(0.8, 0.62, 0.38).lerp(Color(0.66, 0.48, 0.27), _h(k))
		# four sides: slats, then the brace, then the frame on top
		for f in 4:
			var yaw := PI * 0.5 * f
			var bas := Basis(Vector3.UP, yaw)
			var n := bas * Vector3.BACK
			var across := bas * Vector3.RIGHT
			for s in 4:
				var y := 0.1 + 0.07 + s * 0.2
				var c := n * (hs - 0.022) + Vector3.UP * y
				_box(st, c, Vector3(0.8, 0.165, 0.024), pine.call(f * 10.0 + s), bas)
			var dlen := sqrt(0.66 * 0.66 + 0.66 * 0.66)
			_box(st, n * (hs - 0.006) + Vector3.UP * hs, Vector3(dlen, 0.09, 0.022), pine.call(f + 40.0).darkened(0.06),
					bas * Basis(Vector3.BACK, PI * 0.25 * (1.0 if f % 2 == 0 else -1.0)))
			var fz := hs + 0.008
			for side in [-1.0, 1.0]:   # uprights (at the corners) and rails (top and bottom)
				_box(st, n * (fz - 0.015) + across * side * (hs - 0.045) + Vector3.UP * hs, Vector3(0.09, 0.9, 0.03 + 0.002 * f), pine.call(f + 60.0 + side), bas)
				_box(st, n * (fz - 0.013) + Vector3.UP * (hs + side * (hs - 0.045)), Vector3(0.72, 0.09, 0.026), pine.call(f + 70.0 + side), bas)
		# the lid: boards across, with two battens
		for k in 5:
			var x := -0.36 + 0.18 * k
			_box(st, Vector3(x, 0.9 - 0.012, 0), Vector3(0.172, 0.024, 0.86), pine.call(k + 90.0))
		for z in [-0.3, 0.3]:
			_box(st, Vector3(0, 0.9 + 0.012, z), Vector3(0.84, 0.024, 0.09), pine.call(z * 7.0 + 95.0).darkened(0.05))
		# nail heads on the frame
		var nails := _begin()
		for f in 4:
			var bas := Basis(Vector3.UP, PI * 0.5 * f)
			for side in [-1.0, 1.0]:
				for y in [0.17, 0.45, 0.73]:
					_box(nails, bas * Vector3(side * (hs - 0.045), y, hs + 0.024), Vector3(0.014, 0.014, 0.006), Color(0.25, 0.24, 0.24), bas)
		return [_end(st, false), _end(nails, false)])
	_add(root, parts[0], _vmat("wood"))
	_add(root, parts[1], _vmat("metal", 0.6, 0.5))
	# stencils and a shipping label (the same on every crate)
	var red := Color(0.62, 0.09, 0.07)
	var black := Color(0.08, 0.07, 0.06)
	for f in [0, 2]:
		var bas := Basis(Vector3.UP, PI * 0.5 * f)
		_label(root, "FRAGILE", red, bas, bas * Vector3(0.0, 0.4, 0.462), 52, 0.0019)
		_arrows(root, bas, bas * Vector3(0.0, 0.62, 0.462), black)
	for f in [1, 3]:
		var bas := Basis(Vector3.UP, PI * 0.5 * f)
		_label(root, "THIS WAY UP", black, bas, bas * Vector3(0.0, 0.26, 0.462), 40, 0.0016)
		_arrows(root, bas, bas * Vector3(0.0, 0.55, 0.462), black)
	var lb := Basis(Vector3.UP, PI * 0.5)
	var sticker := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.2, 0.13)
	sticker.mesh = qm
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.9, 0.8)
	paper.roughness = 0.9
	sticker.material_override = paper
	sticker.basis = lb
	sticker.position = lb * Vector3(-0.2, 0.75, 0.463)
	root.add_child(sticker)
	_label(root, "HEAVENLY\nFREIGHT CO.", black, lb, lb * Vector3(-0.2, 0.775, 0.465), 22, 0.0011)
	var bars := _begin()
	for k in 14:
		var w := 0.003 + 0.004 * _h(float(k) + 5.0)
		_box(bars, lb * Vector3(-0.27 + k * 0.0105, 0.72, 0.4645), Vector3(w, 0.035, 0.001), black, lb)
	_add(root, _end(bars, false), _vmat(""))


static func _label(root: Node3D, text: String, col: Color, bas: Basis, at: Vector3, size: int, px: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.basis = bas
	l.position = at
	root.add_child(l)


# Two stencilled "this way up" arrows.
static func _arrows(root: Node3D, bas: Basis, at: Vector3, col: Color) -> void:
	var st := _begin()
	var n := bas * Vector3.BACK
	var x := bas * Vector3.RIGHT
	for side in [-1.0, 1.0]:
		var c: Vector3 = at + x * side * 0.07
		_quad(st, c + x * -0.012, c + x * 0.012, c + x * 0.012 + Vector3.UP * 0.07, c + x * -0.012 + Vector3.UP * 0.07, col, n)
		_tri(st, c + x * -0.035 + Vector3.UP * 0.07, c + x * 0.035 + Vector3.UP * 0.07, c + Vector3.UP * 0.11, col, n)
	_add(root, _end(st, false), _vmat("", 0.9))


# A floor lamp: a weighted base, a turned brass stem with collars, a pleated fabric shade with braid at both
# edges, a finial, and a pull chain. Its shade glows when it's on (prop_animator.gd's classic lamp).
# (collision: cylinder r 0.3, h 1.75)
static func _lamp(root: Node3D) -> void:
	var parts := _cached("lamp", func() -> Array:
		var brass := _begin()
		var b := Color(0.72, 0.56, 0.28)
		_lathe(brass, [[0.0, 0.0], [0.23, 0.0], [0.245, 0.012], [0.24, 0.035], [0.2, 0.05], [0.12, 0.065], [0.06, 0.09],
				[0.03, 0.12], [0.02, 0.15], [0.017, 0.5], [0.026, 0.51], [0.026, 0.54], [0.017, 0.55], [0.016, 1.0],
				[0.025, 1.01], [0.025, 1.04], [0.016, 1.05], [0.015, 1.33], [0.03, 1.35], [0.03, 1.39], [0.0, 1.4]], 20, _flat(b))
		# the harp holding the shade, and the finial on top
		for side in [-1.0, 1.0]:
			_tube(brass, [Vector3(side * 0.02, 1.38, 0), Vector3(side * 0.09, 1.5, 0), Vector3(side * 0.03, 1.69, 0)], [0.006, 0.006, 0.006], b, 5)
		_lathe(brass, [[0.0, 1.69], [0.02, 1.695], [0.025, 1.715], [0.012, 1.735], [0.0, 1.745]], 10, _flat(b), Vector3.ZERO)
		# pull chain
		for k in 8:
			_box(brass, Vector3(0.07, 1.42 - k * 0.022, 0.0), Vector3(0.008, 0.012, 0.008), b.darkened(0.15))
		var bulb := _begin()
		_lathe(bulb, [[0.0, 1.4], [0.018, 1.405], [0.04, 1.44], [0.045, 1.47], [0.035, 1.5], [0.0, 1.515]], 14, _flat(Color(1.0, 0.97, 0.88)))
		var shade := _begin()
		var cloth := Color(0.96, 0.88, 0.66)
		var pleat := func(_i: int, a: float) -> float: return 1.0 + 0.025 * cos(a * 36.0)
		_lathe(shade, [[0.285, 1.37], [0.155, 1.69]], 72, func(_i: int, a: float) -> Color: return cloth.darkened(0.08 * (0.5 + 0.5 * cos(a * 36.0))), Vector3.ZERO, pleat)
		var trim := _begin()
		_ring(trim, Vector3(0, 1.37, 0), 0.29, 0.01, Color(0.72, 0.5, 0.2), 36, 5)
		_ring(trim, Vector3(0, 1.69, 0), 0.158, 0.008, Color(0.72, 0.5, 0.2), 36, 5)
		return [_end(brass, true), _end(bulb, true), _end(shade, true), _end(trim, true)])
	_add(root, parts[0], _vmat("metal", 0.3, 0.85))
	_add(root, parts[1], _vmat("glossy", 0.2))
	# (each lamp its own shade material: switching one on mustn't light them all)
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.vertex_color_is_srgb = true
	Surfaces.apply(sm, "cloth")
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.82, 0.5)
	sm.emission_energy_multiplier = 0.7
	_add(root, parts[2], sm)
	_add(root, parts[3], _vmat("cloth", 0.8))


# A cast-iron cooking pot: rounded belly, rolled rim, two loop handles, a lid with a knob, sitting a little
# askew so a sliver of the dark inside shows. (collision: cylinder r 0.35, h 0.6)
static func _pot(root: Node3D) -> void:
	var parts := _cached("pot", func() -> Array:
		var st := _begin()
		var iron := Color(0.2, 0.2, 0.21)
		var col := func(i: int, a: float) -> Color:
			return iron.lerp(Color(0.3, 0.22, 0.16), 0.25 * _h(float(i) * 3.1 + floor(a * 4.0)))   # a little rust
		_lathe(st, [[0.0, 0.0], [0.17, 0.0], [0.22, 0.015], [0.26, 0.06], [0.285, 0.14], [0.29, 0.25], [0.284, 0.36],
				[0.276, 0.42], [0.285, 0.435], [0.29, 0.45], [0.283, 0.462], [0.268, 0.46], [0.262, 0.42],
				[0.27, 0.3], [0.25, 0.12], [0.18, 0.04], [0.0, 0.035]], 40, col)
		# feet
		for k in 3:
			var a := TAU * k / 3.0
			_box(st, Vector3(cos(a) * 0.17, 0.0, sin(a) * 0.17), Vector3(0.06, 0.03, 0.06), iron.darkened(0.1), Basis(Vector3.UP, -a))
		# handles: loops on two sides
		for side in [-1.0, 1.0]:
			var pts := []
			var rad := []
			for k in 9:
				var t := PI * k / 8.0
				pts.append(Vector3(side * (0.28 + 0.06 * sin(t)), 0.36 + 0.06 * cos(t), 0.0))
				rad.append(0.013)
			_tube(st, pts, rad, iron, 6)
		# the lid, domed, set slightly askew
		var lid := _begin()
		_lathe(lid, [[0.0, 0.0], [0.27, 0.0], [0.278, 0.012], [0.26, 0.03], [0.2, 0.06], [0.1, 0.08], [0.035, 0.085],
				[0.035, 0.11], [0.05, 0.12], [0.045, 0.135], [0.0, 0.14]], 40, col)
		return [_end(st, true), _end(lid, true)])
	_add(root, parts[0], _vmat("metal", 0.6, 0.55))
	var lid := _add(root, parts[1], _vmat("metal", 0.55, 0.55))
	lid.position = Vector3(0.025, 0.452, 0.0)
	lid.rotation.z = -0.06


# A garden bench: three seat slats with gaps, a rounded front, trestle legs splayed out with a stretcher between.
# (collision: box 1.6 x 0.5 x 0.5)
static func _bench(root: Node3D) -> void:
	var parts := _cached("bench", func() -> Array:
		var st := _begin()
		var tone := func(k: float) -> Color: return Color(0.55, 0.34, 0.19).lerp(Color(0.46, 0.28, 0.15), _h(k))
		for s in 3:
			var z := -0.16 + 0.16 * s
			_box(st, Vector3(0, 0.455, z), Vector3(1.58, 0.045, 0.145), tone.call(float(s)))
			_box(st, Vector3(0, 0.432, z), Vector3(1.56, 0.003, 0.13), tone.call(float(s)).darkened(0.3))
		for side in [-1.0, 1.0]:
			var x: float = side * 0.62
			for lz in [-1.0, 1.0]:   # two legs each end, splayed
				var top := Vector3(x, 0.42, lz * 0.13)
				var foot := Vector3(x, 0.0, lz * 0.21)
				var d := (top - foot)
				var bas := Basis(Vector3.RIGHT, -atan2(d.z, d.y))
				_box(st, (top + foot) * 0.5, Vector3(0.06, d.length(), 0.07), tone.call(x * 3.0 + lz), bas)
			_box(st, Vector3(x, 0.415, 0), Vector3(0.07, 0.05, 0.46), tone.call(x + 20.0).darkened(0.05))   # cleat under the seat
			_box(st, Vector3(x, 0.12, 0), Vector3(0.05, 0.05, 0.38), tone.call(x + 30.0))                    # foot rail
		_box(st, Vector3(0, 0.15, 0), Vector3(1.2, 0.06, 0.05), tone.call(50.0))   # stretcher
		var bolts := _begin()
		for side in [-1.0, 1.0]:
			for z in [-0.16, 0.0, 0.16]:
				_box(bolts, Vector3(side * 0.62, 0.478, z), Vector3(0.016, 0.004, 0.016), Color(0.2, 0.2, 0.2))
		return [_end(st, false), _end(bolts, false)])
	_add(root, parts[0], _vmat("wood"))
	_add(root, parts[1], _vmat("metal", 0.5, 0.6))


# A stack of four old books: hard covers a little bigger than the pages, rounded spines with gilt bands and
# a gilt title panel, page edges in fine lines, each book turned a little on the one below.
# (collision: box 0.45 x 0.35 x 0.3)
static func _books(root: Node3D) -> void:
	var parts := _cached("books", func() -> Array:
		var covers := _begin()
		var pages := _begin()
		var gilt := _begin()
		var books := [
			[0.42, 0.075, 0.29, Color(0.48, 0.1, 0.1), 0.0, Vector2(0.0, 0.0)],
			[0.39, 0.06, 0.27, Color(0.12, 0.2, 0.4), 0.1, Vector2(0.015, -0.005)],
			[0.4, 0.085, 0.28, Color(0.16, 0.32, 0.18), -0.07, Vector2(-0.01, 0.01)],
			[0.33, 0.05, 0.24, Color(0.42, 0.27, 0.14), 0.18, Vector2(0.02, 0.0)],
		]
		var y := 0.0
		for bk in books:
			var w: float = bk[0]
			var th: float = bk[1]
			var dp: float = bk[2]
			var cc: Color = bk[3]
			var bas := Basis(Vector3.UP, bk[4])
			var off: Vector2 = bk[5]
			var c := Vector3(off.x, y + th * 0.5, off.y)
			var board := 0.007
			for s in [-1.0, 1.0]:   # the boards
				_box(covers, c + bas * Vector3(0.0, s * (th * 0.5 - board * 0.5), 0.003), Vector3(w, board, dp), cc, bas)
			_box(pages, c + bas * Vector3(0.0, 0.0, 0.006), Vector3(w - 0.012, th - board * 2.0 + 0.001, dp - 0.02), Color(0.93, 0.89, 0.78), bas)
			# the spine: a half-round along the back edge
			var r := th * 0.5
			var spine := []
			for k in 9:
				var t := -PI * 0.5 + PI * k / 8.0
				spine.append([cos(t), sin(t)])
			for k in 8:
				var p0: Array = spine[k]
				var p1: Array = spine[k + 1]
				var a0 := c + bas * Vector3(-w * 0.5, p0[1] * r, -dp * 0.5 + 0.003 - p0[0] * r * 0.55)
				var a1 := c + bas * Vector3(-w * 0.5, p1[1] * r, -dp * 0.5 + 0.003 - p1[0] * r * 0.55)
				var b0 := c + bas * Vector3(w * 0.5, p0[1] * r, -dp * 0.5 + 0.003 - p0[0] * r * 0.55)
				var b1 := c + bas * Vector3(w * 0.5, p1[1] * r, -dp * 0.5 + 0.003 - p1[0] * r * 0.55)
				var out := bas * Vector3(0.0, (p0[1] + p1[1]) * 0.5, -(p0[0] + p1[0]) * 0.5)
				_quad(covers, a0, b0, b1, a1, cc.darkened(0.08), out)
				# gilt bands round the spine
				for bx in [-0.36, -0.3, 0.3, 0.36]:
					var gx: float = bx * w
					var g0 := c + bas * Vector3(gx - 0.004, p0[1] * r * 1.03, -dp * 0.5 + 0.003 - p0[0] * r * 0.58)
					var g1 := c + bas * Vector3(gx - 0.004, p1[1] * r * 1.03, -dp * 0.5 + 0.003 - p1[0] * r * 0.58)
					var g2 := c + bas * Vector3(gx + 0.004, p1[1] * r * 1.03, -dp * 0.5 + 0.003 - p1[0] * r * 0.58)
					var g3 := c + bas * Vector3(gx + 0.004, p0[1] * r * 1.03, -dp * 0.5 + 0.003 - p0[0] * r * 0.58)
					_quad(gilt, g0, g1, g2, g3, Color(0.85, 0.66, 0.25), out)
			# the spine's ends, and a gilt title panel
			for s in [-1.0, 1.0]:
				for k in 8:
					var p0: Array = spine[k]
					var p1: Array = spine[k + 1]
					_tri(covers, c + bas * Vector3(s * w * 0.5, 0.0, -dp * 0.5 + 0.003),
							c + bas * Vector3(s * w * 0.5, p0[1] * r, -dp * 0.5 + 0.003 - p0[0] * r * 0.55),
							c + bas * Vector3(s * w * 0.5, p1[1] * r, -dp * 0.5 + 0.003 - p1[0] * r * 0.55), cc.darkened(0.15), bas * Vector3(s, 0, 0))
			_box(gilt, c + bas * Vector3(0.0, 0.0, -dp * 0.5 + 0.003 - r * 0.57), Vector3(w * 0.34, r * 0.8, 0.003), Color(0.8, 0.6, 0.22), bas)
			y += th
		return [_end(covers, false), _end(pages, false), _end(gilt, false)])
	_add(root, parts[0], _vmat("leather"))
	_add(root, parts[1], _page_mat())
	_add(root, parts[2], _vmat("metal", 0.35, 0.8))


static func _page_mat() -> StandardMaterial3D:
	if _cache.has("pages"):
		return _cache["pages"]
	var img := Image.create(4, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var v := 0.93 - 0.18 * float(y % 3 == 0) - 0.06 * _h(float(y))
		for x in 4:
			img.set_pixel(x, y, Color(v, v * 0.96, v * 0.86))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(4.0, 4.0, 4.0)
	m.roughness = 0.95
	_cache["pages"] = m
	return m


# An apple: a proper apple shape (dimples top and bottom, a little lopsided), red streaked over a yellow-green
# blush, a speckle of lenticels, a curved stem and a leaf. (collision: box 0.26 x 0.28 x 0.26)
static func _apple(root: Node3D) -> void:
	var parts := _cached("apple", func() -> Array:
		var st := _begin()
		var prof := [[0.0, 0.035], [0.025, 0.02], [0.06, 0.008], [0.095, 0.025], [0.118, 0.06], [0.128, 0.1], [0.127, 0.14],
				[0.118, 0.18], [0.1, 0.215], [0.07, 0.24], [0.04, 0.24], [0.018, 0.225], [0.0, 0.215]]
		var red := Color(0.72, 0.06, 0.07)
		var deep := Color(0.45, 0.03, 0.05)
		var blush := Color(0.75, 0.62, 0.15)
		var col := func(i: int, a: float) -> Color:
			var streak := 0.5 + 0.5 * sin(a * 23.0 + sin(a * 7.0) * 2.0)
			var c := red.lerp(deep, streak * 0.45)
			var side := 0.5 + 0.5 * cos(a - 2.4)
			c = c.lerp(blush, pow(side, 3.0) * 0.55)
			if i <= 1 or i >= prof.size() - 3:
				c = c.lerp(Color(0.6, 0.55, 0.2), 0.5)   # the dimples paler
			if _h(float(i) * 13.0 + floor(a * 9.0)) > 0.93:
				c = c.lightened(0.35)   # lenticels
			return c
		var lump := func(_i: int, a: float) -> float: return 1.0 + 0.025 * sin(a * 5.0 + 1.0)
		_lathe(st, prof, 36, col, Vector3.ZERO, lump)
		var stem := _begin()
		_tube(stem, [Vector3(0, 0.215, 0), Vector3(0.004, 0.245, 0), Vector3(0.014, 0.27, 0.004), Vector3(0.026, 0.285, 0.006)],
				[0.007, 0.006, 0.005, 0.0045], Color(0.33, 0.21, 0.1), 6)
		var leaf := _begin()
		var lc := Color(0.24, 0.5, 0.14)
		var base := Vector3(0.012, 0.262, 0.003)
		var tip := Vector3(0.085, 0.29, -0.03)
		var along := tip - base
		var side := along.cross(Vector3.UP).normalized() * 0.022
		var n := 6
		for k in n:
			var t0 := float(k) / n
			var t1 := float(k + 1) / n
			var w0 := sin(PI * t0) * (1.0 - t0 * 0.3)
			var w1 := sin(PI * t1) * (1.0 - t1 * 0.3)
			var m0 := base + along * t0 + Vector3.UP * 0.006 * sin(PI * t0)
			var m1 := base + along * t1 + Vector3.UP * 0.006 * sin(PI * t1)
			for s in [-1.0, 1.0]:
				_quad(leaf, m0, m1, m1 + side * w1 * s - Vector3.UP * 0.004 * w1, m0 + side * w0 * s - Vector3.UP * 0.004 * w0,
						lc.lightened(0.08 if s > 0.0 else 0.0), Vector3.UP)
		return [_end(st, true), _end(stem, true), _end(leaf, false)])
	_add(root, parts[0], _vmat("glossy", 0.28))
	_add(root, parts[1], _vmat("wood", 0.8))
	_add(root, parts[2], _vmat("plant", 0.6, -1.0, true))


# The big floppy pickle (Ted's wife: "still needs work"): a fat, slightly bent dill pickle lying on its side,
# rounded at both ends, with real warty bumps raised out of its skin (not stuck on), dark green with paler
# bumps and speckles, a yellowish cut end, and a wet brine shine. (collision: box 0.5 x 0.42 x 1.5)
static func _pickle(root: Node3D) -> void:
	var parts := _cached("pickle", func() -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var bumps := []
		for k in 70:
			bumps.append([rng.randf_range(0.06, 0.94), rng.randf() * TAU, rng.randf_range(0.6, 1.0)])
		var rings := 56
		var around := 36
		var rmax := 0.19
		var center := func(u: float) -> Vector3:
			return Vector3(0.07 * sin(PI * u) - 0.035 + 0.02 * sin(u * 9.0), rmax + 0.012 * sin(PI * u), -0.72 + 1.44 * u)
		var radius := func(u: float, a: float) -> float:
			var end := pow(sin(PI * clampf(u, 0.0, 1.0)), 0.42)
			var r := rmax * end * (1.0 + 0.035 * sin(u * 23.0 + a * 2.0) + 0.02 * sin(a * 5.0 + u * 7.0))
			for b in bumps:
				var du: float = (u - b[0]) * 1.44
				var da := wrapf(a - b[1], -PI, PI) * rmax
				var d2 := du * du + da * da
				r += 0.016 * float(b[2]) * exp(-d2 / 0.0006) * end
			return r
		var st := _begin()
		var grid := []
		for i in rings + 1:
			var u := float(i) / rings
			var row := []
			for j in around + 1:
				var a := TAU * j / around
				var r: float = radius.call(u, a)
				var c: Vector3 = center.call(u)
				var p := c + Vector3(cos(a), sin(a), 0.0) * r
				# colour: dark green, paler on the bumps, faint stripes, speckles, yellowish towards the ends
				var bump := 0.0
				for b in bumps:
					var du: float = (u - b[0]) * 1.44
					var da := wrapf(a - b[1], -PI, PI) * rmax
					bump = maxf(bump, exp(-(du * du + da * da) / 0.0005))
				var col := Color(0.16, 0.29, 0.07).lerp(Color(0.3, 0.45, 0.12), 0.35 + 0.3 * pow(0.5 + 0.5 * cos(a * 8.0 + u * 3.0), 3.0))
				col = col.lerp(Color(0.5, 0.6, 0.22), bump * 0.6)
				if _h(float(i * 41 + j)) > 0.92:
					col = col.lightened(0.18)
				col = col.lerp(Color(0.56, 0.55, 0.2), 0.45 * pow(absf(u - 0.5) * 2.0, 6.0))
				row.append([p, col])
			grid.append(row)
		for i in rings:
			for j in around:
				var q := [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
				var mid: Vector3 = center.call((i + 0.5) / rings)
				var out: Vector3 = (q[0][0] + q[2][0]) * 0.5 - mid
				for t in [[0, 1, 2], [0, 2, 3]]:
					var a: Array = q[t[0]]
					var b: Array = q[t[1]]
					var c: Array = q[t[2]]
					var pa: Vector3 = a[0]
					var pb: Vector3 = b[0]
					var pc: Vector3 = c[0]
					var cb: Color = b[1]
					var cc: Color = c[1]
					if (pb - pa).cross(pc - pa).dot(out) > 0.0:
						var tp := pb
						pb = pc
						pc = tp
						var tc := cb
						cb = cc
						cc = tc
					st.set_color(a[1])
					st.add_vertex(pa)
					st.set_color(cb)
					st.add_vertex(pb)
					st.set_color(cc)
					st.add_vertex(pc)
		return [_end(st, true)])
	_add(root, parts[0], _vmat("glossy", 0.22))


# ---------------------------------------------------------------- new street and garden props

# A galvanised steel garbage can: ribbed sides, a rolled rim, a domed lid with a handle, side handles.
# (collision: cylinder r 0.3, h 0.85)
static func _trash_can(root: Node3D) -> void:
	var parts := _cached("trash_can", func() -> Array:
		var st := _begin()
		var zinc := Color(0.62, 0.64, 0.64)
		var col := func(i: int, a: float) -> Color:
			return zinc.lerp(Color(0.5, 0.52, 0.53), _h(floor(a * 6.0) + float(i) * 0.3) * 0.35)
		var prof := [[0.0, 0.0], [0.24, 0.0], [0.25, 0.02], [0.245, 0.04]]
		for k in 7:   # the ribs
			var y := 0.08 + k * 0.1
			prof.append([0.25, y - 0.03])
			prof.append([0.262, y - 0.01])
			prof.append([0.262, y + 0.01])
			prof.append([0.25, y + 0.03])
		prof.append_array([[0.26, 0.76], [0.27, 0.775], [0.265, 0.79], [0.25, 0.785], [0.0, 0.785]])
		_lathe(st, prof, 36, col)
		for side in [-1.0, 1.0]:   # side handles
			var pts := []
			var rad := []
			for k in 7:
				var t := PI * k / 6.0
				pts.append(Vector3(side * (0.262 + 0.035 * sin(t)), 0.6, -0.07 + 0.14 * k / 6.0))
				rad.append(0.009)
			_tube(st, pts, rad, zinc.darkened(0.1), 6)
		_lathe(st, [[0.0, 0.79], [0.29, 0.79], [0.295, 0.8], [0.28, 0.815], [0.2, 0.835], [0.1, 0.845], [0.0, 0.848]], 36, col)
		_box(st, Vector3(0, 0.855, 0), Vector3(0.18, 0.016, 0.03), zinc.darkened(0.1))
		for side in [-1.0, 1.0]:
			_box(st, Vector3(side * 0.08, 0.848, 0), Vector3(0.02, 0.012, 0.03), zinc.darkened(0.15))
		return [_end(st, true)])
	_add(root, parts[0], _vmat("metal", 0.45, 0.7))


# A wheelie bin: a moulded green body tapering to the bottom, a hinged lid with a lip, axle and wheels at the
# back, a handle bar. (collision: box 0.6 x 1.05 x 0.72)
static func _wheelie_bin(root: Node3D) -> void:
	var parts := _cached("wheelie_bin", func() -> Array:
		var st := _begin()
		var green := Color(0.15, 0.38, 0.2)
		var b0 := [Vector3(-0.25, 0.06, -0.26), Vector3(0.25, 0.06, -0.26), Vector3(0.25, 0.06, 0.28), Vector3(-0.25, 0.06, 0.28)]
		var b1 := [Vector3(-0.29, 0.98, -0.32), Vector3(0.29, 0.98, -0.32), Vector3(0.29, 0.98, 0.33), Vector3(-0.29, 0.98, 0.33)]
		for k in 4:
			var a0: Vector3 = b0[k]
			var a1: Vector3 = b0[(k + 1) % 4]
			var c0: Vector3 = b1[k]
			var c1: Vector3 = b1[(k + 1) % 4]
			var mid := (a0 + a1 + c0 + c1) * 0.25
			_quad(st, a0, a1, c1, c0, green.darkened(0.06 * (k % 2)), Vector3(mid.x, 0.0, mid.z))
		_quad(st, b0[0], b0[1], b0[2], b0[3], green.darkened(0.2), Vector3.DOWN)
		# moulded ribs down the front
		for x in [-0.15, 0.0, 0.15]:
			_box(st, Vector3(x, 0.55, 0.31), Vector3(0.03, 0.75, 0.03), green.lightened(0.04), Basis(Vector3.RIGHT, -0.065))
		# the lid
		_box(st, Vector3(0, 1.0, 0.0), Vector3(0.6, 0.04, 0.7), green.lightened(0.05))
		_box(st, Vector3(0, 0.975, 0.345), Vector3(0.6, 0.06, 0.02), green)
		# handle bar and hinge at the back
		_box(st, Vector3(0, 0.95, -0.34), Vector3(0.5, 0.04, 0.05), Color(0.12, 0.12, 0.12))
		# axle and wheels
		var dark := _begin()
		_box(dark, Vector3(0, 0.1, -0.27), Vector3(0.56, 0.03, 0.03), Color(0.2, 0.2, 0.2))
		for side in [-1.0, 1.0]:
			var wheel := []
			for k in 13:
				var a := TAU * k / 12.0
				wheel.append(Vector3(side * 0.29, 0.1 + sin(a) * 0.1, -0.27 + cos(a) * 0.1))
			for k in 12:
				_tri(dark, Vector3(side * 0.31, 0.1, -0.27), wheel[k] + Vector3(side * 0.02, 0, 0), wheel[k + 1] + Vector3(side * 0.02, 0, 0), Color(0.08, 0.08, 0.08), Vector3(side, 0, 0))
				_quad(dark, wheel[k] - Vector3(side * 0.02, 0, 0), wheel[k + 1] - Vector3(side * 0.02, 0, 0), wheel[k + 1] + Vector3(side * 0.02, 0, 0), wheel[k] + Vector3(side * 0.02, 0, 0),
						Color(0.1, 0.1, 0.1), (wheel[k] + wheel[k + 1]) * 0.5 - Vector3(side * 0.29, 0.1, -0.27))
		return [_end(st, false), _end(dark, false)])
	_add(root, parts[0], _vmat("glossy", 0.55))
	_add(root, parts[1], _vmat("", 0.8))


# ---- leaves and flowers: small cards with a cut-out leaf, many of them (MultiMesh), round lumpy clumps ----

static func _leaf_mat(kind: String) -> StandardMaterial3D:
	if _cache.has("leafmat:" + kind):
		return _cache["leafmat:" + kind]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 64.0 - 0.5
			var v := (y + 0.5) / 64.0
			var a := 0.0
			var c := Color(1, 1, 1)
			match kind:
				"leaf":    # a pointed oval leaf with a midrib
					var w := 0.42 * sin(PI * v) * (1.0 - 0.35 * v)
					a = 1.0 if absf(u) < w else 0.0
					c = Color(1, 1, 1).darkened(0.25 * (1.0 - absf(u) / maxf(w, 0.01)) * 0.4)
					if absf(u) < 0.025:
						c = Color(0.82, 0.88, 0.7)
				"petal":   # five rounded petals round a centre (white: tinted per flower)
					var p := Vector2(u, v - 0.5)
					var ang := atan2(p.y, p.x)
					var r := p.length()
					var edge := 0.28 + 0.16 * absf(cos(ang * 2.5))
					a = 1.0 if r < edge else 0.0
					if r < 0.1:
						c = Color(1.0, 0.78, 0.15)
					else:
						c = Color(1, 1, 1).darkened(0.18 * r)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.3, 0.12)
	_cache["leafmat:" + kind] = m
	return m


static func _card(len: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(len * 0.7, len)
	q.center_offset = Vector3(0, len * 0.5, 0)
	return q


# Many leaf (or flower) cards over lumpy clumps: spots = [[centre, radius], ...].
static func _foliage(root: Node3D, key: String, spots: Array, count: int, size: float, cols: Array, seed: int, kind := "leaf") -> void:
	var mm: MultiMesh
	if _cache.has("mm:" + key):
		mm = _cache["mm:" + key]
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _card(size)
		mm.instance_count = count
		for i in count:
			var s: Array = spots[i % spots.size()]
			var c: Vector3 = s[0]
			var r: float = s[1]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 1), rng.randf_range(-1, 1)).normalized()
			var at := c + dir * r * rng.randf_range(0.9, 1.06)
			# the card points outward (a little upward), turned any way round that
			var yax := (dir + Vector3.UP * 0.4).normalized()
			var ref := Vector3.UP if absf(yax.y) < 0.9 else Vector3.RIGHT
			var xax := yax.cross(ref).normalized().rotated(yax, rng.randf() * TAU)
			var b := Basis(xax, yax, xax.cross(yax)).scaled(Vector3.ONE * rng.randf_range(0.75, 1.2))
			mm.set_instance_transform(i, Transform3D(b, at))
			var col: Color = cols[rng.randi() % cols.size()]
			mm.set_instance_color(i, col.darkened(rng.randf_range(0.0, 0.2)).lightened(0.12 * maxf(dir.y, 0.0)))
		_cache["mm:" + key] = mm
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _leaf_mat(kind)
	root.add_child(mmi)


# Lumpy round clumps (the leafy mass under the cards).
static func _clumps(spots: Array, col: Color, seed: int) -> ArrayMesh:
	var st := _begin()
	for s in spots:
		var c: Vector3 = s[0]
		var r: float = s[1]
		var prof := []
		for k in 9:
			var t := -PI * 0.5 + PI * k / 8.0
			prof.append([cos(t) * r * 0.92, sin(t) * r * 0.85])
		var ph := float(seed) + c.x * 7.0 + c.z * 3.0
		_lathe(st, prof, 14, func(i: int, a: float) -> Color: return col.darkened(0.35 * (1.0 - float(i) / 8.0)).lightened(0.1 * sin(a * 3.0 + ph)),
				c, func(i: int, a: float) -> float: return 1.0 + 0.12 * sin(a * 4.0 + ph + float(i)) * sin(PI * i / 8.0))
	return _end(st, true)


# A garden bush, growing straight from the ground (not in a pot): a few leafy clumps over short woody stems,
# covered in leaves; the flowering one is dotted with pink and white blossom. (collision: cylinder r 0.7 / 0.6)
static func _bush(root: Node3D, flowering: bool) -> void:
	var key := "bush_f" if flowering else "bush"
	var k := 0.85 if flowering else 1.0
	var spots := [[Vector3(0, 0.48, 0) * k, 0.46 * k], [Vector3(0.3, 0.38, 0.12) * k, 0.33 * k], [Vector3(-0.26, 0.36, 0.2) * k, 0.32 * k],
			[Vector3(0.05, 0.36, -0.3) * k, 0.33 * k], [Vector3(-0.2, 0.62, -0.1) * k, 0.3 * k], [Vector3(0.18, 0.66, -0.05) * k, 0.28 * k]]
	var parts := _cached(key, func() -> Array:
		var stems := _begin()
		for i in 5:
			var a := TAU * i / 5.0 + 0.4
			_tube(stems, [Vector3(0, 0, 0), Vector3(cos(a) * 0.08, 0.15, sin(a) * 0.08) * k, Vector3(cos(a) * 0.2, 0.32, sin(a) * 0.2) * k], [0.03, 0.022, 0.012], Color(0.3, 0.2, 0.12), 5)
		return [_clumps(spots, Color(0.18, 0.36, 0.12) if not flowering else Color(0.16, 0.32, 0.13), 11 if flowering else 5), _end(stems, true)])
	_add(root, parts[0], _vmat("plant", 0.9))
	_add(root, parts[1], _vmat("wood", 0.9))
	_foliage(root, key, spots, 1300 if not flowering else 1000, 0.085 * k, [Color(0.17, 0.36, 0.1), Color(0.13, 0.29, 0.08), Color(0.22, 0.42, 0.12), Color(0.28, 0.46, 0.14)], 21 if flowering else 17)
	if flowering:
		_foliage(root, key + "_bloom", spots, 160, 0.08, [Color(1.0, 0.62, 0.78), Color(1.0, 0.95, 0.96), Color(0.98, 0.45, 0.62)], 33, "petal")


# A clump of daisies: strappy leaves at the bottom and white daisies on wiry stems. (collision: cyl r 0.35, h 0.4)
static func _daisies(root: Node3D) -> void:
	_flowers(root, "daisies", 0.4, [Color(1, 1, 1), Color(0.98, 0.96, 0.92)], 18, false)


# Tulips: broad leaves and cupped red and yellow flowers. (collision: cylinder r 0.3, h 0.5)
static func _tulips(root: Node3D) -> void:
	_flowers(root, "tulips", 0.5, [Color(0.85, 0.1, 0.12), Color(0.98, 0.78, 0.12), Color(0.9, 0.3, 0.45)], 11, true)


static func _flowers(root: Node3D, key: String, h: float, heads: Array, n: int, cups: bool) -> void:
	var parts := _cached("fl_" + key, func() -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = 101 if cups else 77
		var green := _begin()
		var bloom := _begin()
		var leaf_col := Color(0.22, 0.45, 0.16)
		# leaves: arching blades from the middle
		for i in (9 if cups else 22):
			var a := rng.randf() * TAU
			var len := rng.randf_range(0.18, 0.3) if cups else rng.randf_range(0.1, 0.2)
			var wid := 0.045 if cups else 0.014
			var dir := Vector3(cos(a), 0, sin(a))
			var side := dir.cross(Vector3.UP) * wid
			var prev := Vector3(dir.x * 0.02, 0.0, dir.z * 0.02)
			for k in 5:
				var t := float(k + 1) / 5.0
				var p := dir * (0.02 + len * 0.55 * t) + Vector3.UP * (len * sin(t * PI * 0.6) * (1.0 if cups else 0.8))
				var w0 := sin(PI * (t - 0.2)) * 1.0
				var w1 := sin(PI * t) * 1.0
				_quad(green, prev - side * maxf(w0, 0.15), p - side * maxf(w1, 0.0), p + side * maxf(w1, 0.0), prev + side * maxf(w0, 0.15), leaf_col.lightened(0.05 * k), Vector3.UP)
				prev = p
		for i in n:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 0.22 if not cups else 0.17)
			var top := Vector3(cos(a) * r, h * rng.randf_range(0.72, 0.92), sin(a) * r)
			var mid := Vector3(cos(a) * r * 0.5, top.y * 0.5, sin(a) * r * 0.5) + Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.02, 0.02))
			_tube(green, [Vector3(cos(a) * 0.02, 0, sin(a) * 0.02), mid, top], [0.006, 0.005, 0.004], leaf_col.darkened(0.1), 4)
			var hc: Color = heads[rng.randi() % heads.size()]
			if cups:
				_lathe(bloom, [[0.0, -0.01], [0.025, -0.005], [0.038, 0.02], [0.04, 0.05], [0.032, 0.075], [0.0, 0.06]], 10,
						func(_i: int, aa: float) -> Color: return hc.darkened(0.15 * (0.5 + 0.5 * cos(aa * 3.0))), top,
						func(i2: int, aa: float) -> float: return 1.0 + (0.12 * cos(aa * 3.0) if i2 >= 4 else 0.0))
			else:
				var face := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
				var u := face.cross(Vector3.FORWARD).normalized()
				var v := face.cross(u)
				for pk in 14:   # petals
					var pa := TAU * pk / 14.0
					var d := (u * cos(pa) + v * sin(pa))
					var w := (u * cos(pa + PI * 0.5) + v * sin(pa + PI * 0.5)) * 0.006
					_quad(bloom, top + d * 0.008 - w, top + d * 0.038 - w * 0.8, top + d * 0.038 + w * 0.8, top + d * 0.008 + w, hc, face)
				_lathe(bloom, [[0.0, -0.003], [0.011, 0.0], [0.009, 0.006], [0.0, 0.008]], 8, _flat(Color(1.0, 0.75, 0.1)), top)
		return [_end(green, false), _end(bloom, true)])
	_add(root, parts[0], _vmat("plant", 0.8, -1.0, true))
	_add(root, parts[1], _vmat("cloth", 0.7, -1.0, true))


# A fern: a dozen arching fronds, each lined with leaflets that get smaller toward the tip.
# (collision: cylinder r 0.45, h 0.55)
static func _fern(root: Node3D) -> void:
	var parts := _cached("fern", func() -> Array:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 404
		for f in 13:
			var a := TAU * f / 13.0 + rng.randf_range(-0.15, 0.15)
			var dir := Vector3(cos(a), 0, sin(a))
			var side := dir.cross(Vector3.UP)
			var len := rng.randf_range(0.38, 0.5)
			var rise := rng.randf_range(0.35, 0.5)
			var pts := []
			for k in 12:
				var t := float(k) / 11.0
				pts.append(dir * len * t + Vector3.UP * (rise * sin(t * PI * 0.75) - 0.05 * t * t) + Vector3.UP * 0.02)
			var col := Color(0.2, 0.45, 0.15).lerp(Color(0.3, 0.55, 0.2), rng.randf())
			for k in 11:
				var p0: Vector3 = pts[k]
				var p1: Vector3 = pts[k + 1]
				_quad(st, p0 - side * 0.004, p1 - side * 0.004, p1 + side * 0.004, p0 + side * 0.004, col.darkened(0.25), Vector3.UP)
				var t := float(k) / 11.0
				var ll := 0.085 * sin(PI * (0.15 + 0.85 * t)) * (1.0 - t * 0.4)
				for s in [-1.0, 1.0]:
					var base := (p0 + p1) * 0.5
					var tip: Vector3 = base + side * s * ll + (p1 - p0).normalized() * ll * 0.4 - Vector3.UP * ll * 0.25
					_tri(st, p0, p1, tip, col.lightened(0.06 * s), Vector3.UP)
		return [_end(st, false)])
	_add(root, parts[0], _vmat("plant", 0.8, -1.0, true))
