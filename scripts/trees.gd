# Deciduous trees (Ted's wife, Nov 26: "add deciduous trees"): an oak and a birch, grown in code. A trunk that
# flares at the foot, branches that fork as they reach out, and leafy crowns of clumps covered in leaf cards
# (classic_props.gd's leaves). Four looks: summer, spring (fresh green with blossom), autumn, and late autumn
# (thin, rusty, the branches showing). Map pieces of type "building" (kind "oak" / "birch"), like the gates:
# placed, turned and coloured in Creative the same way. Only the trunk is solid; you can fly through leaves.
# Everything is seeded, so every screen grows the same tree.
extends RefCounted

const ClassicProps = preload("res://scripts/classic_props.gd")
const Surfaces = preload("res://scripts/surfaces.gd")

const LOOKS := ["Summer", "Spring blossom", "Autumn", "Late autumn"]
const LEAVES := [
	[Color(0.17, 0.36, 0.1), Color(0.13, 0.29, 0.08), Color(0.23, 0.42, 0.12)],
	[Color(0.32, 0.55, 0.16), Color(0.26, 0.5, 0.13), Color(0.38, 0.6, 0.2)],
	[Color(0.85, 0.48, 0.08), Color(0.72, 0.22, 0.06), Color(0.9, 0.7, 0.15), Color(0.55, 0.3, 0.08)],
	[Color(0.55, 0.28, 0.08), Color(0.45, 0.2, 0.06), Color(0.62, 0.42, 0.12)],
]
const CLUMP := [Color(0.13, 0.28, 0.08), Color(0.24, 0.44, 0.12), Color(0.62, 0.3, 0.07), Color(0.4, 0.2, 0.06)]

static var _cache := {}


static func size(kind: String) -> Vector3:
	return Vector3(6.4, 7.2, 6.4) if kind == "oak" else Vector3(3.6, 8.4, 3.6)


static func make(kind: String, look: int) -> Node3D:
	look = clampi(look, 0, 3)
	var g := _grow(kind)
	var root := Node3D.new()
	root.name = "Tree"
	var bark := MeshInstance3D.new()
	bark.mesh = g["bark"]
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	Surfaces.apply(bm, "wood")
	bm.roughness = 0.95
	bark.material_override = bm
	root.add_child(bark)
	var spots: Array = g["crown"]
	if look != 3:   # (late autumn: no leafy mass, just what leaves are left)
		var cl := MeshInstance3D.new()
		cl.mesh = _clumps(kind, look, spots)
		cl.material_override = ClassicProps._vmat("plant", 0.9)
		root.add_child(cl)
	var per := 280 if kind == "oak" else 240   # (Nov 27: fuller, finer crowns)
	var count: int = spots.size() * (per if look != 3 else per / 4)
	ClassicProps._foliage(root, "tree_%s_%d" % [kind, look], spots, count, 0.17 if kind == "oak" else 0.13, LEAVES[look], 500 + look * 7 + (0 if kind == "oak" else 50))
	if look == 1:
		ClassicProps._foliage(root, "tree_%s_bloom" % kind, spots, spots.size() * 60, 0.24, [Color(1.0, 0.8, 0.88), Color(1.0, 0.97, 0.97)], 909, "petal")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32 if kind == "oak" else 0.16
	cyl.height = 2.6 if kind == "oak" else 5.0
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	root.add_child(body)
	return root


static func _clumps(kind: String, look: int, spots: Array) -> ArrayMesh:
	var key := "cl_%s_%d" % [kind, look]
	if not _cache.has(key):
		var shrunk := []
		for s in spots:
			shrunk.append([s[0], float(s[1]) * 0.86])
		_cache[key] = ClassicProps._clumps(shrunk, CLUMP[look], 3 + look)
	return _cache[key]


