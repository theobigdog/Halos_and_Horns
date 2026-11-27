# Demon wings, made properly (Ted, Nov 27: "they all look 'fake', like they're made of kite material and
# bike-spokes... More realistic, and like they actually grow from the demons' bodies"). A bat / dragon wing:
#   - a thick, fleshy shoulder that starts inside the back and narrows into the upper arm, so the wing grows
#     out of the body instead of being stuck on it;
#   - arm and finger bones as one smooth tapering tube each, swelling at the knuckles, curving a little;
#   - leathery skin stretched between the fingers: it billows back between the bones and its trailing edge
#     sags in a scallop between the tips; the inner panel reaches down to the demon's flank;
#   - a hooked thumb claw at the wrist and a small claw at each finger tip.
# The skin shader draws branching veins, fine wrinkles across the stretch, darker skin near the bones and
# thin, glowing-red skin where light shines through it (backlit). One mesh per wing: two surfaces (skin,
# bone), cached, so every demon shares them.
# Wing space: x out from the body (times `side`), y up, z toward the front (the back is -z); the origin is
# the wing's root on the back (characters.gd _wings puts it there).
extends RefCounted

const SKIN_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec3 skin_col : source_color = vec3(0.26, 0.05, 0.06);
uniform vec3 edge_col : source_color = vec3(0.07, 0.015, 0.02);
uniform vec3 vein_col : source_color = vec3(0.12, 0.01, 0.02);
uniform vec3 glow_col : source_color = vec3(1.0, 0.22, 0.05);
uniform vec3 through_col : source_color = vec3(0.85, 0.12, 0.04);
varying vec2 pv;     // x: along the fingers (0 at the wrist, 1 at the edge), y: panel + across (0..1)
varying float thin;  // 1 in the middle of a panel, 0 at the bones
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	pv = UV;
	thin = COLOR.r;
}
void fragment() {
	float across = fract(pv.y);
	float panel = floor(pv.y);
	// veins: run out along the fingers and branch as they go (more of them further out)
	float n = floor(2.0 + pv.x * 4.0);
	float w = across * n + (n2(vec2(pv.x * 6.0, panel * 3.1 + across * 2.0)) - 0.5) * 0.9;
	float vein = 1.0 - smoothstep(0.0, 0.07 + 0.05 * (1.0 - pv.x), abs(fract(w) - 0.5) * 2.0 - 0.0);
	vein *= smoothstep(0.02, 0.15, pv.x) * smoothstep(0.0, 0.12, thin);
	// fine wrinkles across the stretch, and a mottled, leathery skin
	float wr = sin(pv.x * 90.0 + n2(vec2(across * 9.0, panel)) * 6.0) * 0.5 + 0.5;
	float mott = n2(vec2(pv.x * 18.0, across * 14.0 + panel * 7.0));
	vec3 c = skin_col * (0.75 + 0.35 * mott) * (0.9 + 0.1 * wr);
	c = mix(c, edge_col, (1.0 - smoothstep(0.0, 0.35, thin)) * 0.75);      // thick and dark at the bones
	c = mix(c, edge_col, smoothstep(0.9, 1.0, pv.x) * 0.6);                 // and along the trailing edge
	c = mix(c, vein_col, vein * 0.7);
	ALBEDO = c;
	ROUGHNESS = 0.5 + 0.25 * wr;
	SPECULAR = 0.45;
	// light shining through the thin skin: red, with the veins dark against it
	BACKLIGHT = through_col * thin * (1.0 - vein * 0.8) * 0.9;
	EMISSION = glow_col * vein * 0.06;
}
"""

static var _cache := {}


static func materials() -> Array:
	if not _cache.has("mats"):
		var skin := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SKIN_SHADER
		skin.shader = sh
		var bone := StandardMaterial3D.new()
		bone.vertex_color_use_as_albedo = true
		bone.vertex_color_is_srgb = true
		bone.roughness = 0.45
		bone.metallic_specular = 0.55
		_cache["mats"] = [skin, bone]
	return _cache["mats"]


# The wing's skeleton (right-hand wing; the left is mirrored), in wing space.
const S := Vector3(0.0, 0.0, 0.0)          # shoulder
const E := Vector3(0.36, 0.3, -0.07)       # elbow
const W := Vector3(0.74, 0.5, -0.03)       # wrist
# each finger: [mid point, tip], from the wrist
const FINGERS := [
	[Vector3(0.33, 0.13, 0.0), Vector3(0.66, 0.16, -0.04)],
	[Vector3(0.35, -0.09, -0.01), Vector3(0.68, -0.28, -0.06)],
	[Vector3(0.25, -0.33, -0.01), Vector3(0.47, -0.68, -0.06)],
	[Vector3(0.08, -0.45, -0.01), Vector3(0.12, -0.9, -0.05)],
]


static func mesh(side: float) -> ArrayMesh:
	var key := "wing_%d" % int(side)
	if _cache.has(key):
		return _cache[key]
	var m := Vector3(side, 1.0, 1.0)
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bone := SurfaceTool.new()
	bone.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The curves (bones and panel edges), as points along each
	var arm := _curve([W, E, S], 10)            # from the wrist back to the shoulder
	var fingers := []
	for f in FINGERS:
		fingers.append(_curve([W, W + f[0], W + f[1]], 10))
	# Skin: panels between neighbouring ribs, all starting at the wrist. The inner one (last finger to the
	# arm) bulges down to the flank instead of sagging in.
	var ribs: Array = fingers + [arm]
	for i in ribs.size() - 1:
		var inner := i == ribs.size() - 2
		_panel(skin, ribs[i], ribs[i + 1], -0.55 if inner else 0.2, float(i), m, side)
	skin.generate_normals()
	var out := skin.commit()
	# Bones: the shoulder growing out of the back into the arm, the forearm, then each finger
	var dark := Color(0.13, 0.04, 0.045)
	var root_pts := _curve([Vector3(-0.1, -0.04, 0.07), Vector3(-0.02, 0.0, 0.0), E * 0.45], 6)
	_tube(bone, root_pts, [0.11, 0.1, 0.085, 0.075, 0.068, 0.062, 0.058], dark, m, side, 10)
	var upper := _curve([E * 0.4, E * 0.75, E], 6)
	_tube(bone, upper, _taper(upper.size(), 0.06, 0.042, 0.0), dark, m, side, 9)
	var fore := _curve([E, E.lerp(W, 0.5) + Vector3(0, 0.02, 0.01), W], 8)
	_tube(bone, fore, _taper(fore.size(), 0.048, 0.036, 0.012), dark, m, side, 9)
	for f in fingers:
		_tube(bone, f, _taper(f.size(), 0.03, 0.009, 0.008), dark, m, side, 7)
	# knuckles at the elbow and wrist
	_tube(bone, _curve([E - Vector3(0.02, 0.0, 0.0), E + Vector3(0.025, 0.02, 0.0)], 3), [0.04, 0.058, 0.045], dark, m, side, 9)
	_tube(bone, _curve([W - Vector3(0.025, 0.0, 0.0), W + Vector3(0.025, 0.0, 0.0)], 3), [0.034, 0.05, 0.034], dark, m, side, 9)
	# claws: a hooked thumb at the wrist, a small one at each finger tip
	var ivory := Color(0.78, 0.72, 0.6)
	_tube(bone, _curve([W + Vector3(0.0, 0.03, 0.02), W + Vector3(0.02, 0.12, 0.06), W + Vector3(0.07, 0.17, 0.03)], 6),
			[0.03, 0.026, 0.02, 0.014, 0.007, 0.0], ivory, m, side, 7)
	for f in FINGERS:
		var tip: Vector3 = W + f[1]
		var dir: Vector3 = (f[1] - f[0]).normalized()
		_tube(bone, _curve([tip - dir * 0.01, tip + dir * 0.04 + Vector3(0, -0.01, -0.01), tip + dir * 0.06 + Vector3(0, -0.035, -0.02)], 4),
				[0.011, 0.009, 0.005, 0.0], ivory, m, side, 6)
	bone.generate_normals()
	out = bone.commit(out)
	_cache[key] = out
	return out


# Points along a smooth curve through `pts` (Catmull-Rom), `n` per span, ends included.
static func _curve(pts: Array, n: int) -> Array:
	var out := []
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		var steps := maxi(n / maxi(pts.size() - 1, 1), 2)
		for k in steps:
			var t := float(k) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out


static func _taper(n: int, r0: float, r1: float, knuckle: float) -> Array:
	var out := []
	for i in n:
		var t := float(i) / maxf(n - 1, 1)
		out.append(lerpf(r0, r1, t) + knuckle * exp(-pow((t - 0.5) * 6.0, 2.0)))
	return out


# One stretch of skin between two ribs that start at the same point (the wrist): rows along the ribs,
# columns across. Between the ends it sags toward the wrist (`sag` > 0, a scallop) or bulges away (< 0);
# in between the bones it billows back. UV: x along, y = panel + across; COLOR.r = how far from a bone.
static func _panel(st: SurfaceTool, a: Array, b: Array, sag: float, panel: float, m: Vector3, side: float) -> void:
	var rows := 9
	var cols := 7
	var grid := []
	var root: Vector3 = a[0]
	for r in rows + 1:
		var u := float(r) / rows
		var pa := _at(a, u)
		var pb := _at(b, u)
		var row := []
		for c in cols + 1:
			var v := float(c) / cols
			var p := pa.lerp(pb, v)
			var bow := sin(PI * v)
			p = p.lerp(root, sag * bow * pow(u, 3.0))
			p.z -= 0.06 * bow * sin(PI * minf(u * 1.15, 1.0)) * (pa.distance_to(pb) / 0.6)
			row.append([p * m, Vector2(u, panel + v * 0.999), bow])
		grid.append(row)
	for r in rows:
		for c in cols:
			var q := [grid[r][c], grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1]]
			for tri in ([[0, 1, 2], [0, 2, 3]] if side > 0.0 else [[0, 2, 1], [0, 3, 2]]):
				for k in tri:
					var e: Array = q[k]
					st.set_uv(e[1])
					st.set_color(Color(e[2], 0, 0))
					st.add_vertex(e[0])


static func _at(pts: Array, u: float) -> Vector3:
	var f := u * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i] as Vector3).lerp(pts[i + 1], f - i)


# A tube along `pts` with these radii, coloured `col` (lighter along the top, like a ridge of bone).
static func _tube(st: SurfaceTool, pts: Array, radii: Array, col: Color, m: Vector3, side: float, sides: int) -> void:
	var n := pts.size()
	var rings := []
	var ref := Vector3.FORWARD
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var x := ref - t * ref.dot(t)
		if x.length() < 0.01:
			x = t.cross(Vector3.UP)
		x = x.normalized()
		var y := t.cross(x)
		var r: float = radii[mini(i, radii.size() - 1)]
		var ring := []
		for j in sides + 1:
			var a := TAU * j / sides
			var d := x * cos(a) + y * sin(a)
			var shade := col.lightened(0.18 * maxf(d.y, 0.0)).darkened(0.25 * maxf(-d.y, 0.0))
			ring.append([(pts[i] + d * r) * m, shade])
		rings.append(ring)
	for i in n - 1:
		var mid: Vector3 = (pts[i] + pts[i + 1]) * 0.5 * m
		for j in sides:
			var q := [rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]]
			var outward: Vector3 = (q[0][0] + q[2][0]) * 0.5 - mid
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var pa: Vector3 = q[tri[0]][0]
				var pb: Vector3 = q[tri[1]][0]
				var pc: Vector3 = q[tri[2]][0]
				var order := [tri[0], tri[1], tri[2]]
				if (pb - pa).cross(pc - pa).dot(outward) > 0.0:
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					st.set_color(q[k][1])
					st.add_vertex(q[k][0])
	# close the thick end (the shoulder root, inside the body anyway) with a cap
	if radii[0] > 0.0:
		var c0: Vector3 = pts[0] * m
		for j in sides:
			var pa: Vector3 = rings[0][j][0]
			var pb: Vector3 = rings[0][j + 1][0]
			var tdir: Vector3 = (pts[0] - pts[1]) * m
			var order := [c0, pa, pb] if (pa - c0).cross(pb - c0).dot(tdir) > 0.0 else [c0, pb, pa]
			for p in order:
				st.set_color(col)
				st.add_vertex(p)
