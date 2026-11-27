# Enterable buildings, built procedurally: real door and window openings, floors,
# stairs/ramps and roofs, so angels and demons can walk in and out (Ted's wife's
# Creative note, Nov 25). Map piece type "building": make(kind, look) returns a
# Node3D (one merged ArrayMesh, a surface per material, plus a StaticBody3D of
# box/convex shapes on collision layer 1). Origin = bottom centre, front (main
# door) faces +Z. Meshes and shapes are cached per kind/look/quality and shared.
#
# Sizes for players: doorways >= 1.6 m wide and 2.4 m tall, steps <= 0.22 m rise
# and >= 1.3 m wide, storeys >= 2.8 m clear. Windows are open holes, so people can
# peek in. Surface detail (bricks, planks, tiles, stone) is drawn by one small
# shader from metre-scaled UVs; colours are vertex colours.
extends RefCounted

const Graphics = preload("res://scripts/graphics.gd")
const WoodGrain = preload("res://scripts/wood_grain.gd")

const KINDS := {
	"cottage": "Cottage",
	"townhouse": "Townhouse",
	"shop": "Corner Shop",
	"barn": "Barn",
	"chapel": "Chapel",
	"ruin": "Ruined House",
}

const T := 0.25 # wall thickness
const FLOOR := 0.15 # ground floor top

# Materials (one mesh surface each).
enum { PLASTER, BRICK, STONE, PLANKS, ROOF, TRIM, HAY, BOARDS, FLAG, TIMBER }

const SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform int mode = 0;
uniform bool detail = true;

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec2 uv = UV;
	float sh = 1.0;
	float rough = 0.88;
	if (detail) {
		float n = vn(uv * 1.7) * 0.6 + vn(uv * 6.0) * 0.4;
		if (mode == 0) {
			sh = 0.9 + 0.14 * n;
			sh *= 0.97 + 0.03 * vn(uv * 23.0);
		} else if (mode == 1) {
			vec2 b = uv / vec2(0.44, 0.2);
			float row = floor(b.y);
			b.x += 0.5 * mod(row, 2.0);
			vec2 id = floor(b);
			vec2 f = fract(b);
			float e = min(min(f.x, 1.0 - f.x) * 0.44, min(f.y, 1.0 - f.y) * 0.2);
			float mortar = 1.0 - smoothstep(0.012, 0.024, e);
			vec3 bc = base * (0.8 + 0.32 * h21(id)) * (0.9 + 0.14 * n);
			bc *= 0.86 + 0.14 * smoothstep(0.02, 0.06, e);
			base = mix(bc, vec3(0.62, 0.6, 0.56), mortar * 0.85);
		} else if (mode == 2 || mode == 8) {
			vec2 cell = mode == 2 ? vec2(0.62, 0.34) : vec2(0.8, 0.8);
			vec2 b = uv / cell;
			float row = floor(b.y);
			b.x += h21(vec2(row, 3.1));
			vec2 id = floor(b);
			vec2 f = fract(b);
			float e = min(min(f.x, 1.0 - f.x) * cell.x, min(f.y, 1.0 - f.y) * cell.y);
			float mortar = 1.0 - smoothstep(0.015, 0.035, e);
			vec3 sc = base * (0.8 + 0.28 * h21(id)) * (0.84 + 0.22 * n);
			sc *= 0.84 + 0.16 * smoothstep(0.02, 0.1, e);
			base = mix(sc, base * 0.5, mortar);
		} else if (mode == 3 || mode == 7) {
			vec2 p = mode == 3 ? uv : uv.yx;
			float w = mode == 3 ? 0.2 : 0.3;
			float row = floor(p.y / w);
			float len = 2.2;
			float x = p.x + h21(vec2(row, 7.0)) * len;
			float seg = floor(x / len);
			float fy = fract(p.y / w);
			float fx = fract(x / len);
			float gap = max(1.0 - smoothstep(0.0, 0.07, min(fy, 1.0 - fy)), 1.0 - smoothstep(0.0, 0.006, min(fx, 1.0 - fx)));
			// the shared wood grain (wood_grain.gd), each board starting somewhere of its own in it
			vec2 board = vec2(row, seg);
			vec3 wg = wood_grain(vec2(x + h21(board + 1.3) * 40.0, p.y + h21(board + 5.7) * 3.0), mode == 7 ? 0.8 : 0.45);
			vec3 pc = base * (0.86 + 0.2 * h21(board)) * wg.x;
			base = mix(pc, base * 0.35, gap * 0.8);
			rough = wg.z;
		} else if (mode == 4) {
			vec2 cell = vec2(0.36, 0.3);
			vec2 b = uv / cell;
			float row = floor(b.y);
			b.x += 0.5 * mod(row, 2.0);
			vec2 id = floor(b);
			vec2 f = fract(b);
			float edge = 1.0 - smoothstep(0.0, 0.07, min(f.x, 1.0 - f.x));
			float lap = smoothstep(0.0, 1.0, f.y);
			vec3 tc = base * (0.8 + 0.26 * h21(id)) * (0.7 + 0.4 * lap) * (0.92 + 0.1 * n);
			base = mix(tc, base * 0.45, edge * 0.7);
		} else if (mode == 9) {
			// old timber (the ruin's beams, Ted, Nov 26): the shared grain, aged (uv.x runs along the grain,
			// and each beam's uv starts at its own offset: Bld.grain_off)
			// (Ted, Nov 26: frames and beams all get the grain. Painted ones, the white and pale trims, show it
			// only faintly through the paint, and the paint is smoother)
			float lum = dot(base, vec3(0.3, 0.59, 0.11));
			float paint = smoothstep(0.35, 0.55, lum);
			vec3 wg = wood_grain(uv, mix(1.0, 0.3, paint));
			sh = mix(wg.x, 1.0 + (wg.x - 1.0) * 0.3, paint);
			rough = mix(wg.z, 0.6, paint);
		} else if (mode == 6) {
			float s = vn(vec2(uv.x * 3.0, uv.y * 40.0)) * 0.6 + vn(vec2(uv.x * 9.0 + 4.0, uv.y * 70.0)) * 0.4;
			sh = 0.68 + 0.45 * s;
			rough = 1.0;
		} else {
			sh = 0.95 + 0.08 * n;
			rough = 0.7;
		}
	}
	ALBEDO = base * sh;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"""

static var _shader: Shader
static var _mats := {}
static var _cache := {}


# ---------------------------------------------------------------- public API

static func size(kind: String) -> Vector3:
	var b: Dictionary = _built(kind, 0)
	return b["size"]


static func make(kind: String, look: int = 0) -> Node3D:
	if not KINDS.has(kind):
		kind = "cottage"
	var b: Dictionary = _built(kind, clampi(look, 0, 3))
	var root := Node3D.new()
	root.name = "Building"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = b["mesh"]
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	root.add_child(body)
	for s in b["shapes"]:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = s[1]
		body.add_child(cs)
	return root


# Flicker check (tests/test_models.gd; Ted, Nov 26, again: "your eyes are better than mine"): places where two
# faces facing the same way lie in (almost) one plane and overlap, which flicker as the camera moves.
# Returns [[where, material a, material b, overlap m2], ...].
static func coplanar_faces(kind: String, look := 0) -> Array:
	var b := Bld.new()
	b.record = true
	match kind:
		"cottage": _cottage(b, look)
		"townhouse": _townhouse(b, look)
		"shop": _shop(b, look)
		"barn": _barn(b, look)
		"chapel": _chapel(b, look)
		"ruin": _ruin(b, look)
	var buckets := {}
	for t in b.tris:
		var n: Vector3 = t[3]
		var key := "%d,%d,%d" % [roundi(n.x * 50.0), roundi(n.y * 50.0), roundi(n.z * 50.0)]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)
	var out := []
	var seen := {}
	for key in buckets:
		var list: Array = buckets[key]
		for i in list.size():
			var t1: Array = list[i]
			var n: Vector3 = t1[3]
			if n.y < -0.9 and t1[0].y < 0.01:
				continue   # (undersides on the ground: never seen)
			var d1: float = n.dot(t1[0])
			var ax := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
			var ay := n.cross(ax)
			var p1 := PackedVector2Array([Vector2(t1[0].dot(ax), t1[0].dot(ay)), Vector2(t1[1].dot(ax), t1[1].dot(ay)), Vector2(t1[2].dot(ax), t1[2].dot(ay))])
			for j in range(i + 1, list.size()):
				var t2: Array = list[j]
				if t2[4] == t1[4] or n.dot(t2[3]) < 0.9995 or absf(n.dot(t2[0]) - d1) > 0.003:
					continue
				var pair := "%d_%d" % [mini(t1[4], t2[4]), maxi(t1[4], t2[4])]
				if seen.has(pair):
					continue
				var p2 := PackedVector2Array([Vector2(t2[0].dot(ax), t2[0].dot(ay)), Vector2(t2[1].dot(ax), t2[1].dot(ay)), Vector2(t2[2].dot(ax), t2[2].dot(ay))])
				var area := 0.0
				for poly in Geometry2D.intersect_polygons(p1, p2):
					var pa := 0.0
					for k in poly.size():
						pa += poly[k].cross(poly[(k + 1) % poly.size()])
					area += absf(pa) * 0.5
				if area > 0.0004:
					seen[pair] = true
					out.append([(t1[0] + t1[1] + t1[2]) / 3.0, t1[5], t2[5], area, n, (t2[0] + t2[1] + t2[2]) / 3.0])
	return out


# ---------------------------------------------------------------- internals

static func _built(kind: String, look: int) -> Dictionary:
	if not KINDS.has(kind):
		kind = "cottage"
	var low := Graphics.quality <= 0
	var key := "%s_%d_%d" % [kind, look, int(low)]
	if _cache.has(key):
		return _cache[key]
	var b := Bld.new()
	match kind:
		"cottage": _cottage(b, look)
		"townhouse": _townhouse(b, look)
		"shop": _shop(b, look)
		"barn": _barn(b, look)
		"chapel": _chapel(b, look)
		"ruin": _ruin(b, look)
	var mesh := ArrayMesh.new()
	var keys: Array = b.sts.keys()
	keys.sort()
	for m in keys:
		var st: SurfaceTool = b.sts[m]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat(m, low))
	var sz := Vector3(2.0 * maxf(absf(b.lo.x), absf(b.hi.x)), b.hi.y, 2.0 * maxf(absf(b.lo.z), absf(b.hi.z)))
	var out := {"mesh": mesh, "shapes": b.shapes, "size": sz}
	_cache[key] = out
	return out


static func _mat(m: int, low: bool) -> ShaderMaterial:
	var key := m * 2 + int(low)
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER.replace("void fragment() {", WoodGrain.GLSL + "\nvoid fragment() {")
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("mode", m)
	sm.set_shader_parameter("detail", not low)
	_mats[key] = sm
	return sm


static func _c(hex: String) -> Color:
	return Color(hex)


static func _op(u: float, w: float, b: float, t: float, k: String = "win") -> Dictionary:
	return {"u": u, "w": w, "b": b, "t": t, "k": k}


# A squared timber 0.2 m thick from a to b (centre line), solid, with the grain along it.
static func _beam(b: Bld, a: Vector3, c: Vector3, col: Color, size := Vector2(0.2, 0.2)) -> void:
	var dir := (c - a).normalized()
	var x := Vector3.UP.cross(dir)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var bas := Basis(x, dir.cross(x), dir)
	b.grain = dir
	b.grain_off = WoodGrain.offset_for(a + c)
	b.box(TIMBER, (a + c) * 0.5, Vector3(size.x, size.y, a.distance_to(c)), col, size.x >= 0.2, bas)
	b.grain = Vector3.ZERO


# Where a 0.2 m beam's foot goes (at xz) so its lowest corner just touches the floor, the other end at `other`.
static func _on_floor(other: Vector3, xz: Vector3) -> Vector3:
	var f := Vector3(xz.x, FLOOR + 0.1, xz.z)
	for i in 3:
		var dir := (other - f).normalized()
		f.y = FLOOR + 0.1 * Vector2(dir.x, dir.z).length() + 0.002
	return f


# The dark hole in a wall's face where a joist's end goes in (centre on the face, out = the way the face looks).
static func _pocket(b: Bld, c: Vector3, out: Vector3, size: Vector2, wall: Color) -> void:
	var dark := wall.darkened(0.75)
	if absf(out.z) > 0.5:
		b.ab(TRIM, c + Vector3(-size.x * 0.5, -size.y * 0.5, -out.z * 0.02), c + Vector3(size.x * 0.5, size.y * 0.5, out.z * 0.012), dark, false)
	else:
		b.ab(TRIM, c + Vector3(-out.x * 0.02, -size.y * 0.5, -size.x * 0.5), c + Vector3(out.x * 0.012, size.y * 0.5, size.x * 0.5), dark, false)


# A squared timber between two corners, the grain along its longest side.
static func _timber(b: Bld, p0: Vector3, p1: Vector3, col: Color, collide := false) -> void:
	var s := (p1 - p0).abs()
	b.grain = Vector3.RIGHT if s.x >= s.y and s.x >= s.z else (Vector3.UP if s.y >= s.z else Vector3.BACK)
	b.grain_off = WoodGrain.offset_for(p0 + p1)
	b.ab(TIMBER, p0, p1, col, collide)
	b.grain = Vector3.ZERO


# A slatted wooden display crate on the floor (empty: maps put real props on it). Solid, so things sit on it.
static func _crate(b: Bld, at: Vector3) -> void:
	var wood := Color("#9a7448")
	var s := Vector3(0.7, 0.45, 0.5)
	b.ab(BOARDS, at + Vector3(-s.x * 0.5, 0, -s.z * 0.5), at + Vector3(s.x * 0.5, s.y, s.z * 0.5), wood)


# ---------------------------------------------------------------- the builder

class Bld:
	var sts := {}
	var shapes: Array = []
	var grain := Vector3.ZERO   # TIMBER: the way the wood grain runs (set while a beam is drawn)
	var grain_off := Vector2.ZERO   # ...and where in the grain this beam starts (so no two look alike)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	# For the flicker check (coplanar_faces): every triangle drawn, with which face it belongs to.
	var record := false
	var tris: Array = []   # [a, b, c, normal, face id, material]
	var _face := 0
	var _in_quad := false

	func _st(m: int) -> SurfaceTool:
		if not sts.has(m):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[m] = s
		return sts[m]

	func _uv(p: Vector3, n: Vector3, bas: Basis) -> Vector2:
		if grain != Vector3.ZERO:
			var across := n.cross(grain)
			if across.length() < 0.1:   # the sawn end: end grain
				var t1 := grain.cross(Vector3.UP if absf(grain.y) < 0.9 else Vector3.RIGHT).normalized()
				return Vector2(p.dot(t1) * 3.0, p.dot(grain.cross(t1)) * 3.0)
			return Vector2(p.dot(grain), p.dot(across.normalized())) + grain_off
		if absf(n.y) > 0.7:
			return Vector2(p.dot(bas.x), p.dot(bas.z))
		var t := Vector3.UP.cross(n)
		if t.length() < 0.01:
			t = bas.x
		t = t.normalized()
		return Vector2(p.dot(t), p.y)

	func tri(m: int, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, bas := Basis()) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var tmp := b
			b = c
			c = tmp
		if record:
			if not _in_quad:
				_face += 1
			tris.append([a, b, c, n.normalized(), _face, m])
		var s := _st(m)
		var lc := col.srgb_to_linear()
		for p in [a, b, c]:
			s.set_color(lc)
			s.set_normal(n)
			s.set_uv(_uv(p, n, bas))
			s.add_vertex(p)
			lo = lo.min(p)
			hi = hi.max(p)

	func quad(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, bas := Basis()) -> void:
		_face += 1
		_in_quad = true
		tri(m, a, b, c, n, col, bas)
		tri(m, a, c, d, n, col, bas)
		_in_quad = false

	# A box (centre, full size), optionally rotated; collide adds a BoxShape3D.
	func box(m: int, c: Vector3, s: Vector3, col: Color, collide := true, bas := Basis()) -> void:
		var auto_grain := m == TIMBER and grain == Vector3.ZERO
		if auto_grain:   # (the grain runs along the longest side, from a spot in it of this piece's own)
			var k := 0 if s.x >= s.y and s.x >= s.z else (1 if s.y >= s.z else 2)
			grain = (bas.x if k == 0 else (bas.y if k == 1 else bas.z)).normalized()
			grain_off = WoodGrain.offset_for(c)
		_box(m, c, s, col, collide, bas)
		if auto_grain:
			grain = Vector3.ZERO

	func _box(m: int, c: Vector3, s: Vector3, col: Color, collide: bool, bas: Basis) -> void:
		var h := s * 0.5
		var axes := [bas.x.normalized(), bas.y.normalized(), bas.z.normalized()]
		for i in 3:
			for sg in [-1.0, 1.0]:
				var n: Vector3 = axes[i] * sg
				var a1: Vector3 = axes[(i + 1) % 3] * h[(i + 1) % 3]
				var a2: Vector3 = axes[(i + 2) % 3] * h[(i + 2) % 3]
				var fc: Vector3 = c + n * h[i]
				quad(m, fc - a1 - a2, fc + a1 - a2, fc + a1 + a2, fc - a1 + a2, n, col, bas)
		if collide:
			cbox(c, s, bas)

	func cbox(c: Vector3, s: Vector3, bas := Basis()) -> void:
		var sh := BoxShape3D.new()
		sh.size = s
		shapes.append([sh, Transform3D(bas, c)])

	func ab(m: int, p0: Vector3, p1: Vector3, col: Color, collide := true, grow := Vector3.ONE * 0.004) -> void:
		var a := p0.min(p1)
		var b := p0.max(p1)
		if not collide:
			# Looks-only pieces (trim, beams, bands) stand a few mm proud on every side, so none of
			# their faces lies in the very plane of a wall's, floor's or another piece's face: two surfaces in
			# one plane flicker as the camera moves (Ted, Nov 26: tops and bottoms of walls, door frames).
			a -= grow
			b += grow
		if (b - a).x < 0.001 or (b - a).y < 0.001 or (b - a).z < 0.001:
			return
		box(m, (a + b) * 0.5, b - a, col, collide)

	# Wall-local box: axis 0 runs along X (fixed z = c), axis 1 along Z (fixed x = c).
	func wl(m: int, axis: int, c: float, u0: float, u1: float, y0: float, y1: float, th: float, col: Color, collide := true) -> void:
		if u1 - u0 < 0.001 or y1 - y0 < 0.001:
			return
		# (a looks-only wall piece doesn't grow along the wall: grown that way, the pieces a wall is cut into
		# overlapped by 8 mm at every seam, in one plane, and flickered there. Nov 26, found by coplanar_faces)
		if axis == 0:
			ab(m, Vector3(u0, y0, c - th * 0.5), Vector3(u1, y1, c + th * 0.5), col, collide, Vector3(0, 0.004, 0.004))
		else:
			ab(m, Vector3(c - th * 0.5, y0, u0), Vector3(c + th * 0.5, y1, u1), col, collide, Vector3(0.004, 0.004, 0))

	# A wall from a0 to a1 with rectangular (or arched) openings cut out.
	func wall(m: int, axis: int, c: float, a0: float, a1: float, y0: float, y1: float, th: float, ops: Array, col: Color, collide := true) -> void:
		var sorted := ops.duplicate()
		sorted.sort_custom(func(p, q): return p["u"] < q["u"])
		var cur := a0
		for op in sorted:
			var u0: float = op["u"] - op["w"] * 0.5
			var u1: float = op["u"] + op["w"] * 0.5
			wl(m, axis, c, cur, u0, y0, y1, th, col, collide)
			wl(m, axis, c, u0, u1, y0, minf(op["b"], y1), th, col, collide)
			wl(m, axis, c, u0, u1, maxf(op["t"], y0), y1, th, col, collide)
			if op["k"] == "arch":
				var r: float = op["w"] * 0.5
				var spring: float = op["t"] - r
				var steps := 6
				for k in steps:
					var ya := spring + r * k / steps
					var yb := spring + r * (k + 1) / steps
					var ext := sqrt(maxf(0.0, r * r - pow(yb - spring, 2.0)))
					if ya < y0 or yb > y1:
						continue
					wl(m, axis, c, u0, op["u"] - ext, ya, yb, th, col, collide)
					wl(m, axis, c, op["u"] + ext, u1, ya, yb, th, col, collide)
			cur = u1
		wl(m, axis, c, cur, a1, y0, y1, th, col, collide)

	# Trim around openings: jambs, lintel, sills, shutters, arch stones.
	func frames(axis: int, c: float, out: float, th: float, ops: Array, trim: Color, shut = null, mat := TRIM) -> void:
		for op in ops:
			var u: float = op["u"]
			var u0: float = u - op["w"] * 0.5
			var u1: float = u + op["w"] * 0.5
			var b: float = op["b"]
			var t: float = op["t"]
			var k: String = op["k"]
			var fw := 0.14
			var dep := th + 0.1
			if k == "hole":
				continue
			if k == "arch":
				var r: float = op["w"] * 0.5
				var spring := t - r
				wl(mat, axis, c, u0 - fw, u0 + 0.02, b, spring, dep, trim, false)
				wl(mat, axis, c, u1 - 0.02, u1 + fw, b, spring, dep, trim, false)
				var n := 9
				for i in n:
					var ang := PI * (i + 0.5) / n
					var p := Vector2(cos(ang), sin(ang)) * (r + fw * 0.5)
					var rot := ang - PI * 0.5
					var bas: Basis
					var cc: Vector3
					if axis == 0:
						bas = Basis(Vector3(0, 0, 1), rot)
						cc = Vector3(u + p.x, spring + p.y, c)
					else:
						bas = Basis(Vector3(1, 0, 0), -rot)
						cc = Vector3(c, spring + p.y, u + p.x)
					# (alternate stones stand a little further out than their neighbours and the jambs, so no two
					# that touch have their faces in one plane)
					var sd := dep + 0.02 * (1 + i % 2)
					var sz := Vector3(PI * r / n * 1.02 + 0.03, fw + 0.04, sd) if axis == 0 else Vector3(sd, fw + 0.04, PI * r / n * 1.02 + 0.03)
					box(mat, cc, sz, trim, false, bas)
				if b > FLOOR + 0.05:
					wl(mat, axis, c + out * 0.06, u0 - 0.08, u1 + 0.08, b - 0.1, b + 0.012, dep + 0.08, trim, false)
				continue
			# (Ted, Nov 26: "glitchy, flashy" surfaces round the openings. The trim's inner faces lay exactly on
			# the wall's cut faces, and the lintel's front on the jambs': two surfaces in one plane flicker. The
			# trim now stands a hair proud into the opening, and the lintel a hair in front of the jambs.)
			var lip := 0.012
			wl(mat, axis, c, u0 - fw, u0 + lip, b, t, dep, trim, false)
			wl(mat, axis, c, u1 - lip, u1 + fw, b, t, dep, trim, false)
			wl(mat, axis, c, u0 - fw - lip, u1 + fw + lip, t - lip, t + fw, dep + 0.024, trim, false)
			if k == "win":
				# (the sill sticks out further than the jambs but not as far in: its inside face lay in the jambs')
				wl(mat, axis, c + out * 0.08, u0 - 0.2, u1 + 0.2, b - 0.12, b + lip, dep + 0.12, trim, false)
				if shut != null:
					var sc: float = c + out * (th * 0.5 + 0.07)
					var sw: float = op["w"] * 0.5
					wl(BOARDS, axis, sc, u0 - fw - sw, u0 - fw - 0.02, b + 0.02, t - 0.02, 0.06, shut, false)
					wl(BOARDS, axis, sc, u1 + fw + 0.02, u1 + fw + sw, b + 0.02, t - 0.02, 0.06, shut, false)

	# Four walls of a w x d box from y0 to y1; ops: side -> openings.
	func shell(m: int, w: float, d: float, y0: float, y1: float, ops: Dictionary, col: Color, trim: Color, shut = null, collide := true, th := T, do_frames := true, frame_mat := TIMBER) -> void:
		var hw := w * 0.5
		var hd := d * 0.5
		if not do_frames:
			# (Ted, Nov 26, still flickering at the tops and bottoms: a cornice band's inside face lay exactly
			# on the wall's inside face. Every band and plinth is now a touch thicker, so its inside stands
			# just proud of the wall.)
			th += 0.02
		if not do_frames and not ops.is_empty():
			# a plinth round the foot of the walls, cut for the same doors: its cut faces would lie in the
			# very planes of the wall's own and flicker, so its openings are a touch wider (Nov 26)
			var wider := {}
			for side in ops:
				wider[side] = (ops[side] as Array).map(func(o):
					var o2: Dictionary = o.duplicate()
					o2["w"] = o2["w"] + 0.03
					if o2["b"] <= y0 + FLOOR + 0.01:
						o2["b"] = y0 - 1.0   # a doorway: no plinth step of its own, its top was in the wall's threshold's plane
						# ...and it stops just short of the door frame: the plinth's face and the frame's were in one
						# plane where they met (Ted, Nov 26: the townhouse's baseboard stones and the shop's entry)
						if o2["k"] != "hole":
							o2["w"] = o["w"] + 2.0 * 0.14 + 0.04
					return o2)
			ops = wider
		var f: Array = ops.get("front", [])
		var bk: Array = ops.get("back", [])
		var r: Array = ops.get("right", [])
		var l: Array = ops.get("left", [])
		wall(m, 0, hd - th * 0.5, -hw, hw, y0, y1, th, f, col, collide)
		wall(m, 0, -hd + th * 0.5, -hw, hw, y0, y1, th, bk, col, collide)
		# (looks-only shells: the side walls stop a hair short of the front and back ones, which grow 4 mm
		# through their thickness and would overlap them in one plane at the corners)
		var e := 0.0 if collide else 0.006
		wall(m, 1, hw - th * 0.5, -hd + th + e, hd - th - e, y0, y1, th, r, col, collide)
		wall(m, 1, -hw + th * 0.5, -hd + th + e, hd - th - e, y0, y1, th, l, col, collide)
		if do_frames:
			frames(0, hd - th * 0.5, 1.0, th, f, trim, shut, frame_mat)
			frames(0, -hd + th * 0.5, -1.0, th, bk, trim, shut, frame_mat)
			frames(1, hw - th * 0.5, 1.0, th, r, trim, shut, frame_mat)
			frames(1, -hw + th * 0.5, -1.0, th, l, trim, shut, frame_mat)

	# Two sloped roof slabs. along_z: ridge runs along Z (else along X).
	# w x d = wall footprint, h = eave height. Returns the ridge height.
	func gable_roof(m: int, w: float, d: float, h: float, pitch: float, oh: float, th: float, col: Color, cap: Color, along_z := false) -> float:
		var R := Vector3.BACK if along_z else Vector3.RIGHT
		var A := Vector3.RIGHT if along_z else Vector3.BACK
		var length := (d if along_z else w) + 2.0 * oh
		var half := (w if along_z else d) * 0.5
		var ridge := h + half * pitch
		for sg in [-1.0, 1.0]:
			var e: Vector3 = A * sg * (half + oh) + Vector3.UP * (h - oh * pitch)
			var r := Vector3.UP * ridge
			var dir := (r - e).normalized()
			var nrm := R.cross(dir)
			if nrm.y < 0.0:
				nrm = -nrm
			var bas := Basis(R, nrm, R.cross(nrm))
			var L := e.distance_to(r) + th * pitch * 0.5
			var cc: Vector3 = (e + r) * 0.5 + nrm * th * 0.5 + dir * th * pitch * 0.25
			# (the two slabs cross at the ridge, and their ends were in one plane there: one is a hair shorter)
			box(m, cc, Vector3(length - (0.008 if sg < 0.0 else 0.0), th, L), col, true, bas)
		var cs := Vector3(0.36, 0.22, length + 0.04) if along_z else Vector3(length + 0.04, 0.22, 0.36)
		box(TRIM, Vector3(0, ridge + th / cos(atan(pitch)) + 0.02, 0), cs, cap, false)
		return ridge

	# Triangular gable wall between eave h and ridge, thickness along R between r0..r1.
	func gable(m: int, along_z: bool, r0: float, r1: float, half: float, h: float, ridge: float, col: Color) -> void:
		var pts: Array = []
		for r in [r0, r1]:
			var a: Vector3
			var b: Vector3
			var t: Vector3
			if along_z:
				a = Vector3(-half, h, r)
				b = Vector3(half, h, r)
				t = Vector3(0, ridge, r)
			else:
				a = Vector3(r, h, -half)
				b = Vector3(r, h, half)
				t = Vector3(r, ridge, 0)
			pts.append_array([a, b, t])
		var R := Vector3.BACK if along_z else Vector3.RIGHT
		var sgn := 1.0 if r1 > r0 else -1.0
		tri(m, pts[0], pts[1], pts[2], -R * sgn, col)
		tri(m, pts[3], pts[4], pts[5], R * sgn, col)
		var sh := ConvexPolygonShape3D.new()
		sh.points = PackedVector3Array(pts)
		shapes.append([sh, Transform3D()])

	# Straight stairs: n steps of `rise` x `run`, solid down to y0, in an x band,
	# climbing from z_start towards -Z (dir = -1) or +Z (dir = 1).
	func stairs(m: int, x0: float, x1: float, z_start: float, dir: float, y0: float, rise: float, run: float, n: int, col: Color, nose: Color) -> void:
		for i in range(1, n + 1):
			var za := z_start + dir * run * (i - 1)
			var zb := z_start + dir * run * i
			var top := y0 + rise * i
			ab(m, Vector3(x0, y0, za), Vector3(x1, top, zb), col, true)
			ab(TIMBER, Vector3(x0, top - 0.05, za + dir * (run - 0.06)), Vector3(x1, top + 0.012, zb + dir * 0.03), nose, false)

	# A simple railing: posts + top rail (visual), one thin collision box.
	# (skip_end: another rail's corner post is already there; two posts in one spot flicker, Nov 26)
	func rail(p0: Vector3, p1: Vector3, h: float, col: Color, skip_end := false) -> void:
		var d := p1 - p0
		var len := d.length()
		var n := maxi(2, int(len / 0.6) + 1)
		for i in n:
			if skip_end and i == n - 1:
				continue
			var p := p0 + d * (float(i) / (n - 1))
			ab(TIMBER, p + Vector3(-0.05, 0, -0.05), p + Vector3(0.05, h, 0.05), col, false)
		var a := p0.min(p1)
		var b := p0.max(p1)
		var dy := 0.0
		if skip_end:   # (and its rails end inside the other rail's, a touch lower, not flush with its faces)
			var cut := d.normalized() * 0.07
			a = (p0).min(p1 - cut)
			b = (p0).max(p1 - cut)
			dy = -0.012
		a.y += dy
		b.y += dy
		var wt := 0.064 if skip_end else 0.07   # (slimmer too, so its sides aren't flush with the other's end)
		var wm := 0.034 if skip_end else 0.04
		ab(TIMBER, a + Vector3(-wt, h - 0.08, -wt), b + Vector3(wt, h + 0.04, wt), col, false)
		ab(TIMBER, a + Vector3(-wm, h * 0.45, -wm), b + Vector3(wm, h * 0.45 + 0.06, wm), col, false)
		var cc := (a + b) * 0.5 + Vector3(0, h * 0.5, 0)
		cbox(cc, (b - a) + Vector3(0.12, h + 0.04, 0.12))


# ---------------------------------------------------------------- palettes

const COTTAGE_WALL := ["#f1dfb0", "#a9c8dc", "#eeb5ae", "#b9d29a"]
const COTTAGE_ROOF := ["#c4583a", "#4f5f80", "#9b6b3c", "#4c7a5a"]
const COTTAGE_SHUT := ["#4f8f5a", "#c0463c", "#3f6fb0", "#e0b040"]
const WOOD_DARK := "#6b4428"
const WOOD := "#9a6a40"
const WHITE_TRIM := "#ece6da"
const STONE_GREY := "#9a9690"

const TOWN_WALL := ["#c0503e", "#e2924c", "#6f84a6", "#4f9a92"]
const TOWN_TRIM := ["#ece6da", "#f3ead6", "#e9e4dc", "#f1e8cf"]
const TOWN_DOOR := ["#3d6f9e", "#7b3b2e", "#c9a03c", "#8a3f6e"]

const SHOP_WALL := ["#7e8fb0", "#e9d3a0", "#d98a7a", "#8cc0a0"]
const SHOP_AWN := ["#2f9a7e", "#c8443a", "#3a68b8", "#8a4fb0"]

const BARN_WALL := ["#b4402f", "#8d8a82", "#6e4a30", "#4f74a0"]
const BARN_ROOF := ["#4a4c52", "#5f7a54", "#8a4a30", "#5a4636"]

const CHAPEL_WALL := ["#bdb6aa", "#d8c49a", "#9faa98", "#8a8894"]
const CHAPEL_ROOF := ["#4a5266", "#7a4a3c", "#3f5a52", "#5a4a6a"]

const RUIN_WALL := ["#a8a296", "#b8a88a", "#8f9690", "#9a8e8a"]


# ---------------------------------------------------------------- kinds

static func _floor(b: Bld, w: float, d: float, mat: int, col: Color) -> void:
	b.ab(mat, Vector3(-w * 0.5 + T, 0.0, -d * 0.5 + T), Vector3(w * 0.5 - T, FLOOR, d * 0.5 - T), col)


static func _step(b: Bld, x: float, z: float, w: float, col: Color) -> void:
	# a low doorstep slab outside a front door (z = front face)
	b.ab(STONE, Vector3(x - w * 0.5, 0.0, z), Vector3(x + w * 0.5, 0.1, z + 0.55), col)


static func _cottage(b: Bld, look: int) -> void:
	var w := 7.0
	var d := 6.0
	var h := 3.1
	var wall := _c(COTTAGE_WALL[look])
	var roof := _c(COTTAGE_ROOF[look])
	var shut := _c(COTTAGE_SHUT[look])
	var wood := _c(WOOD_DARK)
	var stone := _c(STONE_GREY)
	var ops := {
		"front": [_op(-1.3, 1.7, FLOOR, 2.65, "door"), _op(1.6, 1.3, 1.0, 2.2)],
		"back": [_op(0.0, 1.4, 1.0, 2.2)],
		"left": [_op(0.0, 1.2, 1.0, 2.2)],
		"right": [_op(0.3, 1.2, 1.0, 2.2)],
	}
	b.shell(PLASTER, w, d, 0.0, h, ops, wall, wood, shut)
	# stone skirt (visual)
	b.shell(STONE, w + 0.08, d + 0.08, 0.0, 0.55, ops, stone, wood, null, false, T + 0.08, false)
	# timber corner posts and a sill beam under the eaves
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.ab(TIMBER, Vector3(sx * w * 0.5 - 0.17, 0.0, sz * d * 0.5 - 0.17), Vector3(sx * w * 0.5 + 0.17, h - 0.03, sz * d * 0.5 + 0.17), wood, false)
	for sz in [-1.0, 1.0]:
		b.ab(TIMBER, Vector3(-w * 0.5 - 0.1, h - 0.22, sz * d * 0.5 - 0.19), Vector3(w * 0.5 + 0.1, h, sz * d * 0.5 + 0.19), wood, false)
	_floor(b, w, d, PLANKS, _c(WOOD))
	var ridge := b.gable_roof(ROOF, w, d, h, 0.72, 0.45, 0.2, roof, roof.darkened(0.25))
	for sx in [-1.0, 1.0]:
		b.gable(PLASTER, false, sx * (w * 0.5 - T), sx * w * 0.5, d * 0.5, h, ridge, wall)
		# The gable's timber frame (Ted, Nov 26: a lone upright on each gable "looks weird"): a tie beam along
		# its foot, a king post from it right up under the ridge, and a raking strut each side from the post's
		# foot up to the roof, so it reads as what holds the roof up.
		var gx: float = sx * w * 0.5
		var pitch := 0.72
		b.ab(TIMBER, Vector3(gx - 0.05 * sx, h - 0.18, -d * 0.5 + 0.17), Vector3(gx + 0.07 * sx, h + 0.02, d * 0.5 - 0.17), wood, false)
		b.ab(TIMBER, Vector3(gx - 0.04 * sx, h + 0.02, -0.09), Vector3(gx + 0.06 * sx, ridge - 0.09 * pitch - 0.01, 0.09), wood, false)
		for sz in [-1.0, 1.0]:
			var foot := Vector3(gx, h + 0.1, sz * 0.1)
			var zt: float = sz * 1.9
			var top := Vector3(gx, h + (d * 0.5 - absf(zt)) * pitch - 0.1, zt)
			_beam(b, foot, top, wood, Vector2(0.1, 0.14))
	# tie beams across the room (2.85 m clear)
	for x in [-1.75, 1.75]:
		b.ab(TIMBER, Vector3(x - 0.1, h - 0.22, -d * 0.5 + T), Vector3(x + 0.1, h, d * 0.5 - T), wood, false)
	# A stone stove in the back right corner, and its chimney: straight up from it, out through the roof (Ted,
	# Nov 26: the chimney used to stop just under the roof and hang there inside the cottage).
	var kx1 := w * 0.5 - T
	var kz0 := -d * 0.5 + T
	var soot := _c("#1c1714")
	b.ab(STONE, Vector3(kx1 - 1.1, FLOOR, kz0), Vector3(kx1, 1.15, kz0 + 0.8), stone)                   # the stove
	b.ab(TRIM, Vector3(kx1 - 0.85, 0.3, kz0 + 0.8), Vector3(kx1 - 0.25, 0.85, kz0 + 0.81), soot, false)  # its fire door
	b.ab(TIMBER, Vector3(kx1 - 1.2, 1.15, kz0), Vector3(kx1, 1.24, kz0 + 0.92), wood, false)            # a wooden top
	b.ab(STONE, Vector3(kx1 - 0.75, 1.24, kz0), Vector3(kx1 - 0.15, 6.0, kz0 + 0.6), stone)            # the flue, up and out
	b.ab(TRIM, Vector3(kx1 - 0.83, 6.0, kz0 - 0.08), Vector3(kx1 - 0.07, 6.15, kz0 + 0.68), stone.darkened(0.3), false)
	_step(b, -1.3, d * 0.5, 2.0, stone)
	# a flower box under the front window
	b.ab(BOARDS, Vector3(1.6 - 0.75, 0.72, d * 0.5 + 0.06), Vector3(1.6 + 0.75, 0.88, d * 0.5 + 0.32), shut, false)


static func _townhouse(b: Bld, look: int) -> void:
	var w := 8.0
	var d := 7.0
	var f2 := 3.45 # upper floor top
	var h := 6.7
	var wall := _c(TOWN_WALL[look])
	var trim := _c(TOWN_TRIM[look])
	var door := _c(TOWN_DOOR[look])
	var stone := _c("#a7a49e")
	var ops1 := {
		"front": [_op(2.0, 1.7, FLOOR, 2.75, "door"), _op(-0.6, 1.2, 1.0, 2.45), _op(-2.6, 1.2, 1.0, 2.45)],
		"back": [_op(1.5, 1.2, 1.0, 2.45)],
		"right": [_op(0.0, 1.2, 1.0, 2.45)],
	}
	var ops2 := {
		"front": [_op(-2.4, 1.2, f2 + 0.85, f2 + 2.35), _op(0.0, 1.2, f2 + 0.85, f2 + 2.35), _op(2.4, 1.2, f2 + 0.85, f2 + 2.35)],
		"back": [_op(-1.8, 1.2, f2 + 0.85, f2 + 2.35), _op(1.8, 1.2, f2 + 0.85, f2 + 2.35)],
		"left": [_op(0.0, 1.2, f2 + 0.85, f2 + 2.35)],
		"right": [_op(0.0, 1.2, f2 + 0.85, f2 + 2.35)],
	}
	b.shell(BRICK, w, d, 0.0, f2, ops1, wall, trim)
	b.shell(BRICK, w, d, f2, h, ops2, wall, trim)
	# stone plinth and floor band, cornice and parapet
	b.shell(STONE, w + 0.1, d + 0.1, 0.0, 0.45, ops1, stone, trim, null, false, T + 0.1, false)
	b.shell(TRIM, w + 0.16, d + 0.16, f2 - 0.3, f2, {}, trim, trim, null, false, T + 0.08, false)
	b.shell(TRIM, w + 0.3, d + 0.3, h - 0.3, h + 0.05, {}, trim, trim, null, false, T + 0.15, false)
	b.ab(STONE, Vector3(-w * 0.5 + T, h - 0.25, -d * 0.5 + T), Vector3(w * 0.5 - T, h - 0.05, d * 0.5 - T), stone)
	b.shell(BRICK, w, d, h + 0.05, h + 0.6, {}, wall, trim)
	b.shell(TRIM, w + 0.12, d + 0.12, h + 0.6, h + 0.72, {}, trim, trim, null, false, T + 0.12, false)
	_floor(b, w, d, PLANKS, _c(WOOD))
	# stairs along the left wall, climbing towards the back
	var sx0 := -w * 0.5 + T
	var sx1 := sx0 + 1.35
	var n := 15
	var rise := (f2 - FLOOR) / (n - 1)
	var run := 0.28
	var z0 := d * 0.5 - T - 1.1 # leave a landing at the foot
	var ztop := z0 - run * (n - 1) # front edge of the last step (= floor level)
	b.stairs(PLANKS, sx0, sx1, z0, -1.0, FLOOR, rise, run, n - 1, _c(WOOD), _c(WOOD_DARK))
	# upper floor with a stairwell hole
	var fy0 := f2 - 0.25
	var wood := _c(WOOD)
	b.ab(PLANKS, Vector3(sx1, fy0, -d * 0.5 + T), Vector3(w * 0.5 - T, f2, d * 0.5 - T), wood)
	b.ab(PLANKS, Vector3(sx0, fy0, -d * 0.5 + T), Vector3(sx1, f2, ztop), wood)
	b.rail(Vector3(sx1 + 0.06, f2, ztop + 0.3), Vector3(sx1 + 0.06, f2, d * 0.5 - T - 0.06), 1.0, _c(WOOD_DARK))
	b.rail(Vector3(sx0 + 0.06, f2, d * 0.5 - T - 0.06), Vector3(sx1 + 0.06, f2, d * 0.5 - T - 0.06), 1.0, _c(WOOD_DARK), true)
	# door canopy, steps, coloured door frame accents
	b.ab(TRIM, Vector3(2.0 - 1.25, 2.95, d * 0.5), Vector3(2.0 + 1.25, 3.08, d * 0.5 + 0.75), trim)
	b.ab(TIMBER, Vector3(2.0 - 1.05, 2.75, d * 0.5 - 0.02), Vector3(2.0 + 1.05, 2.95, d * 0.5 + 0.1), door, false)
	_step(b, 2.0, d * 0.5, 2.1, stone)
	# window boxes upstairs
	for u in [-2.4, 0.0, 2.4]:
		b.ab(BOARDS, Vector3(u - 0.7, f2 + 0.55, d * 0.5 + 0.1), Vector3(u + 0.7, f2 + 0.71, d * 0.5 + 0.34), door, false)


static func _shop(b: Bld, look: int) -> void:
	var w := 10.0
	var d := 8.0
	var h := 4.3
	var wall := _c(SHOP_WALL[look])
	var awn := _c(SHOP_AWN[look])
	var white := _c(WHITE_TRIM)
	var stone := _c("#a29f98")
	var wood := _c(WOOD)
	var ops := {
		"front": [_op(-1.4, 5.2, FLOOR, 2.95, "wide"), _op(3.4, 1.6, 0.9, 2.5)],
		"right": [_op(1.6, 1.7, FLOOR, 2.75, "door"), _op(-1.8, 1.4, 0.9, 2.5)],
		"left": [_op(0.0, 1.4, 1.0, 2.5)],
		"back": [_op(2.8, 1.7, FLOOR, 2.65, "door")],
	}
	b.shell(PLASTER, w, d, 0.0, h, ops, wall, white)
	b.shell(BRICK, w + 0.1, d + 0.1, 0.0, 0.6, ops, _c("#8a5a4a"), white, null, false, T + 0.1, false)
	# flat roof, cornice, parapet
	b.ab(STONE, Vector3(-w * 0.5 + T, h - 0.25, -d * 0.5 + T), Vector3(w * 0.5 - T, h - 0.05, d * 0.5 - T), stone)
	b.shell(TRIM, w + 0.3, d + 0.3, h - 0.3, h + 0.05, {}, white, white, null, false, T + 0.15, false)
	b.shell(PLASTER, w, d, h + 0.05, h + 0.55, {}, wall, white)
	b.shell(TRIM, w + 0.12, d + 0.12, h + 0.55, h + 0.67, {}, white, white, null, false, T + 0.12, false)
	_floor(b, w, d, FLAG, _c("#d8d2c4"))
	# striped awning over the open front
	var ax0 := -4.4
	var ax1 := 1.6
	var y_hi := 3.3
	var y_lo := 2.7
	var out := 1.5
	var slope := Vector3(0, y_lo - y_hi, out)
	var nrm := Vector3.RIGHT.cross(slope.normalized())
	if nrm.y < 0.0:
		nrm = -nrm
	var bas := Basis(Vector3.RIGHT, nrm, Vector3.RIGHT.cross(nrm))
	var cz := d * 0.5 + out * 0.5
	var cy := (y_hi + y_lo) * 0.5
	var stripes := 12
	var sw := (ax1 - ax0) / stripes
	for i in stripes:
		var col := awn if i % 2 == 0 else white
		b.box(TRIM, Vector3(ax0 + sw * (i + 0.5), cy, cz), Vector3(sw, 0.06, slope.length()), col, false, bas)
		b.ab(TRIM, Vector3(ax0 + sw * i, y_lo - 0.3, d * 0.5 + out - 0.02), Vector3(ax0 + sw * (i + 1), y_lo, d * 0.5 + out + 0.03), col, false, Vector3(0.004, 0.004 + 0.003 * (i % 2), 0.004 + 0.004 * (i % 2)))
	b.cbox(Vector3((ax0 + ax1) * 0.5, cy, cz), Vector3(ax1 - ax0, 0.06, slope.length()), bas)
	# sign board
	b.ab(TIMBER, Vector3(-4.2, 3.4, d * 0.5), Vector3(4.2, 3.92, d * 0.5 + 0.14), awn.darkened(0.35), false)
	b.ab(TRIM, Vector3(-3.0, 3.54, d * 0.5 + 0.1), Vector3(3.0, 3.78, d * 0.5 + 0.17), white, false)
	# counter (L) and back shelves
	var cc := _c(WOOD_DARK)
	b.ab(BOARDS, Vector3(-3.6, FLOOR, -0.9), Vector3(1.2, 1.1, -0.3), wood)
	b.ab(BOARDS, Vector3(0.6, FLOOR, -0.3), Vector3(1.2, 1.1, 1.6), wood)
	b.ab(TIMBER, Vector3(-3.7, 1.1, -0.98), Vector3(1.3, 1.18, -0.22), cc, false)
	b.ab(TIMBER, Vector3(0.52, 1.1, -0.212), Vector3(1.31, 1.18, 1.7), cc, false)
	var sx0 := -4.6
	var sx1 := 0.4
	var sz0 := -d * 0.5 + T
	var sz1 := sz0 + 0.45
	b.cbox(Vector3((sx0 + sx1) * 0.5, (FLOOR + 2.3) * 0.5, (sz0 + sz1) * 0.5), Vector3(sx1 - sx0, 2.3 - FLOOR, sz1 - sz0))
	for x in [sx0, (sx0 + sx1) * 0.5, sx1 - 0.08]:
		b.ab(TIMBER, Vector3(x, FLOOR, sz0 + 0.01), Vector3(x + 0.08, 2.34, sz1 + 0.01), cc, false)
	# Empty shelves and display crates (Ted, Nov 26: nothing built in that could be mistaken for a prop; maps
	# stock them with real props)
	for sy in [0.25, 0.95, 1.65, 2.3]:
		b.ab(TIMBER, Vector3(sx0 + 0.02, sy - 0.05, sz0), Vector3(sx1 - 0.02, sy, sz1), cc, false)
	for x in [-4.2, -3.4, -2.6]:
		_crate(b, Vector3(x, FLOOR, 1.6))


static func _barn(b: Bld, look: int) -> void:
	var w := 11.0
	var d := 10.0
	var h := 5.0
	var loft := 3.2
	var wall := _c(BARN_WALL[look])
	var roof := _c(BARN_ROOF[look])
	var white := _c(WHITE_TRIM)
	var stone := _c(STONE_GREY)
	var wood := _c(WOOD)
	var ops := {
		"front": [_op(0.0, 4.0, FLOOR, 4.0, "door")],
		"back": [_op(0.0, 1.8, 3.5, 4.75, "win")],
		"left": [_op(-2.5, 1.0, 1.4, 2.4), _op(2.5, 1.0, 1.4, 2.4)],
		"right": [_op(-3.0, 1.0, 1.4, 2.4)],
	}
	b.shell(BOARDS, w, d, 0.0, h, ops, wall, white)
	b.shell(STONE, w + 0.1, d + 0.1, 0.0, 0.5, ops, stone, white, null, false, T + 0.1, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.ab(TIMBER, Vector3(sx * w * 0.5 - 0.16, 0.0, sz * d * 0.5 - 0.16), Vector3(sx * w * 0.5 + 0.16, h - 0.03, sz * d * 0.5 + 0.16), white, false)
	_floor(b, w, d, PLANKS, _c("#8a6a48"))
	var ridge := b.gable_roof(ROOF, w, d, h, 0.85, 0.5, 0.22, roof, roof.darkened(0.3), true)
	for sz in [-1.0, 1.0]:
		b.gable(BOARDS, true, sz * (d * 0.5 - T), sz * d * 0.5, w * 0.5, h, ridge, wall)
		# white trim along the gable edge and a loft hatch
		var zf: float = sz * (d * 0.5 + 0.06)
		b.ab(TIMBER, Vector3(-w * 0.5 - 0.1, h - 0.2, zf - 0.08), Vector3(w * 0.5 + 0.1, h, zf + 0.08), white, false)
		if sz > 0.0:
			b.ab(BOARDS, Vector3(-0.9, h + 0.5, zf - 0.04), Vector3(0.9, h + 2.0, zf + 0.06), wall.darkened(0.12), false)
			# (the uprights stand a little proud of the cross bars, and the X's two bars at different depths:
			# where they met, their faces were in one plane)
			for e in [[-1.04, h + 0.41, 1.04, h + 0.55, 0.12], [-1.04, h + 2.0, 1.04, h + 2.14, 0.12], [-1.05, h + 0.4, -0.9, h + 2.15, 0.135], [0.9, h + 0.4, 1.05, h + 2.15, 0.135]]:
				b.ab(TIMBER, Vector3(e[0], e[1], zf - (0.0 if e[4] < 0.13 else 0.006)), Vector3(e[2], e[3], zf + e[4]), white, false)
			for s2 in [1.0, -1.0]:
				b.box(TIMBER, Vector3(0, h + 1.27, zf + 0.07 + (0.01 if s2 > 0.0 else 0.0)), Vector3(2.15, 0.14, 0.06), white, false, Basis(Vector3(0, 0, 1), s2 * atan2(1.5, 1.8)))
	# front gable is on the long front? no: ridge runs along X, so the +Z front wall is the eave side.
	# sliding doors, slid open beside the opening, with white X braces and a rail
	var fz := d * 0.5 + 0.02
	for sx in [-1.0, 1.0]:
		var xa: float = sx * 2.12
		var xb: float = sx * 4.15
		b.ab(BOARDS, Vector3(minf(xa, xb), 0.1, fz), Vector3(maxf(xa, xb), 4.1, fz + 0.12), wall.darkened(0.1))
		var x0 := minf(xa, xb)
		var x1 := maxf(xa, xb)
		for e in [[x0 + 0.01, 0.11, x1 - 0.01, 0.32], [x0 + 0.01, 3.88, x1 - 0.01, 4.09]]:
			b.ab(TIMBER, Vector3(e[0], e[1], fz + 0.106), Vector3(e[2], e[3], fz + 0.18), white, false)
		b.ab(TIMBER, Vector3(x0, 0.1, fz + 0.094), Vector3(x0 + 0.2, 4.1, fz + 0.195), white, false)
		b.ab(TIMBER, Vector3(x1 - 0.2, 0.1, fz + 0.094), Vector3(x1, 4.1, fz + 0.195), white, false)
		var dg := Vector2(x1 - x0 - 0.2, 3.56)
		var ang := atan2(dg.y, dg.x)
		for s2 in [1.0, -1.0]:
			b.box(TIMBER, Vector3((x0 + x1) * 0.5, 2.1, fz + 0.13 + (0.01 if s2 > 0.0 else 0.0)), Vector3(dg.length(), 0.18, 0.07), white, false, Basis(Vector3(0, 0, 1), ang * s2))
	b.ab(TRIM, Vector3(-4.4, 4.12, fz), Vector3(4.4, 4.3, fz + 0.2), _c("#3a3a3e"), false)
	# hay loft at the back, stairs up the right wall
	var ze := -0.6
	b.ab(PLANKS, Vector3(-w * 0.5 + T, loft - 0.25, -d * 0.5 + T), Vector3(w * 0.5 - T, loft, ze), wood)
	var n := 14
	var rise := (loft - FLOOR) / n
	var run := 0.28
	var bx1 := w * 0.5 - T
	var bx0 := bx1 - 1.4
	b.stairs(PLANKS, bx0, bx1, ze + run * n, -1.0, FLOOR, rise, run, n, wood, _c(WOOD_DARK))
	b.rail(Vector3(-w * 0.5 + T + 0.06, loft, ze - 0.06), Vector3(bx0 - 0.06, loft, ze - 0.06), 1.0, _c(WOOD_DARK))
	for x in [-3.2, 0.0, 3.0]:
		b.ab(TIMBER, Vector3(x - 0.13, FLOOR, ze - 0.4), Vector3(x + 0.13, loft - 0.25, ze - 0.14), _c(WOOD_DARK))
	# loft beam along the edge
	b.ab(TIMBER, Vector3(-w * 0.5 + T, loft - 0.45, ze - 0.3), Vector3(w * 0.5 - T, loft - 0.25, ze), _c(WOOD_DARK), false)
	# (no hay bales built in: Ted, Nov 26, they didn't match the hay bale props, and maps put real props here)
	# hay door frame + a little white X on the gable ends
	b.ab(TIMBER, Vector3(-1.2, 4.75, -d * 0.5 - 0.1), Vector3(1.2, 4.95, -d * 0.5 + 0.1), white, false)


static func _chapel(b: Bld, look: int) -> void:
	var w := 7.0
	var d := 12.0
	var h := 4.4
	var wall := _c(CHAPEL_WALL[look])
	var roof := _c(CHAPEL_ROOF[look])
	var trim := wall.lightened(0.25)
	var wood := _c(WOOD_DARK)
	var ops := {
		"front": [_op(0.0, 2.0, FLOOR, 3.4, "arch")],
		"back": [_op(0.0, 1.2, 1.6, 3.6, "arch")],
		"left": [_op(-3.5, 0.9, 1.4, 3.4, "arch"), _op(0.0, 0.9, 1.4, 3.4, "arch"), _op(3.5, 0.9, 1.4, 3.4, "arch")],
		"right": [_op(-3.5, 0.9, 1.4, 3.4, "arch"), _op(0.0, 0.9, 1.4, 3.4, "arch"), _op(3.5, 0.9, 1.4, 3.4, "arch")],
	}
	b.shell(STONE, w, d, 0.0, h, ops, wall, trim, null, true, T, true, TRIM)   # (stone frames: no grain)
	b.shell(STONE, w + 0.14, d + 0.14, 0.0, 0.5, ops, wall.darkened(0.15), trim, null, false, T + 0.14, false)
	_floor(b, w, d, FLAG, wall.lightened(0.1))
	var ridge := b.gable_roof(ROOF, w, d, h, 1.15, 0.35, 0.22, roof, roof.darkened(0.3), true)
	for sz in [-1.0, 1.0]:
		b.gable(STONE, true, sz * (d * 0.5 - T), sz * d * 0.5, w * 0.5, h, ridge, wall)
	# round window on the front gable (trim ring, visual)
	var gy := h + 1.2
	for i in 10:
		var ang := TAU * i / 10.0
		b.box(TRIM, Vector3(cos(ang) * 0.5, gy + sin(ang) * 0.5, d * 0.5 + 0.03 + 0.01 * (i % 2)), Vector3(0.34, 0.16, 0.1), trim, false, Basis(Vector3(0, 0, 1), ang + PI * 0.5))
	b.ab(TRIM, Vector3(-0.42, gy - 0.42, d * 0.5 - 0.01), Vector3(0.42, gy + 0.42, d * 0.5 + 0.02), _c("#2a2440"), false)
	# buttresses
	for sx in [-1.0, 1.0]:
		for z in [-5.2, -1.75, 1.75, 5.2]:
			b.ab(STONE, Vector3(sx * w * 0.5 - 0.3, 0.0, z - 0.3), Vector3(sx * w * 0.5 + sx * 0.45, 2.6, z + 0.3), wall.darkened(0.08))
			b.ab(STONE, Vector3(sx * w * 0.5 - 0.3, 2.6, z - 0.3), Vector3(sx * w * 0.5 + sx * 0.25, 3.4, z + 0.3), wall.darkened(0.08))
	# bell cote over the front gable
	var bz := d * 0.5 - 0.35
	var by := ridge - 0.4
	for sx in [-1.0, 1.0]:
		b.ab(STONE, Vector3(sx * 0.55 - 0.18, by, bz - 0.3), Vector3(sx * 0.55 + 0.18, by + 1.7, bz + 0.3), wall)
	b.ab(STONE, Vector3(-0.8, by + 1.7, bz - 0.4), Vector3(0.8, by + 2.0, bz + 0.4), wall)
	b.ab(STONE, Vector3(-0.76, by - 0.2, bz - 0.37), Vector3(0.76, by + 0.2, bz + 0.37), wall)
	var gold := _c("#e0b040")
	b.ab(TRIM, Vector3(-0.25, by + 0.75, bz - 0.25), Vector3(0.25, by + 1.35, bz + 0.25), gold, false)
	b.ab(TRIM, Vector3(-0.33, by + 0.66, bz - 0.33), Vector3(0.33, by + 0.8, bz + 0.33), gold, false)
	for sx in [-1.0, 1.0]:
		b.box(ROOF, Vector3(sx * 0.45, by + 2.32, bz), Vector3(1.15, 0.12, 1.1 + 0.01 * sx), roof, false, Basis(Vector3(0, 0, 1), -sx * 0.72))
	# doors: two open wooden leaves just inside, against the wall
	for sx in [-1.0, 1.0]:
		b.ab(BOARDS, Vector3(sx * 1.05, FLOOR, d * 0.5 - T - 1.0), Vector3(sx * 1.13, 2.45, d * 0.5 - T), wood)
	# dais, altar, pews
	b.ab(FLAG, Vector3(-w * 0.5 + T, FLOOR, -d * 0.5 + T), Vector3(w * 0.5 - T, FLOOR + 0.18, -3.6), wall.lightened(0.15))
	b.ab(STONE, Vector3(-0.9, FLOOR + 0.18, -4.9), Vector3(0.9, FLOOR + 1.1, -4.3), wall)
	b.ab(TRIM, Vector3(-1.0, FLOOR + 1.1, -4.95), Vector3(1.0, FLOOR + 1.16, -4.25), _c("#f0ece0"), false)
	b.ab(TRIM, Vector3(-0.25, FLOOR + 0.5, -4.27), Vector3(0.25, FLOOR + 1.1, -4.24), _c("#9a3040"), false)
	for z in [2.6, 1.3, 0.0, -1.3]:
		for sx in [-1.0, 1.0]:
			var x0: float = sx * 0.85
			var x1: float = sx * 3.0
			b.ab(PLANKS, Vector3(minf(x0, x1), FLOOR + 0.4, z - 0.25), Vector3(maxf(x0, x1), FLOOR + 0.48, z + 0.25), _c(WOOD))
			b.ab(PLANKS, Vector3(minf(x0, x1), FLOOR + 0.48, z + 0.2), Vector3(maxf(x0, x1), FLOOR + 1.0, z + 0.28), _c(WOOD))
			for x in [x0, x1]:
				b.ab(TIMBER, Vector3(x - 0.05, FLOOR, z - 0.25), Vector3(x + 0.05, FLOOR + 1.0, z + 0.28), wood, false)
	# tie beams
	for z in [-3.0, 0.0, 3.0]:
		b.ab(TIMBER, Vector3(-w * 0.5 + T, h - 0.25, z - 0.12), Vector3(w * 0.5 - T, h - 0.02, z + 0.12), wood, false)
	_step(b, 0.0, d * 0.5, 2.6, wall.darkened(0.1))


static func _ruin(b: Bld, look: int) -> void:
	var w := 9.0
	var d := 7.0
	var wall := _c(RUIN_WALL[look])
	var wood := _c("#4a3a2c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + look * 31
	var hw := w * 0.5
	var hd := d * 0.5
	var sides := [
		# axis, c, a0, a1, openings, base profile height, gaps [u0, u1]
		[0, hd - T * 0.5, -hw, hw, [_op(-1.5, 1.7, FLOOR, 2.6, "door"), _op(2.2, 1.2, 1.0, 2.2)], 3.2, []],
		[0, -hd + T * 0.5, -hw, hw, [_op(-1.5, 1.2, 1.0, 2.2), _op(2.0, 1.2, 1.0, 2.2)], 3.6, []],
		[1, -hw + T * 0.5, -hd + T, hd - T, [_op(0.5, 1.1, 1.0, 2.2)], 3.3, []],
		[1, hw - T * 0.5, -hd + T, hd - T, [], 2.2, [[-1.2, 1.6]]],
	]
	for s in sides:
		var axis: int = s[0]
		var c: float = s[1]
		var a0: float = s[2]
		var a1: float = s[3]
		var ops: Array = s[4]
		var base: float = s[5]
		var gaps: Array = s[6]
		var cuts := [a0, a1]
		var u := a0 + 0.55
		while u < a1:
			cuts.append(u)
			u += rng.randf_range(0.4, 0.75)
		for op in ops:
			cuts.append(op["u"] - op["w"] * 0.5)
			cuts.append(op["u"] + op["w"] * 0.5)
		for g in gaps:
			cuts.append(g[0])
			cuts.append(g[1])
		cuts.sort()
		var segs := []   # [u0, u1, top, opening or null]
		for i in cuts.size() - 1:
			var u0: float = cuts[i]
			var u1: float = cuts[i + 1]
			if u1 - u0 < 0.02:
				continue
			var m := (u0 + u1) * 0.5
			var t := (m - a0) / (a1 - a0)
			var top := base * (0.55 + 0.45 * sin(t * PI * (1.3 + rng.randf() * 0.2) + float(axis))) + rng.randf_range(-0.35, 0.35)
			top = clampf(top, 0.3, 3.8)
			# (Ted, Nov 26: beams "resting" on air.) Wherever timber bears on a wall, the wall still stands
			# high enough to hold it: under the surviving corner of the upper floor (back-left), and where the
			# fallen joist and the leaning beam meet the back wall.
			if c < 0.0 and axis == 0 and (m < -0.9 or absf(m - 1.0) < 0.45 or absf(m - 3.4) < 0.45):
				top = maxf(top, 3.25 if m < -0.9 else 2.75)
			if c < 0.0 and axis == 1 and m < -0.6:
				top = maxf(top, 3.25)
			var gap := false
			for g in gaps:
				if m > g[0] and m < g[1]:
					gap = true
			if gap:
				top = rng.randf_range(0.0, 0.25)
				if top < 0.12:
					continue
			var hole = null
			for op in ops:
				if m > op["u"] - op["w"] * 0.5 and m < op["u"] + op["w"] * 0.5:
					hole = op
			segs.append([u0, u1, top, hole])
		# Masonry over an opening only stays up where the wall either side of the opening still stands that
		# high (Nov 26: chunks over windows hung in the air).
		for i in segs.size():
			var sg: Array = segs[i]
			var hole = sg[3]
			if hole == null:
				b.wl(STONE, axis, c, sg[0], sg[1], 0.0, sg[2], T, wall)
				continue
			b.wl(STONE, axis, c, sg[0], sg[1], 0.0, minf(hole["b"], sg[2]), T, wall)
			var held := 99.0
			for dir in [-1, 1]:
				var j: int = i + dir
				while j >= 0 and j < segs.size() and segs[j][3] == hole:
					j += dir
				held = minf(held, segs[j][2] if j >= 0 and j < segs.size() else 0.0)
			var top := minf(sg[2], held)
			if top > hole["t"] + 0.2:
				b.wl(STONE, axis, c, sg[0], sg[1], hole["t"], top, T, wall)
		var keep: Array = []
		for op in ops:
			if op["k"] == "door":
				keep.append(op)
		b.frames(axis, c, 1.0, T, keep, wall.darkened(0.2), null, STONE)
	_floor(b, w, d, PLANKS, _c("#6a5440"))
	# the old chimney stack still standing on the left
	b.ab(STONE, Vector3(-hw - 0.55, 0.0, -2.0), Vector3(-hw + 0.02, 4.4, -0.8), wall.darkened(0.12))
	b.ab(STONE, Vector3(-hw - 0.45, 4.4, -1.9), Vector3(-hw - 0.05, 4.9, -1.3), wall.darkened(0.12))
	# A corner of the upper floor still hanging on: floorboards on joists, the joists' ends set into the back
	# wall and resting on a girder at the front, the girder held by the left wall and one post. The boards
	# are broken off raggedly at the front, and the rest of that floor lies slumped down to the ground floor,
	# still hanging off the girder (Ted, Nov 26: "the collapsed 2nd floor would make it look nicer").
	b.cbox(Vector3((-hw + T - 1.4) * 0.5, 3.05, (-hd + T - 1.0) * 0.5), Vector3(-1.4 - (-hw + T), 0.2, -1.0 - (-hd + T)))
	var x := -hw + T
	while x < -1.45:
		var bw := minf(0.22, -1.4 - x)
		var reach := -1.0 + rng.randf_range(-0.25, 0.12)
		_timber(b, Vector3(x + 0.005, 2.95, -hd + T), Vector3(x + bw - 0.005, 3.15, reach), wood.lightened(rng.randf_range(-0.08, 0.08)))
		x += bw
	for jx in [-3.6, -2.4, -1.6]:
		_timber(b, Vector3(jx - 0.1, 2.75, -hd + T * 0.5), Vector3(jx + 0.1, 2.95, -0.95), wood)
		_pocket(b, Vector3(jx, 2.85, -hd + T), Vector3.BACK, Vector2(0.3, 0.3), wall)
	_timber(b, Vector3(-hw + T * 0.5, 2.55, -1.15), Vector3(-1.25, 2.75, -0.95), wood, true)    # girder
	_pocket(b, Vector3(-hw + T, 2.65, -1.05), Vector3.RIGHT, Vector2(0.3, 0.3), wall)
	_timber(b, Vector3(-1.55, FLOOR, -1.15), Vector3(-1.35, 2.55, -0.95), wood, true)          # its post
	# The slumped part (Ted, Nov 26: the sheet of planks "looks WAY too orderly for what must have happened"):
	# a broken, tumbled mess down to the floor. Some boards are gone, most snapped in two with splinters at the
	# break, every piece skewed its own way, a few lying across the others and one of the joists come down
	# with them. Under it all there's still one walkable slope (the collision box), so it can be climbed.
	var top_z := -0.9
	var foot_z := 1.45
	var top_y := 2.8
	var foot_y := FLOOR + 0.06
	var slope_dir := Vector3(0, foot_y - top_y, foot_z - top_z).normalized()
	var slope_up := Vector3.RIGHT.cross(slope_dir)
	if slope_up.y < 0.0:
		slope_up = -slope_up
	var sb := Basis(Vector3.RIGHT, slope_up, Vector3.RIGHT.cross(slope_up))
	var slope_len := Vector2(foot_z - top_z, top_y - foot_y).length()
	var on_slope := func(x: float, s: float, lift: float) -> Vector3:
		return Vector3(x, top_y, top_z) + slope_dir * s + slope_up * lift
	var cx := -3.72
	while cx < -2.0:
		if rng.randf() < 0.22:   # this one's gone
			cx += rng.randf_range(0.22, 0.32)
			continue
		var s0 := rng.randf_range(0.0, 0.45)
		var s1 := slope_len - rng.randf_range(0.0, 0.7)
		var two := rng.randf() < 0.65
		var cut := lerpf(s0, s1, rng.randf_range(0.3, 0.7))
		for k in (2 if two else 1):
			var a0: float = s0 if k == 0 else cut + rng.randf_range(0.06, 0.3)
			var a1: float = (cut if two else s1) if k == 0 else s1
			if a1 - a0 < 0.25:
				continue
			var bas := sb * Basis(Vector3.UP, rng.randf_range(-0.24, 0.24)) * Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)) \
					* Basis(Vector3.RIGHT, rng.randf_range(-0.1, 0.1))
			var mid: Vector3 = on_slope.call(cx + rng.randf_range(-0.06, 0.06), (a0 + a1) * 0.5, rng.randf_range(0.05, 0.14))
			var col := wood.lightened(rng.randf_range(-0.12, 0.06))
			var bw := rng.randf_range(0.15, 0.22)
			b.box(TIMBER, mid, Vector3(bw, 0.045, a1 - a0), col, false, bas)
			if two and k == 0:
				# splinters at the break, fanning out a little
				var end: Vector3 = mid + bas.z.normalized() * (a1 - a0) * 0.5 * signf(bas.z.dot(slope_dir))
				for sp in rng.randi_range(2, 3):
					var sl := rng.randf_range(0.12, 0.3)
					var sbas := bas * Basis(Vector3.UP, rng.randf_range(-0.35, 0.35)) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.25))
					var at: Vector3 = end + bas.x.normalized() * rng.randf_range(-bw * 0.35, bw * 0.35) + sbas.z.normalized() * sl * 0.5 * signf(sbas.z.dot(slope_dir))
					b.box(TIMBER, at, Vector3(rng.randf_range(0.02, 0.04), 0.02, sl), col.lightened(0.08), false, sbas)
		cx += rng.randf_range(0.2, 0.3)
	# a few lying across the others
	for k in 3:
		var bas := sb * Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.45, 0.45)) * Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12))
		var at: Vector3 = on_slope.call(rng.randf_range(-3.3, -2.4), rng.randf_range(0.5, slope_len - 0.4), rng.randf_range(0.17, 0.22))
		b.box(TIMBER, at, Vector3(0.19, 0.045, rng.randf_range(0.7, 1.4)), wood.lightened(rng.randf_range(-0.1, 0.05)), false, bas)
	# a joist that came down with them, slewed across the slope
	_beam(b, on_slope.call(-3.45, 0.35, 0.2), on_slope.call(-2.35, slope_len - 0.35, 0.22), wood)
	b.cbox(Vector3(-2.85, (top_y + foot_y) * 0.5 + 0.06, (top_z + foot_z) * 0.5), Vector3(1.9, 0.12, slope_len), sb)
	# a few loose boards that fell off it
	for k in 3:
		var at := Vector3(rng.randf_range(-3.6, -2.2), FLOOR + 0.03 + 0.05 * k, rng.randf_range(1.7, 2.6))
		b.box(TIMBER, at, Vector3(0.2, 0.05, rng.randf_range(0.8, 1.6)), wood.lightened(rng.randf_range(-0.1, 0.05)), false,
				Basis(Vector3.UP, rng.randf() * TAU))
	b.ab(TRIM, Vector3(-1.6, FLOOR, -1.2), Vector3(-1.3, FLOOR + 0.08, -0.9), wood.darkened(0.2), false)   # pad stone
	# A joist that came loose at one end: still in its pocket in the back wall (a dark hole round it, so it
	# goes INTO the wall instead of through it: Ted, Nov 26), the other end down on the floor.
	var j_top := Vector3(1.0, 2.6, -hd + T * 0.4)
	var j_foot := _on_floor(j_top, Vector3(1.0, 0.0, 0.9))
	_beam(b, j_top, j_foot, wood)
	var jd := (j_foot - j_top).normalized()
	var jy := j_top.y + jd.y * ((-hd + T) - j_top.z) / jd.z
	_pocket(b, Vector3(1.0, jy, -hd + T), Vector3.BACK, Vector2(0.3, 0.2 / absf(jd.z) + 0.1), wall)
	# A beam that fell and leans against the back wall, on solid wall between the window and the corner. Its
	# top edge rests exactly on the wall's face (Ted, Nov 26: first it stood off the wall, then it went into
	# it), and its foot's lowest corner on the floor.
	var l_top := Vector3(3.4, 2.35, -hd + T)
	var l_foot := Vector3(3.4, FLOOR + 0.1, -0.75)
	for it in 3:
		var dir := (l_top - l_foot).normalized()
		l_top.z = -hd + T + 0.1 * absf(dir.y) + 0.003
		l_foot = _on_floor(l_top, Vector3(l_foot.x, 0.0, l_foot.z))
	_beam(b, l_foot, l_top, wood)
	# and one lying across the floor, its far end propped up on a block of fallen masonry
	var prop_at := Vector3(1.35, 0.0, 2.15)
	b.box(STONE, prop_at + Vector3(0, 0.23, 0), Vector3(0.6, 0.46, 0.5), wall.darkened(0.1), true, Basis(Vector3.UP, 0.3))
	_beam(b, _on_floor(prop_at + Vector3(0, 0.56, 0), Vector3(-1.1, 0.0, 1.15)), prop_at + Vector3(0, 0.56, 0), wood)
	# rubble: small bits are only looks, big blocks are solid
	var spots := [Vector3(hw - 0.6, 0, 0.2), Vector3(hw + 0.8, 0, 0.4), Vector3(-hw + 0.9, 0, -hd + 0.9), Vector3(1.8, 0, hd + 0.8), Vector3(-3.5, 0, 2.2)]
	for sp in spots:
		for k in 9:
			var sz := Vector3(rng.randf_range(0.18, 0.45), rng.randf_range(0.12, 0.28), rng.randf_range(0.18, 0.45))
			var p: Vector3 = sp + Vector3(rng.randf_range(-0.9, 0.9), FLOOR * 0.5 + sz.y * 0.4, rng.randf_range(-0.9, 0.9))
			var bas := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
			b.box(STONE, p, sz, wall.darkened(rng.randf_range(0.0, 0.25)), false, bas)
		for k in 2:
			var sz := Vector3(rng.randf_range(0.55, 0.85), rng.randf_range(0.35, 0.55), rng.randf_range(0.45, 0.7))
			var p: Vector3 = sp + Vector3(rng.randf_range(-0.6, 0.6), sz.y * 0.45, rng.randf_range(-0.6, 0.6))
			b.box(STONE, p, sz, wall.darkened(0.1), true, Basis.from_euler(Vector3(0, rng.randf() * TAU, rng.randf_range(-0.15, 0.15))))