# The trunk and branches (one mesh), and where the leafy clumps go: {bark, crown: [[centre, radius], ...]}.
static func _grow(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if kind == "oak" else 5151
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown := []
	var oak := kind == "oak"
	var bark_col := Color(0.3, 0.22, 0.16) if oak else Color(0.88, 0.86, 0.8)
	var top := Vector3(0, 2.4, 0) if oak else Vector3(0.1, 6.2, -0.05)
	# the trunk, flared at the foot, a slight lean
	var tpts := []
	var trad := []
	var n := 8
	for k in n + 1:
		var t := float(k) / n
		tpts.append(Vector3(0.0, 0.0, 0.0).lerp(top, t) + Vector3(sin(t * 3.0) * 0.06, 0, cos(t * 2.0) * 0.04 - 0.04))
		var r := (lerpf(0.34, 0.22, t) if oak else lerpf(0.17, 0.07, t)) + (0.16 if oak else 0.06) * pow(1.0 - t, 6.0)
		trad.append(r)
	_bark(st, tpts, trad, bark_col, oak, 10)
	# roots spreading at the foot
	for k in (5 if oak else 3):
		var a := TAU * k / (5 if oak else 3) + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		_bark(st, [d * 0.1 + Vector3.UP * 0.3, d * 0.45 + Vector3.UP * 0.06, d * 0.75 + Vector3.DOWN * 0.04], [0.12 if oak else 0.06, 0.07 if oak else 0.035, 0.02], bark_col, oak, 6)
	if oak:
		# five big limbs reaching out and up, each forking twice
		for k in 5:
			var a := TAU * k / 5.0 + rng.randf_range(-0.25, 0.25)
			var d := Vector3(cos(a), 0, sin(a))
			var base: Vector3 = tpts[n - rng.randi_range(0, 2)]
			var dir := (d * 0.7 + Vector3.UP * rng.randf_range(0.9, 1.2)).normalized()
			_limb(st, rng, base, dir, 1.9, 0.18, 2, crown, bark_col, oak)
		_fill(crown, rng, Vector3(0, 4.7, 0), Vector3(2.5, 1.9, 2.5), 30, 0.85, 1.2)
	else:
		# short branches up the trunk, angled up, and a narrow crown of clumps along the top half
		for k in 9:
			var t := 0.42 + 0.58 * float(k) / 8.0
			var base: Vector3 = Vector3.ZERO.lerp(top, t)
			var a := k * 2.4
			var dir := (Vector3(cos(a), 0, sin(a)) * 0.7 + Vector3.UP * 0.9).normalized()
			_limb(st, rng, base, dir, lerpf(1.3, 0.7, t), lerpf(0.05, 0.025, t), 1, crown, bark_col, oak)
		_fill(crown, rng, top + Vector3(0, -0.9, 0), Vector3(1.15, 2.4, 1.15), 24, 0.5, 0.72)
	st.index()
	st.generate_normals()
	var out := {"bark": st.commit(), "crown": crown}
	_cache[kind] = out
	return out


# Clumps filling a rounded crown (an ellipsoid), so it reads as one leafy dome, not a bunch of balls.
static func _fill(crown: Array, rng: RandomNumberGenerator, c: Vector3, radii: Vector3, n: int, r0: float, r1: float) -> void:
	for k in n:
		var y := 1.0 - 2.0 * (k + 0.5) / n
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var a := k * 2.39996
		var dir := Vector3(cos(a) * ring, y, sin(a) * ring)
		crown.append([c + dir * radii * rng.randf_range(0.55, 0.8), rng.randf_range(r0, r1)])


static func _limb(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, dir: Vector3, len: float, r: float, forks: int,
		crown: Array, col: Color, oak: bool) -> void:
	var pts := []
	var rad := []
	var p := base
	var d := dir
	for k in 5:
		pts.append(p)
		rad.append(r * lerpf(1.0, 0.55, k / 4.0))
		d = (d + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.05, 0.12), rng.randf_range(-0.2, 0.2))).normalized()
		p += d * len / 4.0
	_bark(st, pts, rad, col, oak, 7)
	var tip: Vector3 = pts[4]
	if forks > 0:
		for s in [-1.0, 1.0]:
			var side: Vector3 = d.cross(Vector3.UP).normalized() * s
			_limb(st, rng, tip, (d + side * 0.6 + Vector3.UP * 0.25).normalized(), len * 0.6, r * 0.5, forks - 1, crown, col, oak)
	else:
		crown.append([tip + Vector3.UP * (0.3 if oak else 0.2), rng.randf_range(1.0, 1.35) if oak else rng.randf_range(0.6, 0.8)])


# A bark-covered tube: oak furrowed (ribs, darker in the cracks), birch white with dark bands and marks.
static func _bark(st: SurfaceTool, pts: Array, radii: Array, col: Color, oak: bool, sides: int) -> void:
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
		side = side - t * side.dot(t)
		if side.length() < 0.01:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var up := t.cross(side)
		var ring := []
		for j in sides + 1:
			var a := TAU * j / sides
			var furrow := 0.5 + 0.5 * cos(a * 5.0 + float(i) * 0.7)
			var r: float = radii[i] * (1.0 + (0.09 * (furrow - 0.5) if oak else 0.0))
			var c := col
			if oak:
				c = col.darkened(0.35 * (1.0 - furrow)).lightened(0.06 * furrow)
			else:
				var pv: Vector3 = pts[i]
				if ClassicProps._h(floor(pv.y * 7.0) + float(j % 3) * 0.37) > 0.72:
					c = Color(0.12, 0.1, 0.09)   # birch's dark marks
			ring.append([pts[i] + (side * cos(a) + up * sin(a)) * r, c])
		rings.append(ring)
	for i in n - 1:
		var mid: Vector3 = (pts[i] + pts[i + 1]) * 0.5
		for j in sides:
			var q := [rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]]
			var out: Vector3 = (q[0][0] + q[2][0]) * 0.5 - mid
			for tr in [[0, 1, 2], [0, 2, 3]]:
				var a: Array = q[tr[0]]
				var b: Array = q[tr[1]]
				var c: Array = q[tr[2]]
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
